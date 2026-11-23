extends MeshInstance3D

const TRAIL_SHADER := preload("res://assets/FX/checker_trail.gdshader")
const TRAIL_TEXTURE := preload("res://assets/FX/checker_trail.png")
const IceTrace := preload("res://assets/FX/checker_ice_trace.gd")
const NORMAL_LIFETIME := 0.22
const SAMPLE_SPACING := 0.055
const MAX_SAMPLES := 18
const MIN_SPEED_SQUARED := 0.24 * 0.24

var ribbons := ImmediateMesh.new()
var trail_material := ShaderMaterial.new()
var ice_trace := IceTrace.new()
var histories: Dictionary[int, Array] = {}
var clock := 0.0


func _ready() -> void:
	trail_material.shader = TRAIL_SHADER
	trail_material.set_shader_parameter("trail_texture", TRAIL_TEXTURE)
	mesh = ribbons
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(ice_trace)


func clear() -> void:
	histories.clear()
	ribbons.clear_surfaces()
	ice_trace.clear()


func forget(piece: Checker) -> void:
	histories.erase(piece.get_instance_id())
	ice_trace.end_stroke(piece)


func update_trails(delta: float, pieces: Array[Checker], emit: bool) -> void:
	clock += delta
	ice_trace.tick(delta)
	if emit:
		for piece in pieces:
			var moving := not piece.falling and piece.planar_body.linear_velocity.length_squared() > (
				MIN_SPEED_SQUARED * Checker.PIXELS_PER_UNIT * Checker.PIXELS_PER_UNIT)
			if piece.icon == Checker.Icon.SNOWFLAKE:
				if moving:
					ice_trace.record(piece)
				else:
					ice_trace.end_stroke(piece)
			elif moving:
				_record(piece)
	else:
		ice_trace.end_strokes()
	if histories.is_empty() and ribbons.get_surface_count() == 0:
		return
	ribbons.clear_surfaces()
	var drawing := false
	for id: int in histories.keys():
		var history: Array = histories[id]
		while not history.is_empty() and clock - history.front().w >= NORMAL_LIFETIME:
			history.pop_front()
		if history.is_empty():
			histories.erase(id)
			continue
		if history.size() < 2:
			continue
		if not drawing:
			ribbons.surface_begin(Mesh.PRIMITIVE_TRIANGLES, trail_material)
			drawing = true
		_draw_ribbon(history)
	if drawing:
		ribbons.surface_end()


func _record(piece: Checker) -> void:
	var id := piece.get_instance_id()
	if not histories.has(id):
		var samples: Array[Vector4] = []
		histories[id] = samples
	var history: Array = histories[id]
	var point := to_local(piece.get_global_transform_interpolated().origin)
	point.y -= Checker.HALF_HEIGHT * 0.62
	if not history.is_empty() and point.distance_squared_to(_position(history.back())) < SAMPLE_SPACING * SAMPLE_SPACING:
		return
	history.append(Vector4(point.x, point.y, point.z, clock))
	if history.size() > MAX_SAMPLES:
		history.pop_front()


func _draw_ribbon(history: Array[Vector4]) -> void:
	var color := Color(0.97, 0.98, 1.0, 0.34)
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	var previous_u := 0.0
	var previous_alpha := 0.0
	var tail_time := history[0].w
	var duration := maxf(history[history.size() - 1].w - tail_time, 0.001)
	for i in history.size():
		var sample: Vector4 = history[i]
		var point := _position(sample)
		var before := _position(history[maxi(0, i - 1)])
		var after := _position(history[mini(i + 1, history.size() - 1)])
		var tangent := after - before
		if tangent.length_squared() < 0.00001:
			tangent = point - before
		var age := clampf((clock - sample.w) / NORMAL_LIFETIME, 0.0, 1.0)
		var across := Vector3.UP.cross(tangent).normalized() * 0.085
		var left := point - across
		var right := point + across
		var u := clampf((sample.w - tail_time) / duration, 0.0, 1.0)
		var alpha := 1.0 - smoothstep(0.12, 1.0, age)
		if i > 0:
			_vertex(previous_left, previous_u, 0.0, color, previous_alpha)
			_vertex(previous_right, previous_u, 1.0, color, previous_alpha)
			_vertex(left, u, 0.0, color, alpha)
			_vertex(left, u, 0.0, color, alpha)
			_vertex(previous_right, previous_u, 1.0, color, previous_alpha)
			_vertex(right, u, 1.0, color, alpha)
		previous_left = left
		previous_right = right
		previous_u = u
		previous_alpha = alpha


func _vertex(point: Vector3, progress: float, side: float, color: Color, alpha: float) -> void:
	color.a *= alpha
	ribbons.surface_set_color(color)
	ribbons.surface_set_uv(Vector2(progress, side))
	ribbons.surface_add_vertex(point)


func _position(sample: Vector4) -> Vector3:
	return Vector3(sample.x, sample.y, sample.z)
