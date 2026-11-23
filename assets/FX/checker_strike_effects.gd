extends MultiMeshInstance3D

const ATLAS := preload("res://assets/FX/checker_strike_atlas.svg")
const SPRITE_SHADER := preload("res://assets/FX/checker_strike.gdshader")
const MAX_SPRITES := 96

var material := ShaderMaterial.new()
var expires := PackedFloat64Array()
var active := 0
var clock := 0.0


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("strike_atlas", ATLAS)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_SPRITES
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-4.0, -0.2, -4.0), Vector3(8.0, 1.0, 8.0))
	expires.resize(MAX_SPRITES)


func clear() -> void:
	active = 0
	multimesh.visible_instance_count = 0


func tick(delta: float) -> void:
	if active == 0:
		return
	clock += delta
	material.set_shader_parameter("effect_clock", fposmod(clock, 8.0))
	var index := 0
	while index < active:
		if expires[index] > clock:
			index += 1
			continue
		active -= 1
		if index < active:
			multimesh.set_instance_transform(index, multimesh.get_instance_transform(active))
			multimesh.set_instance_color(index, multimesh.get_instance_color(active))
			multimesh.set_instance_custom_data(index, multimesh.get_instance_custom_data(active))
			expires[index] = expires[active]
	if multimesh.visible_instance_count != active:
		multimesh.visible_instance_count = active


func lightning_arc(from: Vector3, to: Vector3) -> void:
	var offset := to - from
	if Vector2(offset.x, offset.z).length_squared() < 0.001:
		return
	var direction := offset.normalized()
	var length := offset.length()
	var width := clampf(0.24 + length * 0.11, 0.32, 0.54)
	_sprite(from.lerp(to, 0.5), direction, Vector2(length * 1.15, width),
		Color(0.77, 0.91, 1.0, 0.97), 0.23, false)
	_sprite(to, Vector3.RIGHT, Vector2(0.30, 0.30), Color(0.59, 0.85, 1.0, 0.91), 0.18, true)


func _sprite(point: Vector3, direction: Vector3, size: Vector2, color: Color,
		lifetime: float, glow: bool) -> void:
	if active == MAX_SPRITES:
		return
	var across := direction.cross(Vector3.UP).normalized()
	var up := across.cross(direction)
	var axes := Basis(direction * size.x, up, across * size.y)
	multimesh.set_instance_transform(active, Transform3D(axes, point))
	multimesh.set_instance_color(active, color)
	multimesh.set_instance_custom_data(active, Color(fposmod(clock, 8.0), lifetime, float(glow), 0.0))
	expires[active] = clock + lifetime
	active += 1
	multimesh.visible_instance_count = active
