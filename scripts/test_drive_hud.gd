extends Node

## HUD for test_drive scene — name input, timer, parking result

var _parking_lot: Node3D
var _car: RigidBody3D
var _player_name := ""
var _best_time := 999.0
var _reset_count := 0
var _success_count := 0
var _result_visible_timer := 0.0


func _ready():
	_parking_lot = get_parent().get_node("ParkingLot")
	if _parking_lot:
		_car = _parking_lot.get_node("Car")
		_parking_lot.parking_success.connect(_on_parking_success)
		_parking_lot.timer_updated.connect(_on_timer_updated)

	# Check if AI mode (Sync control_mode != HUMAN)
	var sync = get_parent().get_node("Sync")
	var is_ai_mode = sync and sync.control_mode != 0  # 0 = HUMAN

	if is_ai_mode:
		# AI mode: skip name input, auto-start with "สมศักดิ์"
		$NameInputHUD.visible = false
		$TimerHUD.visible = true
		if _car:
			_car.set_player_name("สมศักดิ์")
	else:
		# Human mode: show name input
		_parking_lot._game_started = false
		$NameInputHUD.visible = true
		$TimerHUD.visible = false
		$NameInputHUD/Panel/NameEdit.text_submitted.connect(_on_name_submitted)
		$NameInputHUD/Panel/NameEdit.grab_focus()


func _on_name_submitted(name_text: String):
	_player_name = name_text.strip_edges()
	if _player_name.is_empty():
		_player_name = "Player"

	if _car:
		_car.set_player_name(_player_name)

	$NameInputHUD.visible = false
	$TimerHUD.visible = true
	_parking_lot._game_started = true
	_parking_lot._start_timer()


func _process(delta):
	if _result_visible_timer > 0:
		_result_visible_timer -= delta
	$TimerHUD/ResultLabel.visible = _result_visible_timer > 0


func _on_timer_updated(time: float, parked: bool, timer_running: bool, is_drifting: bool):
	var time_label = $TimerHUD/Panel/TimeLabel
	var status_label = $TimerHUD/Panel/StatusLabel

	var minutes = int(time) / 60
	var seconds = fmod(time, 60.0)
	time_label.text = "%d:%05.2f" % [minutes, seconds]

	if not timer_running and parked:
		status_label.text = "PARKED! (R = restart)"
		time_label.modulate = Color(0.2, 1.0, 0.3)
	else:
		time_label.modulate = Color(1, 1, 1, 1)
		if parked:
			status_label.text = "STOP THE CAR!"
		elif is_drifting:
			status_label.text = "DRIFT!"
		else:
			status_label.text = "PARK IT! (R = restart)"

	# Best time
	var best_label = $TimerHUD/Panel/BestLabel
	if _best_time < 999.0:
		best_label.text = "BEST: %d:%05.2f" % [int(_best_time) / 60, fmod(_best_time, 60.0)]
	else:
		best_label.text = ""

	# Stats
	$TimerHUD/Panel/StatsLabel.text = "Attempts: %d  |  Success: %d" % [_reset_count, _success_count]


func _on_parking_success(time: float, is_best: bool):
	_success_count += 1
	var time_str = "%d:%05.2f" % [int(time) / 60, fmod(time, 60.0)]
	var result_label = $TimerHUD/ResultLabel

	if is_best:
		_best_time = time
		result_label.text = "NEW BEST!\n%s" % time_str
		result_label.modulate = Color(0.2, 1.0, 0.3)
	else:
		result_label.text = "PARKED!\n%s" % time_str
		result_label.modulate = Color(1.0, 1.0, 0.2)
	_result_visible_timer = 4.0
