extends GutTest

func test_drive():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	add_child(scene)
	var car = scene.get_node("Car")
	car.throttle_input = 1.0
	
	await get_tree().create_timer(2.0).timeout
	
	print("Car linear_velocity: ", car.linear_velocity)
	print("Car position: ", car.global_position)
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " contact: ", child.is_in_contact(), " rpm: ", child.get_rpm(), " slip: ", child.get_skidinfo())
	
	pass
