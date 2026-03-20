extends AIController3D

## AI Controller for parking training
## Spawn ตำแหน่งเดิม (ไกล ~39m) ผ่าน L-shaped road
## Reward: distance shaping + alignment + parking success

# References
var car: RigidBody3D
var raycast_sensor: Node3D
var parking_spot: Area3D

# Parking target info (set by parking_lot.gd)
var target_position := Vector3.ZERO
var target_rotation := 0.0

# Reward shaping
var _previous_distance := 999.0
var _previous_angle_diff := PI
var _episode_steps := 0
var _is_in_spot := false
var _parked_frames := 0
var _parking_time := 0.0

const MAX_SPEED := 15.0
const MAX_DISTANCE := 40.0
const MAX_ANGULAR_VEL := 5.0

# Waypoints ตาม L-shape road (LOCAL offset จาก Env origin)
var _waypoints_local := [
	Vector3(-10, 0, -5),   # ตรงขึ้นไป
	Vector3(-10, 0, 3),    # ก่อนโค้ง
	Vector3(-3, 0, 7),     # กลางโค้ง
	Vector3(5, 0, 10),     # หลังโค้ง
	Vector3(15, 0, 10),    # เข้าใกล้ parking
	Vector3(20, 0, 10),    # หน้าซอง — ตรง ParkingTarget
]
var _waypoints_world: Array[Vector3] = []  # คำนวณตอน runtime จาก env offset
var _env_offset := Vector3.ZERO  # offset ของ Env (ParkingLot parent)
var _current_waypoint := 0
const WAYPOINT_RADIUS := 4.0  # ระยะที่นับว่าถึง waypoint


func _ready():
	super._ready()
	reset_after = 800  # เร็วขึ้น — ไม่จอดใน 800 steps ก็ reset


func init(player: Node3D):
	super.init(player)
	car = player as RigidBody3D

	for child in get_children():
		if child is RayCastSensor3D:
			raycast_sensor = child
			break


func _safe_float(val) -> float:
	## แปลงค่าใดๆ เป็น float ที่ปลอดภัย (ไม่มี NaN, INF, null)
	if val == null:
		return 0.0
	var f := float(val)
	if is_nan(f) or is_inf(f):
		return 0.0
	return clampf(f, -1.0, 1.0)


func get_obs() -> Dictionary:
	var obs: Array[float] = []
	obs.resize(21)
	obs.fill(0.0)

	if not is_instance_valid(car):
		return {"obs": obs}

	# 1. Normalized speed [-1, 1]
	var speed_val = car.get_speed() if car.has_method("get_speed") else 0.0
	obs[0] = _safe_float(speed_val / MAX_SPEED)

	# 2. Angle to target [-1, 1]
	var to_target = target_position - car.global_position
	to_target.y = 0
	var angle_to_target = 0.0
	if to_target.length() > 0.1:
		var forward = -car.global_transform.basis.z
		forward.y = 0
		if forward.length() > 0.01:
			angle_to_target = forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	obs[1] = _safe_float(angle_to_target / PI)

	# 3. Distance to target [0, 1]
	obs[2] = clampf(to_target.length() / MAX_DISTANCE, 0.0, 1.0)

	# 4. Heading alignment [-1, 1]
	var car_angle = car.rotation.y
	var heading_diff = angle_difference(car_angle, target_rotation)
	obs[3] = _safe_float(heading_diff / PI)

	# 5-16. Raycast sensor data (12 values)
	if raycast_sensor and raycast_sensor.has_method("get_observation"):
		var ray_obs = raycast_sensor.get_observation()
		if ray_obs != null:
			for i in mini(ray_obs.size(), 12):
				obs[4 + i] = _safe_float(ray_obs[i])

	# 17. Local velocity X (lateral)
	var local_vel = car.get_velocity_local() if car.has_method("get_velocity_local") else Vector2.ZERO
	if local_vel != null:
		obs[16] = _safe_float(local_vel.x / MAX_SPEED)
		# 18. Local velocity Z (forward)
		obs[17] = _safe_float(local_vel.y / MAX_SPEED)

	# 19. Is in parking spot
	obs[18] = 1.0 if _is_in_spot else 0.0

	# 20-21. Direction & distance to next waypoint
	var next_wp = _get_next_waypoint_pos()
	var to_wp = next_wp - car.global_position
	to_wp.y = 0
	var angle_to_wp = 0.0
	if to_wp.length() > 0.1:
		var fwd = -car.global_transform.basis.z
		fwd.y = 0
		if fwd.length() > 0.01:
			angle_to_wp = fwd.signed_angle_to(to_wp.normalized(), Vector3.UP)
	obs[19] = _safe_float(angle_to_wp / PI)
	obs[20] = clampf(to_wp.length() / MAX_DISTANCE, 0.0, 1.0)

	return {"obs": obs}


func get_reward() -> float:
	var total_reward := reward

	if not car:
		return 0.0

	var to_target = target_position - car.global_position
	to_target.y = 0
	var current_distance = to_target.length()
	var speed = abs(car.get_speed())
	var car_angle = fmod(car.rotation.y, TAU)
	var angle_diff = abs(angle_difference(car_angle, target_rotation))

	# ============================================================
	# 0. WAYPOINT REWARD — ให้ reward ทีละจุดตาม L-shape
	# ============================================================
	_check_waypoints()

	# ============================================================
	# 1. DISTANCE TO NEXT WAYPOINT — เข้าใกล้ waypoint/target ถัดไป
	# ============================================================
	var next_goal = _get_next_waypoint_pos()
	var to_next = next_goal - car.global_position
	to_next.y = 0
	var dist_to_next = to_next.length()
	var distance_delta = _previous_distance - dist_to_next
	total_reward += distance_delta * 0.8
	_previous_distance = dist_to_next

	# Proximity bonus เมื่อใกล้ parking spot
	if current_distance < 10.0:
		total_reward += (10.0 - current_distance) * 0.01

	# ============================================================
	# 2. ALIGNMENT REWARD — หันหน้าเข้าซอง (เริ่มให้ตั้งแต่ 15m)
	# ============================================================
	if current_distance < 15.0:
		var alignment_delta = _previous_angle_diff - angle_diff
		total_reward += alignment_delta * 1.5  # แรงขึ้น 3 เท่า
		_previous_angle_diff = angle_diff

		# Bonus ถ้าหันถูกทาง
		if angle_diff < 0.5:  # ~28 degrees
			total_reward += 0.05
		if angle_diff < 0.2:  # ~11 degrees
			total_reward += 0.15

		# PENALTY ถ้าจอดขวาง (มากกว่า 60°)
		if angle_diff > 1.0:
			total_reward -= 0.1

	# ============================================================
	# 3. SPEED CONTROL — ยิ่งใกล้ ยิ่งต้องช้า
	# ============================================================
	if current_distance < 8.0:
		# เร็วเกินตอนใกล้ = โดน penalty ตาม speed
		if speed > 3.0:
			total_reward -= speed * 0.02
		# ช้าลงตอนใกล้ = ดี
		if speed < 2.0:
			total_reward += 0.02

	# ============================================================
	# 4. COLLISION PENALTY — ชนไม่ตาย แค่เจ็บ
	# ============================================================
	if car.is_colliding:
		total_reward -= 0.3
		if speed > 5.0:
			total_reward -= 0.5

	# ============================================================
	# 5. PARKING SUCCESS — หยุดใน spot = ชนะ
	# ============================================================
	if _is_in_spot:
		# อยู่ใน spot + หันถูกทาง = ดีมาก
		if angle_diff < 0.5:  # < 28°
			total_reward += 0.5
		elif angle_diff < 0.8:  # < 45°
			total_reward += 0.2
		else:
			total_reward -= 0.3  # จอดขวาง = penalty หนัก

		# BRAKE REWARD — ยิ่งช้า + หันถูก ยิ่งได้เยอะ
		if speed < 3.0 and angle_diff < 0.5:
			total_reward += 0.5
		if speed < 1.0 and angle_diff < 0.3:
			total_reward += 1.5
		if speed < 0.3 and angle_diff < 0.2:
			total_reward += 2.0

		# Alignment bonus ใน spot — ยิ่งตรง ยิ่งได้
		var align_quality = maxf(0.0, 1.0 - angle_diff / 0.5)
		total_reward += align_quality * 0.8

		# นับ frame ที่หยุดอยู่ใน spot + หันตรง
		if speed < 1.0 and angle_diff < 0.35:  # ~20° — ต้องตรง
			_parked_frames += 1
			total_reward += 1.0

			if _parked_frames >= 5:
				# SUCCESS! จบ episode
				var align_bonus = maxf(0.0, 15.0 * (1.0 - angle_diff / 0.35))
				total_reward += 25.0 + align_bonus
				var time_bonus = maxf(0.0, 15.0 - _parking_time * 0.3)
				total_reward += time_bonus
				done = true
		else:
			_parked_frames = max(0, _parked_frames - 2)  # ลดเร็วขึ้น
	else:
		_parked_frames = 0

	# ============================================================
	# 6. TIME PENALTY — อย่ายืดเวลา (เพิ่มขึ้นตามเวลา)
	# ============================================================
	total_reward -= 0.008

	# ============================================================
	# 7. OUT OF BOUNDS — ตกแมพจบ
	# ============================================================
	if car.global_position.y < -2.0 or car.global_position.y > 5.0:
		total_reward -= 5.0
		done = true

	# ไม่เคลื่อนที่นาน = จบ (กัน idle) — เร็วขึ้น
	if _episode_steps > 100 and speed < 0.1 and current_distance > 5.0:
		total_reward -= 2.0
		done = true

	_episode_steps += 1
	return total_reward


func get_action_space() -> Dictionary:
	return {
		"steer": {"size": 1, "action_type": "continuous"},
		"throttle": {"size": 1, "action_type": "continuous"},
	}


func set_action(action) -> void:
	if not car:
		return

	if heuristic == "model":
		car.steer_input = clampf(action["steer"][0], -1.0, 1.0)
		car.throttle_input = clampf(action["throttle"][0], -1.0, 1.0)


func get_action() -> Array:
	return [car.steer_input, car.throttle_input]


func reset():
	super.reset()
	_previous_distance = 999.0
	_previous_angle_diff = PI
	_episode_steps = 0
	_is_in_spot = false
	_parked_frames = 0
	_parking_time = 0.0
	_current_waypoint = 0
	# Note: parking_lot.gd handles car.reset_car() with proper spawn positions


func set_parking_target(pos: Vector3, rot_y: float):
	target_position = pos
	target_rotation = rot_y
	# คำนวณ env offset จาก parking lot parent
	var parking_lot = car.get_parent() if car else null
	if parking_lot:
		_env_offset = parking_lot.global_position
	else:
		_env_offset = Vector3.ZERO
	# สร้าง waypoints world จาก local + offset
	_build_world_waypoints()
	_previous_distance = (_get_next_waypoint_pos() - car.global_position).length() if car else 999.0


func _build_world_waypoints():
	## แปลง waypoints local → world โดยเพิ่ม env offset
	_waypoints_world.clear()
	for wp in _waypoints_local:
		_waypoints_world.append(wp + _env_offset)


func _get_next_waypoint_pos() -> Vector3:
	## ถ้าผ่าน waypoint ทั้งหมดแล้ว → เป้าหมายคือ parking spot
	if _current_waypoint >= _waypoints_world.size():
		return target_position
	return _waypoints_world[_current_waypoint]


func _check_waypoints():
	## ตรวจว่ารถถึง waypoint หรือยัง → ให้ reward + ไปจุดถัดไป
	if _current_waypoint >= _waypoints_world.size():
		return
	var wp = _waypoints_world[_current_waypoint]
	var dist = (car.global_position - wp).length()
	if dist < WAYPOINT_RADIUS:
		reward += 3.0  # Bonus ถึง waypoint!
		_current_waypoint += 1
		# Reset distance tracking ไปยังจุดถัดไป
		_previous_distance = (_get_next_waypoint_pos() - car.global_position).length()


func set_in_parking_spot(value: bool):
	_is_in_spot = value


func set_parking_time(time: float):
	_parking_time = time


## Human control for testing
func _physics_process(delta):
	super._physics_process(delta)

	if heuristic == "human":
		var target_steer = 0.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			target_steer -= 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			target_steer += 1.0

		var target_throttle = 0.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			target_throttle += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			target_throttle -= 1.0

		if car:
			car.steer_input = lerp(car.steer_input, target_steer, delta * 12.0)
			car.throttle_input = lerp(car.throttle_input, target_throttle, delta * 20.0)
