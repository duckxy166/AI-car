extends SceneTree

func _init():
	var scene = load("res://scenes/test_drive.tscn").instantiate()
	root.add_child(scene)
	var node = Node.new()
	node.set_script(load("res://test_node.gd"))
	scene.add_child(node)
