extends Node

func test_drive():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	add_child(scene)
	var car = scene.get_node("ParkingLot/Car")
	car.throttle_input = 1.0
	
	# Try to process 60 frames
	for i in range(60):
		get_tree().physics_frame
		
	print("Car speed: ", car.get_speed())
