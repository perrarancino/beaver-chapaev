extends Node3D

const Beaver := preload("res://beaver.gd")
const LIGHT_PIECE := preload("res://piece_light.tscn")
const DARK_PIECE := preload("res://piece_dark.tscn")
const BOARD_RADIUS := 2.35
const FLOOR_Y := -2.1
const SHOT_IMPULSE := 3.0
const DRAG_DEAD_ZONE := 12.0
const MAX_PULL_STRENGTH := 2.8
const AIM_LIFT := 0.09
var pieces: Array[Checker] = []
var starting_sides: Dictionary[Vector3, int] = {}
var selected: Checker
var aiming := false
var drag_start := Vector2.ZERO
var turn := 0 # 0 player, 1 beaver
var phase := "aim"
var still_time := 0.0
var shot_time := 0.0
var round_no := 1
var wins := 0
var losses := 0
var camera: Camera3D
var status: Label
var score: Label
var hint: Label
var beaver_subtitle: Label
var power_back: ColorRect
var power_fill: ColorRect
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
 _build_ui()
 beaver_voice.subtitle_changed.connect(_set_beaver_subtitle)
 get_window().focus_exited.connect(_cancel_aim)
 for piece: Checker in $StartingPieces.get_children():
  starting_sides[piece.position] = piece.side
  piece.reparent(self)
  pieces.append(piece)
 _update_ui()

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
 beaver_subtitle.offset_bottom = 106
 beaver_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 beaver_subtitle.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.013, 0.9))
 beaver_subtitle.add_theme_constant_override("shadow_offset_y", 2)
 hint = _label(root, "ЛКМ: тяни шашку для удара или нижний край для поворота", 16, Color("eed9b8"))
 hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 hint.position = Vector2(-280, -62)
 hint.size = Vector2(560, 30)
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

func _set_beaver_subtitle(text: String) -> void:
 beaver_subtitle.text = "" if text.is_empty() else "«%s»" % text


func _new_round() -> void:
 for p in pieces:
  if is_instance_valid(p): p.queue_free()
 pieces.clear()
 _cancel_aim()
 for start in starting_sides:
  _make_piece(starting_sides[start], start.rotated(Vector3.UP, board_angle))
 turn = 0
 phase = "aim"
 _update_ui()

func _make_piece(side: int, pos: Vector3) -> void:
 var scene := LIGHT_PIECE if side == 0 else DARK_PIECE
 var body := scene.instantiate() as Checker
 body.position = pos
 body.rotation.y = board_angle
 add_child(body)
 pieces.append(body)

func _update_ui() -> void:
 score.text = "РАУНД %d     ТЫ %d : %d БОБЁР" % [round_no, wins, losses]
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
   var ray_end := ray_start + camera.project_ray_normal(event.position) * 100
   var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
   var hit := get_world_3d().direct_space_state.intersect_ray(query)
   var picked := hit.get("collider") as Checker
   if picked and picked.side == 0:
    selected = picked
    drag_start = event.position
    aiming = true
   elif _is_table_drag(ray_start, camera.project_ray_normal(event.position)):
    _begin_board_rotation()
  elif aiming:
   var piece := selected
   var shot := _aim_vector(event.position)
   _cancel_aim()
   if not shot.is_zero_approx():
    _shoot(piece, shot.normalized(), shot.length())
 if event is InputEventMouseMotion and aiming:
  _draw_aim(_aim_vector(event.position))

func _cancel_aim() -> void:
 selected = null
 aiming = false
 aim_arrow.hide()
 power_fill.size = Vector2.ZERO

func _draw_aim(shot: Vector3) -> void:
 aim_arrow.visible = not shot.is_zero_approx()
 if not aim_arrow.visible:
  power_fill.size = Vector2.ZERO
  return
 var direction := shot.normalized()
 var power := shot.length() / MAX_PULL_STRENGTH
 var length := lerpf(0.46, 1.72, power)
 aim_arrow.position = selected.position + Vector3.UP * AIM_LIFT +  + direction * (Checker.RADIUS + 0.025 + length * 0.5)
 aim_arrow.rotation.y = atan2(direction.x, direction.z)
 aim_arrow.scale.z = length
 aim_material.set_shader_parameter("arrow_length", length)
 power_fill.size = Vector2(200 * power, 6)

func _begin_board_rotation() -> void:
 orbiting = true
 for piece in pieces:
  piece.freeze = true
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
  piece.global_transform = proxy.global_transform
  piece.reset_physics_interpolation()
  piece.visible = true
  piece.freeze = false
  piece.sleeping = true
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
 var origin := selected.global_position + Vector3.UP * AIM_LIFT
 # Use a nearby point on the screen ray so long pulls never shoot above the plane's horizon.
 var sample := camera.unproject_position(origin) - drag.normalized() * 12.0
 var plane := Plane(Vector3.UP, origin.y)
 var hit: Variant = plane.intersects_ray(
  camera.project_ray_origin(sample), camera.project_ray_normal(sample))
 if hit == null:
  return Vector3.ZERO
 return origin.direction_to(hit) * _pull_strength(drag)

func _shoot(piece: Checker, direction: Vector3, strength: float) -> void:
 phase = "moving"
 still_time = 0
 shot_time = 0
 piece.sleeping = false
 piece.apply_central_impulse(direction * strength * SHOT_IMPULSE)
 _update_ui()

func _physics_process(delta: float) -> void:
 if phase != "moving": return
 shot_time += delta
 var moving := false
 var falling := false
 for i in range(pieces.size() - 1, -1, -1):
  var p := pieces[i]
  if not p.falling and Vector2(p.position.x, p.position.z).length_squared() > BOARD_RADIUS * BOARD_RADIUS:
   p.leave_board()
  if p.falling:
   if p.position.y <= FLOOR_Y:
    pieces.remove_at(i)
    p.queue_free()
    continue
   falling = true
  elif not p.sleeping and p.linear_velocity.length_squared() > 0.0064:
   moving = true
 if moving: still_time = 0
 else: still_time += delta
 if not falling and (still_time >= 0.35 or shot_time >= 9.0):
  _finish_shot()

func _finish_shot() -> void:
 var counts := [0, 0]
 for p in pieces:
  p.linear_velocity = Vector3.ZERO
  p.angular_velocity = Vector3.ZERO
  p.sleeping = true
  counts[p.side] += 1
 if counts[0] == 0 or counts[1] == 0:
  phase = "round_end"
  if counts[0] == 0 and counts[1] == 0:
   status.text = "НИЧЬЯ!"
   beaver_voice.say(&"draw")
  elif counts[1] == 0:
   wins += 1
   status.text = "ТЫ ПОБЕДИЛ!"
   beaver_voice.say(&"lose")
  else:
   losses += 1
   status.text = "БОБЁР ПОБЕДИЛ"
   beaver_voice.say(&"win")
  score.text = "РАУНД %d     ТЫ %d : %d БОБЁР" % [round_no, wins, losses]
  hint.text = "Следующий раунд через пару секунд…"
  await get_tree().create_timer(2.5).timeout
  round_no += 1
  hint.text = "ЛКМ: тяни шашку для удара или нижний край для поворота"
  _new_round()
  return
 turn = 1 - turn
 phase = "aim"
 _update_ui()
 if turn == 1:
  await get_tree().create_timer(0.38).timeout
  if phase == "aim" and turn == 1: _bot_shoot()

func _bot_shoot() -> void:
 var mine: Array[Checker] = []
 var enemies: Array[Checker] = []
 for p in pieces:
  if not is_instance_valid(p) or p.is_queued_for_deletion() or p.falling: continue
  if p.side == 1: mine.append(p)
  else: enemies.append(p)
 if mine.is_empty() or enemies.is_empty():
  _finish_shot()
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
  _finish_shot()
  return
 phase = "windup"
 _update_ui()
 await beaver.wait_for_stance()
 await beaver_voice.say_turn()
 if is_instance_valid(best) and not best.is_queued_for_deletion():
  var ready := await beaver.wind_up(best.global_position, direction, best_setup)
  if ready and is_instance_valid(best) and not best.is_queued_for_deletion():
   var hit := await beaver.strike(best.global_position, direction)
   if hit and is_instance_valid(best) and not best.is_queued_for_deletion():
    _shoot(best, direction, rng.randf_range(1.8, 2.5))
    beaver.recover(direction)
    return
  if ready:
   await beaver.recover()
 _finish_shot()
