extends SceneTree

func _init():
	print("Running test...")
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	var car = scene.get_node("ParkingLot/Car")
	car.throttle_input = 1.0
	for i in range(60):
		await process_frame
	print("Car speed: ", car.get_speed())
	quit()
