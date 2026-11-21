class_name Checker
extends RigidBody3D

const RADIUS := 0.155
const SLIDING_DECELERATION := 2.0

@export_enum("Light", "Dark") var side: int = 0
var falling := false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if falling:
		return
	state.linear_velocity = state.linear_velocity.move_toward(
		Vector3.ZERO, SLIDING_DECELERATION * state.step)


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
