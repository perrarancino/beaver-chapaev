extends Node3D

enum MarbleState { UNPLAYED, ACTIVE, WON, LOST }

const Beaver := preload("res://beaver.gd")
const Run := preload("res://checker_run.gd")
const Rails := preload("res://edge_rails.gd")
const BoardZones := preload("res://board_zones.gd")
const Fairy := preload("res://assets/lilith/lilith.gd")
const LIGHT_PIECE := preload("res://piece_light.tscn")
const DARK_PIECE := preload("res://piece_dark.tscn")
const CheckerStrikeEffects := preload("res://assets/FX/checker_strike_effects.gd")
const CheckerTrails := preload("res://assets/FX/checker_trails.gd")
const CheckerBlast := preload("res://assets/FX/checker_blast.gd")
const STICKY_SLIME_SHADER := preload("res://assets/FX/checker_sticky_slime.gdshader")
const ROUND_MARBLES := preload("res://assets/ui/round-marbles.png")
const MUSIC_TRACKS: Array[String] = [
	"res://assets/music/khitryi_umysel.mp3",
	"res://assets/music/balalaechnyi_manevr.mp3",
	"res://assets/music/nochnoi_tropar.mp3",
	"res://assets/music/tainaya_zasada.mp3",
]
const TABLE_TOP := 0.003
const BOARD_TOP := TABLE_TOP
const TABLE_RADIUS := Rails.TABLE_RADIUS
const FLOOR_Y := -2.1
const ROOM_FLOOR := Rect2(-7.50, -9.30, 14.98, 16.72)
const PIECE_Y := 0.07
const TURN_REST_TIME := 0.35
const MIN_RAIL_BOUNCE_SPEED := 0.025
const CAMERA_SCROLL_STEP := 0.125
const CAMERA_SCROLL_SPEED := 11.0
const BOARD_ROTATION_SPEED := 0.006
const INTRO_CAMERA_POSITION := Vector3(0.0, 2.2, 0.95)
const BOARD_CAMERA_POSITION := Vector3(0.0, 4.35, 4.45)
const FLOAT_HEIGHT := 0.27
const FLOAT_RANGE := Checker.RADIUS * 6.0
const FLOAT_LIFT_SPEED := 1.35
const PIECE_CLEARANCE := 0.008
const SHOT_IMPULSE := 3.0
const DRAG_DEAD_ZONE := 12.0
const MIN_PULL_STRENGTH := 0.4
const MAX_PULL_STRENGTH := 2.8
const NOSE_HIT_RADII := Vector2(0.38, 0.23)
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
var shot_planner := preload("res://checker_shot_planner.gd").new()
var action_camera := preload("res://checker_action_camera.gd").new()
var camera: Camera3D
var beaver_camera_transform: Transform3D
var board_camera_transform: Transform3D
var camera_view := 0.0
var camera_view_target := 0.0
var intro_ui: Control
var intro_transition: Tween
var beaver_subtitle: Label
var volume_control: HBoxContainer
var round_hud: HBoxContainer
var round_marbles: Array[TextureRect] = []
var round_textures: Array[AtlasTexture] = []
var score_label: Label
var score_popups := Control.new()
var run_actions: CenterContainer
var run_heading: Label
var run_choices: VBoxContainer
var preview: MeshInstance3D
var preview_mesh := ImmediateMesh.new()
var preview_material := StandardMaterial3D.new()
var effects_mesh := ImmediateMesh.new()
var effects_material := StandardMaterial3D.new()
var strike_effects := CheckerStrikeEffects.new()
var checker_trails := CheckerTrails.new()
var zones := BoardZones.new()
var blast_effects := Node3D.new()
var sticky_slime_mesh := SphereMesh.new()
var rng := RandomNumberGenerator.new()
var orbiting := false
var nose_dragging := false
var nose_grabbed := false
var nose_drag_start := Vector2.ZERO
var nose_drag_anchor := Vector3.ZERO
var music_queue: Array[String] = []
var last_music_path := ""
var next_music: AudioStream
var music_response_callback: JavaScriptObject
var music_loaded_callback: JavaScriptObject
var music_failed_callback: JavaScriptObject
var music_loading := false
var music_started := false
var music_failures := 0
@onready var background_music: AudioStreamPlayer = $BackgroundMusic
@onready var checker_strike_sound: AudioStreamPlayer = $CheckerSounds/Strike
@onready var checker_hit_sound: AudioStreamPlayer = $CheckerSounds/Hit
@onready var checker_explosion_sound: AudioStreamPlayer = $CheckerSounds/Explosion
@onready var checker_lightning_sound: AudioStreamPlayer = $CheckerSounds/Lightning
@onready var checker_ghost_touch_sound: AudioStreamPlayer = $CheckerSounds/GhostTouch
@onready var board_pivot: Node3D = $BoardPivot
@onready var rails: Rails = $BoardPivot/Rails
@onready var lilith: Fairy = $Lilith
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
	lilith.configure_table(board_pivot.global_position + Vector3.UP * BOARD_TOP, TABLE_RADIUS, rails)
	_build_ui()
	_build_preview()
	var slime_material := ShaderMaterial.new()
	slime_material.shader = STICKY_SLIME_SHADER
	sticky_slime_mesh.material = slime_material
	sticky_slime_mesh.radial_segments = 32
	sticky_slime_mesh.rings = 16
	board_pivot.add_child(checker_trails)
	zones.name = &"BoardZones"
	board_pivot.add_child(zones)
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
	if OS.has_feature("web") and not ResourceLoader.exists(MUSIC_TRACKS[0]):
		_prepare_next_music_track.call_deferred()

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
	l.add_theme_color_override("font_outline_color", Color("0b1019"))
	l.add_theme_constant_override("outline_size", roundi(size * 0.3))
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
	_build_volume_control(root)
	_build_score_hud(root)
	_build_run_actions(root)
	_build_round_hud(root)
	root.resized.connect(_position_top_hud.bind(root))
	score_label.minimum_size_changed.connect(_position_top_hud.bind(root))


func _build_round_hud(root: Control) -> void:
	round_hud = HBoxContainer.new()
	round_hud.name = &"RoundTracker"
	round_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_hud.add_theme_constant_override("separation", 8)
	root.add_child(round_hud)
	# The atlas cells are evenly spaced. Crop the transparent gutters around each marble.
	var cell_width := float(ROUND_MARBLES.get_width()) / MarbleState.size()
	var diameter := cell_width * 0.86
	for i in MarbleState.size():
		var texture := AtlasTexture.new()
		texture.atlas = ROUND_MARBLES
		texture.region = Rect2((i + 0.5) * cell_width - diameter * 0.5,
			(ROUND_MARBLES.get_height() - diameter) * 0.5, diameter, diameter)
		texture.filter_clip = true
		round_textures.append(texture)
	for _round in Run.ROUNDS_PER_MATCH:
		var marble := TextureRect.new()
		marble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marble.custom_minimum_size = Vector2(37, 37)
		marble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		marble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		round_hud.add_child(marble)
		round_marbles.append(marble)

	round_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	round_hud.hide()


func _refresh_round_hud(active: bool) -> void:
	var resolved := run.round_results.size()
	for i in round_marbles.size():
		var state := MarbleState.UNPLAYED
		if i < resolved:
			state = MarbleState.WON if run.round_results[i] == Run.RoundResult.PLAYER else MarbleState.LOST
		elif i == resolved and active:
			state = MarbleState.ACTIVE
		round_marbles[i].texture = round_textures[state]


func _position_top_hud(root: Control) -> void:
	var round_size := round_hud.get_combined_minimum_size()
	var volume_size := volume_control.get_combined_minimum_size()
	var score_size := score_label.get_combined_minimum_size()
	var side_space := (root.size.x - score_size.x) * 0.5 - 28.0
	var second_row := score_label.position.y + score_size.y + 12.0
	var round_fits := round_size.x <= side_space
	var volume_fits := volume_size.x <= side_space
	round_hud.position.y = 16.0 if round_fits else second_row
	volume_control.position.y = 16.0 if volume_fits else second_row
	volume_control.position.y += (round_size.y - volume_size.y) * 0.5
	if not round_fits and not volume_fits and root.size.x < round_size.x + volume_size.x + 44.0:
		volume_control.position.y = round_hud.position.y + round_size.y + 12.0

func _build_score_hud(root: Control) -> void:
	root.add_child(score_popups)
	score_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	score_label = _label(root, "", 23, Color("fff1d5"))
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 22
	score_label.offset_bottom = 22
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.hide()


func _refresh_score() -> void:
	score_label.text = "Очки  %d" % run.score


func _award(piece: Checker, origin: Vector3, knockout := false) -> void:
	if turn != 0 or phase != "moving" or piece.side != 1:
		return
	var points := run.award(knockout)
	_refresh_score()
	_show_score_popup(points, origin, knockout)


func _show_score_popup(points: int, origin: Vector3, knockout: bool) -> void:
	var size := 46.0 if knockout else minf(46.0, 26.0 + 6.0 * run.action_multiplier())
	var font_size := roundi(size * clampf(score_popups.size.x / 600.0, 0.65, 1.0))
	var popup := _label(score_popups, "+%d" % points, font_size,
		Color("ffad70") if knockout else Color("ffe59a"))
	popup.reset_size()
	popup.pivot_offset = popup.size * 0.5
	popup.scale = Vector2.ONE * 0.6
	var drift := (popup.size.x * 0.67 + randf_range(12.0, 23.0)) * (-1.0 if run.actions % 2 == 0 else 1.0)
	popup.rotation_degrees = signf(drift) * 13.0
	_position_score_popup(0.0, popup, origin, drift)
	var tween := popup.create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_method(_position_score_popup.bind(popup, origin, drift), 0.0, 1.0, 0.82)
	tween.tween_property(popup, "scale", Vector2.ONE * 1.18, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "scale", Vector2.ONE * 0.92, 0.22).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "rotation_degrees", 0.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.34).set_delay(0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(popup.queue_free)


func _position_score_popup(progress: float, popup: Label, origin: Vector3, drift: float) -> void:
	var area := score_popups.size
	var anchor := camera.unproject_position(origin)
	if camera.is_position_behind(origin):
		var camera_side := camera.global_basis.x.dot(origin - camera.global_position)
		anchor = Vector2(0.0 if camera_side < 0.0 else area.x, area.y * 0.55)
	var rise := (22.0 if drift < 0.0 else 14.0) + 76.0 * (1.0 - pow(1.0 - progress, 2.0))
	var spread := 1.26 - pow(1.0 - progress, 4.0)
	var center := anchor + Vector2(drift * spread, -rise)
	var margin := (popup.pivot_offset * 1.3 + Vector2(10.0, 10.0)).min(area * 0.5)
	var top := minf(score_label.get_rect().end.y + margin.y, area.y * 0.5)
	center = center.clamp(Vector2(margin.x, top), area - margin)
	popup.position = center - popup.pivot_offset


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
	volume_control = HBoxContainer.new()
	volume_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	volume_control.add_theme_constant_override("separation", 12)
	root.add_child(volume_control)
	_label(volume_control, "Громкость", 16, Color("f5dfb8"))
	var slider := HSlider.new()
	slider.name = &"Volume"
	slider.mouse_force_pass_scroll_events = false
	slider.custom_minimum_size.x = 116
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.step = 1.0
	slider.value = 0.0 if AudioServer.is_bus_mute(0) else db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0
	slider.value_changed.connect(_set_master_volume)
	volume_control.add_child(slider)
	volume_control.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	volume_control.hide()

func _set_master_volume(percent: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(percent / 100.0, 0.001)))
	AudioServer.set_bus_mute(0, is_zero_approx(percent))

func _start_background_music() -> void:
	music_started = true
	_play_next_music_track()

func _play_next_music_track() -> void:
	if next_music == null:
		_prepare_next_music_track()
		return
	background_music.stream = next_music
	next_music = null
	background_music.play()
	if OS.has_feature("web"):
		_prepare_next_music_track.call_deferred()


func _prepare_next_music_track() -> void:
	if next_music or music_loading or music_failures >= MUSIC_TRACKS.size():
		return
	if music_queue.is_empty():
		music_queue.assign(MUSIC_TRACKS)
		music_queue.shuffle()
		# The first track drawn after a reshuffle must differ from the last one played.
		if music_queue.back() == last_music_path:
			music_queue.push_front(music_queue.pop_back())
	last_music_path = music_queue.pop_back()
	if ResourceLoader.exists(last_music_path):
		_music_track_ready(load(last_music_path) as AudioStream)
		return
	if not OS.has_feature("web"):
		_music_track_ready(null)
		return
	if music_response_callback == null:
		music_response_callback = JavaScriptBridge.create_callback(_on_music_response)
		music_loaded_callback = JavaScriptBridge.create_callback(_on_music_downloaded)
		music_failed_callback = JavaScriptBridge.create_callback(_on_music_failed)
	music_loading = true
	var window := JavaScriptBridge.get_interface("window")
	# Read the whole response in the browser without waiting for a game frame per network chunk.
	var request: JavaScriptObject = window.fetch(last_music_path.trim_prefix("res://"))
	request.then(music_response_callback, music_failed_callback)


func _on_music_response(args: Array) -> void:
	var response: JavaScriptObject = args[0]
	if not response.ok:
		_music_track_ready(null)
		return
	var body: JavaScriptObject = response.arrayBuffer()
	body.then(music_loaded_callback, music_failed_callback)


func _on_music_downloaded(args: Array) -> void:
	var bytes := JavaScriptBridge.js_buffer_to_packed_byte_array(args[0])
	_music_track_ready(AudioStreamMP3.load_from_buffer(bytes))


func _on_music_failed(_args: Array) -> void:
	_music_track_ready(null)


func _music_track_ready(track: AudioStream) -> void:
	music_loading = false
	if track == null:
		music_failures += 1
		push_warning("Could not load soundtrack: " + last_music_path)
		_prepare_next_music_track.call_deferred()
		return
	music_failures = 0
	next_music = track
	if music_started and not background_music.playing:
		_play_next_music_track()

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
		var button := _text_button("Начать")
		intro_ui.add_child(button)
		button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		button.offset_left = -80
		button.offset_right = 80
		button.offset_top = -94
		button.offset_bottom = -50
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
	_end_nose_drag()
	intro_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro_transition.tween_property(camera, "transform", beaver_camera_transform, 0.45)
	intro_transition.finished.connect(_finish_intro, CONNECT_ONE_SHOT)

func _finish_intro() -> void:
	_end_nose_drag()
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

func _build_run_actions(root: Control) -> void:
	run_actions = CenterContainer.new()
	run_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(run_actions)
	run_actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 10)
	run_actions.add_child(stack)
	run_heading = _label(stack, "", 27, Color("fff0d1"))
	run_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_choices = VBoxContainer.new()
	run_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_choices.add_theme_constant_override("separation", 8)
	stack.add_child(run_choices)
	run_actions.hide()

func _text_button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("f8f3e6"))
	button.add_theme_color_override("font_hover_color", Color("9ef0ff"))
	button.add_theme_color_override("font_focus_color", Color("ffe9a6"))
	button.add_theme_color_override("font_outline_color", Color("0b1019"))
	button.add_theme_constant_override("outline_size", 8)
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(style, empty)
	return button

func _choice_button(title: String, detail: String, action: Callable) -> void:
	var button := _text_button(title)
	button.pressed.connect(action)
	run_choices.add_child(button)
	if run_choices.get_child_count() == 1:
		button.grab_focus()
	if not detail.is_empty():
		var caption := _label(run_choices, detail, 14, Color("e4edf4"))
		caption.custom_minimum_size.x = 420
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _show_run_actions(title: String) -> void:
	_clear_score_popups()
	for child in run_choices.get_children():
		run_choices.remove_child(child)
		child.queue_free()
	run_heading.text = title
	run_heading.visible = not title.is_empty()
	run_actions.show()

func _clear_score_popups() -> void:
	for popup in score_popups.get_children():
		popup.hide()
		popup.queue_free()

func _start_run() -> void:
	run.start(player_setup, rng)
	score_label.show()
	round_hud.show()
	_refresh_score()
	_position_top_hud(round_hud.get_parent() as Control)
	_new_round()

func _set_beaver_subtitle(text: String) -> void:
	beaver_subtitle.text = "" if text.is_empty() else "«%s»" % text


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
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
	_clear_score_popups()
	run.begin_player_turn()
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
	var starting_positions := PackedVector2Array()
	for side in 2:
		var roster := run.roster if side == 0 else enemy_roster
		for slot in formations[side].size():
			var point := formations[side][slot]
			_make_piece(side, roster[slot], point, slot)
			starting_positions.append(Vector2(point.x, point.z))
	zones.populate(rng, BOARD_TOP, starting_positions)
	turn = run.next_opening_side()
	_refresh_round_hud(true)
	run_actions.hide()
	_begin_turn()

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
	# A drag can end over the volume control.
	if nose_dragging and event is InputEventMouse:
		if event is InputEventMouseMotion:
			if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				_end_nose_drag()
			elif nose_grabbed and event.relative.length_squared() > 49.0:
				beaver_voice.react_to_nose_pull()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_nose_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
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
				_player_kick(piece, shot, offset)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _can_drag_nose():
			var nose := beaver.nose_transform()
			if _nose_hit(event.position, nose):
				nose_dragging = true
				nose_drag_start = event.position
				nose_drag_anchor = nose.origin
				get_viewport().set_input_as_handled()
				return
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
			selected = picked
			picked.set_turn_aura_selected(true)
			drag_start = event.position
			var hit_point: Vector3 = hit.position
			strike_offset = (hit_point - picked.global_position).slide(Vector3.UP)
			aiming = true
		elif _is_table_drag(ray_start, camera.project_ray_normal(event.position)):
			_begin_board_rotation()


func _can_drag_nose() -> bool:
	var intro_closeup := phase == "intro" and (intro_transition == null or not intro_transition.is_running())
	return ((intro_closeup or _is_player_turn()) and action_camera.mode == action_camera.Mode.IDLE
		and not aiming and not orbiting and beaver.can_grab_nose())


func _nose_hit(cursor: Vector2, nose: Transform3D) -> bool:
	if camera.is_position_behind(nose.origin):
		return false
	var hit: Variant = Plane(nose.basis.z, nose.origin).intersects_ray(
		camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if hit == null:
		return false
	var local_hit := nose.affine_inverse() * (hit as Vector3)
	# The grip point sits to the side of the center of the nose.
	var hit_offset := Vector2(local_hit.x + 0.21, local_hit.y)
	return (hit_offset / NOSE_HIT_RADII).length_squared() <= 1.0


func _update_nose_drag(cursor: Vector2) -> bool:
	var available := _can_drag_nose()
	if nose_dragging and not available:
		_end_nose_drag()
	if not nose_dragging:
		var hovering := (available and get_viewport().get_visible_rect().has_point(cursor)
			and _nose_hit(cursor, beaver.nose_transform()))
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovering else Input.CURSOR_ARROW)
		return false

	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	lilith.reach_for_nose(beaver.nose_transform().origin, beaver.global_rotation.y)
	if lilith.has_nose_grip():
		var depth := maxf(camera.near, -camera.to_local(nose_drag_anchor).z)
		var offset := camera.project_position(cursor, depth) - camera.project_position(nose_drag_start, depth)
		if nose_grabbed:
			beaver.pull_nose(offset)
		else:
			beaver.grab_nose(offset)
			nose_grabbed = true
			beaver_voice.react_to_nose_pull()
	return true


func _end_nose_drag() -> void:
	if not nose_dragging:
		return
	nose_dragging = false
	lilith.release_nose()
	if nose_grabbed:
		beaver.release_nose()
		nose_grabbed = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _piece_hit(cursor: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(cursor)
	var ray := camera.project_ray_normal(cursor)
	var nearest := INF
	var result := {}
	for piece in pieces:
		if piece.falling:
			continue
		var radius := piece.radius * Checker.PIXELS_PER_UNIT
		var height := piece.global_position.y
		var top: Variant = Plane(Vector3.UP, height + piece.half_height).intersects_ray(origin, ray)
		var bottom: Variant = Plane(Vector3.UP, height - piece.half_height).intersects_ray(origin, ray)
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
	lilith.cancel_aim()
	if is_instance_valid(selected):
		selected.set_turn_aura_selected(false)
	selected = null
	aiming = false
	strike_offset = Vector3.ZERO
	aim_arrow.hide()
	preview.hide()

func _end_player_drag() -> void:
	_end_nose_drag()
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
	var start := _on_board(selected.global_position) + direction * (selected.radius + 0.025)
	var length := lerpf(0.46, 1.72, power)
	if selected.hovering:
		start.y += selected.global_position.y - (PIECE_Y + selected.half_height - Checker.HALF_HEIGHT)
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
	return Rails.ray_exit_distance(Vector2(origin.x, origin.z),
		Vector2(local_direction.x, local_direction.z), TABLE_RADIUS - margin)

func _draw_trajectory(piece: Checker, shot: Vector3) -> void:
	var origin := _on_board(piece.global_position)
	var velocity := shot * SHOT_IMPULSE * piece.shot_multiplier() / piece.mass
	if piece.zone_speed_pending:
		velocity *= BoardZones.SPEED_MULTIPLIER
	var radius := piece.radius
	var drag := piece.planar_body.linear_damp
	var friction := piece.contact_material.friction * Checker.SLIDE_GRAVITY
	var visited := piece.zone_hits
	var previous := piece
	var rail_boost_available := true
	var displayed := false
	preview_mesh.clear_surfaces()
	for segment in 7:
		var speed := velocity.length()
		if speed < 0.12:
			break
		var direction := velocity / speed
		var slide_distance := Checker.slide_distance(speed, drag, friction)
		var distance := minf(slide_distance, _edge_distance(origin, direction))
		var local_origin := board_pivot.to_local(origin)
		var local_direction := board_pivot.global_basis.inverse() * direction
		var rail := rails.trace(local_origin, local_direction, distance, radius)
		if rail != null:
			distance = rail.distance
		var target: Checker
		for other in pieces:
			if other == piece or other == previous or other.falling or other.is_intangible():
				continue
			var offset := _on_board(other.global_position) - origin
			var intersection := Checker.sweep_disc(offset, direction, radius + other.radius)
			if intersection < distance:
				target = other
				distance = intersection
		var local_end := local_origin + local_direction * distance
		var zone := zones.first_entry(local_origin, local_end, visited)
		if zone:
			distance *= zone.entry_fraction(Vector2(local_origin.x, local_origin.z), Vector2(local_end.x, local_end.z))
		var dash_offset := radius + 0.025 if segment == 0 else 0.0
		if distance > maxf(dash_offset, 0.025):
			if not displayed:
				preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, preview_material)
				displayed = true
			while dash_offset < distance:
				_draw_line(preview_mesh, origin + direction * dash_offset, origin + direction * minf(dash_offset + 0.055, distance), 0.011)
				dash_offset += 0.10
		if zone and zone.kind == BoardZones.Kind.TELEPORT:
			break
		if zone == null and target == null and rail == null:
			break
		origin += direction * distance
		# Estimate speed at impact with the same sliding and damping as a normal checker.
		velocity = direction * Checker.speed_after_slide(speed, drag, friction, slide_distance - distance)
		if zone:
			visited |= 1 << zone.kind
			match zone.kind:
				BoardZones.Kind.SPEED: velocity *= BoardZones.SPEED_MULTIPLIER
				BoardZones.Kind.POWER:
					if piece.icon == Checker.Icon.SNOWFLAKE:
						drag /= BoardZones.POWER_MULTIPLIER
						friction /= BoardZones.POWER_MULTIPLIER
				BoardZones.Kind.SHRINK:
					radius = Checker.RADIUS * BoardZones.SHRINK_SCALE
					visited &= ~(1 << BoardZones.Kind.GROW)
				BoardZones.Kind.GROW:
					radius = Checker.RADIUS * BoardZones.GROW_SCALE
					visited &= ~(1 << BoardZones.Kind.SHRINK)
		elif target != null:
			var normal := origin.direction_to(_on_board(target.global_position))
			var bounce := piece.contact_material.bounce + target.contact_material.bounce
			var share := target.mass / (piece.mass + target.mass)
			velocity -= normal * velocity.dot(normal) * (1.0 + bounce) * share
			previous = target
		else:
			var local_velocity := local_direction * velocity.length()
			if local_velocity.dot(rail.normal) <= MIN_RAIL_BOUNCE_SPEED:
				break
			velocity = board_pivot.global_basis * Rails.reflected_velocity(
				local_velocity, rail.normal, rail_boost_available)
			rail_boost_available = false
			origin -= (board_pivot.global_basis * rail.normal) * 0.006
			previous = piece
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

func _update_lilith() -> void:
	var viewport := get_viewport()
	var cursor := viewport.get_mouse_position()
	if _update_nose_drag(cursor):
		return
	var look_target := Vector3.INF
	if phase != "intro" and action_camera.mode == action_camera.Mode.IDLE and viewport.get_visible_rect().has_point(cursor):
		var hit: Variant = Plane(Vector3.UP, BOARD_TOP + 0.56).intersects_ray(
			camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
		if hit != null:
			look_target = hit
	lilith.track_cursor(look_target)

	if not aiming or not is_instance_valid(selected):
		return
	var shot := _aim_vector(cursor)
	var direction := (-camera.global_basis.z).slide(Vector3.UP).normalized()
	if not shot.is_zero_approx():
		direction = shot.normalized()
	lilith.aim(_kick_contact(selected, direction, strike_offset),
		direction, shot.length() / MAX_PULL_STRENGTH)


func _kick_contact(piece: Checker, direction: Vector3, offset: Vector3) -> Vector3:
	var lateral := offset.slide(direction).limit_length(piece.radius * 0.75)
	var depth := sqrt(piece.radius * piece.radius - lateral.length_squared())
	return piece.global_position + lateral - direction * depth + Vector3.UP * (0.035 * piece.size_scale)


func _player_kick(piece: Checker, shot: Vector3, offset: Vector3) -> void:
	phase = "player_strike"
	var direction := shot.normalized()
	var strength := shot.length()
	await lilith.kick(_kick_contact(piece, direction, offset), direction, strength / MAX_PULL_STRENGTH)
	lilith.recover(direction)
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
	var lever := offset.slide(direction).limit_length(piece.radius) * 0.30
	_push(piece, piece.incoming_velocity, lever)
	_apply_zone_speed(piece)
	piece.incoming_velocity = piece.linear_velocity
	checker_strike_sound.play()
	var intensity := clampf(piece.incoming_velocity.length() / 6.0, 0.12, 1.0)
	piece.stretch_on_impact(direction, intensity)

func _begin_shot_resolution() -> void:
	if turn == 0:
		run.begin_player_turn()
	action_camera.new_shot()
	phase = "moving"
	shot_knockouts.fill(false)
	for piece in pieces:
		piece.incoming_velocity = Vector3.ZERO
		piece.lightning_used = false
		piece.rail_boost_used = false
	_reset_stillness()

func _is_off_board(world_position: Vector3, margin := 0.0) -> bool:
	return _is_outside_board(board_pivot.to_local(world_position), margin)

func _is_outside_board(local: Vector3, margin: float) -> bool:
	var radius := TABLE_RADIUS - margin
	return Vector2(local.x, local.z).length_squared() > radius * radius

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
			var direction := Checker.from_plane(b.planar_body.position - a.planar_body.position).normalized()
			_touch(a, b, board_pivot.global_basis * direction)
			processed[key] = true
	contacts.clear()
	if phasing_piece != null and not phasing_piece.teleport_dropping:
		_resolve_ghost_contacts()

func _resolve_ghost_contacts() -> void:
	var point := Checker.to_plane(phasing_piece.global_position)
	for other in pieces:
		if other.falling or other.is_intangible() or other in ghost_contacts:
			continue
		var center := Checker.to_plane(other.global_position)
		var radius := (phasing_piece.radius + other.radius) * Checker.PIXELS_PER_UNIT
		var nearest := Geometry2D.get_closest_point_to_segment(center, ghost_previous_position, point)
		if center.distance_squared_to(nearest) <= radius * radius:
			ghost_contacts.append(other)
			_award(other, other.global_position + Vector3.UP * other.half_height)
			checker_ghost_touch_sound.play()
			_push(other, phasing_piece.linear_velocity * ((phasing_piece.zone_power - 1.0) * 0.85))
			_trigger_contact(other, phasing_piece)
	ghost_previous_position = point

func _push(piece: Checker, velocity: Vector3, offset := Vector3.ZERO) -> void:
	if piece.falling or piece.teleport_dropping or velocity.length_squared() < 0.0001:
		return
	piece.apply_planar_impulse(velocity, offset)

func _touch(a: Checker, b: Checker, normal: Vector3) -> void:
	var a_speed := a.incoming_velocity.dot(normal)
	var b_speed := -b.incoming_velocity.dot(normal)
	var closing_speed := a_speed + b_speed
	var a_struck := a_speed >= b_speed
	var contact_point := a.position.lerp(b.position, a.radius / (a.radius + b.radius))
	if closing_speed > 0.0:
		var target := b if a_struck else a
		if a.side != b.side:
			target = a if a.side == 1 else b
		if target.side == 1:
			var origin := board_pivot.to_global(contact_point) + Vector3.UP * target.half_height
			_award(target, origin)
	if closing_speed > 0.32:
		checker_hit_sound.play()
		var intensity := clampf(closing_speed / 4.7, 0.08, 1.0)
		action_camera.hit(board_pivot.to_global(contact_point), lilith.global_position if turn == 0 else Vector3.INF)
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
					"seen": [], "delay": 0.0, "power": piece.zone_power})
		Checker.Icon.STICKY:
			if not other.is_intangible() and not piece.glued and not other.glued:
				_stick_pieces(piece, other)
				_push(other, piece.incoming_velocity * ((piece.zone_power - 1.0) * 0.5))

func _stick_pieces(a: Checker, b: Checker) -> void:
	if a.glued or b.glued:
		return
	_space_sticky_pair(a, b, true)
	var middle := (a.planar_body.global_position + b.planar_body.global_position) * 0.5
	var axis := a.planar_body.global_position.direction_to(b.planar_body.global_position)
	var across := axis.orthogonal() * ((a.radius + b.radius) * Checker.PIXELS_PER_UNIT * 0.31)
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
	slime.custom_aabb = AABB(Vector3.ONE * -0.6, Vector3.ONE * 1.2)
	slime.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slime.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	board_pivot.add_child(slime)
	var link := {"bodies": [a, b], "joints": joints, "slime": slime}
	links.append(link)
	_update_sticky_slime(link)

func _space_sticky_pair(a: Checker, b: Checker, close_gap := false) -> void:
	var offset := b.planar_body.position - a.planar_body.position
	var distance := offset.length()
	var correction := (a.radius + b.radius) * Checker.PIXELS_PER_UNIT - distance
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
	var flat_offset := (end - start).slide(Vector3.UP)
	var distance := flat_offset.length()
	var forward := flat_offset / distance if distance > 0.001 else Vector3.RIGHT
	# Bury both ends in the rims so the gel meets the curved sides of the checkers.
	var inset := minf((a.radius + b.radius) * 0.5 - 0.065, distance * 0.4)
	var span := end - start - forward * (inset * 2.0)
	var axis := span.normalized() if span.length_squared() > 0.000001 else forward
	var side := forward.cross(Vector3.UP)
	var up := side.cross(axis)
	var shape := Basis(side * 0.24, axis * maxf(span.length(), 0.015), up * 0.092)
	slime.transform = Transform3D(shape, start.lerp(end, 0.5))

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
		if piece.fuse >= 0.0 and not piece.teleport_dropping:
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
	blast.scale = Vector3.ONE * bomb.zone_power
	blast_effects.add_child(blast)
	checker_explosion_sound.play()
	for piece in pieces:
		if piece == bomb or piece.falling or piece.is_intangible():
			continue
		var offset := _on_board(piece.global_position) - center
		var strength := 5.2 * bomb.zone_power * (1.0 - offset.length() / (1.12 * bomb.zone_power))
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
	_push(target, (endpoint - chain.origin).normalized() * (0.56 * chain.power))
	chain.seen.append(target)
	chain.origin = endpoint
	chain.visual_origin = target.global_position
	chain.next = null
	chain.delay = 0.10
	return chain.seen.size() < roundi(4.0 * chain.power)

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
	_update_lilith()
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
		_draw_ring(center, bomb.radius * 1.22, 0.019, Color(1.0, 0.60, 0.28, brightness))
	effects_mesh.surface_end()

func _draw_ring(center: Vector3, radius: float, width: float, color: Color) -> void:
	effects_mesh.surface_set_color(color)
	for i in 32:
		var from := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 32.0) * radius
		var to := center + Vector3.FORWARD.rotated(Vector3.UP, TAU * (i + 1) / 32.0) * radius
		_draw_line(effects_mesh, from, to, width)

func _contain_piece(piece: Checker, margin: float) -> void:
	var radial := piece.position.slide(Vector3.UP)
	var radius := TABLE_RADIUS - margin
	if radial.length_squared() <= radius * radius:
		return
	var normal := radial.normalized()
	var point := normal * radius + Vector3.UP * piece.position.y
	var velocity := Checker.from_plane(piece.planar_body.linear_velocity)
	velocity -= normal * maxf(velocity.dot(normal), 0.0)
	piece.place_on_board(point, piece.rotation.y)
	piece.planar_body.linear_velocity = Checker.to_plane(velocity)


func _bounce_on_rail(piece: Checker, previous: Vector3) -> void:
	if piece.hovering:
		return
	var movement := (piece.position - previous).slide(Vector3.UP)
	var distance := movement.length()
	if distance <= 0.00001:
		return
	var direction := movement / distance
	var contact := rails.trace(previous, direction, distance, piece.radius)
	if contact == null:
		return
	var normal := contact.normal
	var velocity := Checker.from_plane(piece.planar_body.linear_velocity)
	var speed := velocity.dot(normal)
	var point := previous + direction * contact.distance - normal * 0.006
	point.y = piece.position.y
	piece.place_on_board(point, piece.rotation.y)
	if speed <= MIN_RAIL_BOUNCE_SPEED:
		return
	var boost := not piece.rail_boost_used
	var outgoing := Rails.reflected_velocity(velocity, normal, boost)
	piece.planar_body.sleeping = false
	piece.planar_body.linear_velocity = Checker.to_plane(outgoing)
	piece.incoming_velocity = piece.linear_velocity
	piece.rail_boost_used = true
	if speed > 0.25:
		checker_hit_sound.play()
		piece.stretch_on_impact(board_pivot.global_basis * normal, clampf(speed / 5.0, 0.1, 0.95))

func _resolve_board_edge(piece: Checker) -> void:
	if not _is_outside_board(piece.position, 0.0):
		piece.hovering = false
		return
	if piece.hovering:
		if _is_outside_board(piece.position, -FLOAT_RANGE * piece.zone_power):
			_contain_piece(piece, -FLOAT_RANGE * piece.zone_power)
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
	_release_piece_links(piece)
	piece.fuse_origin = piece.global_position
	var outward := Vector3.ZERO
	if not _is_outside_board(piece.position, -piece.radius - 0.015):
		outward = board_pivot.global_basis * piece.position.slide(Vector3.UP).normalized()
	_award(piece, piece.global_position + Vector3.UP * piece.half_height, true)
	piece.leave_board(outward)
	action_camera.fall(piece, board_pivot.global_position)
	if not shot_knockouts[piece.side]:
		shot_knockouts[piece.side] = true
		beaver_voice.react_to_knockout(piece.side == 1)


func _release_piece_links(piece: Checker) -> void:
	for i in range(links.size() - 1, -1, -1):
		if piece in links[i].bodies:
			_release_link(i)

func _start_zone_turn() -> void:
	for piece in pieces:
		if piece.falling:
			continue
		var occupied := zones.at(piece.position)
		piece.zone_hits = 0
		piece.zone_speed_pending = false
		piece.set_zone_power(BoardZones.POWER_MULTIPLIER
			if occupied and occupied.kind == BoardZones.Kind.POWER else 1.0)
		var size := 1.0
		if occupied:
			match occupied.kind:
				BoardZones.Kind.SHRINK: size = BoardZones.SHRINK_SCALE
				BoardZones.Kind.GROW: size = BoardZones.GROW_SCALE
				BoardZones.Kind.SPEED: piece.zone_speed_pending = true
			if occupied.kind != BoardZones.Kind.TELEPORT:
				piece.zone_hits = 1 << occupied.kind
				occupied.pulse()
		_resize_zone_piece(piece, size)


func _visit_board_zones(piece: Checker, previous: Vector3) -> bool:
	var visited := piece.zone_hits
	var zone := zones.first_entry(previous, piece.position, visited)
	while zone:
		visited |= 1 << zone.kind
		piece.zone_hits |= 1 << zone.kind
		zone.pulse()
		match zone.kind:
			BoardZones.Kind.TELEPORT:
				return true
			BoardZones.Kind.SPEED:
				piece.zone_speed_pending = true
			BoardZones.Kind.POWER:
				piece.set_zone_power(BoardZones.POWER_MULTIPLIER)
			BoardZones.Kind.SHRINK:
				_resize_zone_piece(piece, BoardZones.SHRINK_SCALE)
				piece.zone_hits &= ~(1 << BoardZones.Kind.GROW)
			BoardZones.Kind.GROW:
				_resize_zone_piece(piece, BoardZones.GROW_SCALE)
				piece.zone_hits &= ~(1 << BoardZones.Kind.SHRINK)
		zone = zones.first_entry(previous, piece.position, visited)
	return false


func _apply_zone_speed(piece: Checker) -> void:
	if not piece.zone_speed_pending or piece.planar_body.linear_velocity.length_squared() < 0.01:
		return
	piece.planar_body.sleeping = false
	piece.planar_body.linear_velocity *= BoardZones.SPEED_MULTIPLIER
	piece.incoming_velocity = piece.linear_velocity
	piece.zone_speed_pending = false


func _resize_zone_piece(piece: Checker, size: float) -> void:
	var radius := Checker.RADIUS * size
	if size > piece.size_scale and not piece.hovering and not _zone_position_clear(piece.position, piece, radius):
		var nearby := _nearby_zone_position(piece, radius)
		if nearby == Vector3.INF:
			return
		_reposition_zone_piece(piece, nearby)
	piece.resize_in_zone(size)


func _nearby_zone_position(piece: Checker, radius: float) -> Vector3:
	for ring in range(1, 9):
		for i in ring * 8:
			var offset := Vector3.RIGHT.rotated(Vector3.UP, TAU * i / (ring * 8)) * (ring * 0.046)
			var point := piece.position + offset
			if _zone_position_clear(point, piece, radius):
				return point
	return Vector3.INF


func _zone_position_clear(point: Vector3, piece: Checker, radius: float) -> bool:
	if _is_outside_board(point, radius + PIECE_CLEARANCE) or rails.overlaps_disc(point, radius):
		return false
	var center := Checker.to_plane(point)
	for other in pieces:
		if other == piece or other.falling:
			continue
		var clearance := (radius + other.radius + PIECE_CLEARANCE) * Checker.PIXELS_PER_UNIT
		if other.planar_body.position.distance_squared_to(center) < clearance * clearance:
			return false
	return true


func _teleport_landing(piece: Checker) -> Vector3:
	const RANDOM_ATTEMPTS := 60
	const SPIRAL_ATTEMPTS := 40
	var limit := Rails.INNER_RADIUS - piece.radius - 0.025
	var height := PIECE_Y + piece.half_height - Checker.HALF_HEIGHT
	var angle_offset := rng.randf_range(0.0, TAU)
	for attempt in RANDOM_ATTEMPTS + SPIRAL_ATTEMPTS:
		var random_sample := attempt < RANDOM_ATTEMPTS
		var angle := rng.randf_range(0.0, TAU) if random_sample else angle_offset + attempt * 2.39996
		var area_fraction := rng.randf() if random_sample else float(attempt - RANDOM_ATTEMPTS) / SPIRAL_ATTEMPTS
		var distance := sqrt(area_fraction) * limit
		var point := Vector3(cos(angle) * distance, height, sin(angle) * distance)
		var field := zones.at(point)
		if field and field.kind == BoardZones.Kind.TELEPORT:
			continue
		if _zone_position_clear(point, piece, piece.radius):
			return point
	return Vector3.INF


func _teleport_from_zone(piece: Checker) -> void:
	var landing := _teleport_landing(piece)
	if landing == Vector3.INF:
		return
	var flash_height := BOARD_TOP + 0.022
	zones.flash(Vector3(piece.position.x, flash_height, piece.position.z), BoardZones.Kind.TELEPORT)
	_reposition_zone_piece(piece, landing)
	piece.hovering = false
	piece.begin_teleport_drop()
	zones.flash(Vector3(landing.x, flash_height, landing.z), BoardZones.Kind.TELEPORT, 0.40)


func _finish_zone_drop(piece: Checker) -> void:
	if not _zone_position_clear(piece.position, piece, piece.radius):
		var clear_point := _nearby_zone_position(piece, piece.radius)
		if clear_point == Vector3.INF:
			clear_point = _teleport_landing(piece)
		if clear_point != Vector3.INF:
			_reposition_zone_piece(piece, clear_point)
	piece.finish_teleport_drop()
	zones.flash(Vector3(piece.position.x, BOARD_TOP + 0.022, piece.position.z), BoardZones.Kind.TELEPORT)
	checker_hit_sound.play()


func _reposition_zone_piece(piece: Checker, point: Vector3) -> void:
	_release_piece_links(piece)
	piece.place_on_board(point, piece.rotation.y)
	PhysicsServer2D.body_set_state(piece.planar_body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM,
		piece.planar_body.global_transform)
	piece.reset_physics_interpolation()
	checker_trails.forget(piece)
	if piece == phasing_piece:
		ghost_previous_position = Checker.to_plane(piece.global_position)


func _physics_process(delta: float) -> void:
	if phase != "moving": return
	var departures: Array[Checker] = []
	for p in pieces:
		if p.teleport_dropping:
			if not p.advance_teleport_drop(delta):
				continue
			_finish_zone_drop(p)
		if not p.falling:
			var previous := p.position
			p.sync_planar_position()
			var stopping_distance := INF
			if p.hovering:
				var direction := p.linear_velocity.normalized()
				stopping_distance = maxf(_edge_distance(p.global_position, direction, -FLOAT_RANGE * p.zone_power), 0.04)
			p.apply_slide_friction(delta, stopping_distance)
			_bounce_on_rail(p, previous)
			if _visit_board_zones(p, previous):
				departures.append(p)
			_apply_zone_speed(p)
	_resolve_contacts()
	for piece in departures:
		_teleport_from_zone(piece)
	var pending := _tick_effects(delta)
	for link in links:
		_space_sticky_pair(link.bodies[0], link.bodies[1])
	var moving := false
	var falling := false
	for i in range(pieces.size() - 1, -1, -1):
		var p := pieces[i]
		if p.teleport_dropping:
			moving = true
			continue
		if not p.falling:
			_resolve_board_edge(p)
			if p.float_used and not p.falling:
				var height := PIECE_Y + p.half_height - Checker.HALF_HEIGHT + (FLOAT_HEIGHT if p.hovering else 0.0)
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
	if (phasing_piece != null and not phasing_piece.teleport_dropping
			and phasing_piece.linear_velocity.length_squared() <= 0.0025):
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
	if _ghost_landing_is_clear(origin, piece):
		return origin
	const SEARCH_STEP := Checker.RADIUS / 3.0
	var search_rings := ceili(TABLE_RADIUS * 2.4 / SEARCH_STEP)
	for ring in range(1, search_rings + 1):
		for i in ring * 8:
			var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / (ring * 8))
			var point := origin + direction * (SEARCH_STEP * ring)
			if _ghost_landing_is_clear(point, piece):
				return point
	return origin

func _ghost_landing_is_clear(position: Vector3, piece: Checker) -> bool:
	if _is_off_board(position) or rails.overlaps_disc(board_pivot.to_local(position), piece.radius):
		return false
	for other in pieces:
		if other == piece or other.falling or other.is_intangible():
			continue
		var offset := (other.global_position - position).slide(Vector3.UP)
		var clearance := piece.radius + other.radius + PIECE_CLEARANCE
		if offset.length_squared() < clearance * clearance:
			return false
	return true

func _materialize_ghost() -> void:
	var piece := phasing_piece
	var destination := _find_ghost_landing(piece)
	for other in pieces:
		if other.falling or other.is_intangible():
			continue
		var offset := (other.global_position - piece.global_position).slide(Vector3.UP)
		var clearance := piece.radius + other.radius + PIECE_CLEARANCE
		var depth := clearance - offset.length()
		if depth > 0.0:
			var direction := offset.normalized()
			if direction.is_zero_approx():
				direction = (other.global_position - destination).slide(Vector3.UP).normalized()
			_push(other, direction * lerpf(0.12, 0.55, depth / clearance))
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
	contacts.clear()
	var counts := [0, 0]
	for p in pieces:
		p.stop_motion()
		counts[p.side] += 1
	if counts[0] == 0 or counts[1] == 0:
		phase = "round_end"
		var result := Run.RoundResult.DRAW
		var result_cue := &"draw"
		if counts[0] > 0:
			result = Run.RoundResult.PLAYER
			result_cue = &"lose"
		elif counts[1] > 0:
			result = Run.RoundResult.BEAVER
			result_cue = &"win"
		run.finish_round(result)
		_refresh_round_hud(result == Run.RoundResult.DRAW)
		await beaver_voice.speak(result_cue)
		_offer_next_round(result)
		return
	turn = 1 - turn
	_begin_turn()


func _begin_turn() -> void:
	_start_zone_turn()
	phase = "aim"
	if turn == 1:
		await get_tree().create_timer(0.38).timeout
		if phase == "aim" and turn == 1: _bot_shoot()


func _offer_next_round(result: Run.RoundResult) -> void:
	if run.match_finished():
		_show_run_actions("")
		_choice_button("Новый матч", "", _start_run)
		return
	if result != Run.RoundResult.PLAYER:
		_new_round()
		return
	var rewards := run.offer()
	if rewards.is_empty():
		_new_round()
		return
	phase = "reward"
	_show_run_actions("Выбери шашку")
	for icon in rewards:
		_choice_button(Checker.ICON_NAMES[icon], Checker.ICON_DETAILS[icon], _choose_reward.bind(icon))

func _choose_reward(icon: Checker.Icon) -> void:
	if phase == "reward":
		run.choose(icon)
		_new_round()

func _bot_shoot() -> void:
	phase = "windup"
	await beaver.wait_for_stance()
	var shot := await shot_planner.choose(beaver, board_pivot, rails, zones, pieces,
		SHOT_IMPULSE, minf(2.5 + (run.stage - 1) * 0.04, MAX_PULL_STRENGTH), run.completed_turns)
	if shot == null:
		_begin_shot_resolution()
		return
	var piece := shot.piece
	await beaver_voice.speak(&"aim")
	if is_instance_valid(piece) and not piece.is_queued_for_deletion():
		var ready := await beaver.wind_up(piece.global_position, shot.direction, shot.setup, piece.size_scale)
		if ready and is_instance_valid(piece) and not piece.is_queued_for_deletion():
			var hit := await beaver.strike(piece.global_position, shot.direction, piece.size_scale)
			if hit and is_instance_valid(piece) and not piece.is_queued_for_deletion():
				_shoot(piece, shot.direction, shot.strength)
				beaver.recover(shot.direction)
				return
		if ready:
			await beaver.recover()
	_begin_shot_resolution()
