extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn")
	var instance = scene.instantiate()
	root.add_child(instance)
	
	print("Started test...")
	await get_tree().create_timer(0.2).timeout
	
	var car = instance.get_node("Car")
	if not car:
		car = instance.find_child("Car*", true, false)
	
	if not car:
		print("Car not found!")
		quit()
		return
	
	print("Initial position: ", car.global_position)
	print("Setting input...")
	car.throttle_input = 1.0
	
	await get_tree().create_timer(1.0).timeout
	
	print("Position after 1s: ", car.global_position)
	print("Wheel FL touching ground: ", car.get_node("Wheel_FL").is_in_contact())
	print("Collision bottom Y: ", car.get_node("CollisionShape3D").global_position.y - 0.6)
	
	quit()
