class_name Checker
extends RigidBody3D

const HIT_FX := preload("res://assets/FX/hitFX_base/hirFX_base.tscn")
const RADIUS := 0.155
const SLIDING_DECELERATION := 2.0

@export_enum("Light", "Dark") var side: int = 0
var falling := false
var touching: Dictionary[int, bool] = {}


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if falling:
		return
	_update_hit_contacts(state)
	state.linear_velocity = state.linear_velocity.move_toward(
		Vector3.ZERO, SLIDING_DECELERATION * state.step)


func _update_hit_contacts(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() == 0:
		touching.clear()
		return
	var current: Dictionary[int, bool] = {}
	for index in state.get_contact_count():
		var other := state.get_contact_collider_object(index) as Checker
		# Only one of the two bodies handles their shared contact.
		if other == null or other.falling or get_instance_id() >= other.get_instance_id():
			continue
		var id := other.get_instance_id()
		if not touching.has(id) and not current.has(id):
			_play_hit_fx.call_deferred(state.get_contact_collider_position(index))
		current[id] = true
	touching = current


func _play_hit_fx(world_point: Vector3) -> void:
	var parent := get_parent_node_3d()
	if parent == null or is_queued_for_deletion():
		return
	var fx := HIT_FX.instantiate() as Node3D
	fx.position = parent.to_local(world_point)
	fx.scale = Vector3.ONE * RADIUS
	parent.add_child(fx)
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


func leave_board() -> void:
	falling = true
	collision_layer = 0
	collision_mask = 0
	axis_lock_linear_y = false
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	gravity_scale = 1.0
	linear_damp = 0.10
	var outward := Vector3(position.x, 0.0, position.z).normalized()
	angular_velocity += Vector3.UP.cross(outward) * 3.8
	sleeping = false
