extends Node3D

# The imported tabletop measures 2.871–2.874 m from its center to the rim.
const TABLE_RADIUS := 2.872
const INNER_RADIUS := 2.59
const OUTER_RADIUS := 2.843
const CONTACT_RADIUS := INNER_RADIUS - Checker.RADIUS
const BOOST_MULTIPLIER := 1.25
const SLOT_COUNT := 6
const SLOT_ANGLE := TAU / SLOT_COUNT
const ARC_HALF_ANGLE := PI * 27.0 / 180.0
const MODEL := preload("res://assets/table/rails/painted_arcs.glb")

class Contact:
	var distance: float
	var normal: Vector3

	func _init(travel: float, into_rail: Vector2) -> void:
		distance = travel
		normal = Vector3(into_rail.x, 0.0, into_rail.y)

class Cap:
	var radial: Vector2
	var inward: Vector2

	func _init(angle: float, end_sign: float) -> void:
		radial = Vector2.from_angle(angle + ARC_HALF_ANGLE * end_sign)
		inward = Vector2(radial.y, -radial.x) * end_sign

@export var rail_slots: Array[int] = [0, 2, 4]

var _caps: Array[Cap] = []


func _ready() -> void:
	var source := MODEL.instantiate()
	var model := source.get_node("Wood") as MeshInstance3D
	for slot in SLOT_COUNT:
		if slot not in rail_slots:
			continue
		var segment := MeshInstance3D.new()
		segment.name = "Rail%d" % (slot + 1)
		segment.mesh = model.mesh
		segment.rotation.y = -slot_angle(slot)
		add_child(segment)
		for end_sign in [-1.0, 1.0]:
			_caps.append(Cap.new(slot_angle(slot), end_sign))
	source.free()


static func slot_angle(side: int) -> float:
	return side * SLOT_ANGLE


static func ray_exit_distance(origin: Vector2, direction: Vector2, radius: float) -> float:
	var direction_squared := direction.length_squared()
	if direction_squared <= 0.000001:
		return INF
	var projection := origin.dot(direction)
	var discriminant := projection * projection + direction_squared * (radius * radius - origin.length_squared())
	if discriminant < 0.0:
		return INF
	return maxf((-projection + sqrt(discriminant)) / direction_squared, 0.0)


func overlaps_disc(point: Vector3, disc_radius := Checker.RADIUS) -> bool:
	var position := Vector2(point.x, point.z)
	var radius := position.length()
	if radius < INNER_RADIUS - disc_radius or radius > OUTER_RADIUS + disc_radius:
		return false
	var angle := position.angle()
	var side := posmod(roundi(angle / SLOT_ANGLE), SLOT_COUNT)
	if side in rail_slots and absf(angle_difference(slot_angle(side), angle)) <= ARC_HALF_ANGLE:
		return true
	for cap in _caps:
		var nearest := cap.radial * clampf(position.dot(cap.radial), INNER_RADIUS, OUTER_RADIUS)
		if position.distance_squared_to(nearest) < disc_radius * disc_radius:
			return true
	return false


func trace(from: Vector3, direction: Vector3, travel: float, disc_radius := Checker.RADIUS) -> Contact:
	var origin := Vector2(from.x, from.z)
	var origin_radius := origin.length()
	var contact_radius := INNER_RADIUS - disc_radius
	if travel <= 0.00001 or origin_radius + travel < contact_radius or rail_slots.is_empty():
		return null
	var heading := Vector2(direction.x, direction.z).normalized()
	var closest := travel
	var contact: Contact
	var distance := ray_exit_distance(origin, heading, contact_radius)
	if distance <= closest and origin_radius <= INNER_RADIUS + 0.01:
		var normal := (origin + heading * distance).normalized()
		var angle := normal.angle()
		var side := posmod(roundi(angle / SLOT_ANGLE), SLOT_COUNT)
		if side in rail_slots and absf(angle_difference(slot_angle(side), angle)) <= ARC_HALF_ANGLE \
				and heading.dot(normal) > 0.0001:
			contact = Contact.new(distance, normal)
			closest = distance
	for cap in _caps:
		var cap_contact := _trace_cap(cap, origin, heading, closest, disc_radius)
		if cap_contact != null:
			contact = cap_contact
			closest = cap_contact.distance
	return contact


func _trace_cap(cap: Cap, origin: Vector2, heading: Vector2, limit: float, disc_radius: float) -> Contact:
	# The disc can also clip the open end of a rail. Sweep against its flat cap
	# and the rounded clearance around both corners.
	if origin.dot(cap.inward) > 0.002:
		return null
	var contact: Contact
	var speed := heading.dot(cap.inward)
	if speed > 0.0001:
		var distance := maxf((-disc_radius - origin.dot(cap.inward)) / speed, 0.0)
		var radial_distance := (origin + heading * distance).dot(cap.radial)
		if distance <= limit and radial_distance >= INNER_RADIUS and radial_distance <= OUTER_RADIUS:
			limit = distance
			contact = Contact.new(distance, cap.inward)
	for radius: float in [INNER_RADIUS, OUTER_RADIUS]:
		var corner := cap.radial * radius
		var offset := origin - corner
		var approach := offset.dot(heading)
		var discriminant := approach * approach + disc_radius * disc_radius - offset.length_squared()
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
		contact = Contact.new(distance, normal)
	return contact


static func reflected_velocity(velocity: Vector3, normal: Vector3, boost: bool) -> Vector3:
	return velocity.bounce(normal) * (BOOST_MULTIPLIER if boost else 1.0)
