extends Node3D

const MODEL := preload("res://assets/player_hand/right_hand.glb")
const SIZE := 2.6
const FOREARM_SWEEP := 0.34
const FOLLOW_SPEED := 15.0
const HOVER_HEIGHT := 0.23

# Thumb, index, middle, ring and little finger, from base joint to tip.
const FINGERS := [
	[&"ThumbPalm", &"Thumb1", &"Thumb2"],
	[&"Index1", &"Index2", &"Index3"],
	[&"Middle1", &"Middle2", &"Middle3"],
	[&"Ring1", &"Ring2", &"Ring3"],
	[&"Little1", &"Little2", &"Little3"],
]
const RELAXED := [
	Vector3(0.12, 0.22, 0.16), Vector3(0.09, 0.16, 0.12),
	Vector3(0.24, 0.38, 0.19), Vector3(0.30, 0.47, 0.22), Vector3(0.38, 0.53, 0.28),
]
const INDEX_FINGER := 1
const INDEX_COCKED := Vector3(0.59, 1.00, 0.41)
const INDEX_EXTENDED := Vector3(-0.05, 0.02, 0.01)
const FINGER_SPREAD := [0.0, 0.065, 0.0, -0.065, -0.13]
const PINCH_CURL := [
	Vector3(0.30, -0.19, 0.15), Vector3(0.79, 0.72, 0.35),
	Vector3(0.97, 1.36, 0.79), Vector3(1.04, 1.48, 0.85), Vector3(1.10, 1.52, 0.85),
]

var _rig: Skeleton3D
var _wrist: int
var _index_tip: int
var _fingers: Array[PackedInt32Array] = []
var _rest_rotations: Array[Quaternion] = []
var _flex_axes := PackedVector3Array()
var _spread_axes := PackedVector3Array()
var _twist_axes := PackedVector3Array()
var _pose := Vector4.ZERO
var _clock := 0.0
var _withdrawal: Tween
var _swinging := false
var _pinch := 0.0


func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	model.scale *= SIZE
	add_child(model)
	_rig = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_wrist = _rig.find_bone(&"Wrist")
	_index_tip = _rig.find_bone(&"IndexTip")
	var hand_to_rig := (global_basis.inverse() * _rig.global_basis).orthonormalized().inverse()
	for bone in _rig.get_bone_count():
		_rest_rotations.append(_rig.get_bone_rest(bone).basis.get_rotation_quaternion())
		var hand_to_bone := _rig.get_bone_global_rest(bone).basis.inverse() * hand_to_rig
		_flex_axes.append((hand_to_bone * Vector3.LEFT).normalized())
		_spread_axes.append((hand_to_bone * Vector3.UP).normalized())
		_twist_axes.append((hand_to_bone * Vector3.FORWARD).normalized())
	for names: Array in FINGERS:
		var bones := PackedInt32Array()
		for joint: StringName in names:
			bones.append(_rig.find_bone(joint))
		_fingers.append(bones)
	for finger in _fingers.size():
		_set_finger(finger, RELAXED[finger])
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply_pose(Vector4.ZERO)
	hide()


func follow(delta: float, target: Vector3, direction: Vector3) -> void:
	_track(delta, target, direction, 0.0)


func aim(delta: float, contact: Vector3, direction: Vector3, power: float) -> void:
	_track(delta, _windup_tip(contact, direction, power), direction, _load_amount(power))


func reach_for_nose(delta: float, nose: Transform3D, view: Basis, grabbed: bool) -> void:
	if _swinging:
		return
	_cancel_withdrawal()
	var direction := (-nose.basis.z * 0.68 - view.x * 0.58 + view.y * 0.63).normalized()
	var facing := Basis.looking_at(direction, view.y) * Basis(Vector3.BACK, -0.82)
	var gap := 0.025 if grabbed else 0.23
	var target := nose.origin + nose.basis.z * gap
	if not visible:
		_enter_from_offscreen(_wrist_at(target, facing, _pinch_center()))
	var weight := 1.0 - exp(-(34.0 if grabbed else 14.0) * delta)
	var anchor := _pinch_center().lerp(target, weight)
	_apply_pose(_pose.lerp(Vector4.ZERO, weight), lerpf(_pinch, 1.0 if grabbed else 0.72, weight))
	global_transform = _wrist_at(anchor, global_basis.slerp(facing, weight), _pinch_center())


func withdraw() -> void:
	if _swinging or not visible or _withdrawal_is_running():
		return
	_slide_offscreen(_offscreen_position(global_position), 0.34)


func flick(contact: Vector3, direction: Vector3, power: float) -> void:
	_cancel_withdrawal()
	_swinging = true
	var facing := _hand_basis(direction)
	var initial_pose := _pose
	var load := _load_amount(power)
	var ready_pose := Vector4(load, 0.0, 0.0, 0.0)
	var impact_pose := Vector4(0.0, 1.0, 0.0, 0.0)

	# Solve the wrist at both endpoints so the skinned index pad lands on the rim.
	_apply_pose(ready_pose)
	var ready := _wrist_at_tip(_windup_tip(contact, direction, power), facing)
	_apply_pose(impact_pose)
	var impact := _wrist_at_tip(contact, facing)
	_apply_pose(initial_pose)

	if not visible:
		_enter_from_offscreen(ready)
	var start := global_transform
	var windup_time := lerpf(0.10, 0.24, smoothstep(0.7, 2.4,
		start.origin.distance_to(ready.origin)))
	var swing := create_tween()
	swing.tween_method(func(t: float) -> void:
		_apply_pose(initial_pose.lerp(ready_pose, t))
		global_transform = start.interpolate_with(ready, t)
		, 0.0, 1.0, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	swing.tween_method(func(t: float) -> void:
		var snap := smoothstep(0.24, 0.96, t)
		_apply_pose(ready_pose.lerp(impact_pose, snap))
		global_transform = ready.interpolate_with(impact, t * t)
		global_position += Vector3.UP * (0.035 * sin(PI * t))
		, 0.0, 1.0, 0.12)
	await swing.finished


func recover(direction: Vector3) -> void:
	var start := global_transform
	var arc := start
	arc.origin += direction * 0.19 + Vector3.UP * 0.20
	var impact_pose := _pose
	var loose_pose := Vector4(0.06, 0.17, -0.38, 0.0)
	# Capture the board view before the impact camera can move or slow down time.
	var stow_point := _offscreen_position(arc.origin)
	var retreat := create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE)
	retreat.tween_method(func(t: float) -> void:
		global_transform = start.interpolate_with(arc, t)
		_apply_pose(impact_pose.lerp(loose_pose, t))
		, 0.0, 1.0, 0.13).set_ease(Tween.EASE_OUT)
	await retreat.finished
	await _slide_offscreen(stow_point, 0.40).finished
	_swinging = false


func _track(delta: float, target: Vector3, direction: Vector3, load: float) -> void:
	if _swinging:
		return
	_cancel_withdrawal()
	_clock += delta
	var facing := _hand_basis(direction)
	var pose := Vector4(load, 0.0, 0.0, 0.0)
	if not visible:
		_apply_pose(Vector4.ZERO)
		_enter_from_offscreen(_wrist_at_tip(target, facing))
		return
	var weight := 1.0 - exp(-FOLLOW_SPEED * delta)
	var tip := _index_tip_world()
	var lag := target - tip
	var sway_weight := 1.0 - load
	pose.z = clampf(lag.dot(global_basis.x) * 3.6, -1.0, 1.0) * sway_weight \
		+ sin(_clock * 3.2) * 0.12
	pose.w = clampf(lag.dot(-global_basis.z) * 3.3, -1.0, 1.0) * sway_weight
	_apply_pose(_pose.lerp(pose, weight), lerpf(_pinch, 0.0, weight))
	facing = global_basis.slerp(facing, weight)
	global_transform = _wrist_at_tip(tip.lerp(target, weight), facing)


func _enter_from_offscreen(goal: Transform3D) -> void:
	goal.origin = _offscreen_position(goal.origin)
	global_transform = goal
	show()


func _slide_offscreen(target: Vector3, duration: float) -> Tween:
	var start := global_position
	var start_pose := _pose
	var start_pinch := _pinch
	_withdrawal = create_tween().set_ignore_time_scale(true)
	_withdrawal.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_withdrawal.tween_method(func(t: float) -> void:
		global_position = start.lerp(target, t)
		_apply_pose(start_pose.lerp(Vector4.ZERO, t), start_pinch * (1.0 - t))
		, 0.0, 1.0, duration)
	_withdrawal.tween_callback(hide)
	return _withdrawal


func _offscreen_position(anchor: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return anchor + global_basis.z * 2.0 + Vector3.DOWN * 2.0
	var rect := get_viewport().get_visible_rect()
	var screen := rect.position + rect.size * Vector2(0.84, 1.57)
	# Bring the hand toward the player at table height so it clears the near edge.
	var parked: Variant = Plane(Vector3.UP, anchor.y).intersects_ray(
		camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if parked != null and camera.to_local(parked).z < -camera.near:
		return parked
	var depth := maxf(1.8, -camera.to_local(anchor).z * 0.92)
	return camera.project_position(screen, depth)


func _withdrawal_is_running() -> bool:
	return _withdrawal != null and _withdrawal.is_running()


func _cancel_withdrawal() -> void:
	if _withdrawal_is_running():
		_withdrawal.kill()


func _index_tip_world() -> Vector3:
	return _rig.to_global(_rig.get_bone_global_pose(_index_tip).origin)


func _wrist_at_tip(target: Vector3, facing: Basis) -> Transform3D:
	return _wrist_at(target, facing, _index_tip_world())


func _wrist_at(target: Vector3, facing: Basis, contact: Vector3) -> Transform3D:
	return Transform3D(facing, target - facing * to_local(contact))


func _pinch_center() -> Vector3:
	var thumb := _rig.get_bone_global_pose(_fingers[0][2])
	var pad := _rig.to_global(thumb * Vector3(0.0, 0.041, 0.0))
	return _index_tip_world().lerp(pad, 0.5)


func _windup_tip(contact: Vector3, direction: Vector3, power: float) -> Vector3:
	return contact - direction * lerpf(0.30, 0.60, power) + Vector3.UP * lerpf(0.22, 0.39, power)


func _load_amount(power: float) -> float:
	return lerpf(0.68, 1.0, power)


func _hand_basis(direction: Vector3) -> Basis:
	return Basis.looking_at(direction.rotated(Vector3.UP, FOREARM_SWEEP) + Vector3.DOWN * 0.20)


func _apply_pose(pose: Vector4, pinch := 0.0) -> void:
	_pose = pose
	pinch = 0.0 if pinch < 0.001 else pinch
	var load := pose.x
	var snap := pose.y
	var side_sway := pose.z
	var forward_sway := pose.w
	_set_joint(_wrist, -0.24 * load + 0.11 * snap + 0.14 * side_sway + 0.31 * forward_sway,
		-FOREARM_SWEEP * (0.43 + 0.47 * snap) - 0.09 * load + 0.19 * side_sway,
		0.22 * load - 0.10 * snap + 0.41 * side_sway)
	if _pinch > 0.0 or pinch > 0.0:
		for finger in _fingers.size():
			if finger == INDEX_FINGER:
				continue
			var base: Vector3 = RELAXED[finger]
			_set_finger(finger, base.lerp(PINCH_CURL[finger], pinch))
		var thumb := _fingers[0]
		var curl: Vector3 = RELAXED[0].lerp(PINCH_CURL[0], pinch)
		_set_joint(thumb[0], curl.x, -0.52 * pinch, 0.24 * pinch)
		_set_joint(thumb[1], curl.y, -0.38 * pinch)
		_set_joint(thumb[2], curl.z, -0.17 * pinch)
	_pinch = pinch
	var relaxed: Vector3 = RELAXED[INDEX_FINGER]
	var index := relaxed.lerp(INDEX_COCKED, load).lerp(INDEX_EXTENDED, snap)
	index = index.lerp(PINCH_CURL[INDEX_FINGER], _pinch)
	_set_finger(INDEX_FINGER, index, 0.24 * pinch)


func _set_finger(finger: int, curl: Vector3, spread := 0.0) -> void:
	var bones := _fingers[finger]
	_set_joint(bones[0], curl.x, FINGER_SPREAD[finger] + spread)
	_set_joint(bones[1], curl.y)
	_set_joint(bones[2], curl.z)


func _set_joint(bone: int, flex: float, spread := 0.0, twist := 0.0) -> void:
	_rig.set_bone_pose_rotation(bone, _rest_rotations[bone]
		* Quaternion(_spread_axes[bone], spread) * Quaternion(_flex_axes[bone], flex)
		* Quaternion(_twist_axes[bone], twist))
