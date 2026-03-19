extends Node

var frames = 0
@onready var car = $"../Car"

func _physics_process(delta):
	frames += 1
	car.throttle_input = 1.0
	
	if frames == 120:
		print("Car linear_velocity: ", car.linear_velocity)
		print("Car position: ", car.global_position)
		for child in car.get_children():
			if child is VehicleWheel3D:
				print(child.name, " contact: ", child.is_in_contact(), " rpm: ", child.get_rpm(), " slip: ", child.get_skidinfo())
		get_tree().quit()
