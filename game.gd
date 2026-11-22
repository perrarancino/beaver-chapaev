extends Node3D

const Beaver := preload("res://beaver.gd")
const Run := preload("res://checker_run.gd")
const LIGHT_PIECE := preload("res://piece_light.tscn")
const DARK_PIECE := preload("res://piece_dark.tscn")
const HIT_FX := preload("res://assets/FX/hitFX_base/hirFX_base.tscn")
const BOARD_APOTHEM := 2.143
const BOARD_TOP := 0.003
const FLOOR_Y := -2.1
const PIECE_Y := 0.07
const TURN_REST_TIME := 0.35
const CAMERA_SCROLL_STEP := 0.125
const CAMERA_SCROLL_SPEED := 11.0
const BOARD_CAMERA_POSITION := Vector3(0.0, 4.35, 4.45)
const GHOST_LANDING_SPEED := 1.25
const SHOT_IMPULSE := 3.0
const DRAG_DEAD_ZONE := 12.0
const MAX_PULL_STRENGTH := 2.8
const PLAY_HINT := "ЛКМ — потяни шашку или край стола  •  Колёсико — ракурс"
const EDGE_NORMALS := [
	Vector3(1, 0, 0), Vector3(0.5, 0, 0.8660254), Vector3(-0.5, 0, 0.8660254),
	Vector3(-1, 0, 0), Vector3(-0.5, 0, -0.8660254), Vector3(0.5, 0, -0.8660254),
]
const DIAMETER := Checker.RADIUS * 2.0
var pieces: Array[Checker] = []
var formations: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var player_setup: Array[Checker.Icon] = []
var enemy_setup: Array[Checker.Icon] = []
var run := Run.new()
var enemy_turns := 0
var defeated: Array[Dictionary] = []
var shot_knockouts: Array[bool] = [false, false]
var contacts: Array[Array] = []
var soft_contacts: Dictionary = {}
var links: Array[Dictionary] = []
var lightning: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var selected: Checker
var aiming := false
var drag_start := Vector2.ZERO
var strike_offset := Vector3.ZERO
var turn := 0 # 0 player, 1 beaver
var phase := "aim"
var still_time := 0.0
var rest_poses: Dictionary[Checker, Transform3D] = {}
var turn_durations_applied := false
var ghost_landings: Dictionary[Checker, Vector3] = {}
var camera: Camera3D
var beaver_camera_transform: Transform3D
var board_camera_transform: Transform3D
var camera_view := 0.0
var camera_view_target := 0.0
var status: Label
var score: Label
var hint: Label
var beaver_subtitle: Label
var power_back: ColorRect
var power_fill: ColorRect
var piece_tooltip: PanelContainer
var piece_tooltip_title: Label
var piece_tooltip_details: Label
var run_overlay: ColorRect
var run_heading: Label
var run_message: Label
var run_choices: VBoxContainer
var preview: MeshInstance3D
var preview_mesh := ImmediateMesh.new()
var preview_material := StandardMaterial3D.new()
var effects_mesh := ImmediateMesh.new()
var effects_material := StandardMaterial3D.new()
var rng := RandomNumberGenerator.new()
var orbiting := false
var board_angle := 0.0
var rotation_proxies: Dictionary[Checker, Node3D] = {}
@onready var beaver: Beaver = $Beaver
@onready var beaver_voice = $Beaver/Voice
@onready var aim_arrow: MeshInstance3D = $AimArrow
@onready var aim_material := aim_arrow.material_override as ShaderMaterial

func _ready() -> void:
	rng.randomize()
	camera = $Camera3D
	beaver_camera_transform = camera.transform
	board_camera_transform = Transform3D(Basis.IDENTITY, BOARD_CAMERA_POSITION).looking_at(
		Vector3(0.0, BOARD_TOP, 0.0))
	_weather_board()
	if OS.has_feature("web"):
		# The room still receives shadows from the board, pieces and beaver.
		for mesh: MeshInstance3D in $Izba.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_ui()
	_build_preview()
	beaver_voice.subtitle_changed.connect(_set_beaver_subtitle)
	get_window().focus_exited.connect(_cancel_aim)
	for piece: Checker in $StartingPieces.get_children():
		formations[piece.side].append(piece.position)
		if piece.side == 0:
			player_setup.append(piece.icon)
		else:
			enemy_setup.append(piece.icon)
		piece.queue_free()
	_start_run()

func _weather_board() -> void:
	var board := get_node("BoardPivot/Board/Three-player chessboard") as MeshInstance3D
	var worn_texture := preload("res://assets/boards/board_worn.webp")
	for surface in board.mesh.get_surface_count():
		var finish := board.mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
		finish.albedo_texture = worn_texture
		if finish.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			finish.albedo_color = Color("e3d9d0")
		else:
			finish.clearcoat = 0.42
		board.set_surface_override_material(surface, finish)

func _material(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _label(parent: Control, text_value: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text_value
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := _label(root, "Ч А П А Е В  /  Б О Б Ё Р", 24, Color("f0d5a7"))
	title.position = Vector2(28, 22)
	score = _label(root, "", 17, Color("bba889"))
	score.position = Vector2(30, 58)
	status = _label(root, "", 25, Color("fff0d1"))
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status.offset_left = -150
	status.offset_right = 150
	status.offset_top = 25
	status.offset_bottom = 65
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	beaver_subtitle = _label(root, "", 19, Color("f3ddbb"))
	beaver_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	beaver_subtitle.offset_left = -210
	beaver_subtitle.offset_right = 210
	beaver_subtitle.offset_top = 72
	beaver_subtitle.offset_bottom = 124
	beaver_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	beaver_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	beaver_subtitle.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.013, 0.9))
	beaver_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	hint = _label(root, PLAY_HINT, 16, Color("eed9b8"))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -280
	hint.offset_right = 280
	hint.offset_top = -62
	hint.offset_bottom = -32
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_back = ColorRect.new()
	power_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_back.color = Color("382d27")
	power_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	power_back.position = Vector2(-100, -28)
	power_back.size = Vector2(200, 6)
	root.add_child(power_back)
	power_fill = ColorRect.new()
	power_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_fill.color = Color("e9a95f")
	power_fill.size = Vector2.ZERO
	power_back.add_child(power_fill)
	_build_tooltip(root)
	_build_run_overlay(root)

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("7b6148")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _build_tooltip(root: Control) -> void:
	piece_tooltip = PanelContainer.new()
	piece_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	piece_tooltip.add_theme_stylebox_override("panel", _panel_style(Color("29211df0")))
	root.add_child(piece_tooltip)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	piece_tooltip.add_child(stack)
	piece_tooltip_title = _label(stack, "", 18, Color("fff0d1"))
	piece_tooltip_details = _label(stack, "", 15, Color("d6bf9f"))
	piece_tooltip_details.custom_minimum_size.x = 246
	piece_tooltip_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	piece_tooltip.hide()

func _build_run_overlay(root: Control) -> void:
	run_overlay = ColorRect.new()
	run_overlay.color = Color("15110dc9")
	root.add_child(run_overlay)
	run_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	run_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 435
	panel.add_theme_stylebox_override("panel", _panel_style(Color("2b221d")))
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 13)
	panel.add_child(stack)
	run_heading = _label(stack, "", 27, Color("fff0d1"))
	run_message = _label(stack, "", 16, Color("dbc39f"))
	run_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_choices = VBoxContainer.new()
	run_choices.add_theme_constant_override("separation", 8)
	stack.add_child(run_choices)
	run_overlay.hide()

func _choice_button(title: String, detail: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 40
	button.add_theme_color_override("font_color", Color("f5dfb8"))
	button.add_theme_stylebox_override("normal", _panel_style(Color("41322a")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("5b4432")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("684e37")))
	button.pressed.connect(action)
	run_choices.add_child(button)
	if run_choices.get_child_count() == 1:
		button.grab_focus()
	if not detail.is_empty():
		var caption := _label(run_choices, detail, 15, Color("dec9aa"))
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _show_run_result(title: String, message: String) -> void:
	for child in run_choices.get_children():
		run_choices.remove_child(child)
		child.queue_free()
	run_heading.text = title
	run_message.text = message
	run_overlay.show()
	piece_tooltip.hide()

func _start_run() -> void:
	run.start(player_setup, rng)
	_new_round()

func _set_beaver_subtitle(text: String) -> void:
	beaver_subtitle.text = "" if text.is_empty() else "«%s»" % text


func _update_camera(delta: float) -> void:
	if camera_view == camera_view_target:
		return
	camera_view = lerpf(camera_view, camera_view_target, 1.0 - exp(-CAMERA_SCROLL_SPEED * delta))
	if is_equal_approx(camera_view, camera_view_target):
		camera_view = camera_view_target
	camera.transform = beaver_camera_transform.interpolate_with(board_camera_transform, camera_view)
	if aiming:
		_draw_aim(_aim_vector(get_viewport().get_mouse_position()))


func _new_round() -> void:
	_clear_links()
	ghost_landings.clear()
	_reset_stillness()
	contacts.clear()
	soft_contacts.clear()
	lightning.clear()
	flashes.clear()
	effects_mesh.clear_surfaces()
	defeated.clear()
	for p in pieces:
		if is_instance_valid(p): p.queue_free()
	pieces.clear()
	_cancel_aim()
	var enemy_roster := run.enemies(enemy_setup)
	for side in 2:
		var roster := run.roster if side == 0 else enemy_roster
		for slot in formations[side].size():
			_make_piece(side, roster[slot], formations[side][slot].rotated(Vector3.UP, board_angle), slot)
	enemy_turns = 2
	turn = 0
	phase = "aim"
	hint.text = PLAY_HINT
	run_overlay.hide()
	_update_ui()

func _make_piece(side: int, icon: Checker.Icon, pos: Vector3, slot: int) -> Checker:
	var scene := LIGHT_PIECE if side == 0 else DARK_PIECE
	var body := scene.instantiate() as Checker
	body.icon = icon
	body.slot = slot
	body.position = pos
	body.rotation.y = board_angle
	add_child(body)
	body.struck.connect(_queue_contact.bind(body))
	for other in pieces:
		if icon == Checker.Icon.ARMORED and other.icon == Checker.Icon.ARMORED:
			body.planar_body.add_collision_exception_with(other.planar_body)
			other.planar_body.add_collision_exception_with(body.planar_body)
	pieces.append(body)
	return body

func _update_ui() -> void:
	score.text = "РАУНД %d / %d     ПОБЕД %d" % [run.stage, Run.STAGES, run.wins]
	if phase == "aim":
		status.text = "ТВОЙ ХОД" if turn == 0 else "БОБЁР ДУМАЕТ…"
	elif phase == "windup":
		status.text = "БОБЁР ЦЕЛИТСЯ…"
	elif phase == "moving":
		status.text = "ШАШКИ В ДЕЛЕ"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_cancel_aim()
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		var steps: float = event.factor if event.factor > 0.0 else 1.0
		camera_view_target = clampf(camera_view_target + direction * steps * CAMERA_SCROLL_STEP, 0.0, 1.0)
		piece_tooltip.hide()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and orbiting:
		_finish_board_rotation()
		return
	if event is InputEventMouseMotion and orbiting:
		board_angle += event.relative.x * 0.006
		$BoardPivot.rotation.y = board_angle
		return
	if phase != "aim" or turn != 0: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var ray_start := camera.project_ray_origin(event.position)
			var hit := _piece_hit(event.position)
			var picked := hit.get("collider") as Checker
			piece_tooltip.hide()
			if picked and picked.side == 0:
				selected = picked
				drag_start = event.position
				var hit_point: Vector3 = hit.position
				strike_offset = (hit_point - picked.global_position).slide(Vector3.UP)
				aiming = true
			elif _is_table_drag(ray_start, camera.project_ray_normal(event.position)):
				_begin_board_rotation()
		elif aiming:
			var piece := selected
			var shot := _aim_vector(event.position)
			var offset := strike_offset
			_cancel_aim()
			if not shot.is_zero_approx():
				_shoot(piece, shot.normalized(), shot.length(), offset)
	if event is InputEventMouseMotion and aiming:
		_draw_aim(_aim_vector(event.position))
	elif event is InputEventMouseMotion:
		_show_piece_info(_piece_hit(event.position).get("collider") as Checker, event.position)

func _piece_hit(cursor: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(cursor)
	var ray := camera.project_ray_normal(cursor)
	var top: Variant = Plane(Vector3.UP, PIECE_Y + Checker.HALF_HEIGHT).intersects_ray(origin, ray)
	var bottom: Variant = Plane(Vector3.UP, PIECE_Y - Checker.HALF_HEIGHT).intersects_ray(origin, ray)
	if top == null or bottom == null:
		return {}
	# Test the part of the mouse ray between the two flat faces of a checker.
	var from := Checker.to_plane(top)
	var to := Checker.to_plane(bottom)
	var radius := Checker.RADIUS * Checker.PIXELS_PER_UNIT
	var nearest := INF
	var picked: Checker
	for piece in pieces:
		if piece.falling:
			continue
		var center := Checker.to_plane(piece.global_position)
		if from.distance_squared_to(center) <= radius * radius:
			return {"collider": piece, "position": top}
		var entry := Geometry2D.segment_intersects_circle(from, to, center, radius)
		if entry >= 0.0 and entry < nearest:
			nearest = entry
			picked = piece
	if picked:
		return {"collider": picked, "position": (top as Vector3).lerp(bottom, nearest)}
	return {}

func _show_piece_info(piece: Checker, cursor: Vector2) -> void:
	piece_tooltip.visible = is_instance_valid(piece)
	if not piece_tooltip.visible:
		return
	piece_tooltip_title.text = Checker.ICON_NAMES[piece.icon]
	piece_tooltip_details.text = Checker.ICON_DETAILS[piece.icon]
	if piece.side == 0 and run.duration[piece.slot] > 0:
		var unit := "ходов" if piece.icon == Checker.Icon.GHOST else "раундов"
		piece_tooltip_details.text += "\nОсталось %s — %d" % [unit, run.duration[piece.slot]]
	var limit := get_viewport().get_visible_rect().size - piece_tooltip.size - Vector2(12, 12)
	piece_tooltip.position = (cursor + Vector2(16, 22)).clamp(Vector2(12, 12), limit)

func _cancel_aim() -> void:
	selected = null
	aiming = false
	strike_offset = Vector3.ZERO
	aim_arrow.hide()
	preview.hide()
	piece_tooltip.hide()
	power_fill.size = Vector2.ZERO

func _draw_aim(shot: Vector3) -> void:
	aim_arrow.visible = not shot.is_zero_approx()
	preview.hide()
	if not aim_arrow.visible:
		power_fill.size = Vector2.ZERO
		return
	var direction := shot.normalized()
	var power := shot.length() / MAX_PULL_STRENGTH
	var start := _on_board(selected.global_position) + direction * (Checker.RADIUS + 0.025)
	var length := minf(lerpf(0.46, 1.72, power), _edge_distance(start, direction))
	aim_arrow.visible = length >= 0.10
	aim_arrow.global_position = start + direction * length * 0.5
	aim_arrow.rotation.y = atan2(direction.x, direction.z)
	aim_arrow.scale.z = length
	aim_material.set_shader_parameter("arrow_length", length)
	if selected.icon == Checker.Icon.SNIPER:
		_draw_trajectory(selected, shot)
	power_fill.size = Vector2(200 * power, 6)

func _build_preview() -> void:
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.no_depth_test = true
	preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_material.albedo_color = Color("f0d7a2d9")
	preview_material.render_priority = 90
	preview = MeshInstance3D.new()
	preview.mesh = preview_mesh
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	effects_material = preview_material.duplicate() as StandardMaterial3D
	effects_material.vertex_color_use_as_albedo = true
	effects_material.albedo_color = Color.WHITE
	effects_material.render_priority = 80
	var effects := MeshInstance3D.new()
	effects.mesh = effects_mesh
	effects.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(effects)

func _on_board(point: Vector3) -> Vector3:
	return Vector3(point.x, BOARD_TOP, point.z)

func _edge_distance(start: Vector3, direction: Vector3, margin := 0.015) -> float:
	var origin: Vector3 = $BoardPivot.to_local(start)
	var local_direction := direction.rotated(Vector3.UP, -board_angle)
	var distance := INF
	for normal: Vector3 in EDGE_NORMALS:
		var speed := local_direction.dot(normal)
		if speed > 0.0001:
			distance = minf(distance, (BOARD_APOTHEM - margin - origin.dot(normal)) / speed)
	return maxf(distance, 0.0)

func _slide_distance(speed: float) -> float:
	var drag := Checker.NORMAL_DAMP
	var friction := Checker.NORMAL_FRICTION * Checker.SLIDE_GRAVITY
	return speed / drag - friction / (drag * drag) * log(1.0 + drag * speed / friction)

func _draw_trajectory(piece: Checker, shot: Vector3) -> void:
	var origin := _on_board(piece.global_position)
	var velocity := shot * SHOT_IMPULSE / piece.mass
	var previous := piece
	var displayed := false
	preview_mesh.clear_surfaces()
	for segment in 4:
		var speed := velocity.length()
		if speed < 0.12:
			break
		var direction := velocity / speed
		var distance := minf(_slide_distance(speed), _edge_distance(origin, direction))
		var target: Checker
		for other in pieces:
			if other == piece or other == previous or other.falling or other.icon == Checker.Icon.GHOST:
				continue
			var offset := _on_board(other.global_position) - origin
			var projection := offset.dot(direction)
			var gap := DIAMETER * DIAMETER - (offset - direction * projection).length_squared()
			if projection <= 0.0 or gap <= 0.0:
				continue
			var intersection := maxf(projection - sqrt(gap), 0.0)
			if intersection < distance:
				target = other
				distance = intersection
		var dash_offset := Checker.RADIUS + 0.025 if segment == 0 else 0.0
		if distance > maxf(dash_offset, 0.025):
			if not displayed:
				preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, preview_material)
				displayed = true
			while dash_offset < distance:
				_draw_line(preview_mesh, origin + direction * dash_offset, origin + direction * minf(dash_offset + 0.055, distance), 0.011)
				dash_offset += 0.10
		if not target:
			break
		origin += direction * distance
		var normal := origin.direction_to(_on_board(target.global_position))
		# Estimate speed at impact with the same sliding and damping as a normal checker.
		var low := 0.0
		var high := speed
		var remaining := _slide_distance(speed) - distance
		for step in 8:
			var guess := (low + high) * 0.5
			if _slide_distance(guess) < remaining: low = guess
			else: high = guess
		velocity = direction * (low + high) * 0.5
		var bounce := piece.contact_material.bounce + target.contact_material.bounce
		var share := target.mass / (piece.mass + target.mass)
		velocity -= normal * velocity.dot(normal) * (1.0 + bounce) * share
		previous = target
	if displayed:
		preview_mesh.surface_end()
		preview.show()

func _draw_line(mesh: ImmediateMesh, start: Vector3, end: Vector3, width: float) -> void:
	var across := (end - start).normalized().cross(Vector3.UP) * width * 0.5
	for point in [start + across, end + across, end - across, start + across, end - across, start - across]:
		mesh.surface_add_vertex(point)

func _begin_board_rotation() -> void:
	orbiting = true
	for piece in pieces:
		piece.planar_body.freeze = true
		var proxy := Node3D.new()
		$BoardPivot.add_child(proxy)
		proxy.global_transform = piece.global_transform
		proxy.add_child(piece.get_node("Visual").duplicate())
		piece.visible = false
		rotation_proxies[piece] = proxy

func _finish_board_rotation() -> void:
	orbiting = false
	for piece in rotation_proxies:
		var proxy := rotation_proxies[piece]
		piece.place_on_board(proxy.global_position, proxy.global_rotation.y)
		piece.visible = true
		piece.planar_body.freeze = false
		piece.stop_motion()
		proxy.queue_free()
	rotation_proxies.clear()

func _is_table_drag(ray_start: Vector3, ray_direction: Vector3) -> bool:
	var hit = Plane(Vector3.UP, -0.35).intersects_ray(ray_start, ray_direction)
	if hit == null:
		return false
	return hit.z > 0.5 and Vector2(hit.x, hit.z).length() <= 2.7

func _pull_strength(drag: Vector2) -> float:
	if drag.length() < 0.001:
		return 0.0
	var direction := drag.normalized()
	var viewport_size := get_viewport().get_visible_rect().size
	var available := INF
	if direction.x > 0.0001:
		available = minf(available, (viewport_size.x - drag_start.x) / direction.x)
	elif direction.x < -0.0001:
		available = minf(available, -drag_start.x / direction.x)
	if direction.y > 0.0001:
		available = minf(available, (viewport_size.y - drag_start.y) / direction.y)
	elif direction.y < -0.0001:
		available = minf(available, -drag_start.y / direction.y)
	return clampf(drag.length() / maxf(available, 1.0) * MAX_PULL_STRENGTH, 0.4, MAX_PULL_STRENGTH)

func _aim_vector(cursor: Vector2) -> Vector3:
	var drag := cursor - drag_start
	if not is_instance_valid(selected) or drag.length_squared() <= DRAG_DEAD_ZONE * DRAG_DEAD_ZONE:
		return Vector3.ZERO
	var origin := _on_board(selected.global_position)
	# Use a nearby point on the screen ray so long pulls never shoot above the plane's horizon.
	var sample := camera.unproject_position(origin) - drag.normalized() * 12.0
	var plane := Plane(Vector3.UP, origin.y)
	var hit: Variant = plane.intersects_ray(
		camera.project_ray_origin(sample), camera.project_ray_normal(sample))
	if hit == null:
		return Vector3.ZERO
	return origin.direction_to(hit) * _pull_strength(drag)

func _shoot(piece: Checker, direction: Vector3, strength: float, offset := Vector3.ZERO) -> void:
	_begin_shot_resolution()
	for p in pieces:
		p.hit_source = null
		p.incoming_velocity = Vector3.ZERO
		p.lightning_used = false
		p.sticky_used = false
	piece.incoming_velocity = direction * strength * SHOT_IMPULSE * piece.shot_multiplier() / piece.mass
	var lever := offset.slide(direction).limit_length(Checker.RADIUS) * 0.30
	_push(piece, piece.incoming_velocity, piece, lever)
	piece_tooltip.hide()

func _begin_shot_resolution() -> void:
	phase = "moving"
	shot_knockouts.fill(false)
	turn_durations_applied = false
	_reset_stillness()
	_update_ui()

func _is_off_board(world_position: Vector3, margin := 0.0) -> bool:
	var local: Vector3 = $BoardPivot.to_local(world_position)
	var x := absf(local.x)
	var z := absf(local.z)
	# The board has one pair of edges parallel to Z and two pairs at 60 degrees.
	return maxf(x, 0.5 * x + 0.8660254 * z) > BOARD_APOTHEM - margin

func _queue_contact(other: Checker, body: Checker) -> void:
	if phase == "moving":
		contacts.append([body, other])

func _pair_id(a: Checker, b: Checker) -> Vector2i:
	return Vector2i(mini(a.slot + a.side * 100, b.slot + b.side * 100),
		maxi(a.slot + a.side * 100, b.slot + b.side * 100))

func _resolve_contacts() -> void:
	var processed := {}
	for pair in contacts:
		var a: Checker = pair[0]
		var b: Checker = pair[1]
		if not is_instance_valid(a) or not is_instance_valid(b) or a.falling or b.falling:
			continue
		var key := _pair_id(a, b)
		if not processed.has(key):
			_touch(a, b, _on_board(a.global_position).direction_to(_on_board(b.global_position)))
			_play_hit_fx(a.global_position.lerp(b.global_position, 0.5))
			processed[key] = true
	contacts.clear()
	var overlaps := {}
	for i in pieces.size():
		var a := pieces[i]
		if a.falling or ghost_landings.has(a): continue
		for j in range(i + 1, pieces.size()):
			var b := pieces[j]
			if b.falling or ghost_landings.has(b): continue
			var ghost := a.icon == Checker.Icon.GHOST or b.icon == Checker.Icon.GHOST
			var armor := a.icon == Checker.Icon.ARMORED and b.icon == Checker.Icon.ARMORED
			if not ghost and not armor: continue
			var offset := _on_board(b.global_position) - _on_board(a.global_position)
			if offset.length_squared() >= DIAMETER * DIAMETER or offset.is_zero_approx():
				continue
			var key := _pair_id(a, b)
			var normal := offset.normalized()
			if ghost:
				overlaps[key] = true
				if not soft_contacts.has(key):
					_ghost_pass(a, b, normal)
			else:
				var penetration := DIAMETER - offset.length() + 0.001
				_armor_contact(a, b, normal, penetration)
	soft_contacts = overlaps

func _play_hit_fx(world_point: Vector3) -> void:
	var fx := HIT_FX.instantiate() as Node3D
	fx.position = to_local(world_point)
	fx.scale = Vector3.ONE * Checker.RADIUS
	add_child(fx)
	var tail := 0.0
	for child in fx.get_children():
		if child is GPUParticles3D:
			child.local_coords = true
			tail = maxf(tail, child.lifetime / child.speed_scale)
	var player := fx.get_node("AnimationPlayer") as AnimationPlayer
	player.play(&"hitFX_base")
	var cleanup := fx.create_tween()
	cleanup.tween_interval(player.current_animation_length + tail)
	cleanup.tween_callback(fx.queue_free)

func _source(piece: Checker) -> Checker:
	return piece.hit_source if is_instance_valid(piece.hit_source) else piece

func _push(piece: Checker, velocity: Vector3, source: Checker, offset := Vector3.ZERO) -> void:
	if piece.falling or velocity.length_squared() < 0.0001:
		return
	piece.hit_source = source
	piece.apply_planar_impulse(velocity, offset)

func _touch(a: Checker, b: Checker, normal: Vector3) -> void:
	var a_speed := a.incoming_velocity.dot(normal)
	var b_speed := -b.incoming_velocity.dot(normal)
	if a_speed > maxf(b_speed, 0.025):
		b.hit_source = _source(a)
	elif b_speed > maxf(a_speed, 0.025):
		a.hit_source = _source(b)
	_trigger_contact(a, b)
	_trigger_contact(b, a)

func _ghost_pass(a: Checker, b: Checker, normal: Vector3) -> void:
	if a.icon == Checker.Icon.GHOST and b.icon == Checker.Icon.GHOST:
		return
	if b.icon == Checker.Icon.GHOST:
		_ghost_pass(b, a, -normal)
		return
	var closing_speed := (a.linear_velocity - b.linear_velocity).dot(normal)
	if closing_speed <= 0.025:
		return
	b.linear_velocity *= 0.62
	_push(b, normal * clampf(closing_speed * 0.14, 0.12, 0.65), a)
	_trigger_contact(b, a)

func _armor_contact(a: Checker, b: Checker, normal: Vector3, penetration: float) -> void:
	var a_forward := a.linear_velocity.dot(normal)
	var b_forward := -b.linear_velocity.dot(normal)
	var closing := a_forward + b_forward
	a.place_on_board(a.global_position - normal * penetration * 0.5, a.global_rotation.y)
	b.place_on_board(b.global_position + normal * penetration * 0.5, b.global_rotation.y)
	if closing <= 0.025:
		return
	# Equal and opposite impulses keep a pair of armored discs moving along the hit.
	var attacker := a if a_forward >= b_forward else b
	var defender := b if attacker == a else a
	var forward := attacker.linear_velocity.normalized()
	var approach := (attacker.linear_velocity - defender.linear_velocity).dot(forward)
	var transfer := forward * maxf(minf(approach, closing), 0.0) * 0.52
	var source := _source(attacker)
	_push(attacker, -transfer, source)
	_push(defender, transfer, source)

func _trigger_contact(piece: Checker, other: Checker) -> void:
	match piece.icon:
		Checker.Icon.EXPLOSIVE:
			if piece.fuse < 0.0 and not piece.exploded:
				piece.start_fuse()
		Checker.Icon.LIGHTNING:
			if not piece.lightning_used:
				piece.lightning_used = true
				lightning.append({"source": piece, "next": other, "origin": _on_board(piece.global_position),
					"seen": [piece], "delay": 0.0})
		Checker.Icon.STICKY:
			if not piece.sticky_used and other.icon != Checker.Icon.GHOST:
				_stick_pieces(piece, other)

func _stick_pieces(a: Checker, b: Checker) -> void:
	for link in links:
		if a in link.bodies or b in link.bodies:
			return
	a.sticky_used = true
	b.sticky_used = true
	var joint := PinJoint2D.new()
	add_child(joint)
	joint.global_position = (a.planar_body.position + b.planar_body.position) * 0.5
	joint.node_a = joint.get_path_to(a.planar_body)
	joint.node_b = joint.get_path_to(b.planar_body)
	a.planar_body.sleeping = false
	b.planar_body.sleeping = false
	links.append({"bodies": [a, b], "joint": joint, "time": 1.15})

func _release_link(index: int) -> void:
	var joint: PinJoint2D = links[index].joint
	joint.node_a = NodePath()
	joint.node_b = NodePath()
	joint.queue_free()
	links.remove_at(index)

func _clear_links() -> void:
	for i in range(links.size() - 1, -1, -1):
		_release_link(i)

func _tick_effects(delta: float) -> bool:
	for i in range(links.size() - 1, -1, -1):
		var link := links[i]
		link.time -= delta
		if link.time <= 0.0 or link.bodies[0].falling or link.bodies[1].falling:
			_release_link(i)
	var armed := false
	for piece in pieces:
		if piece.fuse >= 0.0:
			piece.fuse -= delta
			if piece.fuse <= 0.0:
				_explode(piece)
			else:
				armed = true
	for i in range(lightning.size() - 1, -1, -1):
		var chain := lightning[i]
		chain.delay -= delta
		if chain.delay <= 0.0 and not _lightning_hop(chain):
			lightning.remove_at(i)
	return armed or not links.is_empty() or not lightning.is_empty()

func _explode(bomb: Checker) -> void:
	bomb.fuse = -1.0
	bomb.exploded = true
	var center := _on_board(bomb.fuse_origin if bomb.falling else bomb.global_position)
	flashes.append({"from": center, "to": center, "time": 0.52, "blast": true})
	for piece in pieces:
		if piece == bomb or piece.falling or piece.icon == Checker.Icon.GHOST:
			continue
		var offset := _on_board(piece.global_position) - center
		var strength := 5.2 * (1.0 - offset.length() / 1.12)
		if strength > 0.0:
			_push(piece, offset.normalized() * strength, bomb)
	if not bomb.falling:
		bomb.set_icon(Checker.Icon.NONE)

func _lightning_hop(chain: Dictionary) -> bool:
	var target: Checker = chain.next
	if not is_instance_valid(target) or target.falling or target.icon == Checker.Icon.GHOST:
		target = _find_lightning_target(chain.origin, chain.seen)
	if not target:
		return false
	var endpoint := _on_board(target.global_position)
	flashes.append({"from": chain.origin, "to": endpoint, "time": 0.24, "blast": false})
	var source: Checker = chain.source if is_instance_valid(chain.source) else null
	_push(target, (endpoint - chain.origin).normalized() * 0.56, source)
	chain.seen.append(target)
	chain.origin = endpoint
	chain.next = null
	chain.delay = 0.10
	return chain.seen.size() < 5

func _find_lightning_target(origin: Vector3, seen: Array) -> Checker:
	var available: Array[Checker] = []
	for piece in pieces:
		if not piece.falling and piece.icon != Checker.Icon.GHOST and piece not in seen:
			available.append(piece)
	available.sort_custom(func(a: Checker, b: Checker) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	if available.is_empty():
		return null
	return available[rng.randi_range(0, mini(available.size(), 4) - 1)]

func _process(delta: float) -> void:
	_update_camera(delta)
	var armed: Array[Checker] = []
	if phase == "moving":
		for p in pieces:
			if p.fuse >= 0.0:
				armed.append(p)
	if flashes.is_empty() and armed.is_empty() and effects_mesh.get_surface_count() == 0:
		return
	effects_mesh.clear_surfaces()
	for i in range(flashes.size() - 1, -1, -1):
		flashes[i].time -= delta
		if flashes[i].time <= 0.0:
			flashes.remove_at(i)
	if flashes.is_empty() and armed.is_empty():
		return
	effects_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, effects_material)
	for bomb in armed:
		var center := _on_board(bomb.fuse_origin if bomb.falling else bomb.global_position)
		var brightness := 0.54 + sin(bomb.fuse * lerpf(24.0, 8.0, bomb.fuse * 0.5)) * 0.28
		_draw_ring(center, Checker.RADIUS * 1.22, 0.019, Color(1.0, 0.60, 0.28, brightness))
	for flash in flashes:
		if flash.blast:
			var progress: float = 1.0 - flash.time / 0.52
			var radius := lerpf(0.10, 1.12, progress)
			_draw_ring(flash.from, radius, 0.022, Color(1.0, 0.59, 0.25, 1.0 - progress))
		else:
			var from: Vector3 = flash.from
			var to: Vector3 = flash.to
			var across := from.direction_to(to).cross(Vector3.UP)
			var previous := from
			effects_mesh.surface_set_color(Color(0.65, 0.89, 1.0, flash.time / 0.24))
			for i in range(1, 8):
				var point := from.lerp(to, i / 8.0) + across * sin(i * 4.3 + flash.time * 45.0) * 0.045
				_draw_line(effects_mesh, previous, point, 0.024)
				previous = point
			_draw_line(effects_mesh, previous, to, 0.024)
	effects_mesh.surface_end()

func _draw_ring(center: Vector3, radius: float, width: float, color: Color) -> void:
	effects_mesh.surface_set_color(color)
	for i in 32:
		var from := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 32.0) * radius
		var to := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * (i + 1) / 32.0) * radius
		_draw_line(effects_mesh, from, to, width)

func _keep_on_board(piece: Checker) -> void:
	var point: Vector3 = $BoardPivot.to_local(piece.global_position)
	var velocity := piece.linear_velocity.rotated(Vector3.UP, -board_angle)
	for iteration in 2:
		for normal: Vector3 in EDGE_NORMALS:
			var overshoot := point.dot(normal) - (BOARD_APOTHEM - Checker.RADIUS)
			if overshoot > 0:
				point -= normal * overshoot
				if velocity.dot(normal) > 0.0:
					velocity = velocity.bounce(normal) * 0.72
	piece.place_on_board($BoardPivot.to_global(point), piece.global_rotation.y)
	piece.linear_velocity = velocity.rotated(Vector3.UP, board_angle)

func _eliminate(piece: Checker) -> void:
	piece.fuse_origin = piece.global_position
	piece.leave_board()
	if not shot_knockouts[piece.side]:
		shot_knockouts[piece.side] = true
		beaver_voice.react_to_knockout(piece.side == 1)
	defeated.append({"side": piece.side, "icon": piece.icon, "slot": piece.slot, "used": piece.exploded})
	var source := piece.hit_source
	if is_instance_valid(source) and not source.falling and source.side != piece.side and source.icon == Checker.Icon.VAMPIRE:
		_revive_ally(source)

func _revive_ally(vampire: Checker) -> void:
	for i in defeated.size():
		var lost := defeated[i]
		if lost.side != vampire.side:
			continue
		var spot := _free_spot(vampire.side, lost.slot)
		if spot == Vector3.INF:
			return
		var icon: Checker.Icon = lost.icon
		if vampire.side == 0 and not lost.used:
			icon = run.roster[lost.slot]
		if icon == Checker.Icon.GHOST and vampire.side == 1 and enemy_turns <= 0:
			icon = Checker.Icon.NONE
		_make_piece(vampire.side, icon, spot, lost.slot)
		defeated.remove_at(i)
		return

func _free_spot(side: int, slot: int, ignore: Checker = null) -> Vector3:
	var home := formations[side][slot].rotated(Vector3.UP, board_angle)
	if _spot_is_clear(home, ignore):
		return home
	for ring in range(1, 6):
		for i in ring * 8:
			var point := Vector3(0, PIECE_Y, 0) + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / (ring * 8)) * (0.36 * ring)
			if _spot_is_clear(point, ignore):
				return point
	return Vector3.INF

func _spot_is_clear(point: Vector3, ignore: Checker) -> bool:
	if _is_off_board(point):
		return false
	for other in pieces:
		if other != ignore and not other.falling and other.global_position.distance_squared_to(point) < 0.325 * 0.325:
			return false
	return true

func _physics_process(delta: float) -> void:
	if phase != "moving": return
	for p in pieces:
		if not p.falling:
			p.sync_planar_position()
			p.apply_slide_friction(delta)
	_resolve_contacts()
	var pending := _tick_effects(delta)
	var landing := _tick_ghost_landings(delta)
	var moving := false
	var falling := false
	for i in range(pieces.size() - 1, -1, -1):
		var p := pieces[i]
		if not p.falling:
			if p.stays_on_board():
				if _is_off_board(p.global_position, Checker.RADIUS):
					_keep_on_board(p)
			elif _is_off_board(p.global_position):
				_eliminate(p)
		if p.falling:
			p.animate_fall(delta, FLOOR_Y)
			if p.floor_time >= 0.22 and p.fuse < 0.0:
				pieces.remove_at(i)
				p.queue_free()
				continue
			falling = true
		else:
			p.incoming_velocity = p.linear_velocity
			moving = moving or p.is_in_motion()
	if moving or falling or pending or landing or not _rest_poses_are_stable():
		_reset_stillness()
		return
	still_time += delta
	if still_time < TURN_REST_TIME:
		return
	if not turn_durations_applied and _apply_turn_durations():
		_reset_stillness()
		return
	_finish_shot()

func _reset_stillness() -> void:
	still_time = 0.0
	rest_poses.clear()

func _rest_poses_are_stable() -> bool:
	for p in pieces:
		var pose := p.global_transform
		if not rest_poses.has(p):
			rest_poses[p] = pose
			continue
		var rest_pose := rest_poses[p]
		var drift := pose.origin - rest_pose.origin
		if drift.length_squared() > 0.006 * 0.006:
			return false
		var angle := pose.basis.get_rotation_quaternion().angle_to(rest_pose.basis.get_rotation_quaternion())
		if absf(angle) > deg_to_rad(3.0):
			return false
	return true

func _apply_turn_durations() -> bool:
	turn_durations_applied = true
	run.finish_turn()
	enemy_turns -= 1
	var settling_ghost := false
	for p in pieces:
		if p.icon != Checker.Icon.GHOST:
			continue
		var expired := run.roster[p.slot] != Checker.Icon.GHOST if p.side == 0 else enemy_turns <= 0
		if not expired:
			continue
		var landing := _find_ghost_landing(p)
		if landing == Vector3.INF:
			continue
		settling_ghost = true
		if landing.is_equal_approx(p.global_position):
			_materialize_ghost(p)
		else:
			ghost_landings[p] = landing
	return settling_ghost

func _find_ghost_landing(piece: Checker) -> Vector3:
	var origin := piece.global_position
	if _ghost_landing_is_clear(piece, origin):
		return origin
	const SEARCH_STEP := Checker.RADIUS / 3.0
	var search_rings := ceili(BOARD_APOTHEM * 2.4 / SEARCH_STEP)
	for ring in range(1, search_rings + 1):
		for i in ring * 8:
			var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / (ring * 8))
			var point := origin + direction * (SEARCH_STEP * ring)
			if _ghost_landing_is_clear(piece, point):
				return point
	return Vector3.INF

func _ghost_landing_is_clear(piece: Checker, position: Vector3) -> bool:
	if _is_off_board(position, Checker.RADIUS):
		return false
	const CLEARANCE := DIAMETER + 0.008
	for other in pieces:
		if other == piece or other.falling:
			continue
		if (other.global_position - position).slide(Vector3.UP).length_squared() < CLEARANCE * CLEARANCE:
			return false
		if ghost_landings.has(other):
			if (ghost_landings[other] - position).slide(Vector3.UP).length_squared() < CLEARANCE * CLEARANCE:
				return false
	return true

func _tick_ghost_landings(delta: float) -> bool:
	if ghost_landings.is_empty():
		return false
	# These discs stay non-solid until they have reached their landing positions.
	for piece: Checker in ghost_landings.keys():
		var destination := ghost_landings[piece]
		var point := piece.global_position.move_toward(destination, GHOST_LANDING_SPEED * delta)
		piece.place_on_board(point, piece.global_rotation.y)
		if not piece.global_position.is_equal_approx(destination):
			continue
		ghost_landings.erase(piece)
		if _ghost_landing_is_clear(piece, destination):
			_materialize_ghost(piece)
		else:
			var new_destination := _find_ghost_landing(piece)
			if new_destination != Vector3.INF:
				ghost_landings[piece] = new_destination
	return true

func _materialize_ghost(piece: Checker) -> void:
	piece.set_icon(Checker.Icon.NONE)
	piece.planar_body.sleeping = false

func _finish_shot() -> void:
	contacts.clear()
	soft_contacts.clear()
	var counts := [0, 0]
	for p in pieces:
		p.stop_motion()
		counts[p.side] += 1
	if counts[0] == 0 or counts[1] == 0:
		phase = "round_end"
		run.finish_round()
		var result_cue: StringName
		if counts[0] == 0 and counts[1] == 0:
			status.text = "НИЧЬЯ!"
			result_cue = &"draw"
		elif counts[1] == 0:
			run.wins += 1
			status.text = "ТЫ ПОБЕДИЛ!"
			result_cue = &"lose"
		else:
			status.text = "БОБЁР ПОБЕДИЛ"
			result_cue = &"win"
		_update_ui()
		hint.text = ""
		await beaver_voice.speak(result_cue)
		_offer_next_round(counts[0], counts[1])
		return
	turn = 1 - turn
	phase = "aim"
	_update_ui()
	if turn == 1:
		await get_tree().create_timer(0.38).timeout
		if phase == "aim" and turn == 1: _bot_shoot()

func _offer_next_round(players: int, opponents: int) -> void:
	if players == 0 and opponents == 0:
		_show_run_result("Ничья", "Переиграй этот раунд.")
		_choice_button("Переиграть раунд", "", _new_round)
	elif players == 0 or run.wins == Run.STAGES:
		var title := "Бобёр выиграл забег" if players == 0 else "Забег пройден"
		_show_run_result(title, "Выиграно раундов — %d из %d." % [run.wins, Run.STAGES])
		_choice_button("Начать новый забег", "", _start_run)
	else:
		phase = "reward"
		_show_run_result("Выбери шашку", "Она войдёт в твой состав со следующего раунда.")
		for icon in run.offer():
			_choice_button(Checker.ICON_NAMES[icon], Checker.ICON_DETAILS[icon], _choose_reward.bind(icon))

func _choose_reward(icon: Checker.Icon) -> void:
	if phase == "reward":
		run.choose(icon)
		_new_round()

func _bot_shoot() -> void:
	var mine: Array[Checker] = []
	var enemies: Array[Checker] = []
	for p in pieces:
		if not is_instance_valid(p) or p.is_queued_for_deletion() or p.falling: continue
		if p.side == 1: mine.append(p)
		else: enemies.append(p)
	if mine.is_empty() or enemies.is_empty():
		_begin_shot_resolution()
		return
	var best: Checker
	var best_setup: Beaver.ShotSetup
	var direction := Vector3.ZERO
	var best_score := INF
	for piece in mine:
		for enemy in enemies:
			var shot := enemy.global_position - piece.global_position
			shot.y = 0
			var setup := beaver.shot_setup(piece.global_position, shot.normalized())
			if setup == null: continue
			var cost := setup.cost + shot.length() * 0.30 + rng.randf_range(0.0, 0.16)
			if cost < best_score:
				best_score = cost
				best_setup = setup
				best = piece
				direction = shot.normalized()
	if best == null:
		# Reposition a checker toward the center when there's no reachable shot at an opponent.
		for piece in mine:
			var inward := -Vector3(piece.position.x, 0.0, piece.position.z).normalized()
			if inward.is_zero_approx(): inward = Vector3.BACK
			var shot := global_basis * inward
			var setup := beaver.shot_setup(piece.global_position, shot)
			if setup != null and setup.cost < best_score:
				best_score = setup.cost
				best_setup = setup
				best = piece
				direction = shot
	if best == null:
		_begin_shot_resolution()
		return
	phase = "windup"
	_update_ui()
	await beaver.wait_for_stance()
	await beaver_voice.speak(&"aim")
	if is_instance_valid(best) and not best.is_queued_for_deletion():
		var ready := await beaver.wind_up(best.global_position, direction, best_setup)
		if ready and is_instance_valid(best) and not best.is_queued_for_deletion():
			var hit := await beaver.strike(best.global_position, direction)
			if hit and is_instance_valid(best) and not best.is_queued_for_deletion():
				_shoot(best, direction, rng.randf_range(1.8, 2.5) + (run.stage - 1) * 0.04)
				beaver.recover(direction)
				return
		if ready:
			await beaver.recover()
	_begin_shot_resolution()
