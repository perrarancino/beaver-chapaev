class_name Checker
extends Node3D

const RADIUS := 0.155
const HALF_HEIGHT := 0.068
const PIXELS_PER_UNIT := 100.0
const SLIDE_GRAVITY := 9.8
const TABLE_FRICTION := 5.4
const KNOCKOUT_BLINK_DURATION := 1.0
const KNOCKOUT_FADE := 0.28
const KNOCKOUT_CLOUD := preload("res://assets/FX/checker_knockout_cloud.gdshader")
const NORMAL_FRICTION := 0.24
const ICE_FRICTION := 0.070
const NORMAL_DAMP := 0.10
const NORMAL_BOUNCE := 0.10
const RUBBER_BOUNCE := 0.74
const ARMORED_MASS := 2.5
const SURFACE_SHADER := preload("res://assets/FX/checker_surface.gdshader")
const SURFACE_RIM_SHADER := preload("res://assets/FX/checker_surface_rim.gdshader")
const TELEPORT_DROP_TIME := 0.36
const TELEPORT_DROP_HEIGHT := 0.57
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
const ORDINARY_ICON_RADIUS := ICON_RADIUS * 0.70
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
var slot := -1
var incoming_velocity := Vector3.ZERO
var fuse := -1.0
var exploded := false
var fuse_origin := Vector3.ZERO
var lightning_used := false
var ghost_spent := false
var solid_materials: Dictionary[MeshInstance3D, Material] = {}
var glued := false:
	set(value):
		glued = value
		if glued:
			if stretch_tween and stretch_tween.is_running():
				stretch_tween.kill()
			stretch_amount = 0.0
			_impact_basis = Basis.IDENTITY
			_update_visual_pose()
var float_used := false
var wind_effect: MeshInstance3D
var wind_lift := 0.0
var wind_transition: Tween
var hovering := false:
	set(value):
		if hovering == value:
			return
		hovering = value
		if wind_effect:
			if wind_transition and wind_transition.is_running():
				wind_transition.kill()
			wind_transition = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			wind_transition.tween_method(_set_wind_lift, wind_lift, float(hovering), 0.20)
var hover_started_turn := -1
var rail_boost_used := false
var zone_hits := 0
var zone_speed_pending := false
var zone_power := 1.0
var size_scale := 1.0
var _visual_size := 1.0
var _resize_tween: Tween
var _teleport_drop_age := -1.0
var _teleport_ground_y := 0.0
var _teleport_angles := Vector3.ZERO
var _teleport_squash := 0.0
var _teleport_rebound := 0.0
var _teleport_settle: Tween
var _teleport_collision_layer := 0
var _teleport_collision_mask := 0
var fall_velocity := Vector3.ZERO
var _fall_spin := 0.0
var _sliding_on_table := false
var _cloud_material: ShaderMaterial
var _fall_settled := false
var _knockout_time := 0.0
var stretch_tween: Tween
var stretch_amount := 0.0
var _impact_basis := Basis.IDENTITY
@onready var planar_body: RigidBody2D = $PlanarBody
@onready var planar_shape: CollisionShape2D = $PlanarBody/CollisionShape2D
@onready var contact_material: PhysicsMaterial = planar_body.physics_material_override
@onready var turn_aura := get_node_or_null("TurnAura") as MeshInstance3D
@onready var visual: Node3D = $Visual
var mass: float:
	get: return planar_body.mass
var radius: float:
	get: return RADIUS * size_scale
var teleport_dropping: bool:
	get: return _teleport_drop_age >= 0.0
var half_height: float:
	get: return HALF_HEIGHT * size_scale
var linear_velocity: Vector3:
	get: return _board_basis() * from_plane(planar_body.linear_velocity)


func _ready() -> void:
	planar_shape.shape = planar_shape.shape.duplicate()
	place_on_board(position, rotation.y)
	planar_body.body_entered.connect(_report_contact)
	if is_intangible():
		planar_body.collision_layer = 0
		planar_body.collision_mask = 0
	_refresh_contact_properties()
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


func set_zone_power(multiplier: float) -> void:
	if zone_power == multiplier:
		return
	zone_power = multiplier
	_refresh_contact_properties()


func _refresh_contact_properties() -> void:
	planar_body.mass = ARMORED_MASS * zone_power if icon == Icon.ARMORED else 1.0
	planar_body.linear_damp = 0.04 / zone_power if icon == Icon.SNOWFLAKE else NORMAL_DAMP
	contact_material.friction = ICE_FRICTION / zone_power if icon == Icon.SNOWFLAKE else NORMAL_FRICTION
	match icon:
		Icon.RUBBER: contact_material.bounce = minf(0.96, RUBBER_BOUNCE * zone_power)
		Icon.ARMORED: contact_material.bounce = 0.0
		_: contact_material.bounce = NORMAL_BOUNCE


func resize_in_zone(multiplier: float) -> void:
	if size_scale == multiplier:
		return
	position.y += HALF_HEIGHT * (multiplier - size_scale)
	size_scale = multiplier
	(planar_shape.shape as CircleShape2D).radius = radius * PIXELS_PER_UNIT
	if _resize_tween and _resize_tween.is_running():
		_resize_tween.kill()
	_update_visual_pose()
	_resize_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_resize_tween.tween_method(func(value: float) -> void:
		_visual_size = value
		_update_visual_pose(), _visual_size, multiplier, 0.18)


func apply_slide_friction(delta: float, stopping_distance := INF) -> void:
	if planar_body.sleeping:
		return
	var braking := maxf(contact_material.friction * SLIDE_GRAVITY,
		linear_velocity.length_squared() / (2.0 * stopping_distance))
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


func begin_teleport_drop() -> void:
	stop_motion()
	incoming_velocity = Vector3.ZERO
	planar_body.freeze = true
	_teleport_collision_layer = planar_body.collision_layer
	_teleport_collision_mask = planar_body.collision_mask
	planar_body.collision_layer = 0
	planar_body.collision_mask = 0
	_teleport_ground_y = position.y
	_teleport_drop_age = 0.0
	position.y += TELEPORT_DROP_HEIGHT
	if stretch_tween and stretch_tween.is_running():
		stretch_tween.kill()
	if _teleport_settle and _teleport_settle.is_running():
		_teleport_settle.kill()
	stretch_amount = 0.0
	_impact_basis = Basis.IDENTITY
	_teleport_squash = 0.0
	_teleport_rebound = 0.0
	_teleport_angles = Vector3(0.26, -0.38, -0.19)
	_update_visual_pose()
	reset_physics_interpolation()


func advance_teleport_drop(delta: float) -> bool:
	_teleport_drop_age += delta
	var progress := clampf(_teleport_drop_age / TELEPORT_DROP_TIME, 0.0, 1.0)
	position.y = _teleport_ground_y + TELEPORT_DROP_HEIGHT * (1.0 - progress * progress)
	_teleport_angles = Vector3(0.26, -0.38, -0.19) * (1.0 - progress)
	_update_visual_pose()
	return progress >= 1.0


func finish_teleport_drop() -> void:
	_teleport_drop_age = -1.0
	planar_body.freeze = false
	planar_body.collision_layer = _teleport_collision_layer
	planar_body.collision_mask = _teleport_collision_mask
	stop_motion()
	_set_teleport_settle(0.0)
	_teleport_settle = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_teleport_settle.tween_method(_set_teleport_settle, 0.0, 1.0, 0.23)


func _set_teleport_settle(progress: float) -> void:
	_teleport_squash = 0.23 * (1.0 - smoothstep(0.0, 0.34, progress))
	_teleport_rebound = 0.042 * sin(PI * smoothstep(0.20, 0.94, progress))
	_teleport_angles = Vector3(-0.13, 0.0, 0.095) * sin(progress * TAU) * (1.0 - progress)
	_update_visual_pose()


func show_turn_aura(active: bool) -> void:
	if turn_aura:
		turn_aura.visible = active and not falling


func set_turn_aura_selected(active: bool) -> void:
	if turn_aura:
		turn_aura.set_instance_shader_parameter("is_selected", active)


func stretch_on_impact(world_direction: Vector3, strength: float) -> void:
	if glued:
		return
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
	_impact_basis = alignment * scale_along_impact * alignment.transposed()
	_update_visual_pose()


func _update_visual_pose() -> void:
	var squash := Vector3(1.0 + _teleport_squash * 0.23, 1.0 - _teleport_squash, 1.0 + _teleport_squash * 0.23)
	visual.basis = (Basis.from_euler(_teleport_angles) * _impact_basis).scaled(squash * _visual_size)
	var base_shift := HALF_HEIGHT * (_visual_size * squash.y - size_scale) + _teleport_rebound
	visual.position.y = base_shift
	if turn_aura:
		turn_aura.scale = Vector3.ONE * _visual_size
		turn_aura.position.y = -0.052 * _visual_size + base_shift


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
	wind_effect.custom_aabb = AABB(Vector3(-0.47, -0.51, -0.47), Vector3(0.94, 0.74, 0.94))
	wind_effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wind_effect.position.y = 0.055
	add_child(wind_effect)


func _set_wind_lift(amount: float) -> void:
	wind_lift = amount
	wind_effect.set_instance_shader_parameter("hover_amount", amount)


func _build_emblem() -> void:
	var model := (ICON_MODELS[icon] as PackedScene).instantiate() as Node3D
	var emblem := model.get_child(0) as MeshInstance3D
	var bounds := emblem.get_aabb()
	var center := bounds.get_center()
	var radius_squared := 0.0
	var vertices: PackedVector3Array = emblem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		radius_squared = maxf(radius_squared, Vector2(vertex.x - center.x, vertex.y - center.y).length_squared())
	var face_radius := ORDINARY_ICON_RADIUS if icon == Icon.NONE else ICON_RADIUS
	var face_scale := face_radius / sqrt(radius_squared)
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
	return teleport_dropping or (icon == Icon.GHOST and not ghost_spent)


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
		Icon.SNOWFLAKE: return 1.0 + 0.15 * zone_power
		Icon.ARMORED: return 1.0 + 0.50 * zone_power
		_: return 1.0


func leave_board(outward: Vector3) -> void:
	falling = true
	visual.hide()
	show_turn_aura(false)
	if wind_effect:
		wind_effect.hide()
	fall_velocity = linear_velocity
	# A slow piece still tips clear of the raised board after its center crosses the edge.
	fall_velocity += outward * maxf(1.18 - fall_velocity.dot(outward), 0.0)
	_fall_spin = clampf(-planar_body.angular_velocity, -20.0, 20.0)
	stop_motion()
	planar_body.freeze = true
	planar_body.collision_layer = 0
	planar_body.collision_mask = 0


func animate_fall(delta: float, table_y: float, table_radius: float, floor_y: float, room: Rect2) -> bool:
	if not _fall_settled:
		_advance_fall(delta, table_y, table_radius, floor_y, room)
	return _update_knockout(delta / maxf(Engine.time_scale, 0.001))


func _advance_fall(delta: float, table_y: float, table_radius: float, floor_y: float, room: Rect2) -> void:

	var start := global_position
	var tabletop := table_y + half_height
	var floor := floor_y + half_height
	var radius_squared := table_radius * table_radius
	if not _sliding_on_table:
		fall_velocity.y -= SLIDE_GRAVITY * delta
	var point := start + fall_velocity * delta
	if _sliding_on_table:
		_sliding_on_table = Vector2(point.x, point.z).length_squared() <= radius_squared
		if _sliding_on_table:
			fall_velocity = fall_velocity.move_toward(Vector3.ZERO, TABLE_FRICTION * delta)
			_fall_spin = move_toward(_fall_spin, 0.0, 20.0 * delta)
			if fall_velocity.is_zero_approx() and is_zero_approx(_fall_spin):
				_fall_settled = true
	elif start.y >= tabletop and point.y < tabletop:
		var contact := start.lerp(point, inverse_lerp(start.y, point.y, tabletop))
		if Vector2(contact.x, contact.z).length_squared() <= radius_squared:
			_sliding_on_table = true
			fall_velocity = fall_velocity.slide(Vector3.UP) * 0.84
			_fall_spin *= 0.62
			point = contact
	var wall_x := clampf(point.x, room.position.x + radius, room.end.x - radius)
	var wall_z := clampf(point.z, room.position.y + radius, room.end.y - radius)
	if wall_x != point.x:
		point.x = wall_x
		fall_velocity.x *= -0.25
	if wall_z != point.z:
		point.z = wall_z
		fall_velocity.z *= -0.25
	if point.y <= floor:
		point.y = floor
		_fall_settled = true
	global_position = point
	rotation.y += _fall_spin * delta


func _update_knockout(delta: float) -> bool:
	_knockout_time += delta
	if _knockout_time < KNOCKOUT_BLINK_DURATION:
		var t := _knockout_time / KNOCKOUT_BLINK_DURATION
		# The blink rate rises continuously from two to eight cycles per second.
		var cycles := 2.0 * t + 3.0 * t * t
		visual.visible = fmod(cycles, 1.0) >= 0.5
		return false

	if not _cloud_material:
		visual.hide()
		_fall_settled = true
		_spawn_knockout_cloud()
	var progress := clampf((_knockout_time - KNOCKOUT_BLINK_DURATION) / KNOCKOUT_FADE, 0.0, 1.0)
	_cloud_material.set_shader_parameter("progress", progress)
	return progress >= 1.0


func _spawn_knockout_cloud() -> void:
	var cloud := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.12, 1.12)
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = KNOCKOUT_CLOUD
	cloud.mesh = quad
	cloud.material_override = _cloud_material
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.position.y = 0.14
	add_child(cloud)
