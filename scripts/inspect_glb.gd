@tool
extends EditorScript

func _run():
	var scene = load("res://asset/car/lamb.glb")
	if scene == null:
		print("ERROR: Cannot load lamb.glb")
		return
	var instance = scene.instantiate()
	print("=== lamb.glb Node Tree ===")
	_print_tree(instance, 0)
	instance.queue_free()

func _print_tree(node: Node, depth: int):
	var indent = ""
	for i in depth:
		indent += "  "
	var info = "%s%s [%s]" % [indent, node.name, node.get_class()]
	if node is MeshInstance3D:
		var mesh = node.mesh
		if mesh:
			var aabb = mesh.get_aabb()
			info += " size=(%.3f, %.3f, %.3f) pos=(%.3f, %.3f, %.3f)" % [
				aabb.size.x, aabb.size.y, aabb.size.z,
				node.global_transform.origin.x if node.is_inside_tree() else node.position.x,
				node.global_transform.origin.y if node.is_inside_tree() else node.position.y,
				node.global_transform.origin.z if node.is_inside_tree() else node.position.z
			]
	elif node is Node3D:
		info += " pos=(%.3f, %.3f, %.3f)" % [node.position.x, node.position.y, node.position.z]
	print(info)
	for child in node.get_children():
		_print_tree(child, depth + 1)
