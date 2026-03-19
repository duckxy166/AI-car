@tool
extends EditorScript

func _run():
	var scene = load("res://scenes/car.tscn").instantiate()
	var car = scene
	if scene.name != "Car":
		car = scene.get_node("Car")
	
	if not car:
		print("Car node not found!")
		return
		
	var col = car.get_node_or_null("CollisionShape3D")
	if col:
		print("Collision shape position: ", col.position)
		if "size" in col.shape:
			print("Collision size: ", col.shape.size)
			print("Bottom of collision: ", col.position.y - col.shape.size.y/2)
	else:
		print("No collision shape!")
		
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " position: ", child.position, " radius: ", child.wheel_radius, " suspension rest length: ", child.suspension_rest_length)
			print("Bottom of wheel: ", child.position.y - child.wheel_radius - child.suspension_rest_length)
