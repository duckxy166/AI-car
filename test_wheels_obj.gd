class_name TestWheels
extends Node

func test_wheels():
	var car_scene = load("res://scenes/car.tscn")
	if not car_scene:
		print("Could not load res://scenes/car.tscn")
		return
		
	var car = car_scene.instantiate()
	add_child(car)
	car.global_position = Vector3(0, 1, 0)
	
	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	
	# Wait for physics
	await get_tree().create_timer(1.0).timeout
	
	car.throttle_input = 1.0
	var pos_before = car.global_position
	
	await get_tree().create_timer(1.0).timeout
	
	print("Pos moved from ", pos_before, " to ", car.global_position)
	
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " global pos: ", child.global_position, " local pos: ", child.position, " in contact: ", child.is_in_contact(), " engine_force: ", child.engine_force, " brake: ", child.brake, " wheel_rest_length: ", child.wheel_rest_length, " wheel_radius: ", child.wheel_radius, " suspension_travel: ", child.suspension_travel)
			if child.is_in_contact():
				print("   Contact point: ", child.get_contact_point())
				
	floor_body.queue_free()
	car.queue_free()
