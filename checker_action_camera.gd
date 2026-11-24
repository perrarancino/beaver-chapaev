extends RefCounted

enum Mode { IDLE, HIT, FALL, RETURN }
var mode := Mode.IDLE
var skipped := false
const HIT_DURATION := 2.0
const RETURN_DURATION := 0.26
const CLOSEUP_DURATION := HIT_DURATION - RETURN_DURATION
const ORBIT_ANGLE := PI / 18.0
var camera: Camera3D
var home: Transform3D
var start: Transform3D
var focus: Vector3
var offset: Vector3
var fall_board_center: Vector3
var falling_pieces: Array[Checker] = []
const FALL_SPEED := 0.34
const FALL_FRAME_TIME := 0.80
const NEAR_DISTANCE := Checker.RADIUS * 5.0
var waiting_falls: Array[Checker] = []
var elapsed := 0.0
var original_speed := 1.0


func new_shot() -> void:
	restore()
	skipped = false


func _begin(next_mode: Mode, speed: float) -> void:
	if mode == Mode.IDLE:
		home = camera.global_transform
		original_speed = Engine.time_scale
	start = camera.global_transform
	mode = next_mode
	elapsed = 0.0
	Engine.time_scale = original_speed * speed


func hit(point: Vector3) -> void:
	if skipped or mode == Mode.FALL:
		return
	_begin(Mode.HIT, 0.18)
	focus = point
	var side := (home.origin - point).slide(Vector3.UP).normalized()
	offset = side * 1.10 + Vector3.UP * 0.91


func fall(piece: Checker, board_center: Vector3) -> void:
	if skipped or piece in falling_pieces or piece in waiting_falls:
		return
	waiting_falls.append(piece)
	fall_board_center = board_center
	if mode != Mode.FALL:
		_next_fall_frame()


func waiting_for_camera(piece: Checker) -> bool:
	return piece in waiting_falls


func _near_group(piece: Checker) -> bool:
	for member in falling_pieces:
		if piece.global_position.distance_to(member.global_position) > NEAR_DISTANCE:
			return false
	return true


func _next_fall_frame() -> void:
	falling_pieces.clear()
	if waiting_falls.is_empty():
		_return_home()
		return
	falling_pieces.append(waiting_falls.pop_front())
	_begin(Mode.FALL, FALL_SPEED)


func _frame_fall() -> void:
	# Admit simultaneous neighbours early enough to give every piece screen time.
	if elapsed < 0.10:
		for i in range(waiting_falls.size() - 1, -1, -1):
			var candidate := waiting_falls[i]
			if _near_group(candidate):
				falling_pieces.append(candidate)
				waiting_falls.remove_at(i)
	var bounds := AABB(falling_pieces[0].global_position, Vector3.ZERO)
	for i in range(falling_pieces.size() - 1, 0, -1):
		var member := falling_pieces[i]
		if not _near_group(member):
			waiting_falls.append(member)
			falling_pieces.remove_at(i)
			continue
		bounds = bounds.expand(member.global_position)
	focus = bounds.get_center()
	var side := (focus - fall_board_center).slide(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3.BACK
	# A medium shot includes the edge for isolated falls. Neighbours share a tighter shot.
	var distance := 2.35 if falling_pieces.size() == 1 else 1.55
	if falling_pieces.size() > 1:
		var size := camera.get_viewport().get_visible_rect().size
		var aspect := size.x / maxf(size.y, 1.0)
		var factor := aspect if camera.keep_aspect == Camera3D.KEEP_HEIGHT else 1.0 / aspect
		var half_angle := atan(tan(deg_to_rad(camera.fov * 0.5)) * minf(factor, 1.0))
		distance = maxf(distance, (bounds.size.length() * 0.5 + Checker.RADIUS) / sin(half_angle))
	offset = (side + Vector3.UP * 0.45).normalized() * distance


func update(delta: float) -> void:
	if mode == Mode.IDLE:
		return
	elapsed += delta / maxf(Engine.time_scale, 0.001)
	if mode == Mode.RETURN:
		camera.global_transform = start.interpolate_with(home, smoothstep(0.0, RETURN_DURATION, elapsed))
		if elapsed >= RETURN_DURATION:
			restore()
		return
	if mode == Mode.FALL:
		if elapsed >= FALL_FRAME_TIME:
			_next_fall_frame()
			if mode != Mode.FALL:
				return
		_frame_fall()
	var view_offset := offset
	if mode == Mode.HIT:
		var orbit := smoothstep(0.105, CLOSEUP_DURATION, elapsed)
		view_offset = offset.rotated(Vector3.UP, ORBIT_ANGLE * orbit)
	var view := Transform3D(Basis.IDENTITY, focus + view_offset).looking_at(focus, Vector3.UP)
	var pose := start.interpolate_with(view, smoothstep(0.0, 0.105 if mode == Mode.HIT else 0.055, elapsed))
	if mode == Mode.HIT:
		var shake := 0.049 * exp(-elapsed * 11.0) * smoothstep(0.0, 0.05, elapsed)
		pose.origin += pose.basis.x * sin(elapsed * 99.0) * shake
		pose.origin += pose.basis.y * sin(elapsed * 77.0) * shake * 0.7
	camera.global_transform = pose
	if mode == Mode.HIT and elapsed >= CLOSEUP_DURATION:
		var remainder := elapsed - CLOSEUP_DURATION
		_return_home()
		update(remainder * Engine.time_scale)


func _return_home() -> void:
	_begin(Mode.RETURN, 1.0)
	falling_pieces.clear()


func skip() -> void:
	skipped = true
	restore()


func restore() -> void:
	if mode == Mode.IDLE:
		return
	Engine.time_scale = original_speed
	if is_instance_valid(camera):
		camera.global_transform = home
		camera.reset_physics_interpolation()
	falling_pieces.clear()
	waiting_falls.clear()
	mode = Mode.IDLE
