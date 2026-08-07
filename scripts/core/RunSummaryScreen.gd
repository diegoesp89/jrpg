extends Node
class_name RunSummaryScreen
## RunSummaryScreen — Shown after the credits crawl finishes, before returning to the main menu.
## Reads GameState.run_stats/run_start_time_msec/party, which are still this run's real values —
## GameState.reset() happens on dismissal HERE now, not in CreditsScreen (see CreditsScreen.gd's
## own note on why it used to be the one resetting).

var _root: Control

func _ready() -> void:
	_build_ui()
	set_process_unhandled_input(true)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title = Label.new()
	title.text = "Resumen de la Partida"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 90
	_root.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 260
	scroll.offset_right = -260
	scroll.offset_top = 110
	scroll.offset_bottom = -70
	_root.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	_add_stat(list, "Tiempo de juego", _format_elapsed())
	_add_stat(list, "Turnos", str(int(GameState.run_stats.get("turns", 0))))
	_add_stat(list, "Golpes conectados", str(int(GameState.run_stats.get("hits_landed", 0))))
	_add_stat(list, "XP total", str(GameState.total_xp))
	_add_stat(list, "Oro final", str(GameState.gold))

	var feats_header = Label.new()
	feats_header.text = "Feats obtenidos"
	feats_header.add_theme_font_size_override("font_size", 22)
	feats_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	list.add_child(feats_header)

	for m in GameState.party:
		_add_member_feats(list, m)

	var hint = Label.new()
	hint.text = "Z / X / Esc: Volver al menú"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func _add_stat(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	row.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	row.add_child(value)

func _add_member_feats(parent: VBoxContainer, member: Dictionary) -> void:
	var feat_ids: Array = member.get("feats", [])
	var names: Array = []
	for feat_id in feat_ids:
		var feat = DataLoader.get_feat(str(feat_id))
		names.append(str(feat.get("name", feat_id)))

	var line = Label.new()
	line.text = "%s: %s" % [str(member.get("name", "")), ", ".join(names) if not names.is_empty() else "(ninguno)"]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 17)
	line.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	parent.add_child(line)

func _format_elapsed() -> String:
	var elapsed_ms := Time.get_ticks_msec() - GameState.run_start_time_msec
	var total_seconds := maxi(0, int(elapsed_ms / 1000.0))
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%d:%02d" % [minutes, seconds]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("action1") or event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		SaveManager.clear_active_save()
		GameState.reset()
		SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
