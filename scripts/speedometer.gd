extends CanvasLayer

@onready var speed_label: Label = $Panel/SpeedLabel

var car: RigidBody3D

func _ready() -> void:
	# Find the car in the scene
	car = get_tree().get_first_node_in_group("car")
	if car:
		print("Speedometer connected to car!")
	else:
		print("Warning: No car found in group 'car'")

func _process(_delta: float) -> void:
	if car:
		# Get speed in m/s and convert to km/h
		var speed_ms: float = car.linear_velocity.length()
		var speed_kmh: int = int(speed_ms * 3.6)
		speed_label.text = str(speed_kmh) + " km/h"
