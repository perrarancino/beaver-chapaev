extends MultiMeshInstance3D

const TRACE_SHADER := preload("res://assets/FX/checker_ice_trace.gdshader")
const STROKE_ATLAS := preload("res://assets/FX/checker_ice_trace_tiles.png")
const STAMP_SIZE := Vector2(0.126, 0.15)
const STAMP_SPACING := 0.063
const CAP_OFFSET := 0.038
const START_CAP := -1.0
const BODY_TILE := 0.0
const END_CAP := 1.0
const TRACE_HEIGHT := 0.012
const LIFETIME := 2.2
const MAX_STAMPS := 768

class Stroke:
	var previous: Vector2
	var next_stamp := 0.0
	var distance := 0.0
	var direction := Vector2.ZERO

var strokes: Dictionary[int, Stroke] = {}
var expires := PackedFloat64Array()
var trace_material := ShaderMaterial.new()
var clock := 0.0
var active := 0


func _ready() -> void:
	trace_material.shader = TRACE_SHADER
	trace_material.set_shader_parameter("stroke_atlas", STROKE_ATLAS)
	trace_material.set_shader_parameter("stamp_length", STAMP_SIZE.x)
	trace_material.set_shader_parameter("lifetime", LIFETIME)
	material_override = trace_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_STAMPS
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 0.06, 6.0))
	expires.resize(MAX_STAMPS)


func clear() -> void:
	strokes.clear()
	active = 0
	multimesh.visible_instance_count = 0


func end_strokes() -> void:
	for stroke: Stroke in strokes.values():
		_close_stroke(stroke)
	strokes.clear()


func end_stroke(piece: Checker) -> void:
	var id := piece.get_instance_id()
	if strokes.has(id):
		_close_stroke(strokes[id])
		strokes.erase(id)


func _close_stroke(stroke: Stroke) -> void:
	if not stroke.direction.is_zero_approx():
		_stamp(stroke.previous + stroke.direction * CAP_OFFSET, stroke.direction, END_CAP, stroke.distance)


func tick(delta: float) -> void:
	if active == 0:
		return
	clock += delta
	trace_material.set_shader_parameter("trace_clock", fposmod(clock, 8.0))
	var index := 0
	while index < active:
		if expires[index] > clock:
			index += 1
			continue
		active -= 1
		if index < active:
			multimesh.set_instance_transform(index, multimesh.get_instance_transform(active))
			multimesh.set_instance_custom_data(index, multimesh.get_instance_custom_data(active))
			expires[index] = expires[active]
	multimesh.visible_instance_count = active


func record(piece: Checker) -> void:
	var id := piece.get_instance_id()
	var local := to_local(piece.get_global_transform_interpolated().origin)
	var point := Vector2(local.x, local.z)
	if not strokes.has(id):
		var new_stroke := Stroke.new()
		new_stroke.previous = point
		strokes[id] = new_stroke
		return
	var stroke := strokes[id]
	var offset := point - stroke.previous
	var distance := offset.length()
	if distance < 0.0001:
		return
	var direction := offset / distance
	if stroke.direction.is_zero_approx():
		_stamp(stroke.previous - direction * CAP_OFFSET, direction, START_CAP, 0.0)
	while stroke.next_stamp <= distance:
		_stamp(stroke.previous + direction * stroke.next_stamp, direction, BODY_TILE, stroke.distance + stroke.next_stamp)
		stroke.next_stamp += STAMP_SPACING
	stroke.next_stamp -= distance
	stroke.previous = point
	stroke.distance += distance
	stroke.direction = direction


func _stamp(point: Vector2, direction: Vector2, tile: float, distance: float) -> void:
	if active == MAX_STAMPS:
		return
	var forward := Vector3(direction.x, 0.0, direction.y)
	var across := forward.cross(Vector3.UP)
	var axes := Basis(forward * STAMP_SIZE.x, Vector3.UP, across * STAMP_SIZE.y)
	multimesh.set_instance_transform(active, Transform3D(axes, Vector3(point.x, TRACE_HEIGHT, point.y)))
	var data := Color(fposmod(clock, 8.0), tile, fposmod(distance, 1.56), 0.0)
	multimesh.set_instance_custom_data(active, data)
	expires[active] = clock + LIFETIME
	active += 1
	multimesh.visible_instance_count = active
