extends CanvasLayer

@onready var speed_label: Label = $SpeedLabel

func _process(_delta: float) -> void:
	var cars = get_tree().get_nodes_in_group("car")
	
	if cars.size() > 0:
		var car = cars[0]
		var speed_mps = car.linear_velocity.length()
		var speed_kmh = speed_mps * 3.6
		
		speed_label.text = "%d km/h" % speed_kmh
		speed_label.add_theme_font_size_override("font_size", 32)
	else:
		speed_label.text = "0 km/h"
