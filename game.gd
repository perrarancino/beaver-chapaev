extends Node3D

const Beaver := preload("res://beaver.gd")
const Run := preload("res://checker_run.gd")
const PlayerHand := preload("res://player_hand.gd")
const LIGHT_PIECE := preload("res://piece_light.tscn")
const DARK_PIECE := preload("res://piece_dark.tscn")
const CheckerStrikeEffects := preload("res://assets/FX/checker_strike_effects.gd")
const CheckerTrails := preload("res://assets/FX/checker_trails.gd")
const CheckerBlast := preload("res://assets/FX/checker_blast.gd")
const STICKY_SLIME_SHADER := preload("res://assets/FX/checker_sticky_slime.gdshader")
const MUSIC_TRACKS: Array[AudioStream] = [
	preload("res://assets/music/khitryi_umysel.mp3"),
	preload("res://assets/music/balalaechnyi_manevr.mp3"),
	preload("res://assets/music/nochnoi_tropar.mp3"),
	preload("res://assets/music/tainaya_zasada.mp3"),
]
const BOARD_APOTHEM := 2.143
const BOARD_TOP := 0.003
const TABLE_TOP := -0.132
const TABLE_RADIUS := 2.86
const FLOOR_Y := -2.1
const ROOM_FLOOR := Rect2(-7.50, -9.30, 14.98, 16.72)
const PIECE_Y := 0.07
const TURN_REST_TIME := 0.35
const CAMERA_SCROLL_STEP := 0.125
const CAMERA_SCROLL_SPEED := 11.0
const BOARD_ROTATION_SPEED := 0.006
const INTRO_CAMERA_POSITION := Vector3(0.0, 2.2, 0.95)
const BOARD_CAMERA_POSITION := Vector3(0.0, 4.35, 4.45)
const FLOAT_HEIGHT := 0.27
const FLOAT_RANGE := Checker.RADIUS * 6.0
const FLOAT_LIFT_SPEED := 1.35
const GHOST_LANDING_CLEARANCE := Checker.RADIUS * 2.0 + 0.008
const SHOT_IMPULSE := 3.0
const DRAG_DEAD_ZONE := 12.0
const MIN_PULL_STRENGTH := 0.4
const MAX_PULL_STRENGTH := 2.8
const HAND_HOVER_CEILING := 3.6
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
var shot_knockouts: Array[bool] = [false, false]
var contacts: Array[Array] = []
var links: Array[Dictionary] = []
var lightning: Array[Dictionary] = []
var selected: Checker
var aiming := false
var drag_start := Vector2.ZERO
var strike_offset := Vector3.ZERO
var turn := 0 # 0 player, 1 beaver
var phase := "intro":
	set(value):
		phase = value
		var player_turn := _is_player_turn()
		for piece in pieces:
			piece.show_turn_aura(player_turn)
var still_time := 0.0
var rest_poses: Dictionary[Checker, Transform3D] = {}
var phasing_piece: Checker
var ghost_previous_position := Vector2.ZERO
var ghost_contacts: Array[Checker] = []
var action_camera := preload("res://checker_action_camera.gd").new()
var player_hand := PlayerHand.new()
var hand_waiting_for_motion := false
var camera: Camera3D
var beaver_camera_transform: Transform3D
var board_camera_transform: Transform3D
var camera_view := 0.0
var camera_view_target := 0.0
var intro_ui: Control
var intro_transition: Tween
var beaver_subtitle: Label
var volume_control: PanelContainer
var score_hud := VBoxContainer.new()
var score_label: Label
var score_popups := Control.new()
var pending_popups: Array[Label] = []
var turn_start_score := 0
var run_overlay: ColorRect
var run_heading: Label
var run_message: Label
var run_choices: VBoxContainer
var preview: MeshInstance3D
var preview_mesh := ImmediateMesh.new()
var preview_material := StandardMaterial3D.new()
var effects_mesh := ImmediateMesh.new()
var effects_material := StandardMaterial3D.new()
var strike_effects := CheckerStrikeEffects.new()
var checker_trails := CheckerTrails.new()
var blast_effects := Node3D.new()
var sticky_slime_mesh := PlaneMesh.new()
var rng := RandomNumberGenerator.new()
var orbiting := false
var music_queue: Array[AudioStream] = []
@onready var background_music: AudioStreamPlayer = $BackgroundMusic
@onready var checker_strike_sound: AudioStreamPlayer = $CheckerSounds/Strike
@onready var checker_hit_sound: AudioStreamPlayer = $CheckerSounds/Hit
@onready var checker_explosion_sound: AudioStreamPlayer = $CheckerSounds/Explosion
@onready var checker_lightning_sound: AudioStreamPlayer = $CheckerSounds/Lightning
@onready var checker_ghost_touch_sound: AudioStreamPlayer = $CheckerSounds/GhostTouch
@onready var board_pivot: Node3D = $BoardPivot
@onready var beaver: Beaver = $Beaver
@onready var beaver_voice = $Beaver/Voice
@onready var aim_arrow: MeshInstance3D = $AimArrow
@onready var aim_material := aim_arrow.material_override as ShaderMaterial

func _ready() -> void:
	rng.randomize()
	_start_lamp_flicker()
	background_music.volume_db = linear_to_db(0.2)
	background_music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	background_music.finished.connect(_play_next_music_track)
	camera = $Camera3D
	action_camera.camera = camera
	action_camera.room_bounds = ROOM_FLOOR
	beaver_camera_transform = camera.transform
	board_camera_transform = Transform3D(Basis.IDENTITY, BOARD_CAMERA_POSITION).looking_at(
		Vector3(0.0, BOARD_TOP, 0.0))
	if OS.has_feature("web"):
		# The room still receives shadows from the board, pieces and beaver.
		for mesh: MeshInstance3D in $Izba.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_ui()
	_build_preview()
	var slime_material := ShaderMaterial.new()
	slime_material.shader = STICKY_SLIME_SHADER
	sticky_slime_mesh.material = slime_material
	sticky_slime_mesh.size = Vector2(0.26, 0.31)
	player_hand.name = &"PlayerHand"
	add_child(player_hand)
	board_pivot.add_child(checker_trails)
	board_pivot.add_child(strike_effects)
	board_pivot.add_child(blast_effects)
	beaver_voice.subtitle_changed.connect(_set_beaver_subtitle)
	get_window().focus_exited.connect(_end_player_drag)
	for piece: Checker in $StartingPieces.get_children():
		formations[piece.side].append(piece.position)
		if piece.side == 0:
			player_setup.append(piece.icon)
		else:
			enemy_setup.append(piece.icon)
		piece.queue_free()
	_play_intro.call_deferred()

func _start_lamp_flicker() -> void:
	var key_light: SpotLight3D = $KeyLight
	var pendant_light: OmniLight3D = $Izba/PendantLight
	var diffuser: MeshInstance3D = $Izba/WinterLodge/Izba/HangingLamp/Diffuser
	var glass := diffuser.get_active_material(0).duplicate() as StandardMaterial3D
	diffuser.set_surface_override_material(0, glass)
	var key_energy := key_light.light_energy
	var pendant_energy := pendant_light.light_energy
	var glass_energy := glass.emission_energy_multiplier
	var set_level := func(level: float) -> void:
		key_light.light_energy = key_energy * level
		pendant_light.light_energy = pendant_energy * level
		glass.emission_energy_multiplier = glass_energy * level
	_schedule_lamp_flicker(set_level)

func _schedule_lamp_flicker(set_level: Callable) -> void:
	var flicker := create_tween().set_trans(Tween.TRANS_SINE)
	flicker.tween_interval(randf_range(22.0, 40.0))
	flicker.tween_method(set_level, 1.0, 0.72, 0.065)
	flicker.tween_method(set_level, 0.72, 0.97, 0.075)
	flicker.tween_method(set_level, 0.97, 0.86, 0.055)
	flicker.tween_method(set_level, 0.86, 1.0, 0.14)
	flicker.finished.connect(_schedule_lamp_flicker.bind(set_level), CONNECT_ONE_SHOT)

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
	_build_intro_ui(root)
	_build_run_overlay(root)
	_build_volume_control(root)
	_build_score_hud(root)

func _build_score_hud(root: Control) -> void:
	root.add_child(score_hud)
	score_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	score_hud.offset_left = 16
	score_hud.offset_top = -16
	score_hud.offset_bottom = -16
	score_hud.alignment = BoxContainer.ALIGNMENT_END
	score_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	score_label = _label(score_hud, "", 18, Color("fff1d5"))
	score_label.add_theme_stylebox_override("normal", _panel_style(Color("30231bee")))
	root.add_child(score_popups)
	score_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	score_hud.hide()


func _refresh_score() -> void:
	score_label.text = "Очки  %d     Серия ходов  %d  ·  ×%d" % [
		run.score, run.streak, maxi(1, run.streak)]


func _award(piece: Checker, knockout := false) -> void:
	if turn != 0 or phase != "moving" or piece.side != 1:
		return
	var points := run.award(piece.slot, knockout)
	if points == 0:
		return
	_refresh_score()
	var action := "Вылет" if knockout else "Попадание"
	var multiplier := str(run.action_multiplier()).trim_suffix(".0").replace(".", ",")
	var font_size := 26 + roundi(12.0 * (run.action_multiplier() - 1.0))
	font_size = maxi(14, roundi(font_size * minf(1.0, score_popups.size.x / 650.0)))
	var popup := _score_popup("%s!  ×%s" % [action, multiplier], font_size,
		Color("ffac78") if knockout else Color("ffe6a6"))
	var widest := popup.get_theme_font("font").get_string_size(
		"Попадание!  ×3,9", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	popup.custom_minimum_size.x = ceilf(widest.x) + popup.get_theme_stylebox("normal").get_minimum_size().x
	_queue_score_popup(popup, _animate_score_event.bind(popup))


func _animate_score_event(popup: Label) -> void:
	var tween := popup.create_tween().set_ignore_time_scale(true)
	tween.tween_interval(0.62)
	tween.tween_property(popup, "modulate:a", 0.0, 0.20)
	tween.tween_callback(_dismiss_score_popup.bind(popup))


func _score_popup(caption: String, font_size: int, ink: Color) -> Label:
	var popup := _label(score_popups, caption, font_size, ink)
	popup.hide()
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_stylebox_override("normal", _panel_style(Color("302019f5")))
	popup.rotation_degrees = randf_range(-10.0, 10.0)
	return popup


func _queue_score_popup(popup: Label, animate: Callable, centered := false) -> void:
	popup.reset_size()
	popup.pivot_offset = popup.size * 0.5
	popup.set_meta("centered", centered)
	popup.visibility_changed.connect(animate, CONNECT_ONE_SHOT)
	pending_popups.append(popup)
	_place_pending_popups()


func _dismiss_score_popup(popup: Label) -> void:
	popup.hide()
	popup.queue_free()
	_place_pending_popups()


func _place_pending_popups() -> void:
	while not pending_popups.is_empty():
		var popup := pending_popups[0]
		var center := _free_popup_center(popup)
		if center == Vector2.INF:
			break
		pending_popups.pop_front()
		popup.position = center - popup.pivot_offset
		popup.scale = Vector2.ONE * 0.78
		popup.show()
		var punch := popup.create_tween().set_ignore_time_scale(true)
		punch.tween_property(popup, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _popup_extent(popup: Label) -> Vector2:
	var half := popup.size * 0.52 # Includes the entrance tween's overshoot.
	var c := absf(cos(popup.rotation))
	var s := absf(sin(popup.rotation))
	return Vector2(c * half.x + s * half.y, s * half.x + c * half.y) + Vector2(4, 4)


func _free_popup_center(popup: Label) -> Vector2:
	var area := score_popups.size
	var extent := _popup_extent(popup)
	var left := clampf(extent.x, area.x * 0.25, area.x * 0.5)
	var top := minf(extent.y, area.y / 6.0)
	var centered: bool = popup.get_meta("centered")
	var occupied: Array[Rect2] = []
	for older: Label in score_popups.get_children():
		if older.visible:
			var radius := _popup_extent(older)
			occupied.append(Rect2(older.position + older.pivot_offset - radius, radius * 2.0))
	for attempt in (1 if centered else 32):
		var center := area * 0.5
		if not centered:
			center = Vector2(randf_range(left, area.x - left), randf_range(top, area.y / 3.0 - top))
		var bounds := Rect2(center - extent, extent * 2.0)
		var free := true
		for other in occupied:
			if bounds.intersects(other):
				free = false
				break
		if free:
			return center
	return Vector2.INF


func _show_turn_style(points: int, multiplier: int) -> void:
	var format_text := "Стиль!\n%d очков   ·   Серия ×%d"
	# Reserve the final width so the counter stays centered while the digits change.
	var popup := _score_popup(format_text % [points, multiplier], 32, Color("ffe6a6"))
	popup.custom_minimum_size = popup.get_combined_minimum_size()
	_queue_score_popup(popup, _animate_turn_style.bind(popup, format_text, points, multiplier), true)


func _animate_turn_style(popup: Label, format_text: String, points: int, multiplier: int) -> void:
	var count := func(value: float) -> void:
		popup.text = format_text % [roundi(value), multiplier]
	count.call(0.0)
	var tween := popup.create_tween().set_ignore_time_scale(true)
	tween.tween_method(count, 0.0, float(points), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.65)
	tween.tween_property(popup, "modulate:a", 0.0, 0.18)
	tween.tween_callback(_dismiss_score_popup.bind(popup))


func _build_intro_ui(root: Control) -> void:
	intro_ui = Control.new()
	intro_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(intro_ui)
	intro_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := _label(intro_ui, "Ч А П А Е В  /  Б О Б Ё Р", 24, Color("f0d5a7"))
	title.position = Vector2(28, 22)
	beaver_subtitle = _label(intro_ui, "", 25, Color("f3ddbb"))
	beaver_subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	beaver_subtitle.offset_left = 20
	beaver_subtitle.offset_right = -20
	beaver_subtitle.offset_top = -112
	beaver_subtitle.offset_bottom = -32
	beaver_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	beaver_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	beaver_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	beaver_subtitle.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.013, 0.9))
	beaver_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	var skip_hint := _label(intro_ui, "Пробел — пропустить", 15, Color("d6c3a2"))
	skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	skip_hint.offset_top = -29
	skip_hint.offset_bottom = -5
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_volume_control(root: Control) -> void:
	volume_control = PanelContainer.new()
	volume_control.mouse_force_pass_scroll_events = false
	volume_control.add_theme_stylebox_override("panel", _panel_style(Color("2b221df0")))
	root.add_child(volume_control)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	volume_control.add_child(row)
	_label(row, "Громкость", 16, Color("f5dfb8"))
	var slider := HSlider.new()
	slider.name = &"Volume"
	slider.custom_minimum_size.x = 116
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.step = 1.0
	slider.value = 0.0 if AudioServer.is_bus_mute(0) else db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0
	slider.value_changed.connect(_set_master_volume)
	row.add_child(slider)
	volume_control.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	volume_control.hide()

func _set_master_volume(percent: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(percent / 100.0, 0.001)))
	AudioServer.set_bus_mute(0, is_zero_approx(percent))

func _start_background_music() -> void:
	if background_music.stream == null:
		_play_next_music_track()

func _play_next_music_track() -> void:
	if music_queue.is_empty():
		music_queue.assign(MUSIC_TRACKS)
		music_queue.shuffle()
		# The first track drawn after a reshuffle must differ from the last one played.
		if music_queue.back() == background_music.stream:
			music_queue.push_front(music_queue.pop_back())
	background_music.stream = music_queue.pop_back()
	background_music.play()

func _play_intro() -> void:
	if phase != "intro":
		return
	var camera_position := INTRO_CAMERA_POSITION
	if beaver.opponent == Beaver.Opponent.CHEF:
		camera_position.z += 0.70
	camera.transform = Transform3D(Basis.IDENTITY, camera_position).looking_at(beaver.face_center())
	beaver.addressing_player = true
	if OS.has_feature("web"):
		# Browsers need a player gesture to unlock audio.
		var button := Button.new()
		button.text = "Начать"
		intro_ui.add_child(button)
		button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		button.offset_left = -80
		button.offset_right = 80
		button.offset_top = -94
		button.offset_bottom = -50
		button.add_theme_stylebox_override("normal", _panel_style(Color("41322a")))
		button.grab_focus()
		button.pressed.connect(func() -> void:
			button.queue_free()
			_speak_intro(), CONNECT_ONE_SHOT)
	else:
		_speak_intro()

func _speak_intro() -> void:
	_start_background_music()
	await beaver_voice.speak(&"intro")
	if phase != "intro":
		return
	intro_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro_transition.tween_property(camera, "transform", beaver_camera_transform, 0.45)
	intro_transition.finished.connect(_finish_intro, CONNECT_ONE_SHOT)

func _finish_intro() -> void:
	camera.transform = beaver_camera_transform
	beaver.addressing_player = false
	beaver_voice.subtitle_changed.disconnect(_set_beaver_subtitle)
	intro_ui.queue_free()
	volume_control.show()
	_start_run()

func _skip_intro() -> void:
	_start_background_music()
	if intro_transition and intro_transition.is_running():
		intro_transition.kill()
	_finish_intro()
	beaver_voice.skip_line()

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

func _start_run() -> void:
	run.start(player_setup, rng)
	pending_popups.clear()
	for popup in score_popups.get_children():
		popup.hide()
		popup.queue_free()
	score_hud.show()
	_refresh_score()
	_new_round()

func _set_beaver_subtitle(text: String) -> void:
	beaver_subtitle.text = "" if text.is_empty() else "«%s»" % text


func _exit_tree() -> void:
	action_camera.restore()


func _update_camera(delta: float) -> void:
	if action_camera.mode != action_camera.Mode.IDLE:
		action_camera.update(delta)
		return
	if camera_view == camera_view_target:
		return
	camera_view = lerpf(camera_view, camera_view_target, 1.0 - exp(-CAMERA_SCROLL_SPEED * delta))
	if is_equal_approx(camera_view, camera_view_target):
		camera_view = camera_view_target
	camera.transform = beaver_camera_transform.interpolate_with(board_camera_transform, camera_view)
	if aiming:
		_draw_aim(_aim_vector(get_viewport().get_mouse_position()))


func _new_round() -> void:
	action_camera.new_shot()
	_end_player_drag()
	_clear_links()
	phasing_piece = null
	ghost_contacts.clear()
	_reset_stillness()
	contacts.clear()
	lightning.clear()
	for blast: Node3D in blast_effects.get_children():
		blast.hide()
		blast.queue_free()
	effects_mesh.clear_surfaces()
	checker_trails.clear()
	strike_effects.clear()
	for p in pieces:
		if is_instance_valid(p): p.queue_free()
	pieces.clear()
	var enemy_roster := run.enemies(enemy_setup)
	for side in 2:
		var roster := run.roster if side == 0 else enemy_roster
		for slot in formations[side].size():
			_make_piece(side, roster[slot], formations[side][slot], slot)
	turn = 0
	phase = "aim"
	run_overlay.hide()

func _make_piece(side: int, icon: Checker.Icon, pos: Vector3, slot: int) -> Checker:
	var scene := LIGHT_PIECE if side == 0 else DARK_PIECE
	var body := scene.instantiate() as Checker
	body.icon = icon
	body.slot = slot
	body.position = pos
	board_pivot.add_child(body)
	body.struck.connect(_queue_contact.bind(body))
	pieces.append(body)
	body.show_turn_aura(_is_player_turn())
	return body

func _input(event: InputEvent) -> void:
	if action_camera.mode != action_camera.Mode.IDLE and event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		get_viewport().set_input_as_handled()
		if not event.echo:
			action_camera.skip()
		return
	if phase == "intro" and event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		get_viewport().set_input_as_handled()
		if not event.echo:
			_skip_intro()
		return
	# A drag that started on the board can end over the volume control.
	if event is InputEventMouseMotion:
		if hand_waiting_for_motion and _is_player_turn() and action_camera.mode == action_camera.Mode.IDLE \
				and not event.relative.is_zero_approx():
			hand_waiting_for_motion = false
		if orbiting:
			if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				_finish_board_rotation()
			else:
				board_pivot.rotation.y = wrapf(
					board_pivot.rotation.y + event.relative.x * BOARD_ROTATION_SPEED, -PI, PI)
		elif aiming:
			_draw_aim(_aim_vector(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if orbiting:
			_finish_board_rotation()
		elif aiming:
			var piece := selected
			var shot := _aim_vector(event.position)
			var offset := strike_offset
			_cancel_aim()
			if not shot.is_zero_approx():
				_player_flick(piece, shot, offset)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		_end_player_drag()
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_viewport().set_input_as_handled()

func _is_player_turn() -> bool:
	return phase == "aim" and turn == 0

func _unhandled_input(event: InputEvent) -> void:
	if phase == "intro":
		return
	if (event is InputEventMouseButton and event.pressed
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		var steps: float = event.factor if event.factor > 0.0 else 1.0
		camera_view_target = clampf(camera_view_target + direction * steps * CAMERA_SCROLL_STEP, 0.0, 1.0)
		get_viewport().set_input_as_handled()
		return
	if not _is_player_turn() or action_camera.mode != action_camera.Mode.IDLE or aiming or orbiting:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var ray_start := camera.project_ray_origin(event.position)
		var hit := _piece_hit(event.position)
		var picked := hit.get("collider") as Checker
		if picked and picked.side == 0:
			hand_waiting_for_motion = false
			selected = picked
			picked.set_turn_aura_selected(true)
			drag_start = event.position
			var hit_point: Vector3 = hit.position
			strike_offset = (hit_point - picked.global_position).slide(Vector3.UP)
			aiming = true
		elif _is_table_drag(ray_start, camera.project_ray_normal(event.position)):
			_begin_board_rotation()

func _piece_hit(cursor: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(cursor)
	var ray := camera.project_ray_normal(cursor)
	var radius := Checker.RADIUS * Checker.PIXELS_PER_UNIT
	var nearest := INF
	var result := {}
	for piece in pieces:
		if piece.falling:
			continue
		var height := piece.global_position.y
		var top: Variant = Plane(Vector3.UP, height + Checker.HALF_HEIGHT).intersects_ray(origin, ray)
		var bottom: Variant = Plane(Vector3.UP, height - Checker.HALF_HEIGHT).intersects_ray(origin, ray)
		if top == null or bottom == null:
			continue
		var from := Checker.to_plane(top)
		var to := Checker.to_plane(bottom)
		var center := Checker.to_plane(piece.global_position)
		var entry := 0.0 if from.distance_squared_to(center) <= radius * radius else (
			Geometry2D.segment_intersects_circle(from, to, center, radius))
		if entry < 0.0:
			continue
		var point := (top as Vector3).lerp(bottom, entry)
		var distance := origin.distance_squared_to(point)
		if distance < nearest:
			nearest = distance
			result = {"collider": piece, "position": point}
	return result

func _cancel_aim() -> void:
	if is_instance_valid(selected):
		selected.set_turn_aura_selected(false)
	selected = null
	aiming = false
	strike_offset = Vector3.ZERO
	aim_arrow.hide()
	preview.hide()

func _end_player_drag() -> void:
	_finish_board_rotation()
	_cancel_aim()

func _draw_aim(shot: Vector3) -> void:
	aim_arrow.visible = not shot.is_zero_approx()
	preview.hide()
	if not aim_arrow.visible:
		return
	var direction := shot.normalized()
	var strength := shot.length()
	var power := clampf(strength / MAX_PULL_STRENGTH, 0.0, 1.0)
	var start := _on_board(selected.global_position) + direction * (Checker.RADIUS + 0.025)
	var length := lerpf(0.46, 1.72, power)
	if selected.hovering:
		start.y += selected.global_position.y - PIECE_Y
	else:
		length = minf(length, maxf(_edge_distance(start, direction), 0.34))
	aim_arrow.global_position = start + direction * length * 0.5
	aim_arrow.rotation.y = atan2(direction.x, direction.z)
	aim_arrow.scale.z = length
	aim_material.set_shader_parameter("arrow_length", length)
	aim_material.set_shader_parameter("pull_amount",
		clampf(inverse_lerp(MIN_PULL_STRENGTH, MAX_PULL_STRENGTH, strength), 0.0, 1.0))
	if selected.icon == Checker.Icon.SNIPER:
		_draw_trajectory(selected, shot)

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
	var origin := board_pivot.to_local(start)
	var local_direction := board_pivot.global_basis.inverse() * direction
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
			if other == piece or other == previous or other.falling or other.is_intangible():
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
	strike_effects.clear()
	# The board follows the mouse at render speed. The resting discs follow their parent.
	for piece in pieces:
		piece.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _finish_board_rotation() -> void:
	if not orbiting:
		return
	orbiting = false
	for piece in pieces:
		piece.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		piece.reset_physics_interpolation()

func _is_table_drag(ray_start: Vector3, ray_direction: Vector3) -> bool:
	var hit = Plane(Vector3.UP, TABLE_TOP).intersects_ray(ray_start, ray_direction)
	if hit == null:
		return false
	return hit.z > 0.5 and Vector2(hit.x, hit.z).length_squared() <= TABLE_RADIUS * TABLE_RADIUS

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
	return clampf(drag.length() / maxf(available, 1.0) * MAX_PULL_STRENGTH,
		MIN_PULL_STRENGTH, MAX_PULL_STRENGTH)

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

func _update_player_hand(delta: float) -> void:
	if action_camera.mode != action_camera.Mode.IDLE:
		player_hand.hide()
		return
	var cursor := get_viewport().get_mouse_position()
	var bounds := get_viewport().get_visible_rect()
	if not _is_player_turn() or hand_waiting_for_motion or orbiting or not bounds.has_point(cursor) \
			or (not aiming and volume_control.get_global_rect().has_point(cursor)):
		player_hand.withdraw()
		return

	var facing := (-camera.global_basis.z).slide(Vector3.UP).normalized()
	if aiming:
		var shot := _aim_vector(cursor)
		if not shot.is_zero_approx():
			facing = shot.normalized()
			var power := shot.length() / MAX_PULL_STRENGTH
			var contact := _player_finger_contact(selected, facing, strike_offset)
			player_hand.aim(delta, contact, facing, power)
			return

	var ray_start := camera.project_ray_origin(cursor)
	var ray_direction := camera.project_ray_normal(cursor)
	var hover_hit: Variant = Plane(Vector3.UP, BOARD_TOP + PlayerHand.HOVER_HEIGHT) \
		.intersects_ray(ray_start, ray_direction)
	# Keep the hand on the cursor ray even when it points above the tabletop.
	var depth := -camera.to_local(board_pivot.global_position).z + BOARD_APOTHEM
	if hover_hit != null:
		depth = minf(depth, -camera.to_local(hover_hit).z)
	var target := camera.project_position(cursor, depth)
	if target.y > HAND_HOVER_CEILING and ray_start.y < HAND_HOVER_CEILING:
		target = ray_start.lerp(target, inverse_lerp(ray_start.y, target.y, HAND_HOVER_CEILING))
	player_hand.follow(delta, target, facing)


func _player_finger_contact(piece: Checker, direction: Vector3, offset: Vector3) -> Vector3:
	var lateral := offset.slide(direction).limit_length(Checker.RADIUS * 0.75)
	var depth := sqrt(Checker.RADIUS * Checker.RADIUS - lateral.length_squared())
	return piece.global_position + lateral - direction * depth + Vector3.UP * 0.035


func _player_flick(piece: Checker, shot: Vector3, offset: Vector3) -> void:
	hand_waiting_for_motion = true
	phase = "player_strike"
	var direction := shot.normalized()
	var strength := shot.length()
	await player_hand.flick(_player_finger_contact(piece, direction, offset), direction,
		strength / MAX_PULL_STRENGTH)
	player_hand.recover(direction)
	if is_instance_valid(piece) and not piece.is_queued_for_deletion():
		_shoot(piece, direction, strength, offset)
	else:
		phase = "aim"


func _shoot(piece: Checker, direction: Vector3, strength: float, offset := Vector3.ZERO) -> void:
	_begin_shot_resolution()
	if piece.is_intangible():
		phasing_piece = piece
		ghost_previous_position = Checker.to_plane(piece.global_position)
	piece.incoming_velocity = direction * strength * SHOT_IMPULSE * piece.shot_multiplier() / piece.mass
	var lever := offset.slide(direction).limit_length(Checker.RADIUS) * 0.30
	_push(piece, piece.incoming_velocity, lever)
	checker_strike_sound.play()
	var intensity := clampf(piece.incoming_velocity.length() / 6.0, 0.12, 1.0)
	piece.stretch_on_impact(direction, intensity)

func _begin_shot_resolution() -> void:
	if turn == 0:
		turn_start_score = run.score
		run.begin_player_turn()
	action_camera.new_shot()
	phase = "moving"
	shot_knockouts.fill(false)
	for piece in pieces:
		piece.incoming_velocity = Vector3.ZERO
		piece.lightning_used = false
	_reset_stillness()

func _is_off_board(world_position: Vector3, margin := 0.0) -> bool:
	return _is_outside_board(board_pivot.to_local(world_position), margin)

func _is_outside_board(local: Vector3, margin: float) -> bool:
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
			processed[key] = true
	contacts.clear()
	if phasing_piece != null:
		_resolve_ghost_contacts()

func _resolve_ghost_contacts() -> void:
	var point := Checker.to_plane(phasing_piece.global_position)
	var radius := DIAMETER * Checker.PIXELS_PER_UNIT
	for other in pieces:
		if other.falling or other.is_intangible() or other in ghost_contacts:
			continue
		var center := Checker.to_plane(other.global_position)
		var nearest := Geometry2D.get_closest_point_to_segment(center, ghost_previous_position, point)
		if center.distance_squared_to(nearest) <= radius * radius:
			ghost_contacts.append(other)
			_award(other)
			checker_ghost_touch_sound.play()
			_trigger_contact(other, phasing_piece)
	ghost_previous_position = point

func _push(piece: Checker, velocity: Vector3, offset := Vector3.ZERO) -> void:
	if piece.falling or velocity.length_squared() < 0.0001:
		return
	piece.apply_planar_impulse(velocity, offset)

func _touch(a: Checker, b: Checker, normal: Vector3) -> void:
	var a_speed := a.incoming_velocity.dot(normal)
	var b_speed := -b.incoming_velocity.dot(normal)
	var closing_speed := a_speed + b_speed
	if closing_speed > 0.0:
		if a.side != b.side:
			_award(a if a.side == 1 else b)
		elif a.side == 1:
			_award(b if a_speed >= b_speed else a)
	if closing_speed > 0.32:
		checker_hit_sound.play()
		var a_struck := a_speed >= b_speed
		var intensity := clampf(closing_speed / 4.7, 0.08, 1.0)
		var contact_point := a.position.lerp(b.position, 0.5)
		action_camera.hit(board_pivot.to_global(contact_point))
		var icon := a.icon if a_struck else b.icon
		if not strike_effects.element_planes.has(icon):
			icon = b.icon if a_struck else a.icon
		strike_effects.impact(contact_point, board_pivot.global_basis.inverse() * normal, intensity, icon)
		a.stretch_on_impact(normal, intensity * (0.72 if a_struck else 1.0))
		b.stretch_on_impact(normal, intensity * (1.0 if a_struck else 0.72))
	_trigger_contact(a, b)
	_trigger_contact(b, a)

func _trigger_contact(piece: Checker, other: Checker) -> void:
	match piece.icon:
		Checker.Icon.EXPLOSIVE:
			if piece.fuse < 0.0 and not piece.exploded:
				piece.start_fuse()
		Checker.Icon.LIGHTNING:
			if not piece.lightning_used:
				piece.lightning_used = true
				lightning.append({"side": piece.side, "next": other,
					"origin": _on_board(piece.global_position), "visual_origin": piece.global_position,
					"seen": [], "delay": 0.0})
		Checker.Icon.STICKY:
			if not other.is_intangible():
				_stick_pieces(piece, other)

func _stick_pieces(a: Checker, b: Checker) -> void:
	if a.glued or b.glued:
		return
	_space_sticky_pair(a, b, true)
	var middle := (a.planar_body.global_position + b.planar_body.global_position) * 0.5
	var axis := a.planar_body.global_position.direction_to(b.planar_body.global_position)
	var across := axis.orthogonal() * (DIAMETER * Checker.PIXELS_PER_UNIT * 0.31)
	# Two anchors keep the edges together when either checker spins.
	var joints: Array[PinJoint2D] = []
	for anchor: Vector2 in [middle - across, middle + across]:
		var joint := PinJoint2D.new()
		add_child(joint)
		joint.global_position = anchor
		joint.node_a = joint.get_path_to(a.planar_body)
		joint.node_b = joint.get_path_to(b.planar_body)
		joints.append(joint)
	a.glued = true
	b.glued = true
	a.planar_body.sleeping = false
	b.planar_body.sleeping = false
	var slime := MeshInstance3D.new()
	slime.name = "StickySlime"
	slime.mesh = sticky_slime_mesh
	slime.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slime.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	board_pivot.add_child(slime)
	var link := {"bodies": [a, b], "joints": joints, "slime": slime}
	links.append(link)
	_update_sticky_slime(link)

func _space_sticky_pair(a: Checker, b: Checker, close_gap := false) -> void:
	var offset := b.planar_body.position - a.planar_body.position
	var distance := offset.length()
	var correction := DIAMETER * Checker.PIXELS_PER_UNIT - distance
	if absf(correction) < 0.001 or (correction < 0.0 and not close_gap):
		return
	var axis := offset / distance if distance > 0.001 else Vector2.RIGHT
	var share := b.mass / (a.mass + b.mass)
	a.planar_body.position -= axis * correction * share
	b.planar_body.position += axis * correction * (1.0 - share)
	a.sync_planar_position()
	b.sync_planar_position()

func _update_sticky_slime(link: Dictionary) -> void:
	var a: Checker = link.bodies[0]
	var b: Checker = link.bodies[1]
	var slime: MeshInstance3D = link.slime
	var start := board_pivot.to_local(a.get_global_transform_interpolated().origin)
	var end := board_pivot.to_local(b.get_global_transform_interpolated().origin)
	var axis := start.direction_to(end)
	var side := axis.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		axis = Vector3.RIGHT
		side = Vector3.BACK
	var up := side.cross(axis)
	slime.transform = Transform3D(Basis(axis, up, side), start.lerp(end, 0.5) + up * 0.072)

func _release_link(index: int) -> void:
	var link := links[index]
	for joint: PinJoint2D in link.joints:
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.queue_free()
	for piece: Checker in link.bodies:
		piece.glued = false
	link.slime.hide()
	link.slime.queue_free()
	links.remove_at(index)

func _clear_links() -> void:
	for i in range(links.size() - 1, -1, -1):
		_release_link(i)

func _tick_effects(delta: float) -> bool:
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
	return armed or not lightning.is_empty()

func _explode(bomb: Checker) -> void:
	bomb.fuse = -1.0
	bomb.exploded = true
	var center := _on_board(bomb.fuse_origin if bomb.falling else bomb.global_position)
	var blast := CheckerBlast.new()
	blast.position = board_pivot.to_local(center) + Vector3.UP * 0.038
	blast.rotation.y = bomb.rotation.y
	blast_effects.add_child(blast)
	checker_explosion_sound.play()
	for piece in pieces:
		if piece == bomb or piece.falling or piece.is_intangible():
			continue
		var offset := _on_board(piece.global_position) - center
		var strength := 5.2 * (1.0 - offset.length() / 1.12)
		if strength > 0.0:
			_push(piece, offset.normalized() * strength)

func _lightning_hop(chain: Dictionary) -> bool:
	var target: Checker = chain.next
	if not _can_receive_lightning(target, chain.side, chain.seen):
		target = _find_lightning_target(chain.origin, chain.side, chain.seen)
	if not target:
		return false
	if chain.seen.is_empty():
		checker_lightning_sound.play()
	var endpoint := _on_board(target.global_position)
	var bolt_height := Vector3.UP * 0.08
	strike_effects.lightning_arc(board_pivot.to_local(chain.visual_origin + bolt_height),
		board_pivot.to_local(target.global_position + bolt_height))
	var hop_direction: Vector3 = board_pivot.global_basis.inverse() * (endpoint - chain.origin)
	strike_effects.impact(target.position, hop_direction, 0.3, Checker.Icon.LIGHTNING, true)
	_push(target, (endpoint - chain.origin).normalized() * 0.56)
	chain.seen.append(target)
	chain.origin = endpoint
	chain.visual_origin = target.global_position
	chain.next = null
	chain.delay = 0.10
	return chain.seen.size() < 4

func _can_receive_lightning(piece: Checker, source_side: int, seen: Array) -> bool:
	return (is_instance_valid(piece) and piece.side != source_side and not piece.falling
		and not piece.is_intangible() and piece not in seen)

func _find_lightning_target(origin: Vector3, source_side: int, seen: Array) -> Checker:
	var available: Array[Checker] = []
	for piece in pieces:
		if _can_receive_lightning(piece, source_side, seen):
			available.append(piece)
	available.sort_custom(func(a: Checker, b: Checker) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	if available.is_empty():
		return null
	return available[rng.randi_range(0, mini(available.size(), 4) - 1)]

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_player_hand(delta)
	checker_trails.update_trails(delta, pieces, phase == "moving")
	for link in links:
		_update_sticky_slime(link)
	strike_effects.tick(delta)
	var armed: Array[Checker] = []
	if phase == "moving":
		for p in pieces:
			if p.fuse >= 0.0:
				armed.append(p)
	if effects_mesh.get_surface_count() > 0:
		effects_mesh.clear_surfaces()
	if armed.is_empty():
		return
	effects_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, effects_material)
	for bomb in armed:
		var position := bomb.fuse_origin if bomb.falling else bomb.get_global_transform_interpolated().origin
		var center := _on_board(position)
		var brightness := 0.54 + sin(bomb.fuse * lerpf(24.0, 8.0, bomb.fuse * 0.5)) * 0.28
		_draw_ring(center, Checker.RADIUS * 1.22, 0.019, Color(1.0, 0.60, 0.28, brightness))
	effects_mesh.surface_end()

func _draw_ring(center: Vector3, radius: float, width: float, color: Color) -> void:
	effects_mesh.surface_set_color(color)
	for i in 32:
		var from := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 32.0) * radius
		var to := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * (i + 1) / 32.0) * radius
		_draw_line(effects_mesh, from, to, width)

func _contain_piece(piece: Checker, margin: float) -> void:
	var point := piece.position
	var velocity := Checker.from_plane(piece.planar_body.linear_velocity)
	for iteration in 2:
		for normal: Vector3 in EDGE_NORMALS:
			var overshoot := point.dot(normal) - (BOARD_APOTHEM - margin)
			if overshoot > 0:
				point -= normal * overshoot
				velocity -= normal * maxf(velocity.dot(normal), 0.0)
	piece.place_on_board(point, piece.rotation.y)
	piece.planar_body.linear_velocity = Checker.to_plane(velocity)

func _resolve_board_edge(piece: Checker) -> void:
	if not _is_outside_board(piece.position, 0.0):
		piece.hovering = false
		return
	if piece.hovering:
		if _is_outside_board(piece.position, -FLOAT_RANGE):
			_contain_piece(piece, -FLOAT_RANGE)
		return
	if piece.icon == Checker.Icon.FLOATING and not piece.float_used:
		piece.float_used = true
		piece.hovering = true
		piece.hover_started_turn = run.completed_turns
		return
	_eliminate(piece)

func _eliminate(piece: Checker) -> void:
	if piece == phasing_piece:
		_end_ghost_phase()
	for i in range(links.size() - 1, -1, -1):
		if piece in links[i].bodies:
			_release_link(i)
	piece.fuse_origin = piece.global_position
	var outward := Vector3.ZERO
	if not _is_outside_board(piece.position, -Checker.RADIUS - 0.015):
		var nearest_edge: Vector3 = EDGE_NORMALS[0]
		for normal: Vector3 in EDGE_NORMALS:
			if piece.position.dot(normal) > piece.position.dot(nearest_edge):
				nearest_edge = normal
		outward = board_pivot.global_basis * nearest_edge
	_award(piece, true)
	piece.leave_board(outward)
	action_camera.fall(piece, board_pivot.global_position)
	if not shot_knockouts[piece.side]:
		shot_knockouts[piece.side] = true
		beaver_voice.react_to_knockout(piece.side == 1)

func _physics_process(delta: float) -> void:
	if phase != "moving": return
	for p in pieces:
		if not p.falling:
			p.sync_planar_position()
			var stopping_distance := INF
			if p.hovering:
				var direction := p.linear_velocity.normalized()
				stopping_distance = maxf(_edge_distance(p.global_position, direction, -FLOAT_RANGE), 0.04)
			p.apply_slide_friction(delta, stopping_distance)
	_resolve_contacts()
	var pending := _tick_effects(delta)
	for link in links:
		_space_sticky_pair(link.bodies[0], link.bodies[1])
	var moving := false
	var falling := false
	for i in range(pieces.size() - 1, -1, -1):
		var p := pieces[i]
		if not p.falling:
			_resolve_board_edge(p)
			if p.float_used and not p.falling:
				var height := PIECE_Y + (FLOAT_HEIGHT if p.hovering else 0.0)
				p.global_position.y = move_toward(p.global_position.y, height, FLOAT_LIFT_SPEED * delta)
		if p.falling:
			if p.animate_fall(delta, TABLE_TOP, TABLE_RADIUS, FLOOR_Y, ROOM_FLOOR):
				if p.visible:
					p.hide()
					action_camera.forget_fall(p)
				if p.fuse < 0.0:
					pieces.remove_at(i)
					p.queue_free()
					continue
			falling = true
		else:
			p.incoming_velocity = p.linear_velocity
			moving = moving or p.is_in_motion()
	if phasing_piece != null and phasing_piece.linear_velocity.length_squared() <= 0.0025:
		_materialize_ghost()
		_reset_stillness()
		return
	if moving or falling or pending or not _rest_poses_are_stable():
		_reset_stillness()
		return
	still_time += delta
	if still_time < TURN_REST_TIME or action_camera.mode != action_camera.Mode.IDLE:
		return
	if _expire_hovering():
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

func _expire_hovering() -> bool:
	var dropped := false
	for piece in pieces:
		if piece.hovering and piece.side == turn and piece.hover_started_turn < run.completed_turns:
			piece.hovering = false
			_eliminate(piece)
			dropped = true
	return dropped

func _find_ghost_landing(piece: Checker) -> Vector3:
	var origin := piece.global_position
	if _ghost_landing_is_clear(origin):
		return origin
	const SEARCH_STEP := Checker.RADIUS / 3.0
	var search_rings := ceili(BOARD_APOTHEM * 2.4 / SEARCH_STEP)
	for ring in range(1, search_rings + 1):
		for i in ring * 8:
			var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / (ring * 8))
			var point := origin + direction * (SEARCH_STEP * ring)
			if _ghost_landing_is_clear(point):
				return point
	return origin

func _ghost_landing_is_clear(position: Vector3) -> bool:
	if _is_off_board(position):
		return false
	for other in pieces:
		if other.falling or other.is_intangible():
			continue
		var offset := (other.global_position - position).slide(Vector3.UP)
		if offset.length_squared() < GHOST_LANDING_CLEARANCE * GHOST_LANDING_CLEARANCE:
			return false
	return true

func _materialize_ghost() -> void:
	var piece := phasing_piece
	var destination := _find_ghost_landing(piece)
	for other in pieces:
		if other.falling or other.is_intangible():
			continue
		var offset := (other.global_position - piece.global_position).slide(Vector3.UP)
		var depth := GHOST_LANDING_CLEARANCE - offset.length()
		if depth > 0.0:
			var direction := offset.normalized()
			if direction.is_zero_approx():
				direction = (other.global_position - destination).slide(Vector3.UP).normalized()
			_push(other, direction * lerpf(0.12, 0.55, depth / GHOST_LANDING_CLEARANCE))
	piece.place_on_board(board_pivot.to_local(destination), piece.rotation.y)
	checker_trails.forget(piece)
	piece.reset_physics_interpolation()
	piece.stop_motion()
	_end_ghost_phase()

func _end_ghost_phase() -> void:
	phasing_piece.spend_ghost()
	phasing_piece = null
	ghost_contacts.clear()

func _finish_shot() -> void:
	action_camera.restore()
	run.finish_turn(turn == 0)
	if turn == 0:
		_show_turn_style(run.score - turn_start_score, maxi(1, run.streak))
	_refresh_score()
	contacts.clear()
	var counts := [0, 0]
	for p in pieces:
		p.stop_motion()
		counts[p.side] += 1
	if counts[0] == 0 or counts[1] == 0:
		phase = "round_end"
		run.finish_round(counts[1] == 0 and counts[0] > 0)
		var result_cue: StringName
		if counts[0] == 0 and counts[1] == 0:
			result_cue = &"draw"
		elif counts[1] == 0:
			result_cue = &"lose"
		else:
			result_cue = &"win"
		await beaver_voice.speak(result_cue)
		_offer_next_round(counts[0], counts[1])
		return
	turn = 1 - turn
	phase = "aim"
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
		var message := "Она войдёт в твой состав со следующего раунда."
		if Checker.Icon.NONE not in run.roster:
			message = "Она заменит одну из повторяющихся шашек."
		_show_run_result("Выбери шашку", message)
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
			if piece.hovering and not enemy.hovering:
				cost -= 3.0
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
