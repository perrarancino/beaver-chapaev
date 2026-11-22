class_name Checker
extends RigidBody3D

const RADIUS := 0.155
const HALF_HEIGHT := 0.068
const SURFACE_LAYER := 4
const NORMAL_FRICTION := 0.24
const ICE_FRICTION := 0.070
const NORMAL_DAMP := 0.10
const NORMAL_BOUNCE := 0.10
const RUBBER_BOUNCE := 0.74
const ARMORED_MASS := 2.5

enum Icon { NONE, GHOST, SNIPER, EXPLOSIVE, ARMORED, SNOWFLAKE, FLOATING, LIGHTNING, STICKY, RUBBER, VAMPIRE }

signal struck(other: Checker)

const ICON_NAMES := [
	"Обычная", "Призрачная", "Снайперская", "Взрывная", "Броневая", "Ледяная",
	"Парящая", "Молниеносная", "Липкая", "Резиновая", "Вампирская",
]
const ICON_DETAILS := [
	"Стандартная шашка.",
	"Два хода проходит сквозь шашки, слегка толкая и замедляя их. Её нельзя выбить.",
	"Показывает траекторию удара и до трёх отскоков.",
	"Через 2 секунды после первого столкновения расталкивает соседей взрывом.",
	"Почти не отскакивает; другую броневую толкает прямо по ходу удара.",
	"Разгоняется сильнее и дольше скользит.",
	"Три раунда отскакивает от края поля.",
	"При столкновении пускает цепь молний, которая слегка толкает шашки.",
	"При столкновении ненадолго соединяется с другой шашкой.",
	"Сильно отскакивает при столкновениях.",
	"Выбивает соперника и возвращает одну ранее потерянную союзную шашку.",
]
const SIMPLE_EMBLEMS := {
	Icon.FLOATING: ["≋", Color("bce8f2")],
	Icon.LIGHTNING: ["ϟ", Color("ffdc73")],
	Icon.STICKY: ["∞", Color("8ed3a0")],
	Icon.RUBBER: ["↔", Color("edac71")],
	Icon.VAMPIRE: ["♥", Color("e77683")],
}
const ICON_RADIUS := 0.101
const ICON_DEPTH := 0.029
const ICON_SEAT := 0.047
const ICON_MODELS := {
	Icon.GHOST: preload("res://assets/checkers/ghost.glb"),
	Icon.SNIPER: preload("res://assets/checkers/sniper.fbx"),
	Icon.EXPLOSIVE: preload("res://assets/checkers/explosive.fbx"),
	Icon.ARMORED: preload("res://assets/checkers/armored.fbx"),
	Icon.SNOWFLAKE: preload("res://assets/checkers/snowflake.fbx"),
}
const ICON_TEXTURES := {
	Icon.SNIPER: [
		preload("res://assets/checkers/sniper_albedo.webp"),
		preload("res://assets/checkers/sniper_normal.webp"),
	],
	Icon.EXPLOSIVE: [
		preload("res://assets/checkers/explosive_albedo.webp"),
		preload("res://assets/checkers/explosive_normal.webp"),
	],
	Icon.ARMORED: [
		preload("res://assets/checkers/armored_albedo.webp"),
		preload("res://assets/checkers/armored_normal.webp"),
	],
	Icon.SNOWFLAKE: [
		preload("res://assets/checkers/snowflake_albedo.webp"),
		preload("res://assets/checkers/snowflake_normal.webp"),
	],
}

@export_enum("Light", "Dark") var side: int = 0
@export var icon: Icon = Icon.NONE
var falling := false
var floor_time := 0.0
var slot := -1
var hit_source: Checker
var incoming_velocity := Vector3.ZERO
var fuse := -1.0
var exploded := false
var fuse_origin := Vector3.ZERO
var lightning_used := false
var sticky_used := false
var contact_material: PhysicsMaterial
static var disc_shape: ConvexPolygonShape3D


func _ready() -> void:
	if disc_shape == null:
		disc_shape = _make_disc_shape()
	$CollisionShape3D.shape = disc_shape
	contact_monitor = true
	max_contacts_reported = 12
	body_entered.connect(_report_contact)
	contact_material = physics_material_override.duplicate() as PhysicsMaterial
	physics_material_override = contact_material
	set_icon(icon)
	sleeping = true


static func _make_disc_shape() -> ConvexPolygonShape3D:
	const BEVEL := 0.010
	const SIDES := 32
	var points := PackedVector3Array()
	# Flat faces support the checker; the bevel lets it roll over the rim cleanly.
	for y in [-HALF_HEIGHT, -HALF_HEIGHT + BEVEL, HALF_HEIGHT - BEVEL, HALF_HEIGHT]:
		var radius := RADIUS - BEVEL if is_equal_approx(absf(y), HALF_HEIGHT) else RADIUS
		for i in SIDES:
			var angle := TAU * i / SIDES
			points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	var hull := ConvexPolygonShape3D.new()
	hull.margin = 0.006
	hull.points = points
	return hull


func set_icon(value: Icon) -> void:
	icon = value
	var planar := stays_on_board()
	collision_layer = 2 if icon == Icon.GHOST else 1
	collision_mask = 0 if icon == Icon.GHOST else (1 if planar else 1 | SURFACE_LAYER)
	axis_lock_linear_y = planar
	axis_lock_angular_x = planar
	axis_lock_angular_z = planar
	gravity_scale = 0.0 if planar else 1.0
	mass = ARMORED_MASS if icon == Icon.ARMORED else 1.0
	linear_damp = 0.04 if icon == Icon.SNOWFLAKE else NORMAL_DAMP
	contact_material.friction = ICE_FRICTION if icon == Icon.SNOWFLAKE else NORMAL_FRICTION
	contact_material.bounce = RUBBER_BOUNCE if icon == Icon.RUBBER else NORMAL_BOUNCE
	var old_emblem := $Visual.get_node_or_null("Emblem")
	if old_emblem:
		$Visual.remove_child(old_emblem)
		old_emblem.queue_free()
	if icon == Icon.NONE:
		return
	if SIMPLE_EMBLEMS.has(icon):
		var badge: Array = SIMPLE_EMBLEMS[icon]
		var glyph := Label3D.new()
		glyph.name = "Emblem"
		glyph.text = badge[0]
		glyph.modulate = badge[1]
		glyph.outline_modulate = Color("3a302b")
		glyph.outline_size = 9
		glyph.font_size = 84
		glyph.pixel_size = 0.0019
		glyph.position.y = ICON_SEAT + 0.005
		glyph.rotation.x = -PI / 2.0
		glyph.double_sided = false
		$Visual.add_child(glyph)
		return
	var model := (ICON_MODELS[icon] as PackedScene).instantiate() as Node3D
	var emblem := model.get_child(0) as MeshInstance3D
	var bounds := emblem.get_aabb()
	var center := bounds.get_center()
	var radius_squared := 0.0
	var vertices: PackedVector3Array = emblem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		radius_squared = maxf(radius_squared, Vector2(vertex.x - center.x, vertex.y - center.y).length_squared())
	var face_scale := ICON_RADIUS / sqrt(radius_squared)
	var depth_scale := ICON_DEPTH / bounds.size.z
	# Imported emblems face +Z. Lay them face-up with the underside seated in the insert.
	var basis := Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(face_scale, depth_scale, face_scale))
	var underside := Vector3(center.x, center.y, bounds.position.z)
	emblem.transform = Transform3D(basis, Vector3.UP * ICON_SEAT - basis * underside)
	emblem.layers = 3
	if ICON_TEXTURES.has(icon):
		var textures: Array = ICON_TEXTURES[icon]
		var material := StandardMaterial3D.new()
		material.albedo_texture = textures[0]
		material.roughness = 0.52
		material.normal_enabled = true
		material.normal_texture = textures[1]
		material.emission_enabled = true
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_texture = textures[0]
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 0.23
		emblem.material_override = material
	model.name = "Emblem"
	$Visual.add_child(model)


func _report_contact(body: Node) -> void:
	var other := body as Checker
	if other:
		struck.emit(other)


func start_fuse() -> void:
	fuse = 2.0
	fuse_origin = global_position


func stays_on_board() -> bool:
	return icon == Icon.GHOST or icon == Icon.FLOATING


func is_in_motion() -> bool:
	if sleeping:
		return false
	# Ignore small movements from the contact solver while a flat disc is at rest.
	var tipping := global_basis.y.dot(Vector3.UP) < 0.985 and angular_velocity.length_squared() > 0.36
	return linear_velocity.slide(Vector3.UP).length_squared() > 0.0025 \
		or absf(linear_velocity.y) > 0.16 or absf(angular_velocity.y) > 0.6 or tipping


func shot_multiplier() -> float:
	match icon:
		Icon.SNOWFLAKE: return 1.15
		Icon.ARMORED: return 1.75
		_: return 1.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if stays_on_board() and not falling:
		# The two magical discs have no contact with the wooden surface.
		state.linear_velocity = state.linear_velocity.move_toward(
			Vector3.ZERO, NORMAL_FRICTION * 9.8 * state.step)


func leave_board() -> void:
	falling = true
	collision_layer = 0
	collision_mask = SURFACE_LAYER
	sleeping = false
