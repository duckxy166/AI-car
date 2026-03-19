extends Node3D

## Parking lot — L-shaped road with timer and drift

@export var randomize_spawn := false

var car: RigidBody3D
var ai_controller: Node3D
var parking_target: Area3D
var _is_training := false

# Timer
var _timer := 0.0
var _timer_running := false
var _parked := false
var _best_time := 999.0
var _game_started := false
var _player_name := ""

# Stats
var _reset_count := 0
var _success_count := 0
var _result_visible_timer := 0.0
var _r_held := false

# Spawn configuration (vertical road section)
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


func _ready():
	car = $Car
	if car:
		ai_controller = car.get_node("AIController3D")

	parking_target = $ParkingTarget

	if parking_target:
		parking_target.body_entered.connect(_on_parking_entered)
		parking_target.body_exited.connect(_on_parking_exited)

	_setup_target()

	# Detect training mode
	_is_training = ai_controller and ai_controller.heuristic != "human"

	if _is_training:
		_player_name = "AI"
		if car:
			car.set_player_name(_player_name)
		# Free UI and camera to reduce load
		$NameInputHUD.queue_free()
		$TimerHUD.queue_free()
		$Camera3D.queue_free()
		$DirectionalLight3D.queue_free()
		_game_started = true
		_start_timer()
	else:
		$NameInputHUD/Panel/NameEdit.text_submitted.connect(_on_name_submitted)
		_show_name_input()


func _show_name_input():
	_game_started = false
	$NameInputHUD.visible = true
	$NameInputHUD/Panel/NameEdit.grab_focus()


func _on_name_submitted(name_text: String):
	_player_name = name_text.strip_edges()
	if _player_name.is_empty():
		_player_name = "Player"

	if ai_controller and ai_controller.heuristic == "model":
		_player_name = "สมศักดิ์"

	if car:
		car.set_player_name(_player_name)

	$NameInputHUD.visible = false
	_game_started = true
	_start_timer()


func _process(delta):
	if not _game_started:
		return
	if _timer_running:
		_timer += delta
	if _is_training:
		return
	if _result_visible_timer > 0:
		_result_visible_timer -= delta
	_update_hud()


func _physics_process(_delta):
	if not _game_started:
		return

	if ai_controller and ai_controller.needs_reset:
		_reset_environment()

	# Check parked: in spot + nearly stopped
	if _timer_running and _parked and car:
		var vel = car.linear_velocity.length()
		if vel < 1.5:
			_timer_running = false
			if ai_controller:
				ai_controller.set_parking_time(_timer)
			if _timer < _best_time:
				_best_time = _timer
			if not _is_training:
				_show_result()

	# Reset with R key (human mode only)
	if not _is_training:
		if Input.is_key_pressed(KEY_R) and not _r_held:
			_r_held = true
			_reset_count += 1
			_reset_environment()
			_start_timer()
		elif not Input.is_key_pressed(KEY_R):
			_r_held = false


func _show_result():
	_success_count += 1
	var minutes = int(_timer) / 60
	var seconds = fmod(_timer, 60.0)
	var time_str = "%d:%05.2f" % [minutes, seconds]
	var is_best = _timer <= _best_time
	var result_label = $TimerHUD/ResultLabel
	if is_best:
		result_label.text = "NEW BEST!\n%s" % time_str
		result_label.modulate = Color(0.2, 1.0, 0.3)
	else:
		result_label.text = "PARKED!\n%s" % time_str
		result_label.modulate = Color(1.0, 1.0, 0.2)
	_result_visible_timer = 4.0


func _start_timer():
	_timer = 0.0
	_timer_running = true
	_parked = false
	_result_visible_timer = 0.0


func _update_hud():
	var time_label = $TimerHUD/Panel/TimeLabel
	var status_label = $TimerHUD/Panel/StatusLabel

	var minutes = int(_timer) / 60
	var seconds = fmod(_timer, 60.0)
	time_label.text = "%d:%05.2f" % [minutes, seconds]

	if not _timer_running and _parked:
		status_label.text = "PARKED! (R = restart)"
		if _timer <= _best_time:
			time_label.modulate = Color(0.2, 1.0, 0.3)
		else:
			time_label.modulate = Color(1.0, 1.0, 0.2)
	else:
		time_label.modulate = Color(1.0, 1.0, 1.0)
		if _parked:
			status_label.text = "STOP THE CAR!"
		elif car and car.is_drifting:
			status_label.text = "DRIFT!"
		else:
			status_label.text = "PARK IT! (R = restart)"

	var best_label = $TimerHUD/Panel/BestLabel
	if _best_time < 999.0:
		best_label.text = "BEST: %d:%05.2f" % [int(_best_time) / 60, fmod(_best_time, 60.0)]
	else:
		best_label.text = ""

	var stats_label = $TimerHUD/Panel/StatsLabel
	stats_label.text = "Attempts: %d  |  Success: %d" % [_reset_count, _success_count]

	var result_label = $TimerHUD/ResultLabel
	if _result_visible_timer > 0:
		result_label.visible = true
	else:
		result_label.visible = false


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

	var spawn_pos = _spawn_positions[idx]
	var spawn_rot = _spawn_rotations[idx]

	car.reset_car(spawn_pos, spawn_rot)
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
