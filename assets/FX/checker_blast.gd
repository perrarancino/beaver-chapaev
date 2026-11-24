extends Node3D

const BLAST_SHADER := preload("res://assets/FX/checker_blast.gdshader")
const LIFETIME := 0.94
const PUFF_COUNT := 14
static var puff_mesh: MultiMesh
static var wave_mesh: TorusMesh

var puff_material := ShaderMaterial.new()
var wave_material := ShaderMaterial.new()
var age := 0.0


func _ready() -> void:
	if not puff_mesh:
		_build_meshes()
	puff_material.shader = BLAST_SHADER
	var clouds := MultiMeshInstance3D.new()
	clouds.multimesh = puff_mesh
	clouds.material_override = puff_material
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)

	wave_material.shader = BLAST_SHADER
	wave_material.set_shader_parameter("pressure_wave", true)
	var wave := MeshInstance3D.new()
	wave.mesh = wave_mesh
	wave.material_override = wave_material
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave.custom_aabb = AABB(Vector3(-1.25, -0.06, -1.25), Vector3(2.5, 0.2, 2.5))
	add_child(wave)


func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	puff_material.set_shader_parameter("progress", age / LIFETIME)
	wave_material.set_shader_parameter("progress", age / LIFETIME)


func _build_meshes() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	puff_mesh = MultiMesh.new()
	puff_mesh.transform_format = MultiMesh.TRANSFORM_3D
	puff_mesh.use_custom_data = true
	puff_mesh.mesh = sphere
	puff_mesh.instance_count = PUFF_COUNT
	puff_mesh.custom_aabb = AABB(Vector3(-1.05, -0.3, -1.05), Vector3(2.1, 1.4, 2.1))
	for i in PUFF_COUNT:
		var main_puff := i == 0
		var seed := fposmod(float(i) * 0.618, 1.0)
		var radial := Basis(Vector3.UP, TAU * (float(i) + seed * 0.45) / (PUFF_COUNT - 1.0))
		var start := Vector3.ZERO if main_puff else radial.x * 0.065
		puff_mesh.set_instance_transform(i, Transform3D(radial, start))
		var spread := 0.0 if main_puff else lerpf(0.25, 0.65, seed)
		var rise := 0.31 if main_puff else lerpf(0.16, 0.52, 1.0 - seed)
		puff_mesh.set_instance_custom_data(i, Color(seed, spread, rise, float(main_puff)))

	wave_mesh = TorusMesh.new()
	wave_mesh.inner_radius = 0.92
	wave_mesh.outer_radius = 1.0
	wave_mesh.rings = 32
	wave_mesh.ring_segments = 6
