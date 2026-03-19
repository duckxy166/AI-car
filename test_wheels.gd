extends SceneTree

func _init():
	var root = get_root()
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	
	# Wait for physics
	await create_timer(1.0).timeout
	
	var car = scene.find_child("Car", true, false)
	if not car:
		print("Car not found!")
		quit()
		return
		
	var pos_before = car.global_position
	car.throttle_input = 1.0
	
	await create_timer(1.0).timeout
	
	print("Pos moved from ", pos_before, " to ", car.global_position)
	
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " pos: ", child.global_position, " in contact: ", child.is_in_contact(), " engine_force: ", child.engine_force, " brake: ", child.brake)
			if child.is_in_contact():
				print("   Contact point: ", child.get_contact_point())
				
	quit()
