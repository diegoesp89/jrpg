extends StaticBody3D
class_name Door
## Door — Opens/closes on interaction. Optionally locked behind a key item; using the key
## consumes it from the inventory and unlocks the door permanently (persisted via a flag,
## same pattern as Pickup.gd's chest_id + "_opened").

var is_open: bool = false
@export var door_id: String = ""
@export var locked: bool = false
@export var required_item_id: String = ""

@onready var _collision: CollisionShape3D = null
@onready var _sprite: Sprite3D = null

func _ready() -> void:
	# Find child nodes
	for child in get_children():
		if child is CollisionShape3D:
			_collision = child
		elif child is Sprite3D:
			_sprite = child

	if locked and door_id != "" and GameState.get_flag(door_id + "_unlocked"):
		locked = false

func interact() -> void:
	if locked:
		if not GameState.has_item(required_item_id):
			return
		GameState.remove_item(required_item_id, 1)
		locked = false
		if door_id != "":
			GameState.set_flag(door_id + "_unlocked")
		print("Puerta desbloqueada con %s!" % required_item_id)

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
	if locked:
		var item = DataLoader.get_item(required_item_id)
		var item_name = item.get("name", required_item_id) if item else required_item_id
		return "Necesitas: %s" % item_name
	if is_open:
		return "Z: Cerrar puerta"
	return "Z: Abrir puerta"

func is_available() -> bool:
	return true
