extends VehicleBody3D

## Car physics controller for AI parking training
## Handles movement, collision detection, and reset logic

@export var max_steer_angle := 0.6  # ~35 degrees
@export var max_engine_force := 150.0
@export var max_brake_force := 50.0

# State variables set by AIController
var steer_input := 0.0
var throttle_input := 0.0

# Collision tracking
var collision_count := 0
var is_colliding := false

# Spawn state for reset
var _spawn_position := Vector3.ZERO
var _spawn_rotation := Vector3.ZERO

# Reference to AI controller
@onready var ai_controller: Node3D = $AIController3D


func _ready():
	_spawn_position = global_position
	_spawn_rotation = rotation

	# Connect body_entered for collision detection
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Initialize AI controller with reference to this car
	if ai_controller:
		ai_controller.init(self)


func _physics_process(_delta):
	# Apply steering and engine force
	steering = steer_input * max_steer_angle
	engine_force = throttle_input * max_engine_force

	# Apply braking when throttle opposes velocity
	var forward_speed = -linear_velocity.dot(global_transform.basis.z)
	if throttle_input > 0.0 and forward_speed < -0.5:
		brake = max_brake_force * 0.5
	elif throttle_input < 0.0 and forward_speed > 0.5:
		brake = max_brake_force * 0.5
	else:
		brake = 0.0


func reset_car(pos: Vector3, rot: Vector3):
	"""Reset car to given position and rotation"""
	global_position = pos
	rotation = rot
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer_input = 0.0
	throttle_input = 0.0
	collision_count = 0
	is_colliding = false
	steering = 0.0
	engine_force = 0.0
	brake = 0.0


func reset_to_spawn():
	"""Reset car to its original spawn point"""
	reset_car(_spawn_position, _spawn_rotation)


func get_speed() -> float:
	"""Get forward speed (positive = forward, negative = reverse)"""
	return -linear_velocity.dot(global_transform.basis.z)


func get_velocity_local() -> Vector2:
	"""Get velocity in local space (x = lateral, y = forward)"""
	var local_vel = global_transform.basis.inverse() * linear_velocity
	return Vector2(local_vel.x, -local_vel.z)


func _on_body_entered(_body: Node):
	collision_count += 1
	is_colliding = true


func _on_body_exited(_body: Node):
	collision_count -= 1
	if collision_count <= 0:
		collision_count = 0
		is_colliding = false
