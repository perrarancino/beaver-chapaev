extends Node3D

enum Kind { OPEN, WOOD, SPRING, TELEPORT }

# The imported tabletop measures 2.871–2.874 m from its center to the rim.
const TABLE_RADIUS := 2.872
const INNER_RADIUS := 2.59
const OUTER_RADIUS := 2.843
const CONTACT_RADIUS := INNER_RADIUS - Checker.RADIUS
const TELEPORT_EJECT_SPEED := 3.2
const SLOT_COUNT := 6
const SLOT_ANGLE := TAU / SLOT_COUNT
const ARC_HALF_ANGLE := PI * 27.0 / 180.0
const MAX_RAILS := 5
const MODEL := preload("res://assets/table/rails/painted_arcs.glb")
const MODEL_VARIANTS := ["", "Wood", "Spring", "Teleport"]
const BONUSES := [1.0, 1.10, 1.25, 1.50]
const COLORS := [Color.TRANSPARENT, Color("d29b54"), Color("ce6888"), Color("4b9e99")]

class Contact:
	var side: int
	var distance: float
	var normal: Vector3

	func _init(slot: int, travel: float, inward: Vector2) -> void:
		side = slot
		distance = travel
		normal = Vector3(inward.x, 0.0, inward.y)

class Cap:
	var side: int
	var radial: Vector2
	var inward: Vector2

	func _init(slot: int, angle: float, end_sign: float) -> void:
		side = slot
		radial = Vector2.from_angle(angle + ARC_HALF_ANGLE * end_sign)
		inward = Vector2(radial.y, -radial.x) * end_sign

@export var sides: Array[Kind] = [Kind.WOOD, Kind.OPEN, Kind.SPRING, Kind.OPEN, Kind.TELEPORT, Kind.OPEN]

var _active: Array[int] = []
var _caps: Array[Cap] = []


func _ready() -> void:
	var source := MODEL.instantiate()
	for side in SLOT_COUNT:
		var kind := sides[side] if side < sides.size() else Kind.OPEN
		if kind == Kind.OPEN or _active.size() == MAX_RAILS:
			continue
		var model := source.get_node(MODEL_VARIANTS[kind]) as MeshInstance3D
		var segment := MeshInstance3D.new()
		segment.name = "Rail%d" % (side + 1)
		segment.mesh = model.mesh
		segment.rotation.y = -slot_angle(side)
		add_child(segment)
		_active.append(side)
		for end_sign in [-1.0, 1.0]:
			_caps.append(Cap.new(side, slot_angle(side), end_sign))
	source.free()


static func slot_angle(side: int) -> float:
	return side * SLOT_ANGLE


static func radial_direction(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


static func ray_exit_distance(origin: Vector2, direction: Vector2, radius: float) -> float:
	var direction_squared := direction.length_squared()
	if direction_squared <= 0.000001:
		return INF
	var projection := origin.dot(direction)
	var discriminant := projection * projection + direction_squared * (radius * radius - origin.length_squared())
	if discriminant < 0.0:
		return INF
	return maxf((-projection + sqrt(discriminant)) / direction_squared, 0.0)


func kind_at(side: int) -> Kind:
	return sides[side] if side in _active else Kind.OPEN


func exits_from(side: int) -> Array[int]:
	var exits := _active.duplicate()
	exits.erase(side)
	return exits


func overlaps_disc(point: Vector3) -> bool:
	var position := Vector2(point.x, point.z)
	var radius := position.length()
	if radius < CONTACT_RADIUS or radius > OUTER_RADIUS + Checker.RADIUS:
		return false
	var angle := position.angle()
	var side := posmod(roundi(angle / SLOT_ANGLE), SLOT_COUNT)
	if side in _active and absf(angle_difference(slot_angle(side), angle)) <= ARC_HALF_ANGLE:
		return true
	for cap in _caps:
		var nearest := cap.radial * clampf(position.dot(cap.radial), INNER_RADIUS, OUTER_RADIUS)
		if position.distance_squared_to(nearest) < Checker.RADIUS * Checker.RADIUS:
			return true
	return false


func trace(from: Vector3, direction: Vector3, travel: float) -> Contact:
	var origin := Vector2(from.x, from.z)
	var origin_radius := origin.length()
	if travel <= 0.00001 or origin_radius + travel < CONTACT_RADIUS or _active.is_empty():
		return null
	var heading := Vector2(direction.x, direction.z).normalized()
	var closest := travel
	var contact: Contact
	var distance := ray_exit_distance(origin, heading, CONTACT_RADIUS)
	if distance <= closest and origin_radius <= INNER_RADIUS + 0.01:
		var normal := (origin + heading * distance).normalized()
		var angle := normal.angle()
		var side := posmod(roundi(angle / SLOT_ANGLE), SLOT_COUNT)
		if side in _active and absf(angle_difference(slot_angle(side), angle)) <= ARC_HALF_ANGLE \
				and heading.dot(normal) > 0.0001:
			contact = Contact.new(side, distance, normal)
			closest = distance
	for cap in _caps:
		var cap_contact := _trace_cap(cap, origin, heading, closest)
		if cap_contact != null:
			contact = cap_contact
			closest = cap_contact.distance
	return contact


func _trace_cap(cap: Cap, origin: Vector2, heading: Vector2, limit: float) -> Contact:
	# The disc can also clip the open end of a rail. Sweep against its flat cap
	# and the rounded clearance around both corners.
	if origin.dot(cap.inward) > 0.002:
		return null
	var contact: Contact
	var speed := heading.dot(cap.inward)
	if speed > 0.0001:
		var distance := maxf((-Checker.RADIUS - origin.dot(cap.inward)) / speed, 0.0)
		var radial_distance := (origin + heading * distance).dot(cap.radial)
		if distance <= limit and radial_distance >= INNER_RADIUS and radial_distance <= OUTER_RADIUS:
			limit = distance
			contact = Contact.new(cap.side, distance, cap.inward)
	for radius: float in [INNER_RADIUS, OUTER_RADIUS]:
		var corner := cap.radial * radius
		var offset := origin - corner
		var approach := offset.dot(heading)
		var discriminant := approach * approach + Checker.RADIUS * Checker.RADIUS - offset.length_squared()
		if approach >= 0.0 or discriminant < 0.0:
			continue
		var distance := maxf(-approach - sqrt(discriminant), 0.0)
		if distance > limit:
			continue
		var at := origin + heading * distance
		if at.dot(cap.inward) > 0.002:
			continue
		var normal := at.direction_to(corner)
		if heading.dot(normal) <= 0.0001:
			continue
		limit = distance
		contact = Contact.new(cap.side, distance, normal)
	return contact


func reflected_velocity(side: int, velocity: Vector3, normal: Vector3) -> Vector3:
	var kind := kind_at(side)
	if kind == Kind.TELEPORT:
		return -normal * maxf(velocity.dot(normal), TELEPORT_EJECT_SPEED)
	var reflected := velocity.bounce(normal)
	if kind == Kind.SPRING:
		return (reflected * 1.35).limit_length(maxf(velocity.length(), 12.0))
	return reflected * 0.86
