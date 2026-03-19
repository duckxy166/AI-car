extends Node

var car

func _ready():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	add_child(scene)
	car = scene.get_node("Car")
	car.throttle_input = 1.0
	
func _physics_process(delta):
	car.throttle_input = 1.0
	car.engine_force = 1000.0 # Force it
	
	if Engine.get_physics_frames() == 120:
		print("Car pos: ", car.global_position)
		for w in car.get_children():
			if w is VehicleWheel3D:
				print(w.name, " contact: ", w.is_in_contact(), " is_colliding: ", " y: ", w.global_position.y)
		get_tree().quit()
