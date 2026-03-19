extends VehicleBody3D

## ============================================================
## Lamborghini Huracán - Realistic Physics Calculator
## ============================================================
##
## Reference specs (Huracán LP 610-4):
##   Mass:           1,422 kg (curb weight)
##   Engine:         5.2L V10, 610 HP (449 kW) @ 8,250 rpm
##   Peak torque:    560 Nm @ 6,500 rpm
##   0-100 km/h:     3.2 seconds
##   Top speed:      325 km/h (90.3 m/s)
##   Wheelbase:      2,620 mm
##   Front track:    1,668 mm
##   Rear track:     1,620 mm
##   Length:          4,459 mm
##   Width:           1,924 mm
##   Height:          1,165 mm
##   Tire front:     245/30 R20 → radius ≈ 326 mm
##   Tire rear:      305/30 R20 → radius ≈ 339 mm
##   Steering lock:  ~32° max
##   Brake disc:     380mm front / 356mm rear (carbon ceramic)
##
## ============================================================
## Calculations:
## ============================================================
##
## --- Engine Force ---
## Torque at wheel = engine_torque × 1st_gear × final_drive / tire_radius
##   = 560 Nm × 3.91 × 4.93 / 0.333m
##   ≈ 32,400 N (peak, 1st gear — too much for parking)
##
## For parking scenario, simulating ~1st/2nd gear:
##   Effective force ≈ 20,000 N
##   Godot VehicleBody3D applies internal rolling resistance + slip loss (~60-70%)
##   Real felt acceleration ≈ 20,000 × 0.35 / 1,422 ≈ 4.9 m/s²
##
## --- Brake Force ---
## Deceleration target: ~8 m/s² (moderate braking, not emergency)
## F_brake_total = m × a = 1,422 × 8 = 11,376 N
## Per wheel (4 wheels): 11,376 / 4 ≈ 2,844 N → use 2,800
##
## --- Steering Angle ---
## Real lock-to-lock: ~32° → 0.558 rad
##
## --- Suspension ---
## Spring rate (Huracán MagneRide):
##   Front: ~100 kN/m → Godot stiffness ≈ 55-65
##   Rear:  ~120 kN/m → Godot stiffness ≈ 60-70
## Natural frequency = sqrt(k/m) / (2π)
##   Front: sqrt(100000 / (1422*0.57)) / 6.28 ≈ 1.77 Hz ✓ (sporty: 1.5-2.0 Hz)
##
## Damping ratio ζ = c / (2 × sqrt(k × m))
##   Critical damping c_crit = 2 × sqrt(100000 × 810) ≈ 18,000 Ns/m
##   Sporty ζ ≈ 0.3-0.4
##   Compression: c_comp = ζ × c_crit ≈ 0.3 × 18000 ≈ 5,400 → Godot ≈ 3.0
##   Rebound:     c_reb  = 1.5 × c_comp ≈ 8,100 → Godot ≈ 4.5
##
## --- Tire Friction ---
## Coefficient of friction μ: 1.0-1.2 for performance street tires
## Godot friction_slip ≈ 3.0-4.0 (maps to grip + slip behavior)
##
## ============================================================

# --- Tuned Parameters ---
@export var max_steer_angle := 0.558     # 32° real steering lock
@export var max_engine_force := 800000.0  # Even stronger for higher top speed
@export var max_brake_force := 30000.0	# Stronger brakes for high speed
@export var max_reverse_force := 20000.0 # Reverse ~half of forward

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
	_setup_wheels()

	if ai_controller:
		ai_controller.init(self)



func _physics_process(_delta):
	# --- Steering ---
	var speed_factor = clampf(1.0 - abs(get_speed()) / 20.0, 0.4, 1.0)
	var final_steer = steer_input * max_steer_angle * speed_factor

	# --- Throttle / Brake Logic ---
	var forward_speed = get_speed()
	var final_engine_force = 0.0
	var final_brake = 0.0

	if throttle_input > 0.0:
		if forward_speed >= -0.5:
			final_engine_force = throttle_input * max_engine_force
		else:
			final_brake = max_brake_force * throttle_input

	elif throttle_input < 0.0:
		if forward_speed <= 0.5:
			final_engine_force = throttle_input * max_reverse_force
		else:
			final_brake = max_brake_force * abs(throttle_input)
	else:
		if abs(forward_speed) > 0.5:
			final_brake = 100.0  # Light engine braking
		else:
			final_brake = 500.0  # Hold brake

	# Apply to wheels
	$Wheel_FL.steering = final_steer
	$Wheel_FR.steering = final_steer
	
	$Wheel_FL.engine_force = final_engine_force / 4.0
	$Wheel_FR.engine_force = final_engine_force / 4.0
	$Wheel_RL.engine_force = final_engine_force / 4.0
	$Wheel_RR.engine_force = final_engine_force / 4.0
	
	$Wheel_FL.brake = final_brake / 4.0
	$Wheel_FR.brake = final_brake / 4.0
	$Wheel_RL.brake = final_brake / 4.0
	$Wheel_RR.brake = final_brake / 4.0


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
	"""Get forward speed in m/s (positive = forward, negative = reverse)"""
	return -linear_velocity.dot(global_transform.basis.z)


func get_speed_kmh() -> float:
	"""Get forward speed in km/h"""
	return get_speed() * 3.6


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

func _setup_wheels():
	var model = $CarModel
	if not model: return

	var wheel_nodes = {
		"FL": $Wheel_FL,
		"FR": $Wheel_FR,
		"RL": $Wheel_RL,
		"RR": $Wheel_RR
	}

	var meshes = []
	var to_check = [model]
	while to_check.size() > 0:
		var current = to_check.pop_back()
		for child in current.get_children():
			if child is MeshInstance3D:
				meshes.append(child)
			to_check.append(child)

	for mesh in meshes:
		# Check if it's a wheel using the mesh's AABB position or name
		# Often wheels have "wheel" in name or they are located at the 4 corners
		var pos = mesh.global_position - global_position
		
		# Skip non-wheels (wheels are low Y)
		if pos.y > 0.6 or mesh.name.to_lower().find("wheel") == -1:
			# Not a wheel
			continue

		var is_front = pos.z > 0.0 # GLB forward is Z+ by our mapping
		var is_left = pos.x < 0.0  # Left is X-

		var target_wheel: VehicleWheel3D = null
		if is_front and is_left:
			target_wheel = wheel_nodes["FL"]
		elif is_front and not is_left:
			target_wheel = wheel_nodes["FR"]
		elif not is_front and is_left:
			target_wheel = wheel_nodes["RL"]
		else:
			target_wheel = wheel_nodes["RR"]

		if target_wheel and mesh.get_parent():
			var prev_transform = mesh.global_transform
			mesh.get_parent().remove_child(mesh)
			target_wheel.add_child(mesh)
			mesh.position = Vector3.ZERO # Center on VehicleWheel3D
			mesh.rotation = Vector3.ZERO
