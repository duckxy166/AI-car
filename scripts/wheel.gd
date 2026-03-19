extends RayCast3D

## Raycast-based wheel physics (inspired by Hotlap)
## Each wheel casts a ray downward to detect ground,
## then applies suspension, grip, and acceleration forces.

@onready var car: RigidBody3D = get_parent()

@export var is_front_wheel := false
@export var is_drive_wheel := true  # AWD by default

var previous_spring_length := 0.0


func _ready():
	add_exception(car)
	enabled = true
	# Point ray downward far enough to detect ground
	target_position = Vector3(0, -(car.suspension_rest_dist + car.wheel_radius + 0.3), 0)


func _physics_process(delta):
	if not is_colliding():
		return

	var collision_point = get_collision_point()
	_apply_suspension(delta, collision_point)
	_apply_acceleration(collision_point)
	_apply_lateral_grip(delta, collision_point)
	_apply_longitudinal_damping(collision_point)


func _apply_suspension(delta: float, collision_point: Vector3):
	var distance = global_position.distance_to(collision_point)
	var spring_length = clampf(distance - car.wheel_radius, 0, car.suspension_rest_dist)

	var spring_force = car.spring_strength * (car.suspension_rest_dist - spring_length)
	var spring_velocity = (previous_spring_length - spring_length) / delta
	var damper_force = car.spring_damper * spring_velocity

	var suspension_force = global_basis.y * (spring_force + damper_force)
	previous_spring_length = spring_length

	car.apply_force(suspension_force, collision_point - car.global_position)


func _apply_acceleration(collision_point: Vector3):
	if not is_drive_wheel:
		return

	# Speed limiting
	var speed_kmh = car.linear_velocity.length() * 3.6
	if speed_kmh > car.max_speed_kmh and car.throttle_input > 0:
		return

	var accel_dir = -global_basis.z  # Forward
	var force = car.throttle_input * car.engine_power

	var apply_point = collision_point + Vector3(0, car.wheel_radius, 0)
	car.apply_force(accel_dir * force, apply_point - car.global_position)


func _apply_lateral_grip(delta: float, collision_point: Vector3):
	var dir = global_basis.x
	var tire_vel = _get_point_velocity(global_position)
	var lateral_vel = dir.dot(tire_vel)

	var grip = car.get_current_rear_grip()
	if is_front_wheel:
		grip = car.front_tire_grip

	var desired_vel_change = -lateral_vel * grip
	var x_force = desired_vel_change * car.mass

	car.apply_force(dir * x_force, collision_point - car.global_position)


func _apply_longitudinal_damping(collision_point: Vector3):
	var dir = global_basis.z
	var tire_vel = _get_point_velocity(global_position)
	var z_force = dir.dot(tire_vel) * car.mass / 10.0

	car.apply_force(-dir * z_force, collision_point - car.global_position)


func _get_point_velocity(point: Vector3) -> Vector3:
	return car.linear_velocity + car.angular_velocity.cross(point - car.global_position)
