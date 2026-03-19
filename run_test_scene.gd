extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func():
		var car = scene.get_node("Car")
		print("Car pos: ", car.global_position)
		for w in car.get_children():
			if w is VehicleWheel3D:
				print(w.name, " contact: ", w.is_in_contact(), " y: ", w.global_position.y)
		quit()
	)
	scene.add_child(timer)
	var car = scene.get_node("Car")
	car.throttle_input = 1.0
