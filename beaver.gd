@tool
extends Node3D

const FUR_SHADER = preload("res://beaver_fur.gdshader")
const CHECKER_RADIUS := 0.155
const INDEX_REACH := 0.29

var _sphere := SphereMesh.new()
var _fur_lock: ArrayMesh
var _coat: ShaderMaterial
var _dark_coat: ShaderMaterial
var _cream: ShaderMaterial
var _nose: StandardMaterial3D
var _claw: StandardMaterial3D
var _torso: Node3D
var _head: Node3D
var _tail: Node3D
var _eyes: Array[Node3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _paws: Array[Node3D] = []
var _fingers: Array[Node3D] = []
var _home: Vector3
var _stance := Vector2.ZERO
var _clock := 0.0
var _strike_arm := 0
var _busy := false


func _ready() -> void:
	_home = position
	_stance = Vector2(0.0, -_home.z)
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 32
	_sphere.rings = 16
	_fur_lock = _make_fur_lock()
	_coat = _fur(Color("855139"))
	_dark_coat = _fur(Color("523126"))
	_cream = _fur(Color("c28d5e"))
	_nose = _solid(Color("301f22"), 0.36)
	_claw = _solid(Color("403038"), 0.55)
	_build_body()
	_build_face()
	for side in range(-1, 2, 2):
		_build_arm(side)
	_rest()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	var blink := 1.0 - 0.92 * exp(-pow((fmod(_clock, 3.8) - 3.55) / 0.06, 2.0))
	for eye in _eyes:
		eye.scale.y = blink
	if not _busy:
		_rest()


func _build_body() -> void:
	var scales := _fur(Color("4e3029"), true)
	_tail = _pivot(self, "PaddleTail", Vector3(0.55, -1.47, -0.30))
	_tail.rotation = Vector3(0.13, 1.16, -0.22)
	_oval(_tail, Vector3(0, 0, 0.68), Vector3(0.40, 0.13, 0.94), scales)
	_oval(_tail, Vector3(0, 0.01, 0.04), Vector3(0.24, 0.15, 0.38), _dark_coat)

	for side in range(-1, 2, 2):
		_oval(self, Vector3(side * 0.47, -1.12, 0.06), Vector3(0.43, 0.71, 0.43), _coat,
			Vector3(0.11, 0, side * 0.16))
		var foot := _pivot(self, "Foot", Vector3(side * 0.43, -1.90, 0.24))
		foot.rotation.y = side * 0.17
		_oval(foot, Vector3.ZERO, Vector3(0.30, 0.17, 0.44), _dark_coat)
		for toe in range(-1, 2):
			_oval(foot, Vector3(toe * 0.145, -0.016, 0.30), Vector3(0.092, 0.085, 0.16), _dark_coat)
			_oval(foot, Vector3(toe * 0.145, -0.016, 0.424), Vector3(0.031, 0.028, 0.057), _claw)

	_torso = _pivot(self, "Torso", Vector3(0, -0.62, 0))
	_oval(_torso, Vector3(0, 0.42, -0.07), Vector3(0.78, 1.00, 0.59), _coat)
	_oval(_torso, Vector3(0, 0.58, 0.34), Vector3(0.57, 0.78, 0.28), _cream)
	_oval(_torso, Vector3(0, 1.19, 0.06), Vector3(0.42, 0.50, 0.39), _coat)
	for side in range(-1, 2, 2):
		_oval(_torso, Vector3(side * 0.55, 1.12, 0.06), Vector3(0.30, 0.39, 0.34), _coat,
			Vector3(0, 0, side * 0.24))


func _build_face() -> void:
	var inner_ear := _fur(Color("955b50"))
	var white := _solid(Color("fff0d9"), 0.3)
	var iris := _solid(Color("a8702d"), 0.24)
	var iris_rim := _solid(Color("543326"), 0.32)
	var pupil := _solid(Color("1f151e"), 0.17)
	var gleam := _solid(Color("fff8e8"), 0.24)
	gleam.emission_enabled = true
	gleam.emission = Color("fff4da")
	gleam.emission_energy_multiplier = 0.35
	var tooth := _solid(Color("f8deaa"), 0.32)

	_head = _pivot(_torso, "Head", Vector3(0, 1.62, 0.16))
	_oval(_head, Vector3(0, 0.25, -0.10), Vector3(0.72, 0.62, 0.59), _coat)
	_oval(_head, Vector3(0, -0.04, 0.19), Vector3(0.57, 0.34, 0.45), _coat)
	_oval(_head, Vector3(0, -0.13, 0.50), Vector3(0.37, 0.15, 0.22), _nose)
	_oval(_head, Vector3(0, -0.22, 0.39), Vector3(0.39, 0.13, 0.23), _cream)
	for side in range(-1, 2, 2):
		var ear := _pivot(_head, "Ear", Vector3(side * 0.55, 0.68, -0.03))
		ear.rotation = Vector3(-0.10, side * 0.23, -side * 0.34)
		_oval(ear, Vector3.ZERO, Vector3(0.218, 0.24, 0.13), _dark_coat)
		_oval(ear, Vector3(0, -0.013, 0.088), Vector3(0.148, 0.166, 0.055), inner_ear)

		_oval(_head, Vector3(side * 0.46, 0.02, 0.24), Vector3(0.274, 0.276, 0.32), _coat,
			Vector3(0, 0, side * 0.34))
		var eye_mount := _pivot(_head, "EyeSocket", Vector3(side * 0.34, 0.31, 0.38))
		eye_mount.rotation.y = side * 0.33
		var eye := _pivot(eye_mount, "Eye", Vector3.ZERO)
		_eyes.append(eye)
		_oval(eye, Vector3(0, 0.008, 0), Vector3(0.210, 0.225, 0.141), _dark_coat,
			Vector3(0, 0, side * 0.12))
		_oval(eye, Vector3(0, -0.022, 0.063), Vector3(0.176, 0.175, 0.111), white)
		_oval(eye, Vector3(-side * 0.025, -0.031, 0.130), Vector3(0.123, 0.147, 0.05), iris_rim)
		_oval(eye, Vector3(-side * 0.025, -0.035, 0.155), Vector3(0.107, 0.129, 0.036), iris)
		_oval(eye, Vector3(-side * 0.025, -0.033, 0.180), Vector3(0.066, 0.095, 0.019), pupil)
		_oval(eye, Vector3(-0.048, 0.016, 0.193), Vector3(0.027, 0.033, 0.012), gleam)
		_oval(eye, Vector3(0.027, -0.078, 0.190), Vector3(0.011, 0.013, 0.006), gleam)
		_oval(eye_mount, Vector3(0, 0.217, -0.007), Vector3(0.193, 0.036, 0.058), _dark_coat,
			Vector3(0, 0, side * 0.22))

		_oval(_head, Vector3(side * 0.20, 0.015, 0.535), Vector3(0.252, 0.176, 0.242), _cream,
			Vector3(0, side * 0.27, -side * 0.16))
		_oval(_head, Vector3(side * 0.081, -0.145, 0.677), Vector3(0.075, 0.121, 0.06), tooth,
			Vector3(-0.12, 0, side * 0.055))
		for i in range(3):
			var dot := Vector3(side * (0.225 + i * 0.055), 0.036 - i * 0.041, 0.763 - i * 0.034)
			_oval(_head, dot, Vector3(0.014, 0.012, 0.008), _dark_coat)
			var tip := dot + Vector3(side * (0.36 - i * 0.04), 0.07 - i * 0.065, -0.06)
			_line(_head, dot, tip, 0.006, _claw)
		for i in range(3):
			var tuft := Vector3(side * (0.50 - 0.039 * i), 0.10 - i * 0.064, 0.21)
			_add_lock(tuft, tuft + Vector3(side * (0.31 - i * 0.025), -0.14, -0.04), 0.093, _coat)

	_add_lock(Vector3(-0.32, 0.68, 0.13), Vector3(0.02, 1.04, 0.07), 0.145, _coat)
	_add_lock(Vector3(-0.20, 0.72, 0.10), Vector3(0.23, 1.01, 0.13), 0.145, _coat)
	_add_lock(Vector3(0.05, 0.70, 0.18), Vector3(0.42, 0.92, 0.18), 0.12, _coat)
	_oval(_head, Vector3(0, 0.127, 0.73), Vector3(0.153, 0.090, 0.103), _nose)
	_oval(_head, Vector3(-0.029, 0.171, 0.805), Vector3(0.066, 0.018, 0.01), _solid(Color("604444"), 0.34))


func _build_arm(side: int) -> void:
	_upper_arms.append(_oval(self, Vector3.ZERO, Vector3.ONE, _coat))
	_forearms.append(_oval(self, Vector3.ZERO, Vector3.ONE, _coat))
	var paw := _pivot(self, "Paw", Vector3.ZERO)
	_paws.append(paw)
	_oval(paw, Vector3(0, 0, 0.052), Vector3(0.154, 0.108, 0.182), _dark_coat)
	var index := _pivot(paw, "Index", Vector3(0, 0.022, 0.10))
	_fingers.append(index)
	_oval(index, Vector3(0, 0, 0.091), Vector3(0.047, 0.048, 0.086), _dark_coat)
	_oval(index, Vector3(0, 0.004, 0.154), Vector3(0.024, 0.021, 0.036), _claw)
	for digit in [-1, 1, 2]:
		var x: float = digit * side * 0.065 - side * 0.03
		_oval(paw, Vector3(x, -0.033, 0.15), Vector3(0.041, 0.047, 0.088), _dark_coat,
			Vector3(0.32, x, 0))


func _rest() -> void:
	_torso.position.z = 0.023 * sin(_clock * 2.7)
	_torso.rotation.x = 0.056 + 0.017 * sin(_clock * 2.7)
	_head.rotation = Vector3(0.055, 0.04 * sin(_clock * 0.91), 0.02 * sin(_clock * 1.5))
	_tail.rotation.x = 0.13 + 0.04 * sin(_clock * 1.7)
	for i in range(2):
		_pose_arm(i, _rest_wrist(i), Vector3(0, -0.24, 1), 0.73)


func _rest_wrist(index: int) -> Vector3:
	var side := float(index * 2 - 1)
	return Vector3(side * 0.74, 0.16 + 0.018 * sin(_clock * 3.1), 0.69)


func _pose_arm(index: int, wrist: Vector3, facing: Vector3, curl: float) -> void:
	var side := float(index * 2 - 1)
	var shoulder := _torso.transform * Vector3(side * 0.56, 1.14, 0.11)
	var aim := shoulder.direction_to(wrist)
	var span := shoulder.distance_to(wrist)
	var elbow_out := Vector3(side * 0.72, -1, -0.18)
	var elbow_axis := (elbow_out - aim * elbow_out.dot(aim)).normalized()
	var bend := sqrt(maxf(0.0, 0.68 * 0.68 - span * span * 0.25))
	var elbow := shoulder.lerp(wrist, 0.48) + elbow_axis * bend * 0.68
	_fit_segment(_upper_arms[index], shoulder, elbow, Vector2(0.227, 0.229), 0.12)
	_fit_segment(_forearms[index], elbow, wrist, Vector2(0.172, 0.176), 0.11)
	_paws[index].transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), wrist)
	_fingers[index].rotation.x = curl


func wind_up(checker: Vector3, direction: Vector3) -> void:
	_busy = true
	var offset := get_parent_node_3d().to_local(checker)
	var radius := Vector2(offset.x, offset.z).length()
	var angle := 0.0 if radius < 0.20 else clampf(atan2(offset.x, -offset.z), -2.15, 2.15)
	var stance := Vector2(angle, maxf(-_home.z, radius + 1.27))
	var tween := _physics_tween()
	tween.tween_method(_stand_at, _stance, stance, 0.30).set_trans(Tween.TRANS_SINE)
	await tween.finished

	var facing := _strike_facing(direction)
	var contact := _contact(checker, direction, facing)
	_strike_arm = 0 if contact.x + _stance.x * 0.55 < 0.0 else 1
	var side := float(_strike_arm * 2 - 1)
	var ready_wrist := Vector3(side * maxf(absf(contact.x) + 0.10, 0.98),
		contact.y + 0.55, maxf(contact.z - 0.16, 0.83))
	var lifting := _physics_tween()
	lifting.tween_method(func(t: float) -> void:
		_focus(checker, t)
		_pose_arm(_strike_arm, _rest_wrist(_strike_arm).lerp(ready_wrist, t),
			Vector3(0, -0.24, 1).lerp(facing, t).normalized(), lerpf(0.73, 0.44, t))
		, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	await lifting.finished


func strike(checker: Vector3, direction: Vector3) -> void:
	var start := _paws[_strike_arm].position
	var facing := _strike_facing(direction)
	var contact := _contact(checker, direction, facing)
	var swing := _physics_tween()
	swing.tween_method(func(t: float) -> void:
		_focus(checker, 1.0 + t * 0.24)
		_pose_arm(_strike_arm, start.lerp(contact, t), facing, lerpf(0.44, 0.0, t))
		, 0.0, 1.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await swing.finished


func recover(direction := Vector3.ZERO) -> void:
	var start := _paws[_strike_arm].position
	var facing := _paws[_strike_arm].basis.z
	var through := start + global_basis.inverse() * direction * 0.19 + Vector3.UP * 0.065
	var lean := _torso.rotation.x
	var torso_z := _torso.position.z
	var head_rotation := _head.rotation
	var tween := _physics_tween()
	tween.tween_method(func(t: float) -> void:
		_pose_arm(_strike_arm, start.lerp(through, t), facing, t * 0.27)
		, 0.0, 1.0, 0.11).set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(t: float) -> void:
		_torso.rotation.x = lerpf(lean, 0.056, t)
		_torso.position.z = lerpf(torso_z, 0.0, t)
		_head.rotation = head_rotation.lerp(Vector3(0.055, 0, 0), t)
		_pose_arm(1 - _strike_arm, _rest_wrist(1 - _strike_arm), Vector3(0, -0.24, 1), 0.73)
		_pose_arm(_strike_arm, through.lerp(_rest_wrist(_strike_arm), t),
			facing.lerp(Vector3(0, -0.24, 1), t).normalized(), lerpf(0.27, 0.73, t))
		, 0.0, 1.0, 0.31).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_stand_at, _stance, Vector2(0.0, -_home.z), 0.26).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_busy = false


func _stand_at(stance: Vector2) -> void:
	_stance = stance
	position = Vector3(_home.x, _home.y, 0) + Vector3(sin(stance.x), 0, -cos(stance.x)) * stance.y
	rotation.y = -stance.x
	_rest()


func _focus(checker: Vector3, weight: float) -> void:
	var target := to_local(checker)
	_torso.rotation.x = lerpf(0.056, 0.21, weight)
	_torso.position.z = 0.19 * weight
	_head.rotation = Vector3(0.13 * weight, clampf(atan2(target.x, target.z), -0.50, 0.50) * weight,
		float(1 - _strike_arm * 2) * 0.075 * weight)
	_pose_arm(1 - _strike_arm, _rest_wrist(1 - _strike_arm), Vector3(0, -0.24, 1), 0.73)


func _strike_facing(direction: Vector3) -> Vector3:
	return (global_basis.inverse() * direction + Vector3.DOWN * 0.36).normalized()


func _contact(checker: Vector3, direction: Vector3, facing: Vector3) -> Vector3:
	var tip := to_local(checker + Vector3.UP * 0.012 - direction * CHECKER_RADIUS)
	return tip - Basis.looking_at(facing, Vector3.UP, true) * Vector3(0, 0.026, INDEX_REACH)


func _physics_tween() -> Tween:
	return create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)


func _fur(color: Color, scales := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FUR_SHADER
	material.set_shader_parameter("base", color)
	material.set_shader_parameter("tail_scales", scales)
	return material


func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _pivot(parent: Node3D, label: String, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = pos
	parent.add_child(pivot)
	return pivot


func _oval(parent: Node3D, pos: Vector3, radii: Vector3, material: Material,
		angles := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = _sphere
	part.material_override = material
	part.position = pos
	part.rotation = angles
	part.scale = radii
	parent.add_child(part)
	return part


func _line(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var part := _oval(parent, Vector3.ZERO, Vector3.ONE, material)
	_fit_segment(part, start, end, Vector2(radius, radius), 0.01)


func _add_lock(start: Vector3, end: Vector3, width: float, material: Material) -> void:
	var part := _oval(_head, Vector3.ZERO, Vector3.ONE, material)
	part.mesh = _fur_lock
	_fit_segment(part, start, end, Vector2(width, width * 0.85), 0.0)


func _make_fur_lock() -> ArrayMesh:
	var arrays := _sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(vertices.size()):
		var point := vertices[i]
		var normal := normals[i]
		var taper := 0.86 - point.y * 0.52
		vertices[i] = Vector3(point.x * taper, point.y, point.z * taper)
		normals[i] = Vector3(normal.x / taper,
			normal.y + 0.52 * (point.x * normal.x + point.z * normal.z) / taper,
			normal.z / taper).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _fit_segment(part: MeshInstance3D, start: Vector3, end: Vector3, width: Vector2, overlap: float) -> void:
	var axis := start.direction_to(end)
	var side := Vector3.FORWARD.cross(axis).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var depth := side.cross(axis)
	part.transform = Transform3D(
		Basis(side * width.x, axis * (start.distance_to(end) * 0.5 + overlap), depth * width.y),
		start.lerp(end, 0.5))
