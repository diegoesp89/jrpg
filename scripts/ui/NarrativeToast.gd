extends CanvasLayer
class_name NarrativeToast
## NarrativeToast — a short narrator aside: the dungeon reacting to how far the party has gotten,
## or a warning about what changed while they weren't looking. Not a character speaking (no
## portrait, no speaker name, no branching) — that's what DialogueController/DialogueBox are for.
## This is the narrator, so it is built as its own small overlay instead of stretching an existing
## conversation system to cover a tone it wasn't written for.
##
## Blocks movement and waits for a keypress to dismiss, matching every other overlay already in
## this game (RiddleInputBox, the victory screen) rather than auto-fading on a timer: an important
## story beat competing with a timer is how players miss it.

signal dismissed

## Self-preload rather than referencing the bare class_name below — a global class isn't in the
## class cache until a project scan (e.g. opening the editor) registers it, and show_at() would
## otherwise fail to resolve "NarrativeToast" the first time this script runs after being added.
const _Self = preload("res://scripts/ui/NarrativeToast.gd")

var _label: Label
var _prompt: Label

func _ready() -> void:
	layer = 92
	_build_ui()

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -160
	panel.offset_bottom = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.10, 0.96)
	style.border_color = Color(0.55, 0.15, 0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	panel.add_child(vbox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.75))
	vbox.add_child(_label)

	_prompt = Label.new()
	_prompt.text = "Presiona Z para continuar"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(_prompt)

## Shows the message and disables player movement until it's dismissed. Call as
## `await NarrativeToast.show_at(some_node, text)` — the static helper below is the normal way in.
func show_message(text: String) -> void:
	_label.text = text
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("action1"):
		get_viewport().set_input_as_handled()
		_dismiss()

func _dismiss() -> void:
	set_process_unhandled_input(false)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(false)
	dismissed.emit()
	queue_free()

## Convenience wrapper so a call site doesn't need to manage the node's lifetime:
## `await NarrativeToast.show_at(self, "...")`.
static func show_at(parent: Node, text: String) -> void:
	var toast = _Self.new()
	parent.add_child(toast)
	toast.show_message(text)
	await toast.dismissed
