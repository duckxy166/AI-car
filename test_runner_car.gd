extends SceneTree

func _init():
	print("Running main scene simulation...")
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	for i in range(120):
		await process_frame
		
	var car = scene.get_node("Car")
	print("Car position: ", car.global_position)
	for child in car.get_children():
		if child is VehicleWheel3D:
			print(child.name, " is in contact: ", child.is_in_contact(), " pos: ", child.global_position)
			
	quit()
