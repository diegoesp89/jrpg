extends CanvasLayer
class_name AchievementToast
## AchievementToast — a short "logro desbloqueado" banner in the top-right corner.
##
## Deliberately NOT like NarrativeToast (which blocks input and waits for a keypress): an
## achievement is incidental positive feedback, not a story beat, and firing one mid-combat must
## never interrupt the turn. It just appears, holds for a few seconds, fades, and frees itself —
## no input handling at all.

## Self-preload rather than referencing the bare class_name below — see the identical note in
## NarrativeToast.gd. A global class isn't in the class cache until a project scan registers it,
## so a static factory referencing its own class_name fails the first time this script ever runs.
const _Self = preload("res://scripts/ui/AchievementToast.gd")

const DISPLAY_SECONDS := 2.4
const FADE_SECONDS := 0.5

var _panel: PanelContainer

func _ready() -> void:
	layer = 96
	_build_ui()

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.offset_left = -420
	root.offset_right = -20
	root.offset_top = 20
	root.offset_bottom = 110
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.02, 0.95)
	style.border_color = Color(0.9, 0.8, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var header = Label.new()
	header.text = "🏆 Logro desbloqueado"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	vbox.add_child(header)

	var name_label = Label.new()
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	name_label.name = "NameLabel"
	vbox.add_child(name_label)

func _set_achievement_name(text: String) -> void:
	var name_label: Label = _panel.find_child("NameLabel", true, false)
	if name_label:
		name_label.text = text

## Call as `AchievementToast.show_at(some_node, "achievement_id")` — fire-and-forget from combat
## (don't await, so it never holds up a turn) or `await`ed in sequence at a run-completion
## checkpoint where several might unlock at once.
##
## Parented to the tree ROOT, not to `parent` — `parent` only supplies a way to reach the tree.
## Fire-and-forget callers (BattleController mid-combat, RiddleGate) can be freed or torn down
## (e.g. the battle scene closing) well before this toast's ~3s lifetime is up; if it were a child
## of `parent` it would be freed right along with it and error out trying to finish its tween.
static func show_at(parent: Node, achievement_id: String) -> void:
	var toast = _Self.new()
	parent.get_tree().root.add_child(toast)
	var data = DataLoader.get_achievement(achievement_id)
	toast._set_achievement_name(str(data.get("name", "???")))

	var tree = toast.get_tree()
	var fade_in := toast.create_tween()
	fade_in.tween_property(toast._panel, "modulate:a", 1.0, 0.3)
	await tree.create_timer(DISPLAY_SECONDS).timeout
	var fade_out := toast.create_tween()
	fade_out.tween_property(toast._panel, "modulate:a", 0.0, FADE_SECONDS)
	await fade_out.finished
	toast.queue_free()
