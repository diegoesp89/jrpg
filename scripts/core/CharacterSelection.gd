extends Node
class_name CharacterSelection

const MAX_PARTY_SIZE: int = 4

var _available_characters: Array[Dictionary] = []
var _selected_indices: Array[int] = []
var _cursor_index: int = 0
var _cursor_row: int = 0

var _root: Control
var _characters_container: HBoxContainer
var _start_button: Button
var _message_label: Label
var _card_panels: Array[PanelContainer] = []
var _cursor_highlight: ColorRect

# Feat selection step (runs after "Iniciar aventura", before the party is created)
var _choosing_feats: bool = false
var _feat_step: int = 0
var _feat_selected_index: int = 0
var _chosen_feats: Dictionary = {}  # character index -> feat id
var _feat_panel: Control = null
var _feat_title: Label = null
var _feat_options_container: VBoxContainer = null

func _ready() -> void:
	_load_characters()
	await _build_ui()
	_build_feat_panel()
	_update_cursor()

func _load_characters() -> void:
	var chars = DataLoader.get_all_characters()
	for c in chars:
		_available_characters.append(c)

func _get_modifier(attribute_value: int) -> int:
	if attribute_value >= 18:
		return +4
	elif attribute_value >= 16:
		return +3
	elif attribute_value >= 14:
		return +2
	elif attribute_value >= 12:
		return +1
	elif attribute_value >= 10:
		return 0
	elif attribute_value >= 8:
		return -1
	else:
		return -2

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	
	var title = Label.new()
	title.text = "Selecciona 4 personajes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 100
	_root.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Cada dialogo es unico dependiendo de los personajes que selecciones, elige bien"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 90
	subtitle.offset_bottom = 120
	_root.add_child(subtitle)
	
	_characters_container = HBoxContainer.new()
	_characters_container.add_theme_constant_override("separation", 15)
	_root.add_child(_characters_container)
	
	for i in range(_available_characters.size()):
		var char_card = _create_character_card(i)
		_characters_container.add_child(char_card)
		_card_panels.append(char_card)
	
	await get_tree().process_frame
	
	var screen_size = get_viewport().get_visible_rect().size
	var total_width = _characters_container.size.x
	var start_x = (screen_size.x - total_width) / 2
	_characters_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_characters_container.offset_left = int(start_x)
	_characters_container.offset_top = 140
	
	
	var instructions = Label.new()
	instructions.text = "WASD/Flechas: Mover  |  Z: Seleccionar/Aceptar"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 18)
	instructions.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	instructions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	instructions.offset_top = -100
	instructions.offset_bottom = -70
	_root.add_child(instructions)
	
	_message_label = Label.new()
	_message_label.text = "Selecciona %d personajes" % MAX_PARTY_SIZE
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 24)
	_message_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_message_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_message_label.offset_top = -80
	_message_label.offset_bottom = -40
	_root.add_child(_message_label)
	
	_start_button = Button.new()
	_start_button.text = "Iniciar aventura"
	_start_button.add_theme_font_size_override("font_size", 28)
	_start_button.custom_minimum_size = Vector2(250, 50)
	_start_button.disabled = true
	_start_button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_start_button.offset_left = -125
	_start_button.offset_right = 125
	_start_button.offset_top = -40
	_root.add_child(_start_button)
	
	_cursor_highlight = ColorRect.new()
	_cursor_highlight.color = Color(1, 1, 0, 0.2)
	_cursor_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cursor_highlight)

func _create_character_card(index: int) -> PanelContainer:
	var char = _available_characters[index]
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(80, 160)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.18)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.add_theme_constant_override("margin_left", 6)
	vbox.add_theme_constant_override("margin_right", 6)
	panel.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = char["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	vbox.add_child(name_label)
	
	var class_label = Label.new()
	class_label.text = char["class"]
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_label.add_theme_font_size_override("font_size", 12)
	class_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	vbox.add_child(class_label)
	
	var stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 0)
	vbox.add_child(stats_container)
	
	var attrs = char.get("attributes", {})
	var str_val = attrs.get("fuerza", 10)
	var dex_val = attrs.get("agilidad", 10)
	var con_val = attrs.get("constitucion", 10)
	var wis_val = attrs.get("sabiduria", 10)
	var int_val = attrs.get("inteligencia", 10)
	var cha_val = attrs.get("carisma", 10)
	
	var str_mod = _get_modifier(str_val)
	var dex_mod = _get_modifier(dex_val)
	var con_mod = _get_modifier(con_val)
	var wis_mod = _get_modifier(wis_val)
	var int_mod = _get_modifier(int_val)
	var cha_mod = _get_modifier(cha_val)
	
	var hit_die = char.get("hit_die", 8)
	var clase = char.get("class", "")
	var hp = hit_die + con_mod
	if hp < 1:
		hp = 1
	var ca = 10 + dex_mod
	if clase == "Barbaro" or clase == "Clerigo" or clase == "Gunslinger":
		ca += 2
	
	var stats = [
		["HP", hp],
		["CA", ca],
		["FUE", str_mod],
		["AGI", dex_mod],
		["CON", con_mod],
		["SAB", wis_mod],
		["INT", int_mod],
		["CAR", cha_mod],
	]
	
	for stat in stats:
		var stat_label = Label.new()
		var val = stat[1]
		var stat_name = stat[0]
		if stat_name == "CA" or stat_name == "HP":
			stat_label.text = "%s: %d" % [stat_name, val]
		elif val >= 0:
			stat_label.text = "%s: +%d" % [stat_name, val]
		else:
			stat_label.text = "%s: %d" % [stat_name, val]
		stat_label.add_theme_font_size_override("font_size", 12)
		stat_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		stats_container.add_child(stat_label)
	
	var select_label = Label.new()
	select_label.name = "SelectLabel"
	select_label.text = "[Seleccionar]"
	select_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_label.add_theme_font_size_override("font_size", 12)
	select_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	vbox.add_child(select_label)
	
	panel.gui_input.connect(_on_card_input.bind(index))
	
	return panel

func _build_feat_panel() -> void:
	_feat_panel = Control.new()
	_feat_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feat_panel.visible = false
	_root.add_child(_feat_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feat_panel.add_child(bg)

	_feat_title = Label.new()
	_feat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feat_title.add_theme_font_size_override("font_size", 32)
	_feat_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_feat_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_feat_title.offset_top = 80
	_feat_title.offset_bottom = 140
	_feat_panel.add_child(_feat_title)

	_feat_options_container = VBoxContainer.new()
	_feat_options_container.set_anchors_preset(Control.PRESET_CENTER)
	_feat_options_container.offset_left = -450
	_feat_options_container.offset_right = 450
	_feat_options_container.offset_top = -160
	_feat_options_container.offset_bottom = 200
	_feat_options_container.add_theme_constant_override("separation", 18)
	_feat_panel.add_child(_feat_options_container)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z: Elegir"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -60
	hint.offset_bottom = -20
	_feat_panel.add_child(hint)

func _begin_feat_selection() -> void:
	_choosing_feats = true
	_feat_step = 0
	_chosen_feats.clear()
	_show_feat_step()

func _show_feat_step() -> void:
	var char_index = _selected_indices[_feat_step]
	var char_data = _available_characters[char_index]
	var pool: Array = char_data.get("feat_pool", [])

	_feat_title.text = "%s — elige un feat" % char_data["name"]

	for child in _feat_options_container.get_children():
		child.queue_free()

	for feat_id in pool:
		var feat = DataLoader.get_feat(feat_id)
		var label = Label.new()
		label.text = "%s — %s" % [feat.get("name", feat_id), feat.get("description", "")]
		label.add_theme_font_size_override("font_size", 20)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(900, 0)
		_feat_options_container.add_child(label)

	_feat_selected_index = 0
	_update_feat_highlight()
	_feat_panel.visible = true

func _update_feat_highlight() -> void:
	var children = _feat_options_container.get_children()
	for i in range(children.size()):
		if i == _feat_selected_index:
			children[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			children[i].add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

func _handle_feat_input(event: InputEvent) -> void:
	if _feat_step >= _selected_indices.size():
		return
	var char_index = _selected_indices[_feat_step]
	var pool: Array = _available_characters[char_index].get("feat_pool", [])
	if pool.is_empty():
		return
	if event.is_action_pressed("move_up"):
		_feat_selected_index = maxi(0, _feat_selected_index - 1)
		_update_feat_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_feat_selected_index = mini(pool.size() - 1, _feat_selected_index + 1)
		_update_feat_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action1"):
		_chosen_feats[char_index] = pool[_feat_selected_index]
		_feat_step += 1
		if _feat_step >= _selected_indices.size():
			_finish_feat_selection()
		else:
			_show_feat_step()
		get_viewport().set_input_as_handled()

func _finish_feat_selection() -> void:
	_choosing_feats = false
	GameState.party.clear()
	for i in _selected_indices:
		var c = _available_characters[i]
		var member = GameState.create_party_member(c)
		var feat_id = _chosen_feats.get(i, "")
		member["feat"] = feat_id
		_apply_feat_effects(member, feat_id)
		GameState.party.append(member)

	SceneFlow.change_scene("res://scenes/exploration/Dungeon.tscn")

## Applies the feats whose effect can be resolved once, at party creation (a flat stat
## change or a bonus skill). The rest (per-battle charges, combat-time hooks) are read
## directly from member["feat"] by BattleController where relevant.
func _apply_feat_effects(member: Dictionary, feat_id: String) -> void:
	if feat_id == "":
		return
	var feat = DataLoader.get_feat(feat_id)
	match feat.get("effect", ""):
		"hp_bonus_pct":
			var bonus: float = feat.get("value", 0)
			member["max_hp"] = int(member["max_hp"] * (1.0 + bonus / 100.0))
			member["hp"] = member["max_hp"]
		"ca_bonus_flat":
			member["ca"] += int(feat.get("value", 0))
		"damage_bonus_flat":
			member["damage_bonus_flat"] = int(feat.get("value", 0))
		"heal_double":
			member["heal_multiplier"] = 2.0
		"bonus_skill":
			var skill_id = str(feat.get("value", ""))
			if skill_id != "" and not member["skills"].has(skill_id):
				member["skills"].append(skill_id)

func _unhandled_input(event: InputEvent) -> void:
	if _choosing_feats:
		_handle_feat_input(event)
		return
	if event.is_action_pressed("move_left"):
		if _cursor_row == 0:
			_cursor_index = maxi(0, _cursor_index - 1)
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		if _cursor_row == 0:
			_cursor_index = mini(_available_characters.size() - 1, _cursor_index + 1)
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_up"):
		if _cursor_row == 1:
			_cursor_row = 0
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		if _cursor_row == 0:
			_cursor_row = 1
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action1"):
		if _cursor_row == 0:
			_toggle_selection(_cursor_index)
		elif _cursor_row == 1 and _selected_indices.size() == MAX_PARTY_SIZE:
			_on_start_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action2"):
		if _cursor_row == 0 and _cursor_index in _selected_indices:
			_toggle_selection(_cursor_index)
		get_viewport().set_input_as_handled()

func _update_cursor() -> void:
	await get_tree().process_frame
	
	if _cursor_row == 0 and not _card_panels.is_empty():
		var card = _card_panels[_cursor_index]
		_cursor_highlight.position = card.global_position
		_cursor_highlight.size = card.size
	elif _cursor_row == 1:
		_cursor_highlight.position = _start_button.global_position
		_cursor_highlight.size = _start_button.size

func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cursor_index = index
		_cursor_row = 0
		_update_cursor()
		_toggle_selection(index)

func _toggle_selection(index: int) -> void:
	if index in _selected_indices:
		_selected_indices.erase(index)
	else:
		if _selected_indices.size() < MAX_PARTY_SIZE:
			_selected_indices.append(index)
	
	_update_display()

func _update_display() -> void:
	for i in range(_card_panels.size()):
		var card = _card_panels[i]
		var is_selected = i in _selected_indices
		
		var style = card.get_theme_stylebox("panel") as StyleBoxFlat
		if is_selected:
			style.border_color = Color(0.2, 0.8, 0.3)
		else:
			style.border_color = Color(0.3, 0.3, 0.4)
		
		var vbox = card.get_child(0) as VBoxContainer
		var select_label = vbox.get_child(vbox.get_child_count() - 1) as Label
		if is_selected:
			select_label.text = "[Seleccionado]"
			select_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		else:
			select_label.text = "[Seleccionar]"
			select_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	
	var can_start = _selected_indices.size() == MAX_PARTY_SIZE
	_start_button.disabled = not can_start
	
	if can_start:
		_message_label.text = ""
	else:
		_message_label.text = "Selecciona %d personajes" % (MAX_PARTY_SIZE - _selected_indices.size())
		_message_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _on_start_pressed() -> void:
	if _selected_indices.size() != MAX_PARTY_SIZE:
		return
	_begin_feat_selection()
