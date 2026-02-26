extends StaticBody3D
class_name Door
## Door — Opens/closes on interaction

var is_open: bool = false
var door_id: String = "door_sala3"

@onready var _collision: CollisionShape3D = null
@onready var _sprite: Sprite3D = null

func _ready() -> void:
	# Find child nodes
	for child in get_children():
		if child is CollisionShape3D:
			_collision = child
		elif child is Sprite3D:
			_sprite = child

func interact() -> void:
	if is_open:
		_close()
	else:
		_open()

func _open() -> void:
	is_open = true
	if _collision:
		_collision.disabled = true
	if _sprite:
		_sprite.modulate = Color(1, 1, 1, 0.3)
	print("Door opened!")

func _close() -> void:
	is_open = false
	if _collision:
		_collision.disabled = false
	if _sprite:
		_sprite.modulate = Color(1, 1, 1, 1.0)
	print("Door closed!")

func get_prompt_text() -> String:
	if is_open:
		return "Z: Cerrar puerta"
	return "Z: Abrir puerta"

func is_available() -> bool:
	return true
