extends Node
class_name AchievementsScreen
## AchievementsScreen — Read-only view of the 15 achievements, unlocked or not. Persists in the
## same cross-playthrough profile as completed_party_combos (SaveManager). Reached from
## ContinueScreen's "Logros". None of the 15 descriptions contain spoilers, so locked rows show
## their full text too — just dimmed, rather than hidden.

var _root: Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var unlocked: Dictionary = SaveManager.get_profile().get("achievements", {})
	var achievements: Array = DataLoader.get_all_achievements()
	var unlocked_count := 0
	for a in achievements:
		if unlocked.get(str(a.get("id", "")), false):
			unlocked_count += 1

	var title = Label.new()
	title.text = "Logros (%d/%d)" % [unlocked_count, achievements.size()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 90
	_root.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 200
	scroll.offset_right = -200
	scroll.offset_top = 110
	scroll.offset_bottom = -70
	_root.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	# Sorted by difficulty (Fácil -> Muy difícil) so the list reads as an easy-to-hard ladder,
	# rather than the arbitrary order they happen to sit in the data file.
	var difficulty_rank := {"Fácil": 0, "Media": 1, "Difícil": 2, "Muy difícil": 3}
	achievements.sort_custom(func(a, b):
		return difficulty_rank.get(a.get("difficulty", ""), 9) < difficulty_rank.get(b.get("difficulty", ""), 9))

	for a in achievements:
		var id = str(a.get("id", ""))
		_add_row(list, a, unlocked.get(id, false))

	var hint = Label.new()
	hint.text = "Z / Esc: Volver"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func _add_row(parent: VBoxContainer, achievement: Dictionary, is_unlocked: bool) -> void:
	var panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.05, 0.9) if is_unlocked else Color(0.09, 0.09, 0.1, 0.7)
	style.border_color = Color(0.9, 0.8, 0.4) if is_unlocked else Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var badge = Label.new()
	badge.text = "🏆" if is_unlocked else "🔒"
	badge.add_theme_font_size_override("font_size", 28)
	row.add_child(badge)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	row.add_child(vbox)

	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	vbox.add_child(name_row)

	var name_label = Label.new()
	name_label.text = str(achievement.get("name", "???"))
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45) if is_unlocked else Color(0.6, 0.6, 0.65))
	name_row.add_child(name_label)

	var diff_label = Label.new()
	diff_label.text = str(achievement.get("difficulty", ""))
	diff_label.add_theme_font_size_override("font_size", 16)
	diff_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5) if is_unlocked else Color(0.45, 0.45, 0.5))
	name_row.add_child(diff_label)

	var desc_label = Label.new()
	desc_label.text = str(achievement.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 17)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85) if is_unlocked else Color(0.5, 0.5, 0.55))
	vbox.add_child(desc_label)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("action1") or event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
		get_viewport().set_input_as_handled()
