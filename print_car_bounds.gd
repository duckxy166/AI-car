@tool
extends EditorScript

func _run():
	var car_scene = load("res://scenes/car.tscn").instantiate()
	var col = car_scene.get_node("CollisionShape3D")
	print("Collision position y: ", col.position.y)
	if "size" in col.shape:
		print("Collision size y: ", col.shape.size.y)
		print("Collision bottom: ", col.position.y - col.shape.size.y / 2)
	
	for w in car_scene.get_children():
		if w is VehicleWheel3D:
			print(w.name, " pos y: ", w.position.y, ", radius: ", w.wheel_radius, ", susp rest: ", w.suspension_rest_length)
			print("Wheel bottom: ", w.position.y - w.wheel_radius - w.suspension_rest_length)
