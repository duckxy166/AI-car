extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	
	var car = scene.find_child("Car", true, false)
	car.throttle_input = 1.0
	
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	root.add_child(timer)
	timer.start()
	await timer.timeout
	
	print("Car Y: ", car.global_position.y)
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " is_in_contact: ", child.is_in_contact(), ", skidinfo: ", child.get_skidinfo(), ", rpm: ", child.get_rpm(), " suspension_length: ", child.suspension_travel)
	
	var ground = scene.find_child("Ground", true, false)
	print("Car bounds: ", car.get_node("CollisionShape3D").global_position.y - 0.6)
	print("Ground bounds: ", ground.get_node("CollisionShape3D").global_position.y + 0.1)
	
	quit()
