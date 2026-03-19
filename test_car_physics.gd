extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn")
	var instance = scene.instantiate()
	root.add_child(instance)
	
	print("Scene loaded. Waiting for 10 frames...")
	for i in range(10):
		await get_tree().process_frame
		
	var car = instance.find_child("Car", true, false)
	if not car:
		print("Car not found!")
		quit()
		return
		
	print("Car position: ", car.global_position)
	print("Applying input...")
	
	car.throttle_input = 1.0
	
	for i in range(60):
		await get_tree().physics_frame
		
	print("Car position after 1 sec: ", car.global_position)
	print("Car speed: ", car.get_speed())
	print("Car throttle input: ", car.throttle_input)
	print("Car engine force FL: ", car.get_node("Wheel_FL").engine_force)
	
	var is_touching = car.is_colliding
	print("Car is_colliding: ", is_touching)
	
	quit()
