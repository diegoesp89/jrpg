extends Node
class_name ProfileScreen
## ProfileScreen — Read-only view of the cross-playthrough profile (SaveManager.get_profile()):
## winning party combinations + accumulated stats. Reached from ContinueScreen's "Ver perfil".

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

	var title = Label.new()
	title.text = "Perfil"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 90
	_root.add_child(title)

	var profile = SaveManager.get_profile()

	var stats_box = VBoxContainer.new()
	stats_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stats_box.offset_left = 60
	stats_box.offset_right = -60
	stats_box.offset_top = 100
	stats_box.offset_bottom = 220
	stats_box.add_theme_constant_override("separation", 6)
	_root.add_child(stats_box)

	_add_stat_row(stats_box, "Partidas completadas: %d" % profile.get("total_completions", 0))

	var usage: Dictionary = profile.get("character_usage_counts", {})
	if usage.is_empty():
		_add_stat_row(stats_box, "Personaje mas usado: -")
	else:
		var best_id = ""
		var best_count = -1
		for char_id in usage.keys():
			if usage[char_id] > best_count:
				best_count = usage[char_id]
				best_id = char_id
		var char_data = DataLoader.get_character(best_id)
		var char_name = char_data.get("name", best_id) if not char_data.is_empty() else best_id
		_add_stat_row(stats_box, "Personaje mas usado: %s (%d veces)" % [char_name, best_count])

	_add_stat_row(stats_box, "Oro total acumulado: %d" % profile.get("total_gold_earned", 0))
	_add_stat_row(stats_box, "XP total acumulada: %d" % profile.get("total_xp_earned", 0))

	var combos_title = Label.new()
	combos_title.text = "Combinaciones de party que completaron el mapa:"
	combos_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combos_title.add_theme_font_size_override("font_size", 20)
	combos_title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	combos_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	combos_title.offset_top = 230
	combos_title.offset_bottom = 260
	_root.add_child(combos_title)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_left = 200
	scroll.offset_right = -200
	scroll.offset_top = 270
	scroll.offset_bottom = -70
	_root.add_child(scroll)

	var combos_list = VBoxContainer.new()
	combos_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combos_list.add_theme_constant_override("separation", 4)
	scroll.add_child(combos_list)

	var combos: Array = profile.get("completed_party_combos", [])
	if combos.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Todavia ninguna."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		combos_list.add_child(empty_lbl)
	else:
		for combo_key in combos:
			var ids: Array = str(combo_key).split(",")
			var names: Array = []
			for char_id in ids:
				var char_data = DataLoader.get_character(char_id)
				names.append(str(char_data.get("name", char_id)) if not char_data.is_empty() else char_id)
			var lbl = Label.new()
			lbl.text = ", ".join(names)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 18)
			combos_list.add_child(lbl)

	var hint = Label.new()
	hint.text = "Z / Esc: Volver"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func _add_stat_row(parent: VBoxContainer, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	parent.add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("action1") or event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
		get_viewport().set_input_as_handled()
