class_name Checker
extends Node3D

const RADIUS := 0.155
const HALF_HEIGHT := 0.068
const PIXELS_PER_UNIT := 100.0
const SLIDE_GRAVITY := 9.8
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
var fall_velocity := Vector3.ZERO
@onready var planar_body: RigidBody2D = $PlanarBody
@onready var contact_material: PhysicsMaterial = planar_body.physics_material_override
var mass: float:
	get: return planar_body.mass
var linear_velocity: Vector3:
	get: return from_plane(planar_body.linear_velocity)
	set(value): planar_body.linear_velocity = to_plane(value)


func _ready() -> void:
	place_on_board(global_position, global_rotation.y)
	planar_body.body_entered.connect(_report_contact)
	set_icon(icon)


static func to_plane(vector: Vector3) -> Vector2:
	return Vector2(vector.x, vector.z) * PIXELS_PER_UNIT


static func from_plane(vector: Vector2, height := 0.0) -> Vector3:
	return Vector3(vector.x / PIXELS_PER_UNIT, height, vector.y / PIXELS_PER_UNIT)


func place_on_board(point: Vector3, yaw: float) -> void:
	global_position = point
	global_rotation = Vector3(0.0, yaw, 0.0)
	planar_body.position = to_plane(point)
	# Positive 2D rotation maps to negative yaw on the XZ plane.
	planar_body.rotation = -yaw


func sync_planar_position() -> void:
	global_position = from_plane(planar_body.position, global_position.y)
	global_rotation = Vector3(0.0, -planar_body.rotation, 0.0)


func apply_slide_friction(delta: float) -> void:
	if planar_body.sleeping:
		return
	var friction := ICE_FRICTION if icon == Icon.SNOWFLAKE else NORMAL_FRICTION
	planar_body.linear_velocity = planar_body.linear_velocity.move_toward(
		Vector2.ZERO, friction * SLIDE_GRAVITY * PIXELS_PER_UNIT * delta)


func apply_planar_impulse(velocity: Vector3, offset: Vector3) -> void:
	var planar_velocity := to_plane(velocity)
	planar_body.sleeping = false
	planar_body.linear_velocity += planar_velocity
	if not offset.is_zero_approx():
		planar_body.apply_torque_impulse(to_plane(offset).cross(planar_velocity) * mass)


func stop_motion() -> void:
	planar_body.linear_velocity = Vector2.ZERO
	planar_body.angular_velocity = 0.0
	planar_body.sleeping = true


func set_icon(value: Icon) -> void:
	icon = value
	planar_body.collision_layer = 0 if icon == Icon.GHOST else 1
	planar_body.collision_mask = 0 if icon == Icon.GHOST else 1
	planar_body.mass = ARMORED_MASS if icon == Icon.ARMORED else 1.0
	planar_body.linear_damp = 0.04 if icon == Icon.SNOWFLAKE else NORMAL_DAMP
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
	var other := body.get_parent() as Checker
	if other:
		struck.emit(other)


func start_fuse() -> void:
	fuse = 2.0
	fuse_origin = global_position


func stays_on_board() -> bool:
	return icon == Icon.GHOST or icon == Icon.FLOATING


func is_in_motion() -> bool:
	return not planar_body.sleeping and (linear_velocity.length_squared() > 0.0025
		or absf(planar_body.angular_velocity) > 0.6)


func shot_multiplier() -> float:
	match icon:
		Icon.SNOWFLAKE: return 1.15
		Icon.ARMORED: return 1.75
		_: return 1.0


func leave_board() -> void:
	falling = true
	fall_velocity = linear_velocity
	stop_motion()
	planar_body.freeze = true
	planar_body.collision_layer = 0
	planar_body.collision_mask = 0


func animate_fall(delta: float, floor_y: float) -> void:
	if floor_time > 0.0:
		floor_time += delta
		return
	fall_velocity.y -= SLIDE_GRAVITY * delta
	var point := global_position + fall_velocity * delta
	var floor_height := floor_y + HALF_HEIGHT
	point.y = maxf(point.y, floor_height)
	global_position = point
	if point.y <= floor_height:
		floor_time = delta
