extends GutTest
class_name TestCarDrive

func test_car_drives() -> void:
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	add_child(scene)
	
	var car = scene.find_child("Car", true, false)
	
	if car == null:
		print("Car not found!")
		return
	
	# wait a moment for physics
	await get_tree().create_timer(1.0).timeout
	
	var initial_pos = car.global_position
	
	car.throttle_input = 1.0
	
	for child in car.get_children():
		if child is VehicleWheel3D:
			print("Wheel ", child.name, " contact: ", child.is_in_contact(), " rest_len: ", child.wheel_rest_length, " radius: ", child.wheel_radius, " pos: ", child.global_position.y)
	
	await get_tree().create_timer(1.0).timeout
	
	var new_pos = car.global_position
	
	print("Car position moved from ", initial_pos, " to ", new_pos)
	
	if initial_pos.distance_to(new_pos) > 0.1:
		print("Car moved!")
	else:
		print("Car DID NOT MOVE!")
		for child in car.get_children():
			if child is VehicleWheel3D:
				print(child.name, " is in contact: ", child.is_in_contact(), ", steering: ", child.steering, ", engine_force: ", child.engine_force, ", brake: ", child.brake)
		
		var col = car.get_node_or_null("CollisionShape3D")
		if col:
			print("Collision global y: ", col.global_position.y)
			if col.shape:
				print("Shape type: ", col.shape.get_class())
	
	scene.queue_free()
