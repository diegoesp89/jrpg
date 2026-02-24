extends StaticBody3D
## Pickup — Chest/item pickup. Adds item to inventory on interaction.

@export var item_id: String = "potion"
@export var item_quantity: int = 1
@export var chest_id: String = "chest_sala3"

var _opened: bool = false

@onready var _sprite: Sprite3D = null

func _ready() -> void:
	# Find sprite child first (needed by _hide_chest)
	for child in get_children():
		if child is Sprite3D:
			_sprite = child
	# Check if already opened
	if GameState.get_flag(chest_id + "_opened"):
		_opened = true
		_hide_chest()
		return

func interact() -> void:
	if _opened:
		return
	_opened = true
	GameState.add_item(item_id, item_quantity)
	GameState.set_flag(chest_id + "_opened")
	var item_data = DataLoader.get_item(item_id)
	var item_name = item_data.get("name", item_id) if item_data else item_id
	print("Obtained: %s x%d!" % [item_name, item_quantity])
	_hide_chest()

func _hide_chest() -> void:
	if _sprite:
		_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
	# Disable collision so player can walk through
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true

func get_prompt_text() -> String:
	if _opened:
		return ""
	return "Z: Abrir cofre"

func is_available() -> bool:
	return not _opened
