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
]
var _waypoints_world: Array[Vector3] = []  # คำนวณตอน runtime จาก env offset
var _env_offset := Vector3.ZERO  # offset ของ Env (ParkingLot parent)
var _current_waypoint := 0
const WAYPOINT_RADIUS := 4.0  # ระยะที่นับว่าถึง waypoint


func _ready():
	super._ready()
	reset_after = 2000  # Long episodes for 39m L-shaped navigation


func init(player: Node3D):
	super.init(player)
	car = player as RigidBody3D

	for child in get_children():
		if child is RayCastSensor3D:
			raycast_sensor = child
			break


func get_obs() -> Dictionary:
	var obs := []

	if not car:
		obs.resize(21)
		obs.fill(0.0)
		return {"obs": obs}

	# 1. Normalized speed [-1, 1]
	var speed = car.get_speed() / MAX_SPEED
	obs.append(clampf(speed, -1.0, 1.0))

	# 2. Angle to target [-1, 1]
	var to_target = target_position - car.global_position
	to_target.y = 0
	var angle_to_target = 0.0
	if to_target.length() > 0.1:
		var forward = -car.global_transform.basis.z
		forward.y = 0
		angle_to_target = forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	obs.append(clampf(angle_to_target / PI, -1.0, 1.0))

	# 3. Distance to target [0, 1]
	var distance = to_target.length() / MAX_DISTANCE
	obs.append(clampf(distance, 0.0, 1.0))

	# 4. Heading alignment [-1, 1] (how well car faces parking direction)
	var car_angle = car.rotation.y
	var heading_diff = angle_difference(car_angle, target_rotation)
	obs.append(clampf(heading_diff / PI, -1.0, 1.0))

	# 5-16. Raycast sensor data (12 values)
	if raycast_sensor:
		var ray_obs = raycast_sensor.get_observation()
		for val in ray_obs:
			obs.append(val)
	else:
		for i in 12:
			obs.append(0.0)

	# 17. Local velocity X (lateral)
	var local_vel = car.get_velocity_local()
	obs.append(clampf(local_vel.x / MAX_SPEED, -1.0, 1.0))

	# 18. Local velocity Z (forward)
	obs.append(clampf(local_vel.y / MAX_SPEED, -1.0, 1.0))

	# 19. Is in parking spot
	obs.append(1.0 if _is_in_spot else 0.0)

	# 20-21. Direction & distance to next waypoint
	var next_wp = _get_next_waypoint_pos()
	var to_wp = next_wp - car.global_position
	to_wp.y = 0
	var angle_to_wp = 0.0
	if to_wp.length() > 0.1:
		var fwd = -car.global_transform.basis.z
		fwd.y = 0
		angle_to_wp = fwd.signed_angle_to(to_wp.normalized(), Vector3.UP)
	obs.append(clampf(angle_to_wp / PI, -1.0, 1.0))
	obs.append(clampf(to_wp.length() / MAX_DISTANCE, 0.0, 1.0))

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
	# 2. ALIGNMENT REWARD — หันหน้าเข้าซอง (เริ่มให้ตั้งแต่ 10m)
	# ============================================================
	if current_distance < 10.0:
		var alignment_delta = _previous_angle_diff - angle_diff
		total_reward += alignment_delta * 0.5
		_previous_angle_diff = angle_diff

		# Bonus ถ้าหันถูกทาง
		if angle_diff < 0.5:  # ~28 degrees
			total_reward += 0.02
		if angle_diff < 0.2:  # ~11 degrees
			total_reward += 0.05

	# ============================================================
	# 3. SPEED CONTROL — ใกล้ spot ควรช้าลง
	# ============================================================
	if current_distance < 5.0 and speed > 5.0:
		total_reward -= 0.1  # เร็วเกินตอนใกล้

	# ============================================================
	# 4. COLLISION PENALTY — ชนไม่ตาย แค่เจ็บ
	# ============================================================
	if car.is_colliding:
		total_reward -= 0.3  # ลดจาก 0.5
		# ชนแรงก็แค่เจ็บกว่า ไม่จบ episode
		if speed > 5.0:
			total_reward -= 0.5

	# ============================================================
	# 5. PARKING SUCCESS — จอดได้ = ฟินมาก
	# ============================================================
	if _is_in_spot:
		# อยู่ใน spot = ดีแล้ว
		total_reward += 0.1

		if speed < 1.5 and angle_diff < 0.5:
			_parked_frames += 1
			total_reward += 0.3  # ทุก frame ที่จอดอยู่

			if _parked_frames >= 10:  # ลดจาก 30 → 10
				# SUCCESS! Big bonus
				total_reward += 15.0
				# Time bonus
				var time_bonus = maxf(0.0, 10.0 - _parking_time * 0.5)
				total_reward += time_bonus
				done = true
		else:
			_parked_frames = max(0, _parked_frames - 1)
	else:
		_parked_frames = 0

	# ============================================================
	# 6. TIME PENALTY — อย่ายืดเวลา
	# ============================================================
	total_reward -= 0.005  # ลดจาก 0.01

	# ============================================================
	# 7. OUT OF BOUNDS — ตกแมพเท่านั้นที่จบ
	# ============================================================
	if car.global_position.y < -2.0 or car.global_position.y > 5.0:
		total_reward -= 5.0
		done = true

	# ไม่เคลื่อนที่นาน = จบ (กัน idle)
	if _episode_steps > 200 and speed < 0.1 and current_distance > 5.0:
		total_reward -= 1.0
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
