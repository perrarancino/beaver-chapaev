@tool
extends Node3D

signal returned_to_stance

const BEAVER_MATERIAL := "res://assets/beaver/beaver_material.tres"
const BLUE_BEAVER_MODEL := "res://assets/beaver/blue/beaver.glb"
const BLUE_BEAVER_MATERIAL := "res://assets/beaver/blue/beaver_material.tres"
const CHEF_BEAVER_MODEL := "res://assets/beaver/chef/beaver.glb"
const CHEF_BEAVER_MATERIAL := "res://assets/beaver/chef/beaver_material.tres"
const EYE_SHADER := preload("res://assets/beaver/beaver_eye.gdshader")
const IDLE_PAW_DIRECTION := Vector3(0, -0.985, 0.173)
const SHOULDER_OFFSET := 1.31
const MAX_ARM_EXTENSION := 0.25

const STEP_SPACING := 1.12
const STEP_HEIGHT := 0.22
const WALK_SPEED := 4.8
# Centers of the nose surface in Head bone space for each opponent.
const NOSE_POINTS := [
	Vector3(0.0703, 0.3266, 0.5886),
	Vector3(0.0728, 0.3105, 0.4697),
	Vector3(0.0883, 0.3979, 0.5348),
]
const NOSE_PULL_LIMIT := 0.55

class ShotSetup:
	var stance: Vector3
	var arm: int
	var cost: float

enum Opponent { ORIGINAL, BLUE, CHEF }

enum Joint { UPPER, LOWER, END, FINGERTIP }

@onready var _voice = $Voice

var addressing_player := false

var _model: Node3D
var _rig: Skeleton3D
var _body: MeshInstance3D
var opponent := Opponent.ORIGINAL

var _arms: Array[PackedInt32Array] = []
var _shoulders := PackedInt32Array()
var _legs: Array[PackedInt32Array] = []
var _foot_rest: Array[Transform3D] = []
var _next_foot := 0
var _hips: int
var _waist: int
var _waist_rest_inverse: Transform3D
var _face: ShaderMaterial
var _jaw: int
var _jaw_rest_rotation: Quaternion
var _jaw_axis: Vector3
var _eyes: Array[MeshInstance3D] = []
var _eye_gaze := Vector2.ZERO
var _cursor_head_turn := Vector2.ZERO
var _next_blink := 1.35
var _mouth := 0.0
var _hand_frames: Array[Basis] = []
var _fingertips: Array[Vector3] = []
var _spine: int
var _head: int
var _home: Vector3
var _home_stance: Vector3
var _stance := Vector3.ZERO
var _clock := 0.0
var _strike_arm := 0
var _shot_facing := IDLE_PAW_DIRECTION
var _focus_weight := 0.0
var _reach := 0.0
var _look_yaw := 0.0
var _lunge := Vector3.ZERO
var _busy := false
var _nose_held := false
var _nose_target := Vector3.ZERO
var _nose_pull := Vector3.ZERO
var _nose_velocity := Vector3.ZERO
var _nose_brace := Vector3.ZERO
var _nose_tension := 0.0
var _nose_flinch := 0.0
var _nose_time := 0.0


func _ready() -> void:
	process_priority = -1
	_model = $Model
	var material_path := BEAVER_MATERIAL
	var sole_offset := 0.156
	if not Engine.is_editor_hint():
		opponent = randi_range(0, Opponent.size() - 1) as Opponent
		_voice.select_opponent(opponent)
	match opponent:
		Opponent.BLUE:
			_replace_model(load(BLUE_BEAVER_MODEL) as PackedScene)
			material_path = BLUE_BEAVER_MATERIAL
			sole_offset = 0.042
		Opponent.CHEF:
			_replace_model(load(CHEF_BEAVER_MODEL) as PackedScene)
			material_path = CHEF_BEAVER_MATERIAL
			sole_offset = 0.174
			position.z -= 0.14
	# The shared rig has different sole heights on the three meshes.
	_model.position.y += sole_offset
	_rig = _model.get_node("Rig/Skeleton3D")
	_body = _rig.get_node("Body")
	var material := load(material_path) as ShaderMaterial
	_face = material.duplicate() as ShaderMaterial
	if OS.has_feature("web"):
		_face.set_shader_parameter("normal_strength", 0.55)
	_body.set_surface_override_material(0, _face)
	_jaw = _rig.find_bone("Jaw")
	_jaw_rest_rotation = _rig.get_bone_rest(_jaw).basis.get_rotation_quaternion()
	_jaw_axis = (_rig.get_bone_global_rest(_jaw).basis.inverse() * Vector3.RIGHT).normalized()
	_hips = _rig.find_bone("Hips")
	_waist = _rig.find_bone("Spine1")
	_waist_rest_inverse = _rig.get_bone_global_rest(_waist).affine_inverse()
	_home = position
	_home_stance = Vector3(0.0, -_home.z, 0.0)
	_stance = _home_stance
	_spine = _rig.find_bone("Spine")
	_head = _rig.find_bone("Head")
	_setup_eyes()
	for side in ["Right", "Left"]:
		var leg := PackedInt32Array([
			_rig.find_bone(side + "UpLeg"),
			_rig.find_bone(side + "Leg"),
			_rig.find_bone(side + "Foot"),
		])
		_legs.append(leg)
		_foot_rest.append(_rig.get_bone_global_rest(leg[Joint.END]))
		var arm := PackedInt32Array([
			_rig.find_bone(side + "Arm"),
			_rig.find_bone(side + "ForeArm"),
			_rig.find_bone(side + "Hand"),
			_rig.find_bone(side + "HandIndex4"),
		])
		var hand := _rig.get_bone_global_rest(arm[Joint.END])
		var tip := _rig.get_bone_global_rest(arm[Joint.FINGERTIP]).origin
		var frame := Basis.looking_at(hand.origin.direction_to(tip), Vector3.UP, true)
		_arms.append(arm)
		_shoulders.append(_rig.get_bone_parent(arm[Joint.UPPER]))
		_hand_frames.append(frame.inverse() * hand.basis)
		_fingertips.append(frame.inverse() * (tip - hand.origin))
	_rest()


func _replace_model(scene: PackedScene) -> void:
	var next := scene.instantiate() as Node3D
	next.transform = _model.transform
	remove_child(_model)
	_model.queue_free()
	_model = next
	_model.name = &"Model"
	add_child(_model)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	var eyes_center := (_eyes[0].global_position + _eyes[1].global_position) * 0.5
	var target := _cursor_target(get_viewport().get_camera_3d(), eyes_center)
	var look := (global_basis.inverse() * (target - eyes_center)).normalized()
	var turn := Vector2(look.x, look.y).limit_length(1.0) if look.z > 0.0 else Vector2.ZERO
	_cursor_head_turn = _cursor_head_turn.lerp(turn, 1.0 - exp(-delta * 4.5))
	_update_nose_reaction(delta)
	if not _busy:
		_rest()
	_animate_face(delta, target)


func _setup_eyes() -> void:
	var fur_centers := [Vector2(1208, 844), Vector2(1363, 852)]
	var atlas_axes := [Vector2(0.78, -0.63), Vector2(0.65, 0.76)]
	var iris := Color("87502a")
	match opponent:
		Opponent.BLUE:
			fur_centers = [Vector2(591, 544), Vector2(598, 906)]
			atlas_axes = [Vector2(-0.52, 0.85), Vector2(0.52, 0.85)]
			iris = Color("654030")
		Opponent.CHEF:
			fur_centers = [Vector2(1241, 803), Vector2(988, 803)]
			atlas_axes = [Vector2.RIGHT, Vector2.RIGHT]
			iris = Color("805019")
	var names: Array[StringName] = [&"LeftEye", &"RightEye"]
	for i in names.size():
		var eye := _model.find_child(names[i], true, false) as MeshInstance3D
		var axis: Vector2 = atlas_axes[i].normalized()
		var material := ShaderMaterial.new()
		material.shader = EYE_SHADER
		material.set_shader_parameter("fur_texture", _face.get_shader_parameter("albedo_texture"))
		material.set_shader_parameter("fur_center", fur_centers[i] / 2048.0)
		material.set_shader_parameter("fur_axis", axis)
		material.set_shader_parameter("iris_color", iris)
		eye.material_override = material
		_eyes.append(eye)


func _cursor_target(camera: Camera3D, eyes_center: Vector3) -> Vector3:
	if camera == null:
		return eyes_center + global_basis.z
	if addressing_player:
		return camera.global_position
	var viewport := camera.get_viewport()
	var bounds := viewport.get_visible_rect()
	var cursor := viewport.get_mouse_position()
	if not bounds.has_point(cursor) or camera.is_position_behind(eyes_center):
		return camera.global_position
	# A point on the cursor ray lets the same gaze work as the board camera tilts.
	var depth := camera.to_local(eyes_center).z * -0.33
	return camera.project_position(cursor, maxf(camera.near, depth))


func _animate_face(delta: float, target: Vector3) -> void:
	_animate_eyes(delta, target)
	var opening := maxf(_voice.mouth_opening(), _nose_flinch * 0.36 + _nose_tension * 0.10)
	var speed := 32.0 if opening > _mouth else 21.0
	var mouth := lerpf(_mouth, opening, 1.0 - exp(-delta * speed))
	if mouth < 0.001:
		mouth = 0.0
	if mouth != _mouth:
		_mouth = mouth
		var angle := 0.31 if opponent == Opponent.BLUE else 0.35
		_rig.set_bone_pose_rotation(_jaw, _jaw_rest_rotation * Quaternion(_jaw_axis, angle * mouth))


func _animate_eyes(delta: float, target: Vector3) -> void:
	var blink_time := _clock - _next_blink
	var closure := smoothstep(0.0, 0.067, blink_time) * (1.0 - smoothstep(0.091, 0.19, blink_time))
	if blink_time >= 0.19:
		_next_blink = _clock + randf_range(2.0, 4.6)
	var center := (_eyes[0].global_position + _eyes[1].global_position) * 0.5
	var forward := _eyes[0].global_basis.z + _eyes[1].global_basis.z
	var face_basis := Basis.looking_at(forward, _eyes[0].global_basis.y, true)
	var look := (face_basis.inverse() * (target - center)).normalized()
	var gaze := Vector2(clampf(look.x, -0.46, 0.46), clampf(look.y, -0.33, 0.35))
	_eye_gaze = _eye_gaze.lerp(gaze, 1.0 - exp(-delta * 15.0))
	var gaze_shift := face_basis * Vector3(_eye_gaze.x, _eye_gaze.y, 0.0)
	for eye in _eyes:
		var socket := eye.global_basis.orthonormalized()
		var face_forward := socket.inverse() * face_basis.z
		var neutral := Vector3.BACK.lerp(face_forward, 0.5)
		var local_gaze := neutral + socket.inverse() * gaze_shift
		var material := eye.material_override as ShaderMaterial
		material.set_shader_parameter("gaze", local_gaze.normalized())
		material.set_shader_parameter("blink", maxf(closure, _nose_flinch * 0.76 + _nose_tension * 0.19))


func nose_transform() -> Transform3D:
	var head := _rig.global_transform * _rig.get_bone_global_pose(_head)
	return Transform3D(head.basis.orthonormalized(), head * NOSE_POINTS[opponent])


func grab_nose() -> void:
	_nose_held = true
	_nose_time = 0.0
	_nose_flinch = 1.0
	_nose_velocity += Vector3(0.0, 0.40, -0.76)
	pull_nose(Vector3.ZERO)


func pull_nose(offset: Vector3) -> void:
	var drag := global_basis.inverse() * offset
	_nose_target = Vector3(drag.x, drag.y * 0.82, drag.z * 0.65).limit_length(NOSE_PULL_LIMIT)
	_nose_target.z += 0.075 + _nose_target.length() * 0.24


func release_nose() -> void:
	_nose_held = false
	_nose_target = Vector3.ZERO


func _update_nose_reaction(delta: float) -> void:
	var tension := smoothstep(0.04, 0.50, _nose_target.length())
	if not _nose_held and _nose_pull.length_squared() + _nose_velocity.length_squared() +			+ _nose_brace.length_squared() + _nose_tension + _nose_flinch < 0.0001:
		_nose_pull = Vector3.ZERO
		_nose_velocity = Vector3.ZERO
		_nose_brace = Vector3.ZERO
		_nose_tension = 0.0
		_nose_flinch = 0.0
		return
	_nose_time += delta
	var resistance := Vector3(sin(_nose_time * 12.5), sin(_nose_time * 8.6 + 1.0) * 0.46,
		-cos(_nose_time * 11.1) * 0.52) * tension * 0.065
	var goal := _nose_target + resistance
	var time := minf(delta, 0.08)
	var steps := maxi(1, ceili(time * 120.0))
	var step := time / steps
	for _i in steps:
		_nose_velocity += ((goal - _nose_pull) * 174.0 - _nose_velocity * 13.5) * step
		_nose_pull += _nose_velocity * step
	_nose_brace = _nose_brace.lerp(_nose_pull, 1.0 - exp(-delta * 7.4))
	_nose_tension = lerpf(_nose_tension, maxf(tension, 0.32 if _nose_held else 0.0),
		1.0 - exp(-delta * 10.0))
	var strain := smoothstep(1.2, 4.2, _nose_velocity.length()) * 0.65
	_nose_flinch = maxf(strain, _nose_flinch * exp(-delta * 9.0))


func shot_setup(checker: Vector3, direction: Vector3) -> ShotSetup:
	var board := get_parent_node_3d()
	var target := board.to_local(checker)
	var forward := (board.global_basis.inverse() * direction).normalized()
	if forward.is_zero_approx():
		return null
	var right := Vector3.UP.cross(forward)
	var radius := _home_stance.y
	var best: ShotSetup
	for arm in range(_arms.size()):
		# Put the striking shoulder just outside the shot line, toward the back of the paw.
		var lane := target - right * _side_sign(arm) * SHOULDER_OFFSET
		lane.y = 0.0
		var across := lane.dot(right)
		if absf(across) >= radius:
			continue
		var setback := lane.dot(forward) + sqrt(radius * radius - across * across)
		if setback < 0.74 or setback > 4.01:
			continue
		var base := lane - forward * setback
		var angle := atan2(base.x, -base.z)
		var yaw := angle_difference(-angle, atan2(forward.x, forward.z))
		if absf(yaw) > 0.83:
			continue
		var travel := absf(angle_difference(_stance.x, angle)) * radius
		var score := travel * 0.55 + absf(yaw) * 0.36 + maxf(setback - 1.5, 0.0) * 0.9
		# Prefer the sides and the back so the beaver stays out of the player's view.
		score += maxf(base.z - 0.4, 0.0) * 0.8
		if best == null or score < best.cost:
			best = ShotSetup.new()
			best.stance = Vector3(angle, radius, yaw)
			best.arm = arm
			best.cost = score
	return best


func wait_for_stance() -> void:
	while _busy:
		await returned_to_stance


func wind_up(checker: Vector3, direction: Vector3, setup: ShotSetup = null, size := 1.0) -> bool:
	await wait_for_stance()
	if setup == null:
		setup = shot_setup(checker, direction)
	if setup == null:
		return false
	_busy = true
	_strike_arm = setup.arm
	await _walk_to(setup.stance)

	var local_target := to_local(checker)
	var forward := global_basis.inverse() * direction
	_reach = clampf((local_target.z - 1.25) / 2.4, 0.0, 1.0)
	_lunge = Vector3(_side_sign(_strike_arm) * -0.09, 0.33, 0.49) * _reach / _model.scale.x
	_look_yaw = clampf(atan2(local_target.x, local_target.z), -0.56, 0.56)
	var facing := _strike_facing(direction)
	var contact := to_local(_contact_point(checker, direction, size))
	var ready_tip := contact - forward * 0.47 + Vector3.UP * 0.31
	var start_tip := _tip_position(_strike_arm)
	var lift := _physics_tween()
	lift.tween_method(func(t: float) -> void:
		var arc := sin(PI * t)
		_pose_reach(0.58 * t - 0.12 * arc)
		var tip := start_tip.lerp(ready_tip, t) + Vector3.UP * 0.28 * arc
		_shot_facing = _hip_facing(_strike_arm).lerp(facing, t).normalized()
		_pose_tip(tip, _shot_facing, t, 1.0 - t)
		, 0.0, 1.0, 0.23).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await lift.finished
	return true


func strike(checker: Vector3, direction: Vector3, size := 1.0) -> bool:
	var contact := to_local(_contact_point(checker, direction, size))
	var forward := global_basis.inverse() * direction
	_shot_facing = _strike_facing(direction)
	var approach: Array[Vector3] = []
	var swing := _physics_tween()
	swing.tween_method(func(t: float) -> void:
		_pose_reach(lerpf(0.58, 1.0, t))
		var remaining := 1.0 - t
		var tip := contact - forward * 0.47 * remaining + Vector3.UP * 0.31 * remaining * remaining
		_pose_tip(tip, _shot_facing)
		if t >= 0.55:
			approach.append(_tip_position(_strike_arm))
		, 0.0, 1.0, 0.115).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await swing.finished
	if approach.size() < 2 or approach[-1].distance_to(contact) >= 0.065:
		return false
	var push := approach[-1] - approach[0]
	push.y = 0.0
	return push.normalized().dot(forward) >= 0.96


func recover(direction := Vector3.ZERO) -> void:
	var start := _tip_position(_strike_arm)
	var forward := global_basis.inverse() * direction
	var through := start + forward * 0.21 + Vector3.UP * 0.13
	var facing := _shot_facing
	var weight := _focus_weight
	var tween := _physics_tween()
	tween.tween_method(func(t: float) -> void:
		_pose_reach(lerpf(weight, weight * 0.76, t))
		_pose_tip(start.lerp(through, t), facing)
		, 0.0, 1.0, 0.095).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float) -> void:
		_pose_reach(weight * 0.76 * (1.0 - t))
		var hip_facing := _hip_facing(_strike_arm)
		var rest_facing := facing.lerp(hip_facing, t).normalized()
		var rest_tip := _hip_wrist(_strike_arm) + _finger_offset(_strike_arm, hip_facing)
		var tip := through.lerp(rest_tip, t) + Vector3.UP * 0.18 * sin(PI * t)
		_pose_tip(tip, rest_facing, 1.0 - t, t)
		, 0.0, 1.0, 0.24).set_trans(Tween.TRANS_SINE)
	await tween.finished
	await _walk_to(_home_stance)
	_busy = false
	returned_to_stance.emit()


func _pose_reach(weight: float) -> void:
	_shift_hips(Vector3(_side_sign(_strike_arm) * 0.08, -0.035 - _reach * 0.035, 0.015) * weight)
	_focus(weight)
	for index in _legs.size():
		_pose_foot(index, _foot_rest[index])


# Store each foot in board space until its next step, so the support foot stays planted.
func _walk_to(goal: Vector3) -> void:
	var start := _stance
	goal.x = start.x + angle_difference(start.x, goal.x)
	var change := goal - start
	var arc := absf(change.x) * (start.y + goal.y) * 0.5
	var distance := Vector2(arc + absf(change.z) * 0.53, change.y).length()
	if distance < 0.01:
		_stand_at(goal)
		return

	# Take a shorter first stride from the standing pose and land ahead of the hips.
	var first_stride := lerpf(0.64, 0.50, smoothstep(1.6, 4.0, distance))
	var travel_steps := ceili(distance / STEP_SPACING + 1.0 - first_stride)
	var stride_span := travel_steps - 1.0 + first_stride
	var minimum_duration := lerpf(0.145, 0.195, smoothstep(0.50, 1.5, distance))
	var duration := clampf(distance / (maxf(stride_span, 1.0) * WALK_SPEED), minimum_duration, 0.275)
	var planted := [_foot_at(0, start), _foot_at(1, start)]
	var walk := _physics_tween()
	for i in range(travel_steps + 1):
		var moving := _next_foot
		var stride_end := i + first_stride
		var before := maxf(stride_end - 1.0, 0.0) / stride_span
		var after := minf(stride_end / stride_span, 1.0)
		var reach := minf((stride_end + 0.50) / stride_span, 1.0)
		var landing := _foot_at(moving, _walk_stance(start, goal, reach))
		var stride := Vector2(float(i > 0), float(i < travel_steps))
		var step_duration := duration if i < travel_steps else duration * 0.76
		walk.tween_method(_step.bind(start, goal, Vector2(before, after),
			moving, planted[1 - moving], planted[moving], landing, stride), 0.0, 1.0, step_duration)
		planted[moving] = landing
		_next_foot = 1 - moving
	await walk.finished
	_stand_at(goal)
	_rest()


func _walk_stance(start: Vector3, goal: Vector3, progress: float) -> Vector3:
	var stance := start.lerp(goal, progress)
	var turn := clampf((goal.x - start.x) * 1.4, -0.37, 0.37)
	var weight := smoothstep(0.0, 0.28, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
	stance.y += 0.085 * weight
	stance.z += turn * weight
	return stance


func _step(t: float, start: Vector3, goal: Vector3, progress: Vector2, moving: int,
		support: Transform3D, takeoff: Transform3D, landing: Transform3D, stride: Vector2) -> void:
	_stand_at(_walk_stance(start, goal, lerpf(progress.x, progress.y, t)))
	var lift := sin(PI * t)
	var momentum := smoothstep(0.0, 1.0, lerpf(stride.x, stride.y, t))
	var swing := takeoff.interpolate_with(landing, smoothstep(0.0, 1.0, t))
	swing.origin.y += STEP_HEIGHT * lift * lerpf(0.65, 1.0, momentum)
	swing.basis = swing.basis.rotated(Vector3.RIGHT.rotated(Vector3.UP, rotation.y),
		0.13 * sin(TAU * t))

	var swing_weight := cos(PI * t) * _side_sign(moving)
	var hips := Vector3(_side_sign(1 - moving) * 0.058 * lift, -0.151 + 0.021 * lift, 0.0)
	var hip_offset := Vector3(0.0, -0.047, 0.0).lerp(hips, momentum)
	var board_to_rig := (transform * _model.transform).affine_inverse()
	var support_pose := board_to_rig * support
	_shift_hips(hip_offset)
	_keep_support_reachable(1 - moving, support_pose.origin, hip_offset)
	_focus(0.0)
	_rotate_from_rest(_spine, Vector3(lerpf(0.035, 0.085, momentum),
		-swing_weight * 0.091 * momentum, swing_weight * 0.032 * momentum))
	_rotate_from_rest(_head, Vector3(lerpf(-0.047, -0.10, momentum),
		swing_weight * 0.055 * momentum, -swing_weight * 0.025 * momentum))
	for index in _arms.size():
		var arm_swing := _side_sign(index) * swing_weight
		var swing_wrist := _walking_wrist(index) + Vector3(0.0, 0.028 + 0.035 * lift, 0.11 * arm_swing)
		var wrist := _hip_wrist(index).lerp(swing_wrist, momentum)
		var facing := _hip_facing(index).lerp(Vector3(0, -0.985, 0.17 + 0.09 * arm_swing), momentum)
		_pose_arm(index, wrist, facing.normalized(), 0.0, 1.0 - momentum)
	_pose_foot(1 - moving, support_pose)
	_pose_foot(moving, board_to_rig * swing)


func _keep_support_reachable(index: int, ankle: Vector3, hip_offset: Vector3) -> void:
	var leg := _legs[index]
	var hip := _rig.get_bone_global_pose(leg[Joint.UPPER]).origin
	var reach := ankle - hip
	var length := _rig.get_bone_rest(leg[Joint.LOWER]).origin.length() \
		+ _rig.get_bone_rest(leg[Joint.END]).origin.length() - 0.003
	if reach.length_squared() > length * length:
		var weight_shift := reach - reach.limit_length(length)
		_shift_hips(hip_offset + _model.transform.basis * weight_shift)


func _foot_at(index: int, stance: Vector3) -> Transform3D:
	var body := Transform3D(Basis(Vector3.UP, -stance.x + stance.z), _stance_position(stance))
	return body * _model.transform * _foot_rest[index]


# The stance stores the angle around the board, radius and yaw relative to the table.
func _stand_at(stance: Vector3) -> void:
	_stance = stance
	rotation.y = -stance.x + stance.z
	position = _stance_position(stance)


func _stance_position(stance: Vector3) -> Vector3:
	return Vector3(_home.x, _home.y, 0.0) + Vector3(0.0, 0.0, -stance.y).rotated(
		Vector3.UP, -stance.x)


func _rest() -> void:
	var sway := sin(_clock * 0.74)
	var breath := sin(_clock * 2.35)
	_shift_hips(Vector3(0.036 * sway, -0.047 + 0.010 * breath, 0.017 * sway)
		+ Vector3(_nose_brace.x * 0.17, -_nose_tension * 0.054, -_nose_brace.z * 0.24))
	_rest_body()
	if _nose_tension > 0.005:
		_pose_bracing_paws()
	for index in range(2):
		_pose_foot(index, _foot_rest[index])


func _rest_body() -> void:
	_focus(0.0)
	_pose_arm(_strike_arm, _hip_wrist(_strike_arm), _hip_facing(_strike_arm), 0.0, 1.0)


func _shift_hips(offset: Vector3) -> void:
	var rest := _rig.get_bone_rest(_hips).origin
	_rig.set_bone_pose_position(_hips, rest + offset / _model.scale.x)


func _pose_foot(index: int, target: Transform3D) -> void:
	var leg := _legs[index]
	var hip := _rig.get_bone_global_pose(leg[Joint.UPPER]).origin
	_solve_limb(leg, target.origin - hip, Vector3(_side_sign(index) * 0.22, 0.0, 1.0), 0.0)
	_set_rig_basis(leg[Joint.END], target.basis)


func _pose_bracing_paws() -> void:
	var nose := to_local(nose_transform().origin)
	for index in _arms.size():
		var side := _side_sign(index)
		var lead := clampf(_nose_brace.x * side, -0.25, 0.25)
		var weight := clampf(_nose_tension * (0.70 + lead), 0.0, 1.0)
		var brace := Vector3(nose.x * 0.31 + side * (1.24 - lead * 0.55),
			nose.y - 1.17 + lead * 0.45, nose.z - 0.34)
		var facing := (nose - brace + Vector3.UP * 0.25).normalized()
		_pose_arm(index, _hip_wrist(index).lerp(brace, weight),
			_hip_facing(index).lerp(facing, weight).normalized(), weight * 0.28, 1.0 - weight)


func _focus(weight: float) -> void:
	_focus_weight = weight
	var spine_parent := _rig.get_bone_parent(_spine)
	var spine_offset := _rig.get_bone_global_pose(spine_parent).basis.inverse() * _lunge * weight
	_rig.set_bone_pose_position(_spine, _rig.get_bone_rest(_spine).origin + spine_offset)
	var reaction := 1.0 - weight if not _busy else 0.0
	var lean := lerpf(0.035 + 0.015 * sin(_clock * 2.7), lerpf(0.20, 0.615, _reach), weight) \
		+ _nose_brace.z * 0.23 * reaction
	var roll := _side_sign(_strike_arm) * weight * 0.075 - _nose_brace.x * 0.14 * reaction
	var twist := -_side_sign(_strike_arm) * _reach * weight * 0.22 + _nose_brace.x * 0.10 * reaction
	_rotate_from_rest(_spine, Vector3(lean, _look_yaw * weight * 0.14 + twist, roll))
	var glance := _cursor_head_turn * (1.0 - weight) * (1.0 - _nose_tension * 0.85)
	var recoil := _nose_velocity * reaction
	_set_head_offset(Vector3(_nose_pull.x * 0.30, _nose_pull.y * 0.40, _nose_pull.z * 0.60) * reaction)
	_rotate_from_rest(_head, Vector3(-lean * 1.35 - glance.y * 0.09,
		_look_yaw * weight + glance.x * 0.16 + 0.027 * sin(_clock),
		-roll + 0.018 * sin(_clock * 1.5)) + Vector3(
			-_nose_pull.y * 0.46 - recoil.y * 0.018,
			_nose_pull.x * 0.34 + recoil.x * 0.023,
			-_nose_pull.x * 0.25 - recoil.x * 0.019) * reaction)
	var resting_arm := 1 - _strike_arm
	var release := clampf(weight * 1.8, 0.0, 1.0)
	var counterbalance := Vector3(_side_sign(resting_arm) * 0.09, 0.11, -0.19) * weight
	var wrist := _hip_wrist(resting_arm).lerp(_walking_wrist(resting_arm) + counterbalance, release)
	var facing := _hip_facing(resting_arm).lerp(IDLE_PAW_DIRECTION, release).normalized()
	_pose_arm(resting_arm, wrist, facing, 0.0, 1.0 - release)


func _set_head_offset(offset: Vector3) -> void:
	var parent := _rig.get_bone_global_pose(_rig.get_bone_parent(_head))
	var rest := _rig.get_bone_rest(_head).origin
	_rig.set_bone_pose_position(_head, rest + parent.basis.inverse() * offset / _model.scale.x)


# Waist targets follow the torso as the beaver breathes, leans, and takes a step.
func _waist_motion() -> Transform3D:
	return _rig.get_bone_global_pose(_waist) * _waist_rest_inverse


func face_center() -> Vector3:
	return (_eyes[0].global_position + _eyes[1].global_position) * 0.5 - Vector3.UP * 0.22


func _hip_anchor() -> Vector3:
	match opponent:
		Opponent.BLUE:
			return Vector3(1.66, 0.17, 0.59)
		Opponent.CHEF:
			return Vector3(1.83, 0.13, 0.63)
	return Vector3(1.74, 0.13, 0.54)


func _hip_wrist(index: int) -> Vector3:
	var anchor := _hip_anchor()
	anchor.x *= _side_sign(index)
	return _model.transform * _waist_motion() * (_model.transform.affine_inverse() * anchor)


func _hip_facing(index: int) -> Vector3:
	var tangent := Vector3(-0.14 * _side_sign(index), -0.43, 0.89)
	return (_waist_motion().basis * tangent).normalized()


func _walking_wrist(index: int) -> Vector3:
	var sway := sin(_clock * 2.1 + index * 0.55)
	return Vector3(_side_sign(index) * (_hip_anchor().x - 0.04), 0.31 + 0.014 * sway,
		0.24 + 0.025 * sway)


func _side_sign(index: int) -> float:
	return float(index * 2 - 1)


func _pose_arm(index: int, wrist: Vector3, facing: Vector3, extension_weight := 0.0,
		hip_weight := 0.0) -> void:
	var side := _side_sign(index)
	var arm := _arms[index]
	var hip_elbow := Vector3(side, 0.15, -0.18)
	var hip_shoulder_drop := 0.29 if opponent == Opponent.BLUE else 0.36
	var hip_upper_extension := 0.42 if opponent == Opponent.BLUE else 0.64
	var hip_wrist_roll := 0.76
	var clavicle_drop := -side * hip_weight * hip_shoulder_drop
	_rotate_from_rest(_shoulders[index], Vector3(0.0, 0.0, clavicle_drop))
	var shoulder := _rig.get_bone_global_pose(arm[Joint.UPPER]).origin
	var reach := _model.transform.affine_inverse() * wrist - shoulder
	var elbow_height := lerpf(-1.0, 0.84, extension_weight)
	var pole := Vector3(side * 0.96, elbow_height, -0.45).lerp(hip_elbow, hip_weight)
	_solve_limb(arm, reach, pole, extension_weight, 1.0 + hip_upper_extension * hip_weight)
	var grip := Basis.looking_at(facing, Vector3.UP, true)
	grip = grip.rotated(facing, -side * hip_weight * hip_wrist_roll)
	_set_rig_basis(arm[Joint.END], grip * _hand_frames[index])


# Solve the elbow or knee triangle in skeleton space using the imported bone lengths.
func _solve_limb(limb: PackedInt32Array, reach: Vector3, pole: Vector3, extension_weight: float,
		upper_scale := 1.0) -> void:
	var upper := limb[Joint.UPPER]
	var lower := limb[Joint.LOWER]
	var end := limb[Joint.END]
	var upper_rest := _rig.get_bone_rest(upper)
	var lower_rest := _rig.get_bone_rest(lower)
	_rig.set_bone_pose_rotation(upper, upper_rest.basis.get_rotation_quaternion())
	_rig.set_bone_pose_rotation(lower, lower_rest.basis.get_rotation_quaternion())
	var aim := reach.normalized() if not reach.is_zero_approx() else Vector3.DOWN
	var upper_offset := lower_rest.origin * upper_scale
	var lower_offset := _rig.get_bone_rest(end).origin
	var length := upper_offset.length() + lower_offset.length()
	# Let the striking paw stretch briefly for checkers farther across the board.
	var extension := clampf(reach.length() - length + 0.001, 0.0, MAX_ARM_EXTENSION)
	var length_scale := 1.0 + extension * extension_weight / length
	_rig.set_bone_pose_position(lower, upper_offset * length_scale)
	_rig.set_bone_pose_position(end, lower_offset * length_scale)
	var upper_length := upper_offset.length() * length_scale
	var lower_length := lower_offset.length() * length_scale
	var span := clampf(reach.length(), absf(upper_length - lower_length) + 0.001,
		upper_length + lower_length - 0.001)
	var along := (upper_length * upper_length - lower_length * lower_length + span * span) / (2.0 * span)
	var bend := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var joint_offset := aim * along + (pole - pole.project(aim)).normalized() * bend
	_aim_bone(upper, lower, joint_offset)
	_aim_bone(lower, end, aim * span - joint_offset)


func _aim_bone(bone: int, child: int, direction: Vector3) -> void:
	var pose := _rig.get_bone_global_pose(bone)
	var axis := pose.basis * _rig.get_bone_rest(child).origin
	var rotation_to_target := Quaternion(axis.normalized(), direction.normalized())
	_set_rig_basis(bone, Basis(rotation_to_target) * pose.basis)


func _rotate_from_rest(bone: int, angles: Vector3) -> void:
	var parent := _rig.get_bone_global_pose(_rig.get_bone_parent(bone))
	var rest := _rig.get_bone_rest(bone)
	_set_rig_basis(bone, Basis.from_euler(angles) * parent.basis * rest.basis)


func _set_rig_basis(bone: int, basis_in_rig: Basis) -> void:
	var parent := _rig.get_bone_global_pose(_rig.get_bone_parent(bone))
	var local_basis := parent.basis.inverse() * basis_in_rig
	_rig.set_bone_pose_rotation(bone, local_basis.orthonormalized().get_rotation_quaternion())


func _tip_position(index: int) -> Vector3:
	return _model.transform * _rig.get_bone_global_pose(_arms[index][Joint.FINGERTIP]).origin


func _strike_facing(direction: Vector3) -> Vector3:
	return (global_basis.inverse() * direction + Vector3.DOWN * 0.26).normalized()


func _contact_point(checker: Vector3, direction: Vector3, size := 1.0) -> Vector3:
	return checker + (Vector3.UP * 0.035 - direction * Checker.RADIUS) * size


func _finger_offset(index: int, facing: Vector3) -> Vector3:
	var offset := Basis.looking_at(facing, Vector3.UP, true) * _fingertips[index]
	return _model.transform.basis * offset


func _pose_tip(tip: Vector3, facing: Vector3, reach_weight := 1.0, hip_weight := 0.0) -> void:
	_pose_arm(_strike_arm, tip - _finger_offset(_strike_arm, facing), facing, reach_weight, hip_weight)



func _physics_tween() -> Tween:
	return create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
