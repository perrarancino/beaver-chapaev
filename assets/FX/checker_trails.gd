extends MeshInstance3D

const TRAIL_SHADER := preload("res://assets/FX/checker_trail.gdshader")
const SPACING := 0.030
const MAX_LENGTH := Checker.RADIUS * 15.6
const MAX_SAMPLES := ceili(MAX_LENGTH / SPACING) + 2
const LIFETIME := 0.43
const MIN_SPEED := 0.12
const TAPER_LENGTH := 0.23
const HEIGHT_OFFSET := 0.034
const TURN_SMOOTHING_SAMPLES := 6
const WIDTH_CHANGE_PER_UNIT := 0.72
const CROSS_COORDS := [0.0, 0.18, 0.34, 0.43, 0.50, 0.57, 0.66, 0.82, 1.0]

class Sample:
	var point: Vector3
	var time: float
	var distance: float
	var strength: float

	func _init(position: Vector3, timestamp: float, distance_along: float, intensity: float) -> void:
		point = position
		time = timestamp
		distance = distance_along
		strength = intensity

class Track:
	var samples: Array[Sample] = []
	var head: Sample
	var tint: Color
	var seed: int

var histories: Dictionary[int, Track] = {}
var ribbon_mesh := ArrayMesh.new()
var ribbon_material := ShaderMaterial.new()
var columns := CROSS_COORDS.size()
var indices_per_row := (columns - 1) * 6
var row_indices := PackedInt32Array()
var vertices := PackedVector3Array()
var colors := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var canonical_indices := PackedInt32Array()
var cached_index_rows := 0
var clock := 0.0


func _ready() -> void:
	ribbon_material.shader = TRAIL_SHADER
	ribbon_material.set_shader_parameter("trail_length", MAX_LENGTH)
	for column in range(columns - 1):
		var next_row := column + columns
		row_indices.append_array(PackedInt32Array([column, column + 1, next_row,
			next_row, column + 1, next_row + 1]))
	mesh = ribbon_mesh
	material_override = ribbon_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func clear() -> void:
	histories.clear()
	ribbon_mesh.clear_surfaces()


func forget(piece: Checker) -> void:
	histories.erase(piece.get_instance_id())


func update_trails(delta: float, pieces: Array[Checker], emit: bool) -> void:
	clock += delta
	if emit:
		for piece in pieces:
			if not piece.visible:
				continue
			var speed := piece.fall_velocity.length() if piece.falling else piece.linear_velocity.length()
			if speed >= MIN_SPEED or histories.has(piece.get_instance_id()):
				_record(piece, speed)

	if ribbon_mesh.get_surface_count() > 0:
		ribbon_mesh.clear_surfaces()
	if histories.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	var camera_right := global_basis.inverse() * camera.global_basis.x if camera else Vector3.RIGHT
	var ribbons: Array[Track] = []
	var row_count := 0
	for id: int in histories.keys():
		var track := histories[id]
		if clock - track.head.time >= LIFETIME:
			histories.erase(id)
			continue
		# Keep one expired point so the visible end can fade into it.
		while track.samples.size() > 1 and clock - track.samples[1].time >= LIFETIME:
			track.samples.pop_front()
		if not camera or track.head.distance - track.samples[0].distance < 0.002:
			continue
		ribbons.append(track)
		row_count += track.samples.size() + int(_has_extra_head(track))
	if ribbons.is_empty():
		return
	var vertex_count := row_count * columns
	vertices.resize(vertex_count)
	colors.resize(vertex_count)
	uv.resize(vertex_count)
	uv2.resize(vertex_count)
	var indices := _indices_for_rows(row_count - 1)
	var vertex_start := 0
	var row_start := 0
	for track in ribbons:
		if row_start > 0:
			# Collapse the triangles between separate ribbons so only each ribbon is drawn.
			var seam := (row_start - 1) * indices_per_row
			for j in indices_per_row:
				indices[seam + j] = vertex_start
		var rows := _write_ribbon(track, camera_right, vertex_start)
		vertex_start += rows * columns
		row_start += rows
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _record(piece: Checker, speed: float) -> void:
	var id := piece.get_instance_id()
	var point := to_local(piece.get_global_transform_interpolated().origin) + Vector3.UP * HEIGHT_OFFSET
	var strength := lerpf(0.06, 0.99, smoothstep(0.24, 3.6, speed))
	var track := histories.get(id) as Track
	if track == null or clock - track.head.time >= LIFETIME:
		if speed < MIN_SPEED:
			return
		track = Track.new()
		track.head = Sample.new(point, clock, 0.0, strength)
		track.samples.append(track.head)
		track.tint = _trail_color(piece)
		track.seed = posmod(hash(id), 1009)
		histories[id] = track
		return

	var previous := track.head
	var segment := previous.point.distance_to(point)
	if segment < 0.0001:
		return
	var distance := previous.distance + segment
	var sample_distance := track.samples[-1].distance + SPACING
	while sample_distance <= distance:
		var weight := (sample_distance - previous.distance) / segment
		track.samples.append(Sample.new(previous.point.lerp(point, weight),
			lerpf(previous.time, clock, weight), sample_distance,
			lerpf(previous.strength, strength, weight)))
		if track.samples.size() > MAX_SAMPLES:
			track.samples.pop_front()
		sample_distance += SPACING
	track.head = Sample.new(point, clock, distance, strength)


func _has_extra_head(track: Track) -> bool:
	return track.head.distance - track.samples[-1].distance >= 0.001


func _indices_for_rows(rows: int) -> PackedInt32Array:
	var count := rows * indices_per_row
	if cached_index_rows < rows:
		canonical_indices.resize(count)
		for row in range(cached_index_rows, rows):
			var row_index := row * indices_per_row
			var vertex := row * columns
			for j in indices_per_row:
				canonical_indices[row_index + j] = vertex + row_indices[j]
		cached_index_rows = rows
	return canonical_indices.slice(0, count)


func _write_ribbon(track: Track, camera_right: Vector3, vertex_start: int) -> int:
	var points: Array[Sample] = track.samples.duplicate()
	if _has_extra_head(track):
		points.append(track.head)
	else:
		points[-1] = track.head
	var last := points.size() - 1
	var taper := minf(TAPER_LENGTH, track.head.distance)
	var offset := track.seed * 0.081
	var centers := _smooth_centers(points)
	var profiles := PackedFloat64Array()
	profiles.resize(points.size())
	for i in points.size():
		profiles[i] = _profile(points[i], track.head.distance - points[i].distance, taper)
	var widths := _ribbon_widths(points, centers, profiles)
	var previous_side := Vector3.ZERO
	var white_profile := 1.0 if track.tint == Color.WHITE else 0.0
	for i in points.size():
		var sample: Sample = points[i]
		var center := centers[i]
		var incoming := centers[maxi(i - 1, 0)].direction_to(center)
		var outgoing := center.direction_to(centers[mini(i + 1, last)])
		var tangent := (incoming + outgoing).normalized()
		if incoming.dot(outgoing) < -0.995:
			tangent = outgoing
		# Keep the ribbon across the board plane so the glow cannot intersect it.
		var side := Vector3.UP.cross(tangent).normalized()
		if side.is_zero_approx():
			side = previous_side if not previous_side.is_zero_approx() else camera_right.slide(Vector3.UP).normalized()
		if side.dot(previous_side) < 0.0:
			side = -side
		previous_side = side

		var lag := track.head.distance - sample.distance
		var profile := profiles[i]
		var width := widths[i]
		var opacity := sample.strength * profile * (2.0 - profile)
		var tint := Color(track.tint, opacity)
		var row_start := vertex_start + i * columns
		# Keep the luminous center on shared vertices so it stays aligned through bends.
		for column in columns:
			var across: float = CROSS_COORDS[column]
			var vertex := row_start + column
			vertices[vertex] = center + side * width * (across * 2.0 - 1.0)
			colors[vertex] = tint
			uv[vertex] = Vector2(across, sample.distance + offset)
			uv2[vertex] = Vector2(white_profile, lag)
	return points.size()


func _smooth_centers(points: Array[Sample]) -> PackedVector3Array:
	var centers := PackedVector3Array()
	centers.resize(points.size())
	for i in points.size():
		var radius := mini(TURN_SMOOTHING_SAMPLES, mini(i, points.size() - 1 - i))
		var weight := radius + 1
		var center := points[i].point * weight
		for step in range(1, weight):
			center += (points[i - step].point + points[i + step].point) * (weight - step)
		centers[i] = center / (weight * weight)
	return centers


func _ribbon_widths(points: Array[Sample], centers: PackedVector3Array,
		profiles: PackedFloat64Array) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	widths.resize(points.size())
	for i in points.size():
		var width := Checker.RADIUS * 1.88 * sqrt(profiles[i])
		if i > 0 and i < points.size() - 1:
			var incoming := centers[i] - centers[i - 1]
			var outgoing := centers[i + 1] - centers[i]
			var turn := (incoming.normalized() - outgoing.normalized()).length()
			if turn > 0.02:
				var step := (incoming.length() + outgoing.length()) * 0.5
				width = minf(width, maxf(0.012, step * 0.80 / turn))
		widths[i] = width
	# Taper across several rows around the curve so the inner edge cannot fold over.
	for i in range(1, widths.size()):
		var step := points[i].distance - points[i - 1].distance
		widths[i] = minf(widths[i], widths[i - 1] + step * WIDTH_CHANGE_PER_UNIT)
	for i in range(widths.size() - 2, -1, -1):
		var step := points[i + 1].distance - points[i].distance
		widths[i] = minf(widths[i], widths[i + 1] + step * WIDTH_CHANGE_PER_UNIT)
	return widths


func _profile(sample: Sample, lag: float, taper: float) -> float:
	var age := 1.0 - smoothstep(0.045, LIFETIME, clock - sample.time)
	var length_fade := 1.0 - smoothstep(0.48, MAX_LENGTH, lag)
	var tip := smoothstep(0.0, taper, sample.distance)
	return age * length_fade * tip


func _trail_color(piece: Checker) -> Color:
	match piece.icon:
		Checker.Icon.SNOWFLAKE: return Color(0.035, 0.40, 1.0)
		Checker.Icon.LIGHTNING: return Color(0.035, 0.19, 1.0)
		Checker.Icon.EXPLOSIVE: return Color(1.0, 0.86, 0.016)
		Checker.Icon.FLOATING: return Color(0.03, 0.80, 0.64)
		Checker.Icon.RUBBER: return Color(1.0, 0.075, 0.40)
	return Color.WHITE
