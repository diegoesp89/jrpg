extends StaticBody3D
## Interactable — Base class for interactive objects in the dungeon.
## Subclasses override interact(), get_prompt_text(), is_available().
class_name Interactable

func interact() -> void:
	pass

func get_prompt_text() -> String:
	return "Z: Interactuar"

func is_available() -> bool:
	return true
