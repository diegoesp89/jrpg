extends Node
## Boot — Entry point scene
## Initializes game and transitions to dungeon.

func _ready() -> void:
	print("Boot: Starting JRPG Vertical Slice...")
	# Give autoloads one frame to initialize
	await get_tree().process_frame
	# Transition to dungeon
	SceneFlow.change_scene("res://scenes/exploration/Dungeon.tscn")
