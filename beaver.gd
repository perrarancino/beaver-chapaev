@tool
extends Node3D

signal returned_to_stance

const BEAVER_MATERIAL := preload("res://assets/beaver/beaver_material.tres")
const IDLE_PAW_DIRECTION := Vector3(0, -0.82, 0.57)
const MIN_STANCE_RADIUS := 2.68
const APPROACH_DISTANCE := 1.21
const SHOULDER_OFFSET := 0.80
const MAX_ARM_EXTENSION := 0.51

const STEP_SPACING := 0.225
const STEP_HEIGHT := 0.095
const BACKSTEP_DISTANCE := 0.22

enum Joint { UPPER, LOWER, END, FINGERTIP }

@onready var _model: Node3D = $Model
@onready var _rig: Skeleton3D = $Model/Rig/Skeleton3D
@onready var _body: MeshInstance3D = $Model/Rig/Skeleton3D/Body
@onready var _voice = $Voice

var _arms: Array[PackedInt32Array] = []
var _legs: Array[PackedInt32Array] = []
var _foot_rest: Array[Transform3D] = []
var _next_foot := 0
var _hips: int
var _face: ShaderMaterial
var _jaw: int
var _eyelids: int
var _next_blink := 1.35
var _mouth := 0.0
var _hand_frames: Array[Basis] = []
var _fingertips: Array[Vector3] = []
var _spine: int
var _head: int
var _home: Vector3
var _stance := Vector3.ZERO
var _clock := 0.0
var _strike_arm := 0
var _shot_facing := IDLE_PAW_DIRECTION
var _focus_weight := 0.0
var _look_yaw := 0.0
var _lunge := Vector3.ZERO
var _busy := false


func _ready() -> void:
	_face = BEAVER_MATERIAL.duplicate() as ShaderMaterial
	_body.material_override = _face
	_jaw = _body.find_blend_shape_by_name(&"JawOpen")
	_eyelids = _body.find_blend_shape_by_name(&"Blink")
	_hips = _rig.find_bone("Hips")
	_home = position
	_stance = Vector3(0.0, -_home.z, 0.0)
	_spine = _rig.find_bone("Spine")
	_head = _rig.find_bone("Head")
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
		_hand_frames.append(frame.inverse() * hand.basis)
		_fingertips.append(frame.inverse() * (tip - hand.origin))
	_rest()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	_animate_face(delta)
	if not _busy:
		_rest()


func _animate_face(delta: float) -> void:
	var blink_time := _clock - _next_blink
	var closure := smoothstep(0.0, 0.067, blink_time) * (1.0 - smoothstep(0.091, 0.19, blink_time))
	if blink_time >= 0.19:
		_next_blink = _clock + randf_range(2.0, 4.6)
	_face.set_shader_parameter("eye_closure", closure)
	_body.set_blend_shape_value(_eyelids, closure)
	_mouth = lerpf(_mouth, _voice.mouth_opening(), 1.0 - exp(-delta * 27.0))
	_face.set_shader_parameter("jaw_open", _mouth)
	_body.set_blend_shape_value(_jaw, _mouth)


func wind_up(checker: Vector3, direction: Vector3) -> void:
	while _busy:
		await returned_to_stance
	_busy = true
	var target := get_parent_node_3d().to_local(checker)
	var radius := Vector2(target.x, target.z).length()
	var local_direction := get_parent_node_3d().global_basis.inverse() * direction
	var approach_point := target - local_direction * maxf(0.0, (1.3 - radius) * 0.54)
	var angle := clampf(atan2(approach_point.x, -approach_point.z), -2.65, 2.65)
	var aim_in_stance := target.rotated(Vector3.UP, angle)
	_strike_arm = 0 if aim_in_stance.x + angle * 0.55 < 0.0 else 1
	var side := _side_sign(_strike_arm)
	var stance := Vector3(angle, maxf(MIN_STANCE_RADIUS, radius + APPROACH_DISTANCE),
		-side * SHOULDER_OFFSET)
	# Back away from the rim before turning or stepping sideways around it.
	if absf(stance.x - _stance.x) > 0.18 or absf(stance.z - _stance.z) > 0.45:
		var clearance := maxf(_stance.y + BACKSTEP_DISTANCE, stance.y)
		await _walk_to(Vector3(_stance.x, clearance, _stance.z))
	await _walk_to(stance)

	var local_target := to_local(checker)
	var reach_across_board := clampf((local_target.z - APPROACH_DISTANCE) / 1.3, 0.0, 1.0)
	_lunge = Vector3(0.0, 0.10, 0.43) * reach_across_board / _model.scale.x
	_look_yaw = clampf(atan2(local_target.x, local_target.z), -0.50, 0.50)
	var facing := _strike_facing(direction)
	var ready_wrist := _contact(checker, direction, facing) + Vector3(side * 0.22, 0.46, -0.30)
	var lift := _physics_tween()
	lift.tween_method(func(t: float) -> void:
		_focus(t)
		_shot_facing = IDLE_PAW_DIRECTION.lerp(facing, t).normalized()
		_pose_arm(_strike_arm, _idle_wrist(_strike_arm).lerp(ready_wrist, t), _shot_facing)
		, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	await lift.finished


func strike(checker: Vector3, direction: Vector3) -> void:
	var start := _wrist_position(_strike_arm)
	_shot_facing = _strike_facing(direction)
	var contact := _contact(checker, direction, _shot_facing)
	var swing := _physics_tween()
	swing.tween_method(func(t: float) -> void:
		_focus(1.0 + t * 0.12)
		_pose_arm(_strike_arm, start.lerp(contact, t), _shot_facing, t)
		, 0.0, 1.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await swing.finished


func recover(direction := Vector3.ZERO) -> void:
	var start := _wrist_position(_strike_arm)
	var through := start + global_basis.inverse() * direction * 0.14 + Vector3.UP * 0.08
	var facing := _shot_facing
	var weight := _focus_weight
	var tween := _physics_tween()
	tween.tween_method(func(t: float) -> void:
		_pose_arm(_strike_arm, start.lerp(through, t), facing, 1.0)
		, 0.0, 1.0, 0.11).set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(t: float) -> void:
		_focus(weight * (1.0 - t))
		_pose_arm(_strike_arm, through.lerp(_idle_wrist(_strike_arm), t),
			facing.lerp(IDLE_PAW_DIRECTION, t).normalized(), 1.0 - t)
		, 0.0, 1.0, 0.31).set_trans(Tween.TRANS_SINE)
	await tween.finished
	await _walk_to(Vector3(0.0, -_home.z, 0.0))
	_busy = false
	returned_to_stance.emit()


# Store each foot in board space until its next step, so the support foot stays planted.
func _walk_to(goal: Vector3) -> void:
	var start := _stance
	var change := goal - start
	var arc := absf(change.x) * (start.y + goal.y) * 0.5
	var distance := Vector2(arc + absf(change.z), change.y).length()
	if distance < 0.01:
		_stand_at(goal)
		return

	var steps := ceili(distance / STEP_SPACING) + 1
	var duration := clampf(distance / (steps * 1.45) + 0.07, 0.14, 0.23)
	duration = minf(duration, 4.0 / steps)
	var planted := [_foot_at(0, start), _foot_at(1, start)]
	var walk := _physics_tween()
	for i in range(steps):
		var moving := _next_foot
		var before := float(i) / (steps - 1)
		var after := minf(float(i + 1) / (steps - 1), 1.0)
		var reach := minf(float(i + 1.18) / (steps - 1), 1.0)
		var landing := _foot_at(moving, start.lerp(goal, reach))
		walk.tween_method(_step.bind(start.lerp(goal, before), start.lerp(goal, after),
			moving, planted[1 - moving], planted[moving], landing), 0.0, 1.0, duration)
		planted[moving] = landing
		_next_foot = 1 - moving
	await walk.finished
	_rest()


func _step(t: float, start: Vector3, end: Vector3, moving: int,
		support: Transform3D, takeoff: Transform3D, landing: Transform3D) -> void:
	_stand_at(start.lerp(end, t))
	var lift := sin(PI * t)
	var swing := takeoff.interpolate_with(landing, smoothstep(0.0, 1.0, t))
	swing.origin.y += STEP_HEIGHT * lift
	swing.basis = swing.basis.rotated(Vector3.RIGHT.rotated(Vector3.UP, rotation.y),
		0.13 * sin(TAU * t))

	_shift_hips(Vector3(_side_sign(1 - moving) * 0.043 * lift, -0.067 + 0.026 * lift, 0.0))
	_rest_body()
	var board_to_rig := (transform * _model.transform).affine_inverse()
	_pose_foot(1 - moving, board_to_rig * support)
	_pose_foot(moving, board_to_rig * swing)


func _foot_at(index: int, stance: Vector3) -> Transform3D:
	var body := Transform3D(Basis(Vector3.UP, -stance.x), _stance_position(stance))
	return body * _model.transform * _foot_rest[index]


# The stance stores the angle around the board, distance from its center and lateral step.
func _stand_at(stance: Vector3) -> void:
	_stance = stance
	rotation.y = -stance.x
	position = _stance_position(stance)


func _stance_position(stance: Vector3) -> Vector3:
	return Vector3(_home.x, _home.y, 0.0) + Vector3(stance.z, 0.0, -stance.y).rotated(
		Vector3.UP, -stance.x)


func _rest() -> void:
	var sway := sin(_clock * 0.74)
	var breath := sin(_clock * 2.35)
	_shift_hips(Vector3(0.036 * sway, -0.047 + 0.010 * breath, 0.017 * sway))
	_rest_body()
	for index in range(2):
		_pose_foot(index, _foot_rest[index])


func _rest_body() -> void:
	_focus(0.0)
	_pose_arm(_strike_arm, _idle_wrist(_strike_arm), IDLE_PAW_DIRECTION)


func _shift_hips(offset: Vector3) -> void:
	var rest := _rig.get_bone_rest(_hips).origin
	_rig.set_bone_pose_position(_hips, rest + offset / _model.scale.x)


func _pose_foot(index: int, target: Transform3D) -> void:
	var leg := _legs[index]
	var hip := _rig.get_bone_global_pose(leg[Joint.UPPER]).origin
	_solve_limb(leg, target.origin - hip, Vector3(_side_sign(index) * 0.22, 0.0, 1.0), 0.0)
	_set_rig_basis(leg[Joint.END], target.basis)


func _focus(weight: float) -> void:
	_focus_weight = weight
	var spine_parent := _rig.get_bone_parent(_spine)
	var spine_offset := _rig.get_bone_global_pose(spine_parent).basis.inverse() * _lunge * weight
	_rig.set_bone_pose_position(_spine, _rig.get_bone_rest(_spine).origin + spine_offset)
	var lean := lerpf(0.035 + 0.015 * sin(_clock * 2.7), 0.33, weight)
	var roll := _side_sign(_strike_arm) * weight * 0.075
	_rotate_from_rest(_spine, Vector3(lean, _look_yaw * weight * 0.14, roll))
	_rotate_from_rest(_head, Vector3(-lean * 1.35, _look_yaw * weight + 0.035 * sin(_clock),
		-roll + 0.018 * sin(_clock * 1.5)))
	var resting_arm := 1 - _strike_arm
	_pose_arm(resting_arm, _idle_wrist(resting_arm), IDLE_PAW_DIRECTION)


func _idle_wrist(index: int) -> Vector3:
	return Vector3(_side_sign(index) * 1.01, -0.34 + 0.015 * sin(_clock * 3.1), 0.22)


func _side_sign(index: int) -> float:
	return float(index * 2 - 1)


func _pose_arm(index: int, wrist: Vector3, facing: Vector3, extension_weight := 0.0) -> void:
	var arm := _arms[index]
	var shoulder := _rig.get_bone_global_pose(arm[Joint.UPPER]).origin
	var reach := _model.transform.affine_inverse() * wrist - shoulder
	_solve_limb(arm, reach, Vector3(_side_sign(index) * 0.85, -1.0, -0.35), extension_weight)
	_set_rig_basis(arm[Joint.END], Basis.looking_at(facing, Vector3.UP, true) * _hand_frames[index])


# Solve the elbow or knee triangle in skeleton space using the imported bone lengths.
func _solve_limb(limb: PackedInt32Array, reach: Vector3, pole: Vector3, extension_weight: float) -> void:
	var upper := limb[Joint.UPPER]
	var lower := limb[Joint.LOWER]
	var end := limb[Joint.END]
	var upper_rest := _rig.get_bone_rest(upper)
	var lower_rest := _rig.get_bone_rest(lower)
	_rig.set_bone_pose_rotation(upper, upper_rest.basis.get_rotation_quaternion())
	_rig.set_bone_pose_rotation(lower, lower_rest.basis.get_rotation_quaternion())
	var aim := reach.normalized() if not reach.is_zero_approx() else Vector3.DOWN
	var upper_offset := lower_rest.origin
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


func _wrist_position(index: int) -> Vector3:
	return _model.transform * _rig.get_bone_global_pose(_arms[index][Joint.END]).origin


func _strike_facing(direction: Vector3) -> Vector3:
	return (global_basis.inverse() * direction + Vector3.DOWN * 0.36).normalized()


func _contact(checker: Vector3, direction: Vector3, facing: Vector3) -> Vector3:
	var tip := to_local(checker + Vector3.UP * 0.012 - direction * Checker.RADIUS)
	var finger := Basis.looking_at(facing, Vector3.UP, true) * _fingertips[_strike_arm]
	return tip - _model.transform.basis * finger


func _physics_tween() -> Tween:
	return create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
