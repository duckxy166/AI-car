extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	
	for i in range(120):
		get_root().get_world_3d().space.get_direct_state()
		# Oh, we need to advance the physics frame
	
	var car = scene.get_node("Car")
	car.throttle_input = 1.0
	
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		print("Car pos: ", car.global_position)
		for w in car.get_children():
			if w is VehicleWheel3D:
				print(w.name, " contact: ", w.is_in_contact(), " pos: ", w.global_position)
		quit()
	)
