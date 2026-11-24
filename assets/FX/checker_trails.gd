extends MeshInstance3D

const TRAIL_SHADER := preload("res://assets/FX/checker_trail.gdshader")
const SPACING := 0.032
const DIAMETER := Checker.RADIUS * 2.0
const TAIL_DIAMETERS := 3.8
const BOARD_TRAIL_DIAMETERS := 4.8
const BOARD_MARK := preload("res://assets/FX/checker_board_mark.gdshader")
const STOP_FADE := 0.29

class Track:
	var points: Array[Vector3] = []
	var head: Vector3
	var distance := 0.0
	var last_motion := 0.0
	var sample_index := 0
	var icon: Checker.Icon

var board_height := 0.0
var histories: Dictionary[int, Track] = {}
var trails := ImmediateMesh.new()
var surface := ShaderMaterial.new()
var board_material := ShaderMaterial.new()
var clock := 0.0
var camera_right := Vector3.RIGHT
var camera_up := Vector3.UP


func _ready() -> void:
	surface.shader = TRAIL_SHADER
	board_material.shader = BOARD_MARK

	mesh = trails
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func clear() -> void:
	histories.clear()
	trails.clear_surfaces()


func forget(piece: Checker) -> void:
	histories.erase(piece.get_instance_id())


func update_trails(delta: float, pieces: Array[Checker], emit: bool) -> void:
	clock += delta
	if emit:
		for piece in pieces:
			var id := piece.get_instance_id()
			if histories.has(id) or piece.falling or piece.is_in_motion():
				_record(id, piece)
	trails.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera:
		var axes := global_basis.inverse() * camera.global_basis
		camera_right = axes.x.normalized()
		camera_up = axes.y.normalized()
	var drawing := false
	for id: int in histories.keys():
		var track := histories[id]
		var idle := clock - track.last_motion
		if idle >= STOP_FADE:
			histories.erase(id)
			continue
		if track.points.size() < 2:
			continue
		if not drawing:
			trails.surface_begin(Mesh.PRIMITIVE_TRIANGLES, surface)
			drawing = true
		_draw(track, id, 1.0 - smoothstep(0.02, STOP_FADE, idle))
	if drawing:
		trails.surface_end()
		_draw_board_marks()


func _draw_board_marks() -> void:
	var drawing := false
	for id: int in histories:
		var track := histories[id]
		var retreat := smoothstep(0.015, STOP_FADE, clock - track.last_motion)
		var head_distance := track.sample_index * SPACING + track.distance
		var previous := track.head
		var previous_lag := 0.0
		var previous_side := Vector3.ZERO
		for i in track.points.size():
			var point := track.points[-1 - i]
			var lag := (i * SPACING + track.distance) / DIAMETER
			if lag > BOARD_TRAIL_DIAMETERS:
				point = previous.lerp(point, (BOARD_TRAIL_DIAMETERS - previous_lag) / (lag - previous_lag))
				lag = BOARD_TRAIL_DIAMETERS
			var across := Vector3.UP.cross(point - previous)
			if absf(point.y - board_height - Checker.HALF_HEIGHT) < 0.025 and absf(previous.y - board_height - Checker.HALF_HEIGHT) < 0.025 and across.length_squared() > 0.000001:
				if not drawing:
					trails.surface_begin(Mesh.PRIMITIVE_TRIANGLES, board_material)
					drawing = true
				var side := across.normalized() * 0.15
				if previous_side.is_zero_approx():
					previous_side = side
				var a := Vector3(previous.x, board_height + 0.005, previous.z)
				var b := Vector3(point.x, board_height + 0.005, point.z)
				var near_alpha := 1.0 - smoothstep(0.0, 1.0, previous_lag / BOARD_TRAIL_DIAMETERS + retreat)
				var far_alpha := 1.0 - smoothstep(0.0, 1.0, lag / BOARD_TRAIL_DIAMETERS + retreat)
				trails.surface_set_uv2(Vector2(track.icon, id % 113))
				for vertex in [0, 1, 2, 2, 1, 3]:
					var far_end: bool = vertex >= 2
					var sign_x: float = -1.0 if vertex % 2 == 0 else 1.0
					trails.surface_set_color(Color(1, 1, 1, far_alpha if far_end else near_alpha))
					var along := head_distance - (lag if far_end else previous_lag) * DIAMETER
					trails.surface_set_uv(Vector2(sign_x, along))
					trails.surface_add_vertex(b + side * sign_x if far_end else a + previous_side * sign_x)
				previous_side = side
			else:
				previous_side = Vector3.ZERO
			previous = point
			previous_lag = lag
			if lag >= BOARD_TRAIL_DIAMETERS:
				break
	if drawing:
		trails.surface_end()


func _record(id: int, piece: Checker) -> void:
	var point := to_local(piece.get_global_transform_interpolated().origin)
	if not histories.has(id):
		var fresh := Track.new()
		fresh.head = point
		fresh.points.append(point)
		fresh.last_motion = clock
		fresh.icon = piece.icon
		histories[id] = fresh
		return
	var track := histories[id]
	var segment := track.head.distance_to(point)
	if segment < 0.0001:
		return
	var along := SPACING - track.distance
	while along <= segment:
		track.points.append(track.head.lerp(point, along / segment))
		track.sample_index += 1
		if track.points.size() > ceili(BOARD_TRAIL_DIAMETERS * DIAMETER / SPACING) + 1:
			track.points.pop_front()
		along += SPACING
	track.distance = fposmod(track.distance + segment, SPACING)
	track.head = point
	track.last_motion = clock


func _draw(track: Track, id: int, opacity: float) -> void:
	var previous := track.head
	for i in track.points.size():
		var lag := (i * SPACING + track.distance) / DIAMETER
		var fade := (1.0 - smoothstep(0.5, TAIL_DIAMETERS, lag)) * opacity
		if fade < 0.006:
			break
		var p := track.points[-1 - i]
		var seed_value := float(posmod(hash(Vector2i(id, track.sample_index - i)), 100003))
		var jitter := Vector3(sin(seed_value), cos(seed_value * 1.7), sin(seed_value * 0.73))
		match track.icon:
			Checker.Icon.SNOWFLAKE:
				var center := p + jitter * Vector3(0.067, 0.042, 0.067)
				var axis := (Vector3.UP + jitter * 0.85).normalized()
				var length := (0.026 + 0.012 * jitter.z) * sqrt(fade)
				_crystal(center - axis * length, center + axis * length, length * 0.54,
					Color(0.48, 0.90, 1.18, fade))
			Checker.Icon.LIGHTNING:
				var bend := Vector3(sin(clock * 31.0 + seed_value), jitter.y, cos(clock * 28.0 + seed_value))
				var bolt := p + bend * (0.043 * smoothstep(0.0, 0.4, lag))
				_crystal(previous, bolt, 0.023 * fade, Color(0.19, 0.75, 1.8, fade))
				_crystal(previous, bolt, 0.009 * fade, Color(1.5, 1.9, 2.0, fade))
				if i % 2 == track.sample_index % 2:
					var spark := bolt + jitter * 0.092
					_crystal(spark, spark + jitter * 0.041, 0.007, Color(0.65, 1.4, 2.0, fade))
				previous = bolt
			Checker.Icon.EXPLOSIVE:
				var heat := smoothstep(0.33, 1.02, lag)
				var tint := Color(0.32, 0.30, 0.31).lerp(Color(1.9, 0.38, 0.035), heat)
				tint = tint.lerp(Color(2.2, 1.25, 0.17), heat * (0.35 + 0.25 * jitter.y))
				tint.a = fade * 0.87
				_puff(p + jitter * 0.033 + Vector3.UP * lag * 0.034,
					(0.077 + jitter.x * 0.018) * sqrt(fade), tint)
			_:
				_crystal(previous, p, 0.046 * fade, Color(0.95, 0.98, 1.0, 0.28 * fade))
				previous = p


func _crystal(a: Vector3, b: Vector3, radius: float, tint: Color) -> void:
	var axis := a.direction_to(b)
	if axis.is_zero_approx():
		return
	var side := axis.cross(Vector3.RIGHT if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var up := axis.cross(side)
	var mid := a.lerp(b, 0.44)
	var rim := [mid + side * radius, mid + up * radius, mid - side * radius, mid - up * radius]
	for k in 4:
		var shade := [1.0, 0.81, 0.57, 0.92][k] as float
		trails.surface_set_color(Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a))
		trails.surface_set_uv(Vector2(-1, -1))
		for vertex: Vector3 in [a, rim[k], rim[(k+1)%4], b, rim[(k+1)%4], rim[k]]:
			trails.surface_add_vertex(vertex)


func _puff(p: Vector3, radius: float, tint: Color) -> void:
	trails.surface_set_color(tint)
	for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2.DOWN]:
		trails.surface_set_uv(uv)
		trails.surface_add_vertex(p + (camera_right * (uv.x * 2.0 - 1.0) + camera_up * (uv.y * 2.0 - 1.0)) * radius)
