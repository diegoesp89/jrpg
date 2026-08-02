extends Node
class_name DialogueController
## DialogueController — Manages dialogue flow

signal dialogue_finished(dialogue_id: String)

const MOOD_EMOJI: Dictionary = {
	"bittersweet": "🥲",
	"happy": "😄",
	"hopeful": "🌅",
	"anxious": "😰",
	"analytical": "🧐",
	"grim": "😬",
	"playful": "😸",
	"mysterious": "🌫️",
	"determined": "😤",
	"protective": "🛡️",
	"tense": "😥",
	"curious": "🤔",
	"heroic": "🦸",
	"serious": "😐",
	"flirty": "😉",
	"sarcastic": "😏",
	"focused": "🎯",
	"shy": "😳",
	"noble": "⚔️",
}
const DEFAULT_MOOD_EMOJI: String = "💬"

var _current_dialogue: Dictionary = {}
var _current_node_id: String = ""
var _dialogue_id: String = ""
var _is_active: bool = false
var _dialogue_box = null
var _current_emoji: String = ""

func _ready() -> void:
	add_to_group("dialogue_controller")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return

	if _dialogue_box and _dialogue_box.is_showing_choices():
		# During choice: action1 confirms selected, action2 picks option 2
		if event.is_action_pressed("action1"):
			var choice_idx = _dialogue_box.get_selected_choice()
			_pick_choice(choice_idx)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("action2"):
			# action2 = pick option 2 (index 1) immediately
			_pick_choice(1)
			get_viewport().set_input_as_handled()
	else:
		# During text: action1 advances, action2 does nothing
		if event.is_action_pressed("action1"):
			_advance()
			get_viewport().set_input_as_handled()

func start(dialogue_id: String) -> void:
	var dialogue_data = DataLoader.get_dialogue(dialogue_id)
	if dialogue_data.is_empty():
		push_error("DialogueController: dialogue not found: %s" % dialogue_id)
		# Re-enable player movement since dialogue failed to start
		_end_dialogue()
		return

	_dialogue_id = dialogue_id
	_current_dialogue = dialogue_data
	_current_emoji = ""
	_is_active = true

	# Find or create dialogue box
	_dialogue_box = _find_or_create_dialogue_box()
	_dialogue_box.show()

	# Start at the start node
	var start_node = dialogue_data.get("start_node", "start")
	_show_node(start_node)

## Plays a narrative waypoint scene (data/adventure/*.json entry): a linear sequence of
## "Speaker: text" lines with no branching, tagged with a mood emoji portrait.
## `substitutions` replaces literal "{key}" tokens in every line (e.g. {"respuesta": "La Luna"}
## turns "¡{respuesta}!" into "¡La Luna!") — used by scenes whose wording depends on runtime data.
func start_waypoint(entry: Dictionary, substitutions: Dictionary = {}) -> void:
	var lines: Array = entry.get("dialogue", [])
	var nodes: Dictionary = {}
	for i in range(lines.size()):
		var line = str(lines[i])
		for key in substitutions:
			line = line.replace("{%s}" % key, str(substitutions[key]))
		var parts = line.split(":", true, 1)
		var speaker = parts[0].strip_edges() if parts.size() > 1 else ""
		var text = parts[1].strip_edges() if parts.size() > 1 else line.strip_edges()
		var node_id = "line_%d" % i
		var node_data = {"speaker": speaker, "text": text}
		if i < lines.size() - 1:
			node_data["next"] = "line_%d" % (i + 1)
		nodes[node_id] = node_data

	_dialogue_id = str(entry.get("id", "waypoint"))
	_current_dialogue = {"nodes": nodes, "start_node": "line_0"}
	_current_emoji = MOOD_EMOJI.get(entry.get("mood", ""), DEFAULT_MOOD_EMOJI)
	_is_active = true

	_dialogue_box = _find_or_create_dialogue_box()
	_dialogue_box.show()

	_show_node("line_0")

func _show_node(node_id: String) -> void:
	_current_node_id = node_id
	var nodes = _current_dialogue.get("nodes", {})
	var node_data = nodes.get(node_id, {})

	if node_data.is_empty():
		_end_dialogue()
		return

	var speaker = node_data.get("speaker", "")
	var text = node_data.get("text", "")
	var choices = node_data.get("choices", [])

	if choices.size() > 0:
		_dialogue_box.show_choices(speaker, text, choices)
	else:
		var char_data = DataLoader.get_character_by_name(speaker)
		var portrait = CharacterSprites.get_portrait_texture(char_data) if not char_data.is_empty() else null
		# A waypoint scene's mood is a single tag meant for its opening line (typically whoever
		# leads that scene) — showing the same emoji glued to every later speaker misrepresents
		# their own, often very different, reaction, so it only shows on line_0.
		var emoji = _current_emoji if node_id == "line_0" else ""
		_dialogue_box.show_text(speaker, text, emoji, portrait)

	# Process flags
	if node_data.has("set_flag"):
		GameState.set_flag(node_data["set_flag"])

func _advance() -> void:
	var nodes = _current_dialogue.get("nodes", {})
	var node_data = nodes.get(_current_node_id, {})

	if node_data.has("next"):
		_show_node(node_data["next"])
	else:
		_end_dialogue()

func _pick_choice(choice_idx: int) -> void:
	var nodes = _current_dialogue.get("nodes", {})
	var node_data = nodes.get(_current_node_id, {})
	var choices = node_data.get("choices", [])

	if choice_idx >= 0 and choice_idx < choices.size():
		var next_node = choices[choice_idx].get("next", "")
		if next_node != "":
			_show_node(next_node)
		else:
			_end_dialogue()
	else:
		_end_dialogue()

func _end_dialogue() -> void:
	_is_active = false
	if _dialogue_box:
		_dialogue_box.hide()

	# Re-enable player movement
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(false)

	dialogue_finished.emit(_dialogue_id)

func _find_or_create_dialogue_box():
	# Check if one exists already
	var existing = get_tree().get_first_node_in_group("dialogue_box")
	if existing:
		return existing

	# Create one dynamically
	var box_script = load("res://scripts/ui/DialogueBox.gd")
	var canvas = CanvasLayer.new()
	canvas.layer = 50
	add_child(canvas)

	var box = PanelContainer.new()
	box.set_script(box_script)
	box.add_to_group("dialogue_box")
	canvas.add_child(box)  # _ready() calls setup() automatically
	return box
