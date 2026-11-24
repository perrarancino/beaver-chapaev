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
const SURFACE_SHADER := preload("res://assets/FX/checker_surface.gdshader")
const SURFACE_RIM_SHADER := preload("res://assets/FX/checker_surface_rim.gdshader")
const GHOST_SHADER := preload("res://assets/FX/checker_ghost.gdshader")
const WIND_SHADER := preload("res://assets/FX/checker_wind.gdshader")
const ARC_ATLAS := preload("res://assets/FX/checker_strike_atlas.svg")
static var blue_flame_materials: Dictionary[StandardMaterial3D, ShaderMaterial] = {}
static var ember_materials: Dictionary[StandardMaterial3D, ShaderMaterial] = {}
static var electric_materials: Dictionary[StandardMaterial3D, ShaderMaterial] = {}
static var surface_rim_mesh: CylinderMesh
static var surface_rim_materials: Dictionary[int, ShaderMaterial] = {}
static var ghost_materials: Dictionary[int, ShaderMaterial] = {}
static var wind_mesh: CylinderMesh

enum Icon {
	NONE, GHOST, SNIPER, EXPLOSIVE, ARMORED, SNOWFLAKE, FLOATING, LIGHTNING, STICKY, RUBBER,
}

signal struck(other: Checker)

const ICON_NAMES := {
	Icon.NONE: "Обычная",
	Icon.GHOST: "Призрачная",
	Icon.EXPLOSIVE: "Взрывная",
	Icon.ARMORED: "Броневая",
	Icon.SNOWFLAKE: "Ледяная",
	Icon.FLOATING: "Парящая",
	Icon.LIGHTNING: "Молниеносная",
	Icon.STICKY: "Липкая",
	Icon.RUBBER: "Резиновая",
}
const ICON_DETAILS := {
	Icon.NONE: "Стандартная шашка.",
	Icon.GHOST: "До первого удара неуязвима. При первом ударе проходит сквозь шашки, активирует их свойства, а после остановки становится твёрдой.",
	Icon.EXPLOSIVE: "Через 2 секунды после первого столкновения расталкивает соседей взрывом.",
	Icon.ARMORED: "Скользит медленнее и толкает другие шашки без собственного отскока.",
	Icon.SNOWFLAKE: "Разгоняется сильнее и дольше скользит.",
	Icon.FLOATING: "После первого вылета парит у края. Её можно вернуть на поле в следующий ход владельца.",
	Icon.LIGHTNING: "При столкновении пускает цепь молний, которая слегка толкает вражеские шашки.",
	Icon.STICKY: "При столкновении сцепляется с другой шашкой, пока одна из них не покинет поле.",
	Icon.RUBBER: "Сильно отскакивает от шашек и препятствий.",
}
const ICON_RADIUS := 0.101
const ICON_DEPTH := 0.029
const ICON_SEAT := 0.047
const ICON_MODELS := {
	Icon.NONE: preload("res://assets/checkers/ordinary.fbx"),
	Icon.FLOATING: preload("res://assets/checkers/floating.fbx"),
	Icon.LIGHTNING: preload("res://assets/checkers/lightning.fbx"),
	Icon.STICKY: preload("res://assets/checkers/sticky.fbx"),
	Icon.RUBBER: preload("res://assets/checkers/rubber.fbx"),
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
	Icon.NONE: [
		preload("res://assets/checkers/ordinary_albedo.webp"),
		preload("res://assets/checkers/ordinary_normal.webp"),
	],
	Icon.FLOATING: [
		preload("res://assets/checkers/floating_albedo.webp"),
		preload("res://assets/checkers/floating_normal.webp"),
	],
	Icon.LIGHTNING: [
		preload("res://assets/checkers/lightning_albedo.webp"),
		preload("res://assets/checkers/lightning_normal.webp"),
	],
	Icon.STICKY: [
		preload("res://assets/checkers/sticky_albedo.webp"),
		preload("res://assets/checkers/sticky_normal.webp"),
	],
	Icon.RUBBER: [
		preload("res://assets/checkers/rubber_albedo.webp"),
		preload("res://assets/checkers/rubber_normal.webp"),
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
var incoming_velocity := Vector3.ZERO
var fuse := -1.0
var exploded := false
var fuse_origin := Vector3.ZERO
var lightning_used := false
var ghost_spent := false
var solid_materials: Dictionary[MeshInstance3D, Material] = {}
var float_used := false
var wind_effect: MeshInstance3D
var hovering := false:
	set(value):
		if hovering == value:
			return
		hovering = value
		if wind_effect:
			wind_effect.set_instance_shader_parameter("wind_strength", 1.12 if hovering else 0.68)
var hover_started_turn := -1
var fall_velocity := Vector3.ZERO
var stretch_tween: Tween
var stretch_amount := 0.0
@onready var planar_body: RigidBody2D = $PlanarBody
@onready var contact_material: PhysicsMaterial = planar_body.physics_material_override
@onready var turn_aura := get_node_or_null("TurnAura") as MeshInstance3D
@onready var visual: Node3D = $Visual
var mass: float:
	get: return planar_body.mass
var linear_velocity: Vector3:
	get: return _board_basis() * from_plane(planar_body.linear_velocity)


func _ready() -> void:
	place_on_board(position, rotation.y)
	planar_body.body_entered.connect(_report_contact)
	if is_intangible():
		planar_body.collision_layer = 0
		planar_body.collision_mask = 0
	planar_body.mass = ARMORED_MASS if icon == Icon.ARMORED else 1.0
	planar_body.linear_damp = 0.04 if icon == Icon.SNOWFLAKE else NORMAL_DAMP
	contact_material.friction = ICE_FRICTION if icon == Icon.SNOWFLAKE else NORMAL_FRICTION
	match icon:
		Icon.RUBBER: contact_material.bounce = RUBBER_BOUNCE
		Icon.ARMORED: contact_material.bounce = 0.0
		_: contact_material.bounce = NORMAL_BOUNCE
	if icon == Icon.SNOWFLAKE or icon == Icon.EXPLOSIVE or icon == Icon.LIGHTNING:
		_coat_surface()
		_add_surface_rim()
	elif icon == Icon.FLOATING:
		_add_wind()
	_build_emblem()
	if is_intangible():
		_apply_ghost_look()
	reset_physics_interpolation()


static func to_plane(vector: Vector3) -> Vector2:
	return Vector2(vector.x, vector.z) * PIXELS_PER_UNIT


static func from_plane(vector: Vector2, height := 0.0) -> Vector3:
	return Vector3(vector.x / PIXELS_PER_UNIT, height, vector.y / PIXELS_PER_UNIT)


func place_on_board(point: Vector3, yaw: float) -> void:
	position = point
	rotation = Vector3(0.0, yaw, 0.0)
	planar_body.position = to_plane(point)
	# Positive 2D rotation maps to negative yaw on the XZ plane.
	planar_body.rotation = -yaw


func sync_planar_position() -> void:
	position = from_plane(planar_body.position, position.y)
	rotation = Vector3(0.0, -planar_body.rotation, 0.0)


func _board_basis() -> Basis:
	var board := get_parent_node_3d()
	return board.global_basis if board else Basis.IDENTITY


func apply_slide_friction(delta: float, stopping_distance := INF) -> void:
	if planar_body.sleeping:
		return
	var friction := ICE_FRICTION if icon == Icon.SNOWFLAKE else NORMAL_FRICTION
	var braking := maxf(friction * SLIDE_GRAVITY, linear_velocity.length_squared() / (2.0 * stopping_distance))
	planar_body.linear_velocity = planar_body.linear_velocity.move_toward(
		Vector2.ZERO, braking * PIXELS_PER_UNIT * delta)


func apply_planar_impulse(velocity: Vector3, offset: Vector3) -> void:
	var world_to_board := _board_basis().inverse()
	var planar_velocity := to_plane(world_to_board * velocity)
	planar_body.sleeping = false
	planar_body.linear_velocity += planar_velocity
	if not offset.is_zero_approx():
		planar_body.apply_torque_impulse(to_plane(world_to_board * offset).cross(planar_velocity) * mass)


func stop_motion() -> void:
	planar_body.linear_velocity = Vector2.ZERO
	planar_body.angular_velocity = 0.0
	planar_body.sleeping = true


func show_turn_aura(active: bool) -> void:
	if turn_aura:
		turn_aura.visible = active and not falling


func set_turn_aura_selected(active: bool) -> void:
	if turn_aura:
		turn_aura.set_instance_shader_parameter("is_selected", active)


func stretch_on_impact(world_direction: Vector3, strength: float) -> void:
	var peak := lerpf(0.19, 0.49, clampf(strength, 0.0, 1.0))
	if stretch_amount > peak:
		return
	if stretch_tween and stretch_tween.is_running():
		stretch_tween.kill()
	var axis := (_board_basis().inverse() * world_direction).slide(Vector3.UP).normalized()
	stretch_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	stretch_tween.tween_method(_apply_impact_stretch.bind(axis), stretch_amount, peak, 0.028).set_trans(
		Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	stretch_tween.tween_interval(0.045)
	stretch_tween.tween_method(_apply_impact_stretch.bind(axis), peak, -peak * 0.16, 0.16).set_trans(
		Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


	stretch_tween.tween_method(_apply_impact_stretch.bind(axis), -peak * 0.16, 0.0, 0.11).set_trans(
		Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_impact_stretch(amount: float, board_axis: Vector3) -> void:
	stretch_amount = amount
	var axis := basis.inverse() * board_axis
	var alignment := Basis(Vector3.UP, atan2(-axis.z, axis.x))
	var scale_along_impact := Basis.from_scale(Vector3(1.0 + amount, 1.0 - amount * 0.32, 1.0 - amount * 0.71))
	visual.basis = alignment * scale_along_impact * alignment.transposed()


func _coat_surface() -> void:
	var materials := ember_materials
	match icon:
		Icon.SNOWFLAKE: materials = blue_flame_materials
		Icon.LIGHTNING: materials = electric_materials
	for part: MeshInstance3D in [$Visual/OuterRim, $Visual/InnerInsert/Body,
			$Visual/InnerInsert/Trim, $Visual/InnerInsert/Face]:
		var base := part.get_active_material(0) as StandardMaterial3D
		if not base:
			continue
		if not materials.has(base):
			var coating := ShaderMaterial.new()
			coating.shader = SURFACE_SHADER
			coating.set_shader_parameter("blue_flame", icon == Icon.SNOWFLAKE)
			if icon == Icon.LIGHTNING:
				coating.set_shader_parameter("electric", true)
				coating.set_shader_parameter("arc_atlas", ARC_ATLAS)
			coating.set_shader_parameter("base_color", base.albedo_color)
			coating.set_shader_parameter("base_roughness", base.roughness)
			coating.set_shader_parameter("metal", base.metallic)
			if base.albedo_texture:
				coating.set_shader_parameter("wood_texture", base.albedo_texture)
			if base.normal_enabled and base.normal_texture:
				coating.set_shader_parameter("has_normal", true)
				coating.set_shader_parameter("surface_normal", base.normal_texture)
			materials[base] = coating
		part.material_override = materials[base]
		part.set_instance_shader_parameter("is_rim", part == $Visual/OuterRim)
		part.set_instance_shader_parameter("part_offset", to_local(part.global_position))


func _add_surface_rim() -> void:
	if surface_rim_mesh == null:
		surface_rim_mesh = CylinderMesh.new()
		surface_rim_mesh.top_radius = RADIUS
		surface_rim_mesh.bottom_radius = RADIUS + 0.004
		surface_rim_mesh.height = 0.118
		surface_rim_mesh.radial_segments = 48
		surface_rim_mesh.rings = 0
		surface_rim_mesh.cap_top = false
		surface_rim_mesh.cap_bottom = false
	if not surface_rim_materials.has(icon):
		var rim_material := ShaderMaterial.new()
		rim_material.shader = SURFACE_RIM_SHADER
		rim_material.set_shader_parameter("icy", icon == Icon.SNOWFLAKE)
		if icon == Icon.LIGHTNING:
			rim_material.set_shader_parameter("electric", true)
			rim_material.set_shader_parameter("arc_atlas", ARC_ATLAS)
		surface_rim_materials[icon] = rim_material
	var rim := MeshInstance3D.new()
	rim.name = "SurfaceEffect"
	rim.mesh = surface_rim_mesh
	rim.material_override = surface_rim_materials[icon]
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.position.y = 0.046
	if icon == Icon.LIGHTNING:
		rim.scale = Vector3(1.15, 1.13, 1.15)
	$Visual.add_child(rim)


func _apply_ghost_look() -> void:
	# The inner cylinder would stack another see-through layer under the face.
	$Visual/InnerInsert/Body.hide()
	var emblem := visual.get_node("Emblem")
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if not part.visible:
			continue
		var is_emblem := emblem.is_ancestor_of(part)
		var variant := side * 2 + int(is_emblem)
		if not ghost_materials.has(variant):
			var material := ShaderMaterial.new()
			material.shader = GHOST_SHADER
			material.set_shader_parameter("emblem", is_emblem)
			material.set_shader_parameter("hostile", side == 1)
			ghost_materials[variant] = material
		solid_materials[part] = part.material_override
		part.material_override = ghost_materials[variant]


func _add_wind() -> void:
	if not wind_mesh:
		var material := ShaderMaterial.new()
		material.shader = WIND_SHADER
		wind_mesh = CylinderMesh.new()
		wind_mesh.top_radius = 0.236
		wind_mesh.bottom_radius = 0.177
		wind_mesh.height = 0.24
		wind_mesh.radial_segments = 40
		wind_mesh.rings = 3
		wind_mesh.cap_top = false
		wind_mesh.cap_bottom = false
		wind_mesh.material = material
	wind_effect = MeshInstance3D.new()
	wind_effect.name = "WindVortex"
	wind_effect.mesh = wind_mesh
	wind_effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wind_effect.position.y = 0.055
	visual.add_child(wind_effect)


func _build_emblem() -> void:
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


func is_intangible() -> bool:
	return icon == Icon.GHOST and not ghost_spent


func spend_ghost() -> void:
	ghost_spent = true
	planar_body.collision_layer = 1
	planar_body.collision_mask = 1
	if not solid_materials.is_empty():
		for part: MeshInstance3D in solid_materials:
			part.material_override = solid_materials[part]
		solid_materials.clear()
		$Visual/InnerInsert/Body.show()


func is_in_motion() -> bool:
	return not planar_body.sleeping and (linear_velocity.length_squared() > 0.0025
		or absf(planar_body.angular_velocity) > 0.6)


func shot_multiplier() -> float:
	match icon:
		Icon.SNOWFLAKE: return 1.15
		Icon.ARMORED: return 1.50
		_: return 1.0


func leave_board() -> void:
	falling = true
	if wind_effect:
		wind_effect.hide()
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
