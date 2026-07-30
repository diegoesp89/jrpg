extends Area3D
class_name StoryTrigger
## StoryTrigger — plays a party-specific narrative beat (data/adventure/*.json) the first
## time its zone is entered. Reusable "collision box" component for any story checkpoint.

signal scene_finished

@export var event_id: String = ""
@export var requires_flag: String = ""  # optional: only fires once this flag is already set
@export var auto_trigger: bool = true   # if false, must be invoked externally via play_for_current_party()

var _is_playing: bool = false

func _ready() -> void:
	if auto_trigger:
		body_entered.connect(_on_body_entered)

func _flag_id() -> String:
	return "story_%s_done" % event_id

func is_playing() -> bool:
	return _is_playing

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		play_for_current_party()

## Plays the scene matching event_id + the current party for the current party composition.
## No-ops (without consuming the attempt) if requires_flag isn't satisfied yet.
## `substitutions` is forwarded to DialogueController.start_waypoint (e.g. {"respuesta": "La Luna"}).
func play_for_current_party(substitutions: Dictionary = {}) -> void:
	if GameState.get_flag(_flag_id()):
		return
	if requires_flag != "" and not GameState.get_flag(requires_flag):
		return

	var party_names: Array = GameState.party.map(func(m): return m["name"])
	var entry = DataLoader.get_waypoint_scene(event_id, party_names)
	GameState.set_flag(_flag_id())

	if entry.is_empty():
		push_warning("StoryTrigger: no matching scene for '%s' with party %s" % [event_id, party_names])
		return

	var dialogue_controller = _find_dialogue_controller()
	if not dialogue_controller:
		push_warning("StoryTrigger: no DialogueController found in scene")
		return

	_is_playing = true
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)

	dialogue_controller.dialogue_finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
	dialogue_controller.start_waypoint(entry, substitutions)
	await scene_finished

func _on_dialogue_finished(_id: String) -> void:
	_is_playing = false
	scene_finished.emit()

func _find_dialogue_controller():
	var controllers = get_tree().get_nodes_in_group("dialogue_controller")
	if controllers.size() > 0:
		return controllers[0]
	return null
