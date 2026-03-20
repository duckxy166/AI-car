extends Camera3D

@export var mouse_sensitivity: float = 0.002
@export var base_speed: float = 5.0
@export var sprint_multiplier: float = 2.5

func _ready() -> void:
	# ล็อกเคอร์เซอร์เมาส์ซ่อนไว้ตรงกลางหน้าจอเมื่อเริ่มเกม
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	# จัดการการหมุนมุมกล้องเมื่อมีการขยับเมาส์
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# หมุนแกน Y (ซ้าย-ขวา) ใน Global space
		rotate_y(-event.relative.x * mouse_sensitivity)
		# หมุนแกน X (ก้ม-เงย) ใน Local space
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		
		# ล็อกองศาการก้มเงยไม่ให้หมุนทะลุ (ตีลังกา)
		rotation.x = clamp(rotation.x, -PI/2, PI/2)

	# กด ESC เพื่อปลดเมาส์ออก
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# คลิกเมาส์ซ้ายบนหน้าจอเพื่อล็อกเมาส์กลับเข้าไปใหม่
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	# ถ้าไม่ได้ล็อกเมาส์อยู่ ให้ข้ามการประมวลผลการเดินไปเลย
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
		
	var input_dir := Vector3.ZERO

	# ตรวจสอบปุ่ม WASD สำหรับแนวราบ และ Q/E สำหรับขึ้นลง
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_E): input_dir.y += 1
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1

	# ปรับเวกเตอร์ให้เป็น 1 (ป้องกันการเดินทะแยงแล้วเร็วขึ้น)
	input_dir = input_dir.normalized()

	# จัดการความเร็วเมื่อกด Shift
	var current_speed = base_speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed *= sprint_multiplier

	# เคลื่อนที่ตามทิศทางที่กล้องหันไป (Local Transform)
	translate(input_dir * current_speed * delta)
