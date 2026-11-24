extends MultiMeshInstance3D

const IMPACT_PLANE := preload("res://assets/FX/checker_impact.tres")
const IMPACT_AGE := preload("res://assets/FX/checker_impact_age.tres")
const ATLAS := preload("res://assets/FX/checker_strike_atlas.svg")
const SPRITE_SHADER := preload("res://assets/FX/checker_strike.gdshader")
const MAX_SPRITES := 96

const ELEMENT_SHADER := preload("res://assets/FX/checker_element_hit.gdshader")
var element_planes := {}
var fragment_meshes := {}
var fragment_scale := Curve.new()

var material := ShaderMaterial.new()
var expires := PackedFloat64Array()
var active := 0
var clock := 0.0


func _ready() -> void:
	for icon in [Checker.Icon.LIGHTNING, Checker.Icon.SNOWFLAKE, Checker.Icon.EXPLOSIVE]:
		var surface := ShaderMaterial.new()
		surface.shader = ELEMENT_SHADER
		surface.set_shader_parameter("element", icon)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		plane.material = surface
		element_planes[icon] = plane
	fragment_scale.add_point(Vector2(0.0, 1.0))
	fragment_scale.add_point(Vector2(0.65, 0.85))
	fragment_scale.add_point(Vector2(1.0, 0.0))
	for icon in [Checker.Icon.NONE, Checker.Icon.LIGHTNING, Checker.Icon.SNOWFLAKE, Checker.Icon.EXPLOSIVE]:
		fragment_meshes[icon] = _fragment_mesh(icon)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("strike_atlas", ATLAS)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_SPRITES
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-4.0, -0.2, -4.0), Vector3(8.0, 1.0, 8.0))
	expires.resize(MAX_SPRITES)


func clear() -> void:
	for burst in get_children():
		burst.hide()
		burst.queue_free()
	active = 0
	multimesh.visible_instance_count = 0


func tick(delta: float) -> void:
	if active == 0:
		return
	clock += delta
	material.set_shader_parameter("effect_clock", fposmod(clock, 8.0))
	var index := 0
	while index < active:
		if expires[index] > clock:
			index += 1
			continue
		active -= 1
		if index < active:
			multimesh.set_instance_transform(index, multimesh.get_instance_transform(active))
			multimesh.set_instance_color(index, multimesh.get_instance_color(active))
			multimesh.set_instance_custom_data(index, multimesh.get_instance_custom_data(active))
			expires[index] = expires[active]
	if multimesh.visible_instance_count != active:
		multimesh.visible_instance_count = active


func _fragment_mesh(icon: Checker.Icon) -> PrimitiveMesh:
	var mote := SphereMesh.new()
	mote.radial_segments = 5
	mote.rings = 2
	mote.radius = 0.024
	mote.height = 0.12
	var tint := Color(1.0, 0.77, 0.36)
	if icon == Checker.Icon.LIGHTNING:
		mote.radius = 0.012
		mote.height = 0.17
		tint = Color(0.16, 0.76, 1.0)
	elif icon == Checker.Icon.EXPLOSIVE or icon == Checker.Icon.SNOWFLAKE:
		mote.height = 0.064
		tint = Color(0.48, 0.87, 1.0) if icon == Checker.Icon.SNOWFLAKE else Color(1.0, 0.38, 0.075)
	var surface := StandardMaterial3D.new()
	surface.albedo_color = tint
	surface.emission_enabled = true
	surface.emission = tint
	surface.emission_energy_multiplier = 0.30 if icon == Checker.Icon.NONE else 0.75
	mote.material = surface
	return mote


func impact(point: Vector3, direction: Vector3, intensity: float,
		icon := Checker.Icon.NONE, secondary := false) -> void:
	var strength := lerpf(0.72, 1.15, intensity)
	if secondary:
		strength *= 0.59
	var origin := point + Vector3.UP * (Checker.HALF_HEIGHT + 0.025)
	var ordinary := not element_planes.has(icon)
	var duration := 0.18 if not secondary else 0.13
	if ordinary:
		duration = 0.34 if not secondary else 0.24
	var flash := _emitter(origin, 1, duration)
	flash.mesh = element_planes.get(icon, IMPACT_PLANE)
	flash.color_ramp = IMPACT_AGE
	flash.scale = Vector3.ONE * strength
	var camera := get_viewport().get_camera_3d()
	if camera:
		var toward_camera := origin.direction_to(to_local(camera.global_position))
		flash.quaternion = Quaternion(Vector3.UP, toward_camera)
	flash.rotate_object_local(Vector3.UP, randf_range(-PI, PI))
	flash.emitting = true

	var mesh: Mesh = fragment_meshes.get(icon, fragment_meshes[Checker.Icon.NONE])
	# The fine layer travels a little farther through its longer lifetime.
	_fragments(origin, direction, mesh, strength, 4 if secondary else 9, 0.27, 1.0, ordinary)
	_fragments(origin, direction, mesh, strength, 6 if secondary else 15, 0.39, 0.46, ordinary)


func _emitter(origin: Vector3, count: int, duration: float) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = count
	burst.explosiveness = 1.0
	burst.lifetime = duration
	burst.gravity = Vector3.ZERO
	burst.local_coords = true
	burst.position = origin
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(burst)
	burst.finished.connect(burst.queue_free)
	return burst


func _fragments(origin: Vector3, hit_direction: Vector3, mesh: Mesh, strength: float,
		count: int, duration: float, size_factor: float, ordinary: bool) -> void:
	var burst := _emitter(origin, count, duration)
	burst.mesh = mesh
	burst.direction = (Vector3.UP + hit_direction.normalized() * 0.3).normalized()
	burst.spread = 113.0
	if ordinary:
		# Larger chips rise first, fine sparks carry the impact direction.
		var lift := Vector3.UP * (1.35 if size_factor >= 1.0 else 0.48)
		burst.direction = (lift + hit_direction.normalized()).normalized()
		burst.spread = 44.0 if size_factor >= 1.0 else 31.0
	burst.gravity = Vector3.DOWN * (3.2 if ordinary else 1.85)
	burst.initial_velocity_min = 1.0 * strength
	burst.initial_velocity_max = 1.65 * strength
	burst.particle_flag_align_y = true
	burst.scale_amount_min = strength * size_factor * 0.78
	burst.scale_amount_max = strength * size_factor * 1.25
	burst.scale_amount_curve = fragment_scale
	burst.emitting = true


func lightning_arc(from: Vector3, to: Vector3) -> void:
	var offset := to - from
	if Vector2(offset.x, offset.z).length_squared() < 0.001:
		return
	var direction := offset.normalized()
	var length := offset.length()
	var width := clampf(0.24 + length * 0.11, 0.32, 0.54)
	_sprite(from.lerp(to, 0.5), direction, Vector2(length * 1.15, width),
		Color(0.25, 0.72, 1.0, 0.97), 0.23, false)
	_sprite(to, Vector3.RIGHT, Vector2(0.30, 0.30), Color(0.59, 0.85, 1.0, 0.91), 0.18, true)


func _sprite(point: Vector3, direction: Vector3, size: Vector2, color: Color,
		lifetime: float, glow: bool) -> void:
	if active == MAX_SPRITES:
		return
	var across := direction.cross(Vector3.UP).normalized()
	var up := across.cross(direction)
	var axes := Basis(direction * size.x, up, across * size.y)
	multimesh.set_instance_transform(active, Transform3D(axes, point))
	multimesh.set_instance_color(active, color)
	multimesh.set_instance_custom_data(active, Color(fposmod(clock, 8.0), lifetime, float(glow), 0.0))
	expires[active] = clock + lifetime
	active += 1
	multimesh.visible_instance_count = active
