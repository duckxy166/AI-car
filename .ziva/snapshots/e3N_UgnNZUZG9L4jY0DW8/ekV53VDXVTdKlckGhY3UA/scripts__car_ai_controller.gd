extends AIController3D

## AI Controller for parking training
## Observations: 19 values (speed, angle, distance, 12 raycasts, vel_x, vel_z, angular_vel, in_spot)
## Actions: 2 continuous (steer, throttle)

# References
var car: VehicleBody3D
var raycast_sensor: Node3D
var parking_spot: Area3D

# Parking target info (set by parking_lot.gd)
var target_position := Vector3.ZERO
var target_rotation := 0.0  # Y-axis rotation of the parking spot

# Reward shaping
var _previous_distance := 999.0
var _previous_angle_diff := PI
var _episode_steps := 0
var _is_in_spot := false
var _parked_frames := 0  # Count frames car stays parked correctly
const PARKED_THRESHOLD := 30  # Frames needed to confirm parked

# Limits for normalization
const MAX_SPEED := 15.0
const MAX_DISTANCE := 30.0
const MAX_ANGULAR_VEL := 5.0


func _ready():
	super._ready()
	reset_after = 1500  # Max steps per episode


func init(player: Node3D):
	super.init(player)
	car = player as VehicleBody3D

	# Find raycast sensor child
	for child in get_children():
		if child is RayCastSensor3D:
			raycast_sensor = child
			break


func get_obs() -> Dictionary:
	var obs := []

	if not car:
		# Return zero obs if car not ready
		obs.resize(19)
		obs.fill(0.0)
		return {"obs": obs}

	# 1. Normalized speed [-1, 1]
	var speed = car.get_speed() / MAX_SPEED
	obs.append(clampf(speed, -1.0, 1.0))

	# 2. Angle to target [-1, 1] (normalized by PI)
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

	# 4-15. Raycast sensor data (12 values, already normalized 0-1)
	if raycast_sensor:
		var ray_obs = raycast_sensor.get_observation()
		for val in ray_obs:
			obs.append(val)
	else:
		for i in 12:
			obs.append(0.0)

	# 16. Local velocity X (lateral) normalized
	var local_vel = car.get_velocity_local()
	obs.append(clampf(local_vel.x / MAX_SPEED, -1.0, 1.0))

	# 17. Local velocity Z (forward) normalized
	obs.append(clampf(local_vel.y / MAX_SPEED, -1.0, 1.0))

	# 18. Angular velocity Y normalized
	var ang_vel = car.angular_velocity.y / MAX_ANGULAR_VEL
	obs.append(clampf(ang_vel, -1.0, 1.0))

	# 19. Is in parking spot (0 or 1)
	obs.append(1.0 if _is_in_spot else 0.0)

	return {"obs": obs}


func get_reward() -> float:
	var total_reward := reward

	if not car:
		return 0.0

	var to_target = target_position - car.global_position
	to_target.y = 0
	var current_distance = to_target.length()

	# --- Distance shaping reward ---
	var distance_reward = (_previous_distance - current_distance) * 0.5
	total_reward += distance_reward
	_previous_distance = current_distance

	# --- Alignment reward (when close to target) ---
	if current_distance < 5.0:
		var car_angle = fmod(car.rotation.y, TAU)
		var angle_diff = abs(angle_difference(car_angle, target_rotation))
		var alignment_reward = (_previous_angle_diff - angle_diff) * 0.3
		total_reward += alignment_reward
		_previous_angle_diff = angle_diff

		# Bonus for being well-aligned and close
		if angle_diff < 0.3 and current_distance < 2.0:
			total_reward += 0.05

	# --- Collision penalty ---
	if car.is_colliding:
		total_reward -= 0.5

	# --- Parking success bonus ---
	if _is_in_spot:
		var speed = abs(car.get_speed())
		var car_angle = fmod(car.rotation.y, TAU)
		var angle_diff = abs(angle_difference(car_angle, target_rotation))

		if speed < 0.5 and angle_diff < 0.35:  # ~20 degrees
			_parked_frames += 1
			total_reward += 0.2

			if _parked_frames >= PARKED_THRESHOLD:
				total_reward += 10.0  # Big success bonus
				done = true
		else:
			_parked_frames = max(0, _parked_frames - 1)
	else:
		_parked_frames = 0

	# --- Time penalty ---
	total_reward -= 0.01

	# --- Out of bounds / flipped penalty ---
	if car.global_position.y < -2.0 or car.global_position.y > 5.0:
		total_reward -= 5.0
		done = true

	# --- Severe collision (high speed) ---
	if car.is_colliding and abs(car.get_speed()) > 5.0:
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

	if car:
		car.reset_to_spawn()


func set_parking_target(pos: Vector3, rot_y: float):
	target_position = pos
	target_rotation = rot_y
	_previous_distance = (target_position - car.global_position).length() if car else 999.0


func set_in_parking_spot(value: bool):
	_is_in_spot = value


## Human control for testing
func _physics_process(delta):
	super._physics_process(delta)

	if heuristic == "human":
		var steer = 0.0
		var throttle = 0.0

		if Input.is_action_pressed("ui_left"):
			steer = 1.0
		elif Input.is_action_pressed("ui_right"):
			steer = -1.0

		if Input.is_action_pressed("ui_up"):
			throttle = 1.0
		elif Input.is_action_pressed("ui_down"):
			throttle = -1.0

		if car:
			car.steer_input = steer
			car.throttle_input = throttle
