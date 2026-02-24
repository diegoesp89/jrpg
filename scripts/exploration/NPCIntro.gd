extends StaticBody3D
## NPCIntro — The introductory NPC with dialogue and branching choice.

var dialogue_id: String = "npc_intro"

func interact() -> void:
	if GameState.get_flag("intro_done"):
		print("NPC: Ya hablamos. Adelante, explorador.")
		return
	# Start dialogue
	var dialogue_controller = _find_dialogue_controller()
	if dialogue_controller:
		# Disable player movement
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("set_movement_disabled"):
			player.set_movement_disabled(true)
		# Connect to dialogue_finished to re-enable movement if it fails
		if not dialogue_controller.dialogue_finished.is_connected(_on_dialogue_finished):
			dialogue_controller.dialogue_finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
		dialogue_controller.start(dialogue_id)
	else:
		# Fallback: just set flag
		print("NPC: Dialogue system not found. Setting intro_done.")
		GameState.set_flag("intro_done")

func _on_dialogue_finished(_id: String) -> void:
	# Safety: ensure movement re-enabled (DialogueController also does this)
	pass

func _find_dialogue_controller():
	# Look for DialogueController in the scene tree
	var controllers = get_tree().get_nodes_in_group("dialogue_controller")
	if controllers.size() > 0:
		return controllers[0]
	return null

func get_prompt_text() -> String:
	if GameState.get_flag("intro_done"):
		return "Z: Hablar (ya completado)"
	return "Z: Hablar"

func is_available() -> bool:
	return true
