extends Node3D

## Parking lot environment manager
## Handles reset, target assignment, and parking spot detection

@export var randomize_spawn := true
@export var lot_size := Vector2(25.0, 25.0)

var car: VehicleBody3D
var ai_controller: Node3D
var parking_target: Area3D

# Spawn configuration
var _spawn_positions := [
	Vector3(0.0, 0.5, -8.0),
	Vector3(-3.0, 0.5, -10.0),
	Vector3(3.0, 0.5, -9.0),
	Vector3(-1.0, 0.5, -12.0),
]
var _spawn_rotations := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.2, 0.0),
	Vector3(0.0, -0.2, 0.0),
	Vector3(0.0, 0.1, 0.0),
]


func _ready():
	# Find the car in this environment
	car = $Car
	if car:
		ai_controller = car.get_node("AIController3D")

	# Find parking target
	parking_target = $ParkingTarget

	# Connect parking spot detection
	if parking_target:
		parking_target.body_entered.connect(_on_parking_entered)
		parking_target.body_exited.connect(_on_parking_exited)

	# Set initial target for AI
	_setup_target()

	# Connect AI reset signal
	if ai_controller:
		ai_controller.needs_reset_changed = _on_needs_reset


func _physics_process(_delta):
	if ai_controller and ai_controller.needs_reset:
		_reset_environment()


func _setup_target():
	if ai_controller and parking_target:
		ai_controller.set_parking_target(
			parking_target.global_position,
			parking_target.rotation.y
		)


func _reset_environment():
	if not car or not ai_controller:
		return

	# Pick random or fixed spawn
	var idx = 0
	if randomize_spawn:
		idx = randi() % _spawn_positions.size()

	var spawn_pos = global_position + _spawn_positions[idx]
	var spawn_rot = _spawn_rotations[idx]

	# Add small random offset for variety
	if randomize_spawn:
		spawn_pos.x += randf_range(-1.5, 1.5)
		spawn_pos.z += randf_range(-1.5, 1.5)
		spawn_rot.y += randf_range(-0.3, 0.3)

	car.reset_car(spawn_pos, spawn_rot)

	# Update target info
	_setup_target()

	# Reset the controller
	ai_controller.reset()


func _on_parking_entered(body: Node3D):
	if body == car and ai_controller:
		ai_controller.set_in_parking_spot(true)


func _on_parking_exited(body: Node3D):
	if body == car and ai_controller:
		ai_controller.set_in_parking_spot(false)


func _on_needs_reset():
	_reset_environment()
