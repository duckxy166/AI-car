extends RigidBody3D

## ============================================================
## Arcade Racer — เร็ว ฮา ดริฟท์ได้ ไม่ลอย
## ============================================================

# --- Suspension ---
@export var suspension_rest_dist := 0.5
@export var spring_strength := 200.0
@export var spring_damper := 12.0

# --- Wheels ---
@export var wheel_radius := 0.3

# --- Engine ---
@export var engine_power := 25.0
@export var max_speed_kmh := 160.0

# --- Steering ---
@export var max_steer_angle := 40.0  # degrees

# --- Tire Grip ---
@export var front_tire_grip := 6.0
@export var rear_tire_grip := 2.5
@export var drift_grip := 0.8          # grip ตอนดริฟท์ (ยิ่งต่ำยิ่งลื่น)
@export var drift_angle_threshold := 15.0  # องศา เริ่มนับว่าดริฟท์

# --- Downforce ---
@export var downforce_coeff := 0.3     # กดลงดินแรงขึ้น ไม่ลอยแน่นอน

# State variables set by AIController
var steer_input := 0.0
var throttle_input := 0.0

# Drift state
var is_drifting := false
var drift_angle := 0.0
var _current_rear_grip := 2.5

# Collision tracking
var collision_count := 0
var is_colliding := false

# Spawn state for reset
var _spawn_position := Vector3.ZERO
var _spawn_rotation := Vector3.ZERO

var _name_label: Label3D

@onready var ai_controller: Node3D = $AIController3D


func _ready():
	_spawn_position = global_position
	_spawn_rotation = rotation

	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_current_rear_grip = rear_tire_grip

	# Create name label above car
	_name_label = Label3D.new()
	_name_label.position = Vector3(0, 3.0, 0)
	_name_label.font_size = 128
	_name_label.outline_size = 12
	_name_label.pixel_size = 0.008
	_name_label.modulate = Color(1, 1, 0.2)
	_name_label.outline_modulate = Color(0, 0, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.text = ""
	add_child(_name_label)

	if ai_controller:
		ai_controller.init(self)


func set_player_name(pname: String):
	if _name_label:
		_name_label.text = pname


func _physics_process(delta):
	var speed = absf(get_speed())

	# --- Steering (ลดที่ความเร็วสูง) ---
	var speed_factor = clampf(1.0 - speed / 30.0, 0.3, 1.0)
	var steer_rad = deg_to_rad(steer_input * max_steer_angle * speed_factor)
	$Wheel_FL.rotation.y = steer_rad
	$Wheel_FR.rotation.y = steer_rad

	# --- Drift Detection ---
	_update_drift(delta)

	# --- Downforce (ยิ่งเร็วยิ่งกด ไม่ลอย) ---
	var speed_sq = linear_velocity.length_squared()
	apply_central_force(-global_transform.basis.y * speed_sq * downforce_coeff)

	# --- Anti-flip: จำกัด angular velocity แกน X,Z กันรถพลิก ---
	var ang = angular_velocity
	ang.x = clampf(ang.x, -2.0, 2.0)
	ang.z = clampf(ang.z, -2.0, 2.0)
	angular_velocity = ang


func _update_drift(delta):
	var speed = linear_velocity.length()
	if speed < 2.0:
		is_drifting = false
		drift_angle = 0.0
		_current_rear_grip = lerpf(_current_rear_grip, rear_tire_grip, delta * 5.0)
		return

	# คำนวณมุมดริฟท์ = มุมระหว่าง velocity กับทิศหน้ารถ
	var forward = -global_transform.basis.z
	var vel_dir = linear_velocity.normalized()
	# ใช้เฉพาะ XZ plane
	forward.y = 0
	vel_dir.y = 0
	if forward.length() < 0.01 or vel_dir.length() < 0.01:
		return
	forward = forward.normalized()
	vel_dir = vel_dir.normalized()

	drift_angle = rad_to_deg(acos(clampf(forward.dot(vel_dir), -1.0, 1.0)))

	if drift_angle > drift_angle_threshold:
		# กำลังดริฟท์! ลด rear grip
		is_drifting = true
		var drift_factor = clampf(drift_angle / 90.0, 0.0, 1.0)
		var target_grip = lerpf(rear_tire_grip, drift_grip, drift_factor)
		_current_rear_grip = lerpf(_current_rear_grip, target_grip, delta * 8.0)
	else:
		is_drifting = false
		_current_rear_grip = lerpf(_current_rear_grip, rear_tire_grip, delta * 3.0)


func get_current_rear_grip() -> float:
	return _current_rear_grip


func reset_car(pos: Vector3, rot: Vector3):
	global_position = pos
	rotation = rot
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer_input = 0.0
	throttle_input = 0.0
	collision_count = 0
	is_colliding = false
	is_drifting = false
	drift_angle = 0.0
	_current_rear_grip = rear_tire_grip


func reset_to_spawn():
	reset_car(_spawn_position, _spawn_rotation)


func get_speed() -> float:
	return -linear_velocity.dot(global_transform.basis.z)


func get_speed_kmh() -> float:
	return get_speed() * 3.6


func get_velocity_local() -> Vector2:
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
