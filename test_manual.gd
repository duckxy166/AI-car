extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	
	var car = scene.find_child("Car", true, false)
	car.throttle_input = 1.0
	
	# Simulate 100 physics frames
	for i in range(100):
		root.physics_process(1.0 / 60.0)
		
	print("Car linear_velocity: ", car.linear_velocity)
	print("Car position: ", car.global_position)
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " contact: ", child.is_in_contact(), " rpm: ", child.get_rpm(), " slip: ", child.get_skidinfo())
			
	quit()
