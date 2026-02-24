extends Area3D
## CombatTrigger — Initiates a battle encounter when player enters the area.

@export var encounter_id: String = ""
var _triggered: bool = false
var _flag_id: String = ""

func _ready() -> void:
	# Auto-detect encounter_id from node name if not set
	if encounter_id == "":
		if "hallway" in name:
			encounter_id = "encounter_hallway"
		elif "golem" in name:
			encounter_id = "encounter_golem"
		elif "boss" in name:
			encounter_id = "encounter_boss"
		else:
			encounter_id = "encounter_hallway"

	_flag_id = "combat_" + encounter_id + "_done"

	# Check if already completed
	if GameState.get_flag(_flag_id):
		_triggered = true
		return

	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if body is CharacterBody3D:
		_triggered = true
		# NOTE: Flag is NOT set here — it's set on victory by BattleScene.
		# This allows re-triggering the encounter if the player loses/flees.
		print("Combat triggered: %s" % encounter_id)
		var dungeon_path = "res://scenes/exploration/Dungeon.tscn"
		SceneFlow.start_battle(encounter_id, dungeon_path, body.global_position)

func get_prompt_text() -> String:
	return ""

func is_available() -> bool:
	return false
