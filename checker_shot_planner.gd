extends RefCounted

const Beaver := preload("res://beaver.gd")
const Rails := preload("res://edge_rails.gd")
const Zones := preload("res://board_zones.gd")
const AIM_OFFSETS := [0.0, -0.58, 0.58]
const POWER_STEPS := [0.28, 0.52, 0.76, 1.0]
const MIN_IMPACT_SPEED := 0.12
const THINK_SLICE_USEC := 5500

class Shot:
	var piece: Checker
	var setup: Beaver.ShotSetup
	var direction: Vector3
	var strength: float
	var score := -INF

class Slide:
	var position: Vector3
	var velocity: Vector3
	var target: Checker
	var mass: float
	var radius: float
	var drag: float
	var friction: float
	var visited: int
	var rail_boost := true
	var exited := false
	var teleported := false


func choose(beaver: Beaver, board: Node3D, rails: Rails, zones: Zones, pieces: Array[Checker],
		impulse: float, max_strength: float, completed_turns: int) -> Shot:
	var active: Array[Checker] = []
	var rivals: Array[Checker] = []
	var obstacles: Dictionary[Checker, Vector3] = {}
	for piece in pieces:
		if not is_instance_valid(piece) or piece.is_queued_for_deletion() or piece.falling or piece.teleport_dropping:
			continue
		active.append(piece)
		if not piece.is_intangible():
			obstacles[piece] = _flat(piece.position)
		if piece.side == 0:
			rivals.append(piece)
	if rivals.is_empty():
		return null

	var best := Shot.new()
	var board_basis := board.global_basis
	var deadline := Time.get_ticks_usec() + THINK_SLICE_USEC
	for piece in active:
		if piece.side == 0:
			continue
		var origin := _flat(piece.position)
		var headings := PackedVector3Array()
		for rival in rivals:
			var offset := _flat(rival.position) - origin
			var distance := offset.length()
			if distance < 0.001:
				continue
			var aim_width := minf(0.90, (piece.radius + rival.radius) / distance)
			for aim: float in AIM_OFFSETS:
				headings.append((offset / distance).rotated(Vector3.UP, aim * aim_width))
		# The additional headings cover banks and moves back in from the rim.
		var inward := -origin.normalized() if origin.length_squared() > 0.0001 else Vector3.BACK
		headings.append(inward)
		for i in 16:
			headings.append(Vector3.BACK.rotated(Vector3.UP, TAU * i / 16.0))
		var visited_headings: Dictionary[int, bool] = {}
		for direction in headings:
			var key := roundi(atan2(direction.x, direction.z) * 36.0)
			if visited_headings.has(key):
				continue
			visited_headings[key] = true
			if Time.get_ticks_usec() >= deadline:
				await beaver.get_tree().process_frame
				if not is_instance_valid(beaver):
					return null
				deadline = Time.get_ticks_usec() + THINK_SLICE_USEC
			var world_direction := board_basis * direction
			var setup := beaver.shot_setup(piece.global_position, world_direction, piece.size_scale)
			if setup == null:
				continue
			for fraction: float in POWER_STEPS:
				var strength := max_strength * fraction
				var speed := strength * impulse * piece.shot_multiplier() / piece.mass
				var result := _slide(piece, origin, direction * speed, rails, zones, obstacles)
				var score := _score_shot(piece, result, rails, zones, obstacles, completed_turns)
				score -= 0.048 * setup.cost + 0.045 * strength
				if score > best.score:
					best.score = score
					best.piece = piece
					best.setup = setup
					best.direction = world_direction
					best.strength = strength
	return best if best.piece != null else null


func _slide(piece: Checker, origin: Vector3, initial_velocity: Vector3, rails: Rails, zones: Zones,
		obstacles: Dictionary[Checker, Vector3], ignore: Checker = null, continuation: Slide = null) -> Slide:
	var result := continuation
	if result == null:
		result = Slide.new()
		result.mass = piece.mass
		result.radius = piece.radius
		result.drag = piece.planar_body.linear_damp
		result.friction = piece.contact_material.friction * Checker.SLIDE_GRAVITY
		result.visited = piece.zone_hits
		if piece.zone_speed_pending:
			initial_velocity *= Zones.SPEED_MULTIPLIER
	result.position = origin
	result.velocity = initial_velocity
	result.target = null
	var hovering := piece.hovering and origin.length() > Rails.TABLE_RADIUS
	for segment in 8:
		var speed := result.velocity.length()
		if speed < MIN_IMPACT_SPEED:
			break
		var direction := result.velocity / speed
		var travel := Checker.slide_distance(speed, result.drag, result.friction)
		var entry := INF
		var edge := INF
		if hovering:
			entry = Checker.sweep_disc(-origin, direction, Rails.TABLE_RADIUS)
			if entry < INF:
				entry += 0.015
		else:
			edge = _edge_distance(origin, direction)
		var distance := minf(travel, minf(edge, entry))
		var target: Checker
		for other in obstacles:
			if other == piece or other == ignore:
				continue
			var intersection := Checker.sweep_disc(obstacles[other] - origin, direction, result.radius + other.radius)
			if intersection < distance:
				distance = intersection
				target = other
		var rail := rails.trace(origin, direction, distance, result.radius) if not hovering else null
		if rail != null:
			distance = rail.distance
			target = null

		var end := origin + direction * distance
		var zone := zones.first_entry(origin, end, result.visited)
		if zone:
			var fraction := zone.entry_fraction(Vector2(origin.x, origin.z), Vector2(end.x, end.z))
			distance *= fraction
		origin += direction * distance
		result.position = origin
		if zone == null and target == null and rail == null and distance < entry:
			result.exited = edge <= travel
			break

		result.velocity = direction * Checker.speed_after_slide(speed, result.drag, result.friction, travel - distance)
		if zone:
			result.visited |= 1 << zone.kind
			match zone.kind:
				Zones.Kind.TELEPORT:
					result.teleported = true
					break
				Zones.Kind.SPEED: result.velocity *= Zones.SPEED_MULTIPLIER
				Zones.Kind.POWER:
					if piece.icon == Checker.Icon.SNOWFLAKE:
						result.drag = 0.04 / Zones.POWER_MULTIPLIER
						result.friction = Checker.ICE_FRICTION * Checker.SLIDE_GRAVITY / Zones.POWER_MULTIPLIER
					elif piece.icon == Checker.Icon.ARMORED:
						result.mass = Checker.ARMORED_MASS * Zones.POWER_MULTIPLIER
				Zones.Kind.SHRINK:
					result.radius = Checker.RADIUS * Zones.SHRINK_SCALE
					result.visited &= ~(1 << Zones.Kind.GROW)
				Zones.Kind.GROW:
					result.radius = Checker.RADIUS * Zones.GROW_SCALE
					result.visited &= ~(1 << Zones.Kind.SHRINK)
		elif target != null:
			result.target = target
			break
		elif rail != null:
			if result.velocity.dot(rail.normal) <= 0.025:
				break
			result.velocity = Rails.reflected_velocity(result.velocity, rail.normal, result.rail_boost)
			result.rail_boost = false
			origin -= rail.normal * 0.006
		hovering = hovering and origin.length() > Rails.TABLE_RADIUS
	return result


func _score_shot(piece: Checker, shot: Slide, rails: Rails, zones: Zones, obstacles: Dictionary[Checker, Vector3],
		completed_turns: int) -> float:
	var target := shot.target
	if target == null:
		return _position_score(piece, shot, completed_turns)
	var center := obstacles[target]
	var normal := shot.position.direction_to(center)
	var impact := maxf(shot.velocity.dot(normal), 0.0)
	var rival := target.side != piece.side
	var contact_score := 0.30 * minf(impact, 4.0) if rival else -0.42
	var launched := shot.velocity
	var transferred := Vector3.ZERO
	if piece.is_intangible():
		transferred = shot.velocity * ((piece.zone_power - 1.0) * 0.85)
		contact_score *= 0.20
	else:
		var bounce := piece.contact_material.bounce + target.contact_material.bounce
		var momentum := impact * (1.0 + bounce) / (shot.mass + target.mass)
		launched -= normal * momentum * target.mass
		transferred = normal * momentum * shot.mass
		if piece.glued or target.glued:
			transferred *= 0.65
		elif piece.icon == Checker.Icon.STICKY or target.icon == Checker.Icon.STICKY:
			launched = shot.velocity * shot.mass / (shot.mass + target.mass)
			transferred = launched

	var striker_end := _slide(piece, shot.position, launched, rails, zones, obstacles, target, shot)
	var target_end := _slide(target, center, transferred, rails, zones, obstacles, piece)
	if rival and target.icon == Checker.Icon.EXPLOSIVE and not target.exploded:
		contact_score -= 0.48 if striker_end.position.distance_squared_to(target_end.position) < 0.85 else 0.18
	if rival and target.icon == Checker.Icon.LIGHTNING:
		contact_score -= 0.20
	return contact_score + _position_score(piece, striker_end, completed_turns) + _position_score(target, target_end, completed_turns)


func _position_score(piece: Checker, result: Slide, completed_turns: int) -> float:
	var ally := piece.side == 1
	var landing := result.position.length()
	var was_hovering := piece.hovering and piece.hover_started_turn < completed_turns
	var lost := result.exited or (was_hovering and landing >= Rails.TABLE_RADIUS - 0.025)
	if lost:
		var can_hover := piece.icon == Checker.Icon.FLOATING and not piece.float_used
		if ally:
			return -3.0 if can_hover else -10.0
		return 3.3 if can_hover else 8.0
	if result.teleported:
		return -0.68 if ally else -0.15
	var start := _flat(piece.position).length()
	var rim_change := smoothstep(1.65, Rails.TABLE_RADIUS, landing) - smoothstep(1.65, Rails.TABLE_RADIUS, start)
	if ally:
		return (4.8 if was_hovering else 0.0) - 1.4 * rim_change + 0.16 * (start - landing)
	return 1.8 * rim_change + 0.24 * (landing - start)


func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _edge_distance(origin: Vector3, direction: Vector3) -> float:
	return Rails.ray_exit_distance(Vector2(origin.x, origin.z), Vector2(direction.x, direction.z), Rails.TABLE_RADIUS)
