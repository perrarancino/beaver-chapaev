extends Node3D

const PIECE_Y = 0.07
const COUNT = 8
const TABLE_BOTTOM_Y = -0.60
var pieces: Array[RigidBody3D] = []
var selected: RigidBody3D
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
var power_back: ColorRect
var power_fill: ColorRect
var aim_line: MeshInstance3D
var rng := RandomNumberGenerator.new()
var orbiting := false
var board_angle := 0.0
var rotation_proxies: Dictionary = {}
@onready var beaver = $Beaver

func _ready() -> void:
 rng.randomize()
 camera = $Camera3D
 aim_line = $AimLine
 $PreviewPieces.queue_free()
 _build_ui()
 _new_round()

func _material(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = roughness
 m.metallic = metallic
 return m

func _label(parent: Control, text_value: String, size: int, color: Color) -> Label:
 var l := Label.new()
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
 hint = _label(root, "ЛКМ: тяни шашку для удара или нижний край для поворота", 16, Color("eed9b8"))
 hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 hint.position = Vector2(-280, -62)
 hint.size = Vector2(560, 30)
 hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 power_back = ColorRect.new()
 power_back.color = Color("382d27")
 power_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 power_back.position = Vector2(-100, -28)
 power_back.size = Vector2(200, 6)
 root.add_child(power_back)
 power_fill = ColorRect.new()
 power_fill.color = Color("e9a95f")
 power_fill.size = Vector2.ZERO
 power_back.add_child(power_fill)

func _new_round() -> void:
 for p in pieces:
  if is_instance_valid(p): p.queue_free()
 pieces.clear()
 selected = null
 aiming = false
 aim_line.visible = false
 for side in range(2):
  for i in range(COUNT):
   var start := Vector3(-1.4 + i * 0.4, PIECE_Y, 1.65 if side == 0 else -1.65)
   _make_piece(side, start.rotated(Vector3.UP, board_angle))
 turn = 0
 phase = "aim"
 _update_ui()

func _make_piece(side: int, pos: Vector3) -> void:
 var scene: PackedScene = load("res://piece_light.tscn" if side == 0 else "res://piece_dark.tscn")
 var body := scene.instantiate() as RigidBody3D
 body.position = pos
 body.set_meta("side", side)
 body.contact_monitor = true
 body.max_contacts_reported = 8
 body.body_entered.connect(_on_piece_body_entered.bind(body))
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
  if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
   DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
  else:
   DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
  get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and orbiting:
  orbiting = false
  for piece in rotation_proxies:
   var proxy: Node3D = rotation_proxies[piece]
   if is_instance_valid(piece) and is_instance_valid(proxy):
    piece.global_transform = proxy.global_transform
    piece.reset_physics_interpolation()
    piece.linear_velocity = Vector3.ZERO
    piece.angular_velocity = Vector3.ZERO
    piece.visible = true
    piece.freeze = false
    piece.sleeping = true
    proxy.queue_free()
  rotation_proxies.clear()
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
   if hit and hit.collider is RigidBody3D and hit.collider.get_meta("side", -1) == 0:
    selected = hit.collider
    drag_start = event.position
    aiming = true
   elif _is_table_drag(ray_start, camera.project_ray_normal(event.position)):
    orbiting = true
    rotation_proxies.clear()
    for piece in pieces:
     if is_instance_valid(piece):
      piece.linear_velocity = Vector3.ZERO
      piece.angular_velocity = Vector3.ZERO
      piece.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
      piece.freeze = true
      var proxy := Node3D.new()
      $BoardPivot.add_child(proxy)
      proxy.global_transform = piece.global_transform
      for child in piece.get_children():
       if child is MeshInstance3D:
        proxy.add_child(child.duplicate())
      piece.visible = false
      rotation_proxies[piece] = proxy
  elif aiming:
   var drag: Vector2 = event.position - drag_start
   aiming = false
   aim_line.visible = false
   power_fill.size = Vector2.ZERO
   if drag.length() > 12 and is_instance_valid(selected):
    var direction := _drag_direction(drag)
    _shoot(selected, direction, clampf(_pull_strength(drag), 0.4, 2.8))
   selected = null
 if event is InputEventMouseMotion and aiming and is_instance_valid(selected):
  var drag: Vector2 = event.position - drag_start
  var direction := _drag_direction(drag)
  var strength := _pull_strength(drag)
  aim_line.visible = strength > 0.12
  aim_line.position = selected.position + direction * (0.3 + strength * 0.22) + Vector3(0, 0.15, 0)
  aim_line.rotation.y = atan2(direction.x, direction.z)
  aim_line.scale.z = strength * 0.44
  power_fill.size = Vector2(200 * strength / 2.8, 6)

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
 return clampf(drag.length() / maxf(available, 1.0) * 2.8, 0.0, 2.8)

func _drag_direction(drag: Vector2) -> Vector3:
 var right := camera.global_transform.basis.x
 var back := camera.global_transform.basis.z
 right.y = 0
 back.y = 0
 return (-right.normalized() * drag.x - back.normalized() * drag.y).normalized()

func _shoot(piece: RigidBody3D, direction: Vector3, strength: float) -> void:
 phase = "moving"
 still_time = 0
 shot_time = 0
 piece.sleeping = false
 piece.apply_central_impulse(direction * strength * 4.2)
 _update_ui()

func _physics_process(delta: float) -> void:
 if phase != "moving": return
 shot_time += delta
 var moving := false
 var falling := false
 for p in pieces:
  if not is_instance_valid(p) or p.is_queued_for_deletion(): continue
  if p.position.y < TABLE_BOTTOM_Y:
   falling = true
  if not moving and not p.sleeping and (
   p.linear_velocity.length_squared() > 0.01 or p.angular_velocity.length_squared() > 0.25
  ):
   moving = true
 if moving: still_time = 0
 else: still_time += delta
 if not falling and ((still_time > 0.7 and shot_time > 0.7) or shot_time > 9):
  _finish_shot()

func _on_piece_body_entered(other: Node, piece: RigidBody3D) -> void:
 if other == $FloorPhysics:
  piece.queue_free()

func _finish_shot() -> void:
 var remaining: Array[RigidBody3D] = []
 var counts := [0, 0]
 for p in pieces:
  if is_instance_valid(p) and not p.is_queued_for_deletion():
   remaining.append(p)
   counts[int(p.get_meta("side"))] += 1
 pieces = remaining
 if counts[0] == 0 or counts[1] == 0:
  phase = "round_end"
  if counts[0] == 0 and counts[1] == 0:
   status.text = "НИЧЬЯ!"
  elif counts[1] == 0:
   wins += 1
   status.text = "ТЫ ПОБЕДИЛ!"
  else:
   losses += 1
   status.text = "БОБЁР ПОБЕДИЛ"
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
  await get_tree().create_timer(0.9).timeout
  if phase == "aim" and turn == 1: _bot_shoot()

func _bot_shoot() -> void:
 var mine: Array[RigidBody3D] = []
 var enemies: Array[RigidBody3D] = []
 for p in pieces:
  if not is_instance_valid(p) or p.is_queued_for_deletion(): continue
  if p.get_meta("side") == 1: mine.append(p)
  else: enemies.append(p)
 if mine.is_empty() or enemies.is_empty():
  _finish_shot()
  return
 var best: RigidBody3D = mine[0]
 var target: RigidBody3D = enemies[0]
 var best_distance := INF
 for a in mine:
  for b in enemies:
   var distance := a.position.distance_to(b.position) + rng.randf_range(0, 0.4)
   if distance < best_distance:
    best_distance = distance
    best = a
    target = b
 var direction := target.position - best.position
 direction.y = 0
 if direction.is_zero_approx(): direction = Vector3.BACK
 direction = direction.normalized().rotated(Vector3.UP, rng.randf_range(-0.08, 0.08))
 phase = "windup"
 _update_ui()
 await beaver.wind_up(best.global_position, direction)
 if is_instance_valid(best) and not best.is_queued_for_deletion():
  await beaver.strike(best.global_position, direction)
  if is_instance_valid(best) and not best.is_queued_for_deletion():
   _shoot(best, direction, rng.randf_range(1.8, 2.5))
   beaver.recover(direction)
   return
 await beaver.recover()
 _bot_shoot()
