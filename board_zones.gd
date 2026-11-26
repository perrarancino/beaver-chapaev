extends Node3D

enum Kind { TELEPORT, SPEED, POWER, SHRINK, GROW }

const SPEED_MULTIPLIER := 1.5
const POWER_MULTIPLIER := 1.35
const SHRINK_SCALE := 0.75
const GROW_SCALE := 1.30
const SHADER := preload("res://assets/FX/board_zone.gdshader")
const FLASH_SHADER := preload("res://assets/FX/board_zone_flash.gdshader")
const NOISE_TEXTURE := preload("res://assets/FX/board_zone_noise.png")
const OUTLINE_SEGMENTS := 64
const COLORS := [
	Color("827dff"), Color("ffb347"), Color("f078d7"), Color("56e3dc"), Color("a3db5d"),
]

class Zone extends MeshInstance3D:
	var kind: Kind
	var center: Vector2
	var radii: Vector2
	var shape_phase: float
	var ink: ShaderMaterial
	var _pulse: Tween

	func boundary_radius(angle: float) -> float:
		return 1.0 + 0.13 * sin(3.0 * angle + shape_phase) + 0.07 * cos(5.0 * angle - shape_phase * 1.7)

	func contains(point: Vector2) -> bool:
		var p := (point - center) / radii
		if p.length_squared() > 1.21 * 1.21:
			return false
		var boundary := boundary_radius(p.angle())
		return p.length_squared() <= boundary * boundary

	func entry_fraction(from: Vector2, to: Vector2) -> float:
		if contains(from):
			return 0.0
		if from.is_equal_approx(to):
			return INF
		var closest := Geometry2D.get_closest_point_to_segment(center, from, to)
		var extent := maxf(radii.x, radii.y) * 1.21
		if closest.distance_squared_to(center) > extent * extent:
			return INF
		var steps := maxi(1, ceili(from.distance_to(to) / 0.055))
		for step in range(1, steps + 1):
			var fraction := float(step) / steps
			if not contains(from.lerp(to, fraction)):
				continue
			var outside := float(step - 1) / steps
			for _i in 5:
				var midpoint := (outside + fraction) * 0.5
				if contains(from.lerp(to, midpoint)):
					fraction = midpoint
				else:
					outside = midpoint
			return fraction
		return INF

	func pulse() -> void:
		if _pulse and _pulse.is_running():
			_pulse.kill()
		_pulse = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_pulse.tween_method(func(value: float) -> void:
			ink.set_shader_parameter("impact", value), 1.0, 0.0, 0.62)


var fields: Array[Zone] = []
static var _flash_mesh: PlaneMesh


func at(point: Vector3) -> Zone:
	for zone in fields:
		if zone.contains(Vector2(point.x, point.z)):
			return zone
	return null


func first_entry(from: Vector3, to: Vector3, visited: int) -> Zone:
	var first: Zone
	var earliest := INF
	for zone in fields:
		if visited & (1 << zone.kind):
			continue
		var entry := zone.entry_fraction(Vector2(from.x, from.z), Vector2(to.x, to.z))
		if entry < earliest:
			first = zone
			earliest = entry
	return first


func populate(rng: RandomNumberGenerator, table_top: float, starting_positions: PackedVector2Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	fields.clear()
	var kinds: Array[Kind] = [Kind.TELEPORT, Kind.SPEED, Kind.POWER, Kind.SHRINK, Kind.GROW]
	var centers := _pick_positions(rng, starting_positions, kinds.size())
	for i in Kind.size():
		var zone := Zone.new()
		zone.kind = kinds.pop_at(rng.randi_range(0, kinds.size() - 1))
		zone.center = centers[i]
		zone.radii = Vector2(rng.randf_range(0.43, 0.51), rng.randf_range(0.40, 0.50))
		zone.shape_phase = rng.randf_range(0.0, TAU)
		zone.name = Kind.keys()[zone.kind].capitalize()
		zone.position = Vector3(zone.center.x, table_top + 0.008, zone.center.y)
		zone.ink = _style(zone.kind, zone.radii, zone.shape_phase)
		zone.ink.set_shader_parameter("reveal", 0.0)
		_mount(zone, _outline_mesh(zone), zone.ink)
		fields.append(zone)
		var reveal := zone.create_tween().set_trans(Tween.TRANS_SINE)
		reveal.tween_method(func(amount: float) -> void:
			zone.ink.set_shader_parameter("reveal", amount), 0.0, 1.0, 0.64).set_delay(i * 0.07)


func _pick_positions(rng: RandomNumberGenerator, starting_positions: PackedVector2Array,
		count: int) -> PackedVector2Array:
	# Keep the five shapes apart and favor layouts whose centers stay visible at the opening.
	var best := PackedVector2Array()
	var best_cost := INF
	for _attempt in 30:
		var start_angle := rng.randf_range(0.0, TAU)
		var centers := PackedVector2Array()
		var cost := 0.0
		for i in count:
			var angle := start_angle + TAU * i / count + rng.randf_range(-0.11, 0.11)
			var center := Vector2.from_angle(angle) * rng.randf_range(1.38, 1.87)
			centers.append(center)
			for position in starting_positions:
				var overlap := maxf(0.0, 0.68 - center.distance_to(position))
				cost += overlap * overlap
		if cost < best_cost:
			best_cost = cost
			best = centers
	return best


func flash(point: Vector3, kind: Kind, strength := 1.0) -> void:
	var effect := MeshInstance3D.new()
	var ink := ShaderMaterial.new()
	ink.shader = FLASH_SHADER
	ink.set_shader_parameter("noise_texture", NOISE_TEXTURE)
	ink.set_shader_parameter("tint", COLORS[kind])
	ink.set_shader_parameter("strength", strength)
	effect.position = point
	if _flash_mesh == null:
		_flash_mesh = PlaneMesh.new()
		_flash_mesh.size = Vector2.ONE * (0.37 * 2.8)
	_mount(effect, _flash_mesh, ink)
	var tween := effect.create_tween()
	tween.tween_method(func(progress: float) -> void:
		ink.set_shader_parameter("progress", progress), 0.0, 1.0, 0.57)
	tween.tween_callback(effect.queue_free)


func _style(kind: Kind, radii: Vector2, shape_phase: float) -> ShaderMaterial:
	var ink := ShaderMaterial.new()
	ink.shader = SHADER
	ink.set_shader_parameter("noise_texture", NOISE_TEXTURE)
	ink.set_shader_parameter("kind", int(kind))
	ink.set_shader_parameter("tint", COLORS[kind])
	ink.set_shader_parameter("radii", radii)
	ink.set_shader_parameter("shape_phase", shape_phase)
	ink.set_shader_parameter("stream_axis", Vector2.from_angle(shape_phase * 0.52))
	return ink


func _outline_mesh(zone: Zone) -> ArrayMesh:
	# UV2 runs from the center to the gameplay boundary for shading the wet rim.
	var points := PackedVector3Array([Vector3.ZERO])
	var radial_uv := PackedVector2Array([Vector2.ZERO])
	var triangles := PackedInt32Array()
	for i in OUTLINE_SEGMENTS:
		var angle := TAU * i / OUTLINE_SEGMENTS
		var point := Vector2.from_angle(angle) * zone.boundary_radius(angle) * zone.radii
		points.append(Vector3(point.x, 0.0, point.y))
		radial_uv.append(Vector2(1.0, 0.0))
		triangles.append(0)
		triangles.append(1 + i)
		triangles.append(1 + ((i + 1) % OUTLINE_SEGMENTS))
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = points
	surface[Mesh.ARRAY_TEX_UV2] = radial_uv
	surface[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


func _mount(mark: MeshInstance3D, mesh: Mesh, ink: ShaderMaterial) -> void:
	mark.mesh = mesh
	mark.material_override = ink
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
