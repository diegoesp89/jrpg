extends StaticBody3D
class_name Pickup
## Pickup — Chest/item pickup

## Preloaded by path rather than through its class_name — see the note in DungeonBuilder.gd on why
## a class_name added in the same change as the code using it can't be trusted yet.
const NarrativeToastScript = preload("res://scripts/ui/NarrativeToast.gd")

@export var item_id: String = "potion"
@export var item_quantity: int = 1
@export var chest_id: String = "chest_sala3"

## Set by DungeonBuilder for chests only (plain vars, not @export — generated textures, not
## map-editor config data). Loose floor items leave these null and just dim on pickup instead,
## same as before.
var closed_texture: Texture2D = null
var open_texture: Texture2D = null

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
	AudioManager.play_sfx("chest_open")
	GameState.add_item(item_id, item_quantity)
	GameState.set_flag(chest_id + "_opened")
	var item_data = DataLoader.get_item(item_id)
	var item_name = item_data.get("name", item_id) if item_data else item_id
	print("Obtained: %s x%d!" % [item_name, item_quantity])
	_hide_chest()

	# A floor pickup never changes scenes, so — unlike a boss drop — nothing will reload this map
	# and catch the message later. Show it here, right away, and consume it so DungeonManager's
	# own check on the next scene load doesn't show it a second time.
	if GameState.pending_tier_message != "":
		var msg := GameState.pending_tier_message
		GameState.pending_tier_message = ""
		await NarrativeToastScript.show_at(self, msg)

	var player = get_tree().get_first_node_in_group("player")
	if player:
		SaveManager.save_game(DataLoader.get_current_map_path(), player.global_position)

func _hide_chest() -> void:
	if _sprite:
		if open_texture:
			_sprite.texture = open_texture
		else:
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
