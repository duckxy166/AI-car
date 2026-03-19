extends Node3D

## Parking lot — L-shaped road with parking detection and AI training support
## UI is handled by test_drive_hud.gd (only in test_drive.tscn)

@export var randomize_spawn := false

var car: RigidBody3D
var ai_controller: Node3D
var parking_target: Area3D

# Timer (internal, used for AI reward)
var _timer := 0.0
var _timer_running := false
var _parked := false
var _best_time := 999.0
var _game_started := false

# Spawn configuration
var _spawn_positions := [
	Vector3(-10, 0.55, -15),
	Vector3(-10, 0.55, -10),
	Vector3(-10, 0.55, -5),
]
var _spawn_rotations := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.1, 0.0),
	Vector3(0.0, -0.1, 0.0),
]

# Signals for external HUD
signal parking_success(time: float, is_best: bool)
signal timer_updated(time: float, parked: bool, timer_running: bool, is_drifting: bool)
signal game_started


func _ready():
	car = $Car
	if car:
		ai_controller = car.get_node("AIController3D")

	parking_target = $ParkingTarget
	if parking_target:
		parking_target.body_entered.connect(_on_parking_entered)
		parking_target.body_exited.connect(_on_parking_exited)

	_setup_target()

	# AI ใช้ชื่อ สมศักดิ์
	if car and ai_controller:
		car.set_player_name("สมศักดิ์")

	_game_started = true
	_start_timer()
	game_started.emit()


func _process(delta):
	if not _game_started:
		return
	if _timer_running:
		_timer += delta
	timer_updated.emit(_timer, _parked, _timer_running, car.is_drifting if car else false)


func _physics_process(_delta):
	if not _game_started:
		return

	if ai_controller and ai_controller.needs_reset:
		_reset_environment()

	# Check parked: in spot + nearly stopped
	if _timer_running and _parked and car:
		if car.linear_velocity.length() < 1.5:
			_timer_running = false
			if ai_controller:
				ai_controller.set_parking_time(_timer)
			var is_best = _timer < _best_time
			if is_best:
				_best_time = _timer
			parking_success.emit(_timer, is_best)

	# Reset with R key
	if Input.is_key_pressed(KEY_R):
		_reset_environment()
		_start_timer()


func _start_timer():
	_timer = 0.0
	_timer_running = true
	_parked = false


func _setup_target():
	if ai_controller and parking_target:
		ai_controller.set_parking_target(
			parking_target.global_position,
			parking_target.rotation.y
		)


func _reset_environment():
	if not car:
		return

	var idx = 0
	if randomize_spawn:
		idx = randi() % _spawn_positions.size()

	car.reset_car(_spawn_positions[idx], _spawn_rotations[idx])
	_setup_target()
	_start_timer()

	if ai_controller:
		ai_controller.reset()


func _on_parking_entered(body: Node3D):
	if body == car:
		_parked = true
		if ai_controller:
			ai_controller.set_in_parking_spot(true)


func _on_parking_exited(body: Node3D):
	if body == car:
		_parked = false
		if ai_controller:
			ai_controller.set_in_parking_spot(false)
