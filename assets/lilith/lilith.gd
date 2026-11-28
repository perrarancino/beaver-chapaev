extends Node3D

signal stance_reached
signal recovered

const Rails := preload("res://edge_rails.gd")
const FOOT_TIP_LENGTH := 0.182
const LEFT_SOLE := Vector3(0.074, 0.002, 0.124)
const REST_TOE := Vector3(-0.091, 0.018, 0.065)
const STAND_POSE := Vector3(0.10, 0.0, 0.0)
const REST_EYES := Vector3(0.0, 1.67, 0.17)
const HIT_POSE := Vector3(0.46, 0.35, -0.82)
const HIT_PITCH := 0.28
const FLIGHT_RESPONSE := 13.0
const TURN_RESPONSE := 14.0
const LANDING_CLEARANCE := 0.27
## Palm center in the rest pose, in skeleton space.
const NOSE_HAND := Vector3(-0.655, 1.086, 0.138)
const NOSE_HOVER_OFFSET := Vector3(-0.11, 0.70, 0.34)
const EDGE_TURNS := [0.0, 0.46, -0.46, 0.92, -0.92, 1.38, -1.38, 1.95, -1.95, 2.55, -2.55, PI]

@onready var model: Node3D = $Model
@onready var fill: OmniLight3D = $WindowFill
@onready var shadow: MeshInstance3D = $ContactShadow

var _rig: Skeleton3D
var _right := PackedInt32Array()
var _left := PackedInt32Array()
var _chest := -1
var _shoulders := PackedInt32Array()
var _wings := PackedInt32Array()
var _rest_rotations: Array[Quaternion] = []
var _rest_bases: Array[Basis] = []
var _upper_length := 0.0
var _lower_length := 0.0
var _rest_thigh := Vector3.ZERO
var _rest_shin := Vector3.ZERO
var _sole_offset := Vector3.ZERO
var _impact_offset := Vector3.ZERO
var _impact_reach := 0.0
var _board_center := Vector3.ZERO
var _board_radius := 0.0
var _rails: Rails

var _home := Transform3D.IDENTITY
var _plant := Transform3D.IDENTITY
# Crouch, torso pitch and arm counterbalance, respectively.
var _pose := STAND_POSE
var _toe_pitch := 0.0
var _goal := Transform3D.IDENTITY
var _velocity := Vector3.ZERO
var _turn_speed := 0.0
var _lift := 0.0
var _flight := 0.0
var _landing := 0.0
var _aim_load := 0.0
var _approaching_kick := false
var _kicking := false
var _load := 0.0
var _clock := 0.0
var _wing_phase := 0.0
var _leg_phase := 0.0
var _look_target := Vector3.INF
var _look := Vector2.ZERO
var _shadow_material: StandardMaterial3D
var _nose_hand_local := Vector3.ZERO
var _nose_contact := Vector3.ZERO
var _nose_yaw := 0.0
var _nose_flight := false
var _nose_reaching := false
var _nose_gripped := false
var _nose_reach := 0.0
var _nose_grip_offset := Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rig = model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_right = _leg("R")
	_left = _leg("L")
	_chest = _rig.find_bone("Chest")
	_shoulders = PackedInt32Array([_rig.find_bone("Shoulder.R"), _rig.find_bone("Shoulder.L")])
	_wings = PackedInt32Array([_rig.find_bone("Wing.R"), _rig.find_bone("Wing.L")])
	for bone in _rig.get_bone_count():
		_rest_rotations.append(_rig.get_bone_rest(bone).basis.get_rotation_quaternion())
		_rest_bases.append(_rig.get_bone_global_rest(bone).basis)
	_nose_hand_local = _rig.get_bone_global_rest(_shoulders[0]).affine_inverse() * NOSE_HAND
	var hip := _rig.get_bone_global_rest(_right[0]).origin
	var knee := _rig.get_bone_global_rest(_right[1]).origin
	var ankle := _rig.get_bone_global_rest(_right[2]).origin
	_rest_thigh = hip.direction_to(knee)
	_rest_shin = knee.direction_to(ankle)
	_upper_length = hip.distance_to(knee)
	_lower_length = knee.distance_to(ankle)
	_sole_offset = _rig.get_bone_global_rest(_left[2]).affine_inverse() * LEFT_SOLE
	_bend_support(HIT_POSE.x)
	var toe_from_ankle := Basis(Vector3.RIGHT, HIT_PITCH) * _rest_bases[_right[2]] * Vector3(0.0, FOOT_TIP_LENGTH, 0.0)
	_impact_offset = to_local(_rig.to_global(hip + toe_from_ankle)) - to_local(support_position())
	_impact_reach = (_upper_length + _lower_length - 0.006) * model.scale.x
	var mesh := model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	mesh.layers |= fill.light_cull_mask
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.top_level = true
	_shadow_material = shadow.mesh.surface_get_material(0) as StandardMaterial3D
	_home = global_transform
	_goal = _home
	_board_center.y = _home.origin.y
	_stage(_home, _rest_toe_at(_home), STAND_POSE, 0.0)


func configure_table(center: Vector3, radius: float, rails: Rails = null) -> void:
	_board_center = center
	_board_radius = radius
	_rails = rails


func _process(delta: float) -> void:
	_clock = fposmod(_clock + delta, TAU)
	var cadence := lerpf(1.75, 4.25, _flight) + 0.16 * sin(_clock * 3.0)
	_wing_phase = fposmod(_wing_phase + TAU * cadence * delta, TAU)
	_leg_phase = fposmod(_leg_phase + TAU * lerpf(1.0, 1.85, _flight) * delta, TAU)
	if _kicking and not _approaching_kick:
		_update_look(_plant, delta)
		return

	var stance := _advance_nose_flight(delta) if _nose_flight else _advance_stance(delta)
	_update_look(stance, delta)
	_load = lerpf(_load, _aim_load, 1.0 - exp(-9.0 * delta))
	_stage_stance(stance)
	if _nose_flight:
		_pose_nose_grip()
	if _approaching_kick and stance == _goal:
		_approaching_kick = false
		stance_reached.emit()


func track_cursor(point: Vector3) -> void:
	_look_target = point


func reach_for_nose(point: Vector3, beaver_yaw: float) -> void:
	_nose_contact = point
	_nose_yaw = beaver_yaw + 1.98
	_nose_flight = true
	_nose_reaching = true
	track_cursor(point)


func has_nose_grip() -> bool:
	return _nose_gripped


func release_nose() -> void:
	_nose_reaching = false
	_nose_gripped = false
	_plant.origin += _nose_grip_offset
	_nose_grip_offset = Vector3.ZERO


func _advance_nose_flight(delta: float) -> Transform3D:
	var target := _goal
	if _nose_reaching:
		var facing := Basis(Vector3.UP, _nose_yaw)
		target = Transform3D(facing, _nose_contact - facing * NOSE_HOVER_OFFSET)
	else:
		var remaining := (_plant.origin - target.origin).slide(Vector3.UP).length()
		target.origin.y += minf(0.34, remaining * 0.48)

	var response := 27.0 if _nose_gripped else 9.0
	var error := (_plant.origin - target.origin).limit_length(2.2)
	var acceleration_term := _velocity + error * response
	var decay := exp(-response * delta)
	var position := _plant.origin + (error + acceleration_term * delta) * decay - error
	_velocity = (_velocity - acceleration_term * response * delta) * decay
	var yaw := lerp_angle(_plant.basis.get_euler().y, target.basis.get_euler().y, 1.0 - exp(-12.0 * delta))
	_turn_speed = 0.0
	var distance := position.distance_to(target.origin)
	var reach := 0.0
	if _nose_reaching:
		reach = 1.0 - smoothstep(0.12, 0.62, distance)
	_nose_reach = 1.0 if _nose_gripped else lerpf(_nose_reach, reach, 1.0 - exp(-18.0 * delta))
	_lift = maxf(0.0, position.y - _board_center.y)
	_flight = lerpf(_flight, smoothstep(0.03, 0.35, _lift), 1.0 - exp(-10.0 * delta))
	_landing = lerpf(_landing, 0.0, 1.0 - exp(-18.0 * delta))
	if (not _nose_reaching and position.distance_to(_goal.origin) < 0.006
			and _velocity.length_squared() < 0.008 and absf(angle_difference(yaw, target.basis.get_euler().y)) < 0.012):
		_nose_flight = false
		_nose_reach = 0.0
		_velocity = Vector3.ZERO
		_lift = 0.0
		return _goal
	return Transform3D(Basis(Vector3.UP, yaw), position)


func _pose_nose_grip() -> void:
	if _nose_reach < 0.001:
		return
	var shoulder := _shoulders[0]
	var arm := _rig.get_bone_global_pose(shoulder)
	var toward_hand := arm.origin.direction_to(arm * _nose_hand_local)
	var toward_nose := arm.origin.direction_to(_rig.to_local(_nose_contact))
	if not toward_nose.is_zero_approx():
		var turn := Quaternion.IDENTITY.slerp(Quaternion(toward_hand, toward_nose), _nose_reach)
		_set_global_basis(shoulder, Basis(turn) * arm.basis)
	if _nose_reaching:
		var hand := _rig.to_global(_rig.get_bone_global_pose(shoulder) * _nose_hand_local)
		# Once held, keep the palm on the nose even while the torso catches up to a tug.
		var offset := _nose_contact - hand
		_nose_grip_offset = offset if _nose_gripped else offset.limit_length(0.25) * _nose_reach
		global_position += _nose_grip_offset
		if _nose_reach > 0.94 and (hand + _nose_grip_offset).distance_to(_nose_contact) < 0.06:
			_nose_gripped = true


func aim(contact: Vector3, direction: Vector3, power: float) -> void:
	if _approaching_kick:
		return
	_goal = _stance_at(contact, direction)
	_aim_load = lerpf(0.22, 1.0, power)


func cancel_aim() -> void:
	if _approaching_kick:
		return
	_goal = _home
	_aim_load = 0.0


func kick(contact: Vector3, direction: Vector3, power: float) -> void:
	if _kicking:
		await recovered
	_kicking = true
	_goal = _stance_at(contact, direction)
	_aim_load = lerpf(0.55, 1.0, power)
	_approaching_kick = true
	await stance_reached
	var room := smoothstep(LANDING_CLEARANCE, LANDING_CLEARANCE + 0.15, _rail_clearance(_plant.origin))
	var backswing := Vector3(-0.018 * power, 0.037 * (1.0 - room) + 0.030 * power,
		0.060 * (1.0 - room) - 0.044 * room * power)
	var windup := _windup_toe(_plant) + _plant.basis * backswing
	var windup_time := lerpf(0.17, 0.08, _load * (1.0 - _flight))
	await _blend(windup, Vector3(0.64, -0.31, 1.0),
		-0.56, windup_time, Tween.TRANS_SINE).finished
	var toe_arc := _plant.basis * Vector3(-0.045, lerpf(0.058, 0.102, power), 0.012)
	await _blend(contact, HIT_POSE, HIT_PITCH, lerpf(0.16, 0.12, power),
		Tween.TRANS_QUAD, Tween.EASE_IN, toe_arc).finished


func recover(direction: Vector3) -> void:
	cancel_aim()
	var follow_through := toe_position() + direction * 0.090 + Vector3.UP * 0.092
	await _blend(follow_through, Vector3(0.29, 0.39, -1.0),
		0.18, 0.09, Tween.TRANS_QUAD, Tween.EASE_OUT).finished
	var recoil := _plant * (REST_TOE + Vector3(-0.019, 0.047, -0.025))
	await _blend(recoil, Vector3(0.39, 0.08, -0.15), -0.18, 0.12, Tween.TRANS_SINE).finished
	await _blend(_rest_toe_at(_plant), STAND_POSE, 0.0, 0.15, Tween.TRANS_SINE).finished
	_load = 0.0
	_kicking = false
	recovered.emit()


func toe_position() -> Vector3:
	return _rig.to_global(_rig.get_bone_global_pose(_right[2]) * Vector3(0.0, FOOT_TIP_LENGTH, 0.0))


func support_position() -> Vector3:
	return _rig.to_global(_rig.get_bone_global_pose(_left[2]) * _sole_offset)


func _stance_at(contact: Vector3, direction: Vector3) -> Transform3D:
	var facing := Basis.looking_at(direction, Vector3.UP, true)
	var radius := _board_radius - 0.11
	var inside_radius := minf(radius, Rails.INNER_RADIUS - LANDING_CLEARANCE - 0.002) if _rails else radius
	var side := (contact - _board_center).slide(Vector3.UP)
	for turn: float in EDGE_TURNS:
		var angled := facing.rotated(Vector3.UP, turn)
		var stance := (side + angled * Vector3(0.091, 0.0, -0.237)).limit_length(radius)
		var desired := Transform3D(angled, _board_center + stance)
		if _can_land(desired) and _can_hit_from(desired, contact):
			return desired
		# Near the rim, pick the closest stance that keeps both the sole and the kick in reach.
		var reach_center := (contact - _board_center - angled * _impact_offset).slide(Vector3.UP)
		var nearest := Transform3D(angled, _board_center + reach_center.limit_length(radius))
		if not _can_land(nearest):
			nearest.origin = _board_center + reach_center.limit_length(inside_radius)
		if _can_hit_from(nearest, contact):
			var adjusted := nearest.interpolate_with(desired, 0.21)
			return adjusted if _can_land(adjusted) and _can_hit_from(adjusted, contact) else nearest
	return Transform3D(facing, _board_center + side.limit_length(inside_radius))


func _can_land(stance: Transform3D) -> bool:
	return _rail_clearance(stance.origin) >= LANDING_CLEARANCE


func _rail_clearance(position: Vector3) -> float:
	return _rails.distance_to_rail(_rails.to_local(position)) if _rails else INF


func _can_hit_from(stance: Transform3D, contact: Vector3) -> bool:
	if (stance * _impact_offset).distance_squared_to(contact) > _impact_reach * _impact_reach:
		return false
	if contact.y >= _board_center.y + Rails.HEIGHT + 0.055:
		return true
	# The heel still needs room when the toe reaches the checker.
	var heel := contact - stance.basis.z * 0.108
	return _rail_clearance(heel) >= 0.040


func _rest_toe_at(stance: Transform3D) -> Vector3:
	return stance * REST_TOE


func _windup_toe(stance: Transform3D) -> Vector3:
	return stance * Vector3(-0.11, 0.140, -0.142)


func _advance_stance(delta: float) -> Transform3D:
	var position := Vector3(_plant.origin.x, _goal.origin.y, _plant.origin.z)
	var distance := position.distance_to(_goal.origin)
	# Critically damped motion carries the current velocity into every new aim target.
	var error := (position - _goal.origin).limit_length(1.50)
	var acceleration_term := _velocity + error * FLIGHT_RESPONSE
	var decay := exp(-FLIGHT_RESPONSE * delta)
	position += (error + acceleration_term * delta) * decay - error
	_velocity = (_velocity - acceleration_term * FLIGHT_RESPONSE * delta) * decay

	var radial := (position - _board_center).slide(Vector3.UP)
	var radius := _board_radius - 0.11
	if radius > 0.0 and radial.length_squared() > radius * radius:
		var outward := radial.normalized()
		position -= radial - outward * radius
		_velocity -= outward * maxf(0.0, _velocity.dot(outward))

	var yaw := _plant.basis.get_euler().y
	var angle_error := angle_difference(_goal.basis.get_euler().y, yaw)
	var turn_term := _turn_speed + angle_error * TURN_RESPONSE
	var turn_decay := exp(-TURN_RESPONSE * delta)
	var angle_step := (angle_error + turn_term * delta) * turn_decay - angle_error
	_turn_speed = (_turn_speed - turn_term * TURN_RESPONSE * delta) * turn_decay

	var activity := maxf(distance, _velocity.length() * 0.15)
	var near_flight := smoothstep(0.045, 0.34, activity)
	var long_flight := smoothstep(0.22, 2.25, activity)
	var previous_lift := _lift
	var target_lift := 0.13 * near_flight + 0.38 * long_flight
	var minimum_lift := 0.0
	if _rails:
		var clearance := _rail_clearance(position)
		var ahead := _rail_clearance(position + _velocity * 0.13)
		var rail_lift := Rails.HEIGHT + 0.075
		# Rise before the feet cross a rail, then keep clearance until they are past it.
		var approaching := 1.0 - smoothstep(0.17, 0.31, minf(clearance, ahead))
		target_lift = maxf(target_lift, rail_lift * approaching * near_flight)
		minimum_lift = rail_lift * (1.0 - smoothstep(0.17, LANDING_CLEARANCE, clearance))
	_lift = maxf(minimum_lift, lerpf(_lift, target_lift, 1.0 - exp(-15.0 * delta)))
	_flight = lerpf(_flight, maxf(long_flight, near_flight * 0.68), 1.0 - exp(-10.0 * delta))
	var descent := (previous_lift - _lift) / maxf(delta, 0.001)
	var touchdown := smoothstep(0.08, 0.75, descent) * (1.0 - smoothstep(0.02, 0.11, _lift))
	_landing = lerpf(_landing, touchdown, 1.0 - exp(-18.0 * delta))

	if (distance < 0.004 and _velocity.length_squared() < 0.008
			and absf(angle_error) < 0.012 and absf(_turn_speed) < 0.25 and _lift < 0.004):
		_velocity = Vector3.ZERO
		_turn_speed = 0.0
		_lift = 0.0
		return _goal
	var bob := sin(_wing_phase - 0.45) * 0.022 * _flight * smoothstep(0.14, 0.28, _lift)
	return Transform3D(Basis(Vector3.UP, yaw + angle_step), position + Vector3.UP * (_lift + bob))


func _stage_stance(stance: Transform3D) -> void:
	var breath := sin(_clock * 2.0)
	var shift := sin(_clock * 3.0 - 0.8)
	var weight := _load * (1.0 - _flight)
	var pose := STAND_POSE + Vector3(breath * 0.036, breath * 0.034, shift * 0.085) * (1.0 - weight)
	pose += Vector3(0.48, -0.25, 0.78) * weight + Vector3(0.33, 0.29, -0.76) * _flight
	pose += Vector3(0.31, 0.10, -0.22) * _landing
	var toe := REST_TOE + Vector3(shift * 0.008, 0.008 + breath * 0.008, shift * 0.015)
	var airborne := _flight * smoothstep(0.016, 0.15, _lift)
	var stride := sin(_leg_phase)
	toe += Vector3(-0.026 + 0.018 * cos(_leg_phase), 0.072 - 0.055 * stride,
		-0.18 - 0.115 * stride) * airborne
	var step := (stance * toe).lerp(_windup_toe(stance), weight)
	var pitch := shift * 0.032 * (1.0 - weight) - 0.49 * weight
	pitch += (0.24 + 0.23 * cos(_leg_phase)) * airborne
	_stage(stance, step, pose, pitch, airborne)


func _update_look(stance: Transform3D, delta: float) -> void:
	var desired := Vector2.ZERO
	if _look_target.is_finite() and not _kicking:
		var toward := stance.affine_inverse() * _look_target - REST_EYES * model.scale
		if toward.length_squared() > 0.006:
			desired.x = clampf(atan2(-toward.y, Vector2(toward.x, toward.z).length()), -0.21, 0.27)
			desired.y = clampf(atan2(toward.x, maxf(toward.z, 0.18)), -0.48, 0.48)
		desired *= 1.0 - 0.74 * _load
	_look = _look.lerp(desired, 1.0 - exp(-7.5 * delta))


func _blend(toe: Vector3, pose: Vector3, pitch: float,
		duration: float, curve: Tween.TransitionType, ease := Tween.EASE_IN_OUT,
		toe_arc := Vector3.ZERO) -> Tween:
	var start_toe := toe_position()
	var start_pose := _pose
	var start_pitch := _toe_pitch
	var motion := create_tween().set_ignore_time_scale(true)
	motion.tween_method(func(t: float) -> void:
		var step := start_toe.lerp(toe, t) + toe_arc * sin(PI * t)
		_stage(_plant, step, start_pose.lerp(pose, t), lerpf(start_pitch, pitch, t)),
		0.0, 1.0, duration).set_trans(curve).set_ease(ease)
	return motion


func _stage(stance: Transform3D, toe: Vector3, pose: Vector3, pitch: float, airborne := 0.0) -> void:
	_plant = stance
	_pose = pose
	_toe_pitch = pitch

	# Solve the body from the sole so bending the support knee cannot lift or slide it.
	_bend_support(pose.x)
	var offset := to_local(support_position())
	global_transform = Transform3D(stance.basis, stance.origin - stance.basis * offset)
	if airborne > 0.0:
		_bend_support(pose.x, airborne)
	_solve_kick_leg(toe, pitch)
	_place_shadow(stance)

	var bank := clampf(_turn_speed * 0.022, -0.17, 0.17) * _flight
	_gesture(_chest, Vector3(pose.y + _look.x, _look.y - 0.13 * pose.z, -0.10 * pose.z - bank))
	_gesture(_shoulders[0], Vector3(-0.55 * pose.z, 0.095, -0.19 * absf(pose.z)))
	_gesture(_shoulders[1], Vector3(0.68 * pose.z, -0.11, 0.27 * absf(pose.z)))
	_flap_wing(_wings[0], 1.0, _wing_phase, pose.z, bank)
	_flap_wing(_wings[1], -1.0, _wing_phase - 0.21, pose.z, bank)


func _flap_wing(bone: int, side: float, phase: float, arm_swing: float, bank: float) -> void:
	var beat := fposmod(phase / TAU, 1.0)
	# The power stroke is brisk, with a slower return and a delayed twist.
	var drive := 2.0 * (smoothstep(0.0, 0.37, beat) - smoothstep(0.37, 1.0, beat)) - 1.0
	var lift := sin(phase + 0.63)
	var twist := sin(phase - 0.48)
	var span := lerpf(0.36, 0.74, _flight) * (1.0 + 0.08 * sin(_clock * 4.0) - side * bank * 0.55)
	var sweep := -0.03 + 0.11 * arm_swing + 0.04 * _flight
	_gesture(bone, Vector3(
		0.04 + lerpf(0.11, 0.23, _flight) * twist,
		side * (sweep + span * drive),
		side * (0.02 + lerpf(0.17, 0.35, _flight) * lift) - bank * 0.26))


func _place_shadow(stance: Transform3D) -> void:
	var height := smoothstep(0.0, 0.58, stance.origin.y - _board_center.y)
	var projected := stance.origin - stance.basis.x * 0.043 - stance.basis.z * 0.035
	shadow.visible = not _nose_flight or (projected - _board_center).slide(Vector3.UP).length() < _board_radius
	projected.y = _board_center.y + 0.019
	shadow.global_transform = Transform3D(stance.basis.scaled(Vector3.ONE * lerpf(1.0, 1.42, height)), projected)
	_shadow_material.albedo_color.a = lerpf(1.0, 0.18, height)


func _solve_kick_leg(toe: Vector3, pitch: float) -> void:
	var foot_basis := Basis(Vector3.RIGHT, pitch) * _rest_bases[_right[2]]
	var goal := _rig.to_local(toe) - foot_basis * Vector3(0.0, FOOT_TIP_LENGTH, 0.0)
	var hip := _rig.get_bone_global_pose(_right[0]).origin
	var delta := goal - hip
	var direction := delta.normalized()
	var length := clampf(delta.length(), absf(_upper_length - _lower_length) + 0.001,
		_upper_length + _lower_length - 0.001)
	var advance := (_upper_length * _upper_length - _lower_length * _lower_length
		+ length * length) / (2.0 * length)
	var height := sqrt(maxf(0.0, _upper_length * _upper_length - advance * advance))
	var pole := Vector3.BACK.slide(direction)
	if pole.length_squared() < 0.001:
		pole = Vector3.DOWN.slide(direction)
	var knee := hip + direction * advance + pole.normalized() * height
	var ankle := hip + direction * length
	_set_global_basis(_right[0], Basis(Quaternion(_rest_thigh, hip.direction_to(knee))) * _rest_bases[_right[0]])
	_set_global_basis(_right[1], Basis(Quaternion(_rest_shin, knee.direction_to(ankle))) * _rest_bases[_right[1]])
	_set_global_basis(_right[2], foot_basis)


func _leg(side: String) -> PackedInt32Array:
	return PackedInt32Array([
		_rig.find_bone("Thigh." + side),
		_rig.find_bone("Shin." + side),
		_rig.find_bone("Foot." + side),
	])


func _bend_support(crouch: float, airborne := 0.0) -> void:
	var stride := sin(_leg_phase)
	_rotate_hinge(_left[0], -0.11 - 0.29 * crouch - (0.38 + 0.40 * stride) * airborne)
	_rotate_hinge(_left[1], 0.19 + 0.65 * crouch + (0.68 + 0.29 * sin(_leg_phase - 1.25)) * airborne)
	var pitch := (0.18 + 0.20 * cos(_leg_phase - 0.45)) * airborne
	_set_global_basis(_left[2], Basis(Vector3.RIGHT, pitch) * _rest_bases[_left[2]])


func _rotate_hinge(bone: int, angle: float) -> void:
	_rig.set_bone_pose_rotation(bone, _rest_rotations[bone] * Quaternion(Vector3.RIGHT, angle))


func _gesture(bone: int, angles: Vector3) -> void:
	var rest := _rest_bases[bone]
	var delta := rest.inverse() * Basis.from_euler(angles) * rest
	_rig.set_bone_pose_rotation(bone, _rest_rotations[bone] * delta.get_rotation_quaternion())


func _set_global_basis(bone: int, basis: Basis) -> void:
	var parent := _rig.get_bone_global_pose(_rig.get_bone_parent(bone)).basis
	_rig.set_bone_pose_rotation(bone, (parent.inverse() * basis).get_rotation_quaternion())
