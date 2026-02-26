extends Node
class_name Boot
## Boot — Entry point scene

func _ready() -> void:
	print("Boot: Starting JRPG Vertical Slice...")
	await get_tree().process_frame
	SceneFlow.change_scene("res://scenes/boot/CharacterSelection.tscn")
