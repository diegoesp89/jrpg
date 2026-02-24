extends CanvasLayer
## BattleUI — The complete battle UI with menus, stats, sprites, and action log.

var _battle_controller = null

# UI Nodes
var _party_stats_container: VBoxContainer = null
var _enemy_stats_container: VBoxContainer = null
var _action_menu: VBoxContainer = null
var _skill_menu: VBoxContainer = null
var _item_menu: VBoxContainer = null
var _target_menu: VBoxContainer = null
var _log_label: RichTextLabel = null
var _turn_indicator: Label = null
var _battle_sprites_container: HBoxContainer = null
var _enemy_sprites_container: HBoxContainer = null

# State
enum MenuState { MAIN, SKILL, ITEM, TARGET_ENEMY, TARGET_ALLY }
var _menu_state: MenuState = MenuState.MAIN
var _selected_index: int = 0
var _pending_action: Dictionary = {}
var _menu_items: Array[String] = []
var _target_list: Array[Dictionary] = []
var _log_lines: Array[String] = []

const MAX_LOG_LINES = 6
const MENU_OPTIONS = ["Atacar", "Habilidad", "Objeto", "Defender", "Huir"]

func _ready() -> void:
	layer = 20
	_build_ui()

func setup(battle_ctrl) -> void:
	_battle_controller = battle_ctrl
	_battle_controller.action_performed.connect(_on_action_performed)
	_battle_controller.turn_changed.connect(_on_turn_changed)
	_battle_controller.hp_updated.connect(_on_hp_updated)
	_battle_controller.battle_ended.connect(_on_battle_ended)

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# --- Battle field (top 60%) ---
	var field = Control.new()
	field.set_anchors_preset(Control.PRESET_TOP_WIDE)
	field.custom_minimum_size = Vector2(0, 645)
	field.size = Vector2(1920, 645)
	root.add_child(field)

	# Party sprites (left side)
	_battle_sprites_container = HBoxContainer.new()
	_battle_sprites_container.position = Vector2(120, 220)
	_battle_sprites_container.add_theme_constant_override("separation", 30)
	field.add_child(_battle_sprites_container)

	# Enemy sprites (right side)
	_enemy_sprites_container = HBoxContainer.new()
	_enemy_sprites_container.position = Vector2(1150, 180)
	_enemy_sprites_container.add_theme_constant_override("separation", 30)
	field.add_child(_enemy_sprites_container)

	# --- Bottom panel (40%) ---
	var bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -435
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.05, 0.05, 0.12, 0.95)
	bottom_style.border_color = Color(0.5, 0.45, 0.2)
	bottom_style.border_width_top = 2
	bottom.add_theme_stylebox_override("panel", bottom_style)
	root.add_child(bottom)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_hbox.add_theme_constant_override("separation", 10)
	bottom.add_child(bottom_hbox)

	# Left: Party stats
	_party_stats_container = VBoxContainer.new()
	_party_stats_container.custom_minimum_size = Vector2(650, 0)
	var stats_margin = MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 15)
	stats_margin.add_theme_constant_override("margin_top", 10)
	stats_margin.add_child(_party_stats_container)
	bottom_hbox.add_child(stats_margin)

	# Center: Action menu
	var menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(450, 0)
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.08, 0.08, 0.15)
	menu_style.border_color = Color(0.4, 0.35, 0.15)
	menu_style.set_border_width_all(1)
	menu_style.set_content_margin_all(10)
	menu_panel.add_theme_stylebox_override("panel", menu_style)
	bottom_hbox.add_child(menu_panel)

	_action_menu = VBoxContainer.new()
	_action_menu.add_theme_constant_override("separation", 4)
	menu_panel.add_child(_action_menu)

	# Also create hidden skill/item/target menus (reuse _action_menu by swapping content)
	_skill_menu = VBoxContainer.new()
	_skill_menu.visible = false
	menu_panel.add_child(_skill_menu)

	_item_menu = VBoxContainer.new()
	_item_menu.visible = false
	menu_panel.add_child(_item_menu)

	_target_menu = VBoxContainer.new()
	_target_menu.visible = false
	menu_panel.add_child(_target_menu)

	# Right: Log
	var log_panel = PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color(0.03, 0.03, 0.08)
	log_style.set_content_margin_all(8)
	log_panel.add_theme_stylebox_override("panel", log_style)
	bottom_hbox.add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = false
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 39)
	log_panel.add_child(_log_label)

	# Turn indicator
	_turn_indicator = Label.new()
	_turn_indicator.position = Vector2(820, 15)
	_turn_indicator.add_theme_font_size_override("font_size", 54)
	_turn_indicator.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	field.add_child(_turn_indicator)

	# Enemy stats (above enemy sprites)
	_enemy_stats_container = VBoxContainer.new()
	_enemy_stats_container.position = Vector2(1150, 70)
	field.add_child(_enemy_stats_container)

func _unhandled_input(event: InputEvent) -> void:
	if not _battle_controller or not _battle_controller.is_waiting_for_player():
		return

	match _menu_state:
		MenuState.MAIN:
			_handle_main_menu_input(event)
		MenuState.SKILL:
			_handle_sub_menu_input(event)
		MenuState.ITEM:
			_handle_sub_menu_input(event)
		MenuState.TARGET_ENEMY:
			_handle_target_input(event)
		MenuState.TARGET_ALLY:
			_handle_target_input(event)

func _handle_main_menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(_action_menu)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(MENU_OPTIONS.size() - 1, _selected_index + 1)
		_update_menu_highlight(_action_menu)
	elif event.is_action_pressed("action1"):
		_select_main_option(_selected_index)
	elif event.is_action_pressed("action2"):
		pass  # Can't go back from main menu

func _handle_sub_menu_input(event: InputEvent) -> void:
	if _menu_items.is_empty():
		if event.is_action_pressed("action2"):
			_back_to_main()
		return
	var container = _skill_menu if _menu_state == MenuState.SKILL else _item_menu
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(container)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_menu_items.size() - 1, _selected_index + 1)
		_update_menu_highlight(container)
	elif event.is_action_pressed("action1"):
		_select_sub_option(_selected_index)
	elif event.is_action_pressed("action2"):
		_back_to_main()

func _handle_target_input(event: InputEvent) -> void:
	if _target_list.is_empty():
		if event.is_action_pressed("action2"):
			_back_to_main()
		return
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(_target_menu)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_target_list.size() - 1, _selected_index + 1)
		_update_menu_highlight(_target_menu)
	elif event.is_action_pressed("action1"):
		_select_target(_selected_index)
	elif event.is_action_pressed("action2"):
		_back_to_main()

func _select_main_option(idx: int) -> void:
	match idx:
		0:  # Attack
			_pending_action = { "type": "attack" }
			_show_target_menu(false)
		1:  # Skill
			_show_skill_menu()
		2:  # Item
			_show_item_menu()
		3:  # Defend
			_battle_controller.player_action({ "type": "defend" })
			_hide_all_menus()
		4:  # Flee
			_battle_controller.player_action({ "type": "flee" })
			_hide_all_menus()

func _show_skill_menu() -> void:
	var current = _battle_controller._turn_system.get_current_combatant()
	var skills = current.get("skills", [])
	_menu_items.clear()

	_clear_container(_skill_menu)
	for skill_id in skills:
		var skill = DataLoader.get_skill(skill_id)
		if skill:
			_menu_items.append(skill_id)
			var label = Label.new()
			label.text = "%s (MP: %d)" % [skill["name"], skill["mp_cost"]]
			label.add_theme_font_size_override("font_size", 42)
			_skill_menu.add_child(label)

	if _menu_items.is_empty():
		var label = Label.new()
		label.text = "Sin habilidades"
		label.add_theme_font_size_override("font_size", 42)
		_skill_menu.add_child(label)

	_menu_state = MenuState.SKILL
	_selected_index = 0
	_action_menu.visible = false
	_skill_menu.visible = true
	_update_menu_highlight(_skill_menu)

func _show_item_menu() -> void:
	_menu_items.clear()
	_clear_container(_item_menu)

	for item in GameState.inventory:
		if item["quantity"] > 0:
			_menu_items.append(item["id"])
			var label = Label.new()
			label.text = "%s x%d" % [item["name"], item["quantity"]]
			label.add_theme_font_size_override("font_size", 42)
			_item_menu.add_child(label)

	if _menu_items.is_empty():
		var label = Label.new()
		label.text = "Sin objetos"
		label.add_theme_font_size_override("font_size", 42)
		_item_menu.add_child(label)

	_menu_state = MenuState.ITEM
	_selected_index = 0
	_action_menu.visible = false
	_item_menu.visible = true
	_update_menu_highlight(_item_menu)

func _show_target_menu(ally: bool) -> void:
	_target_list.clear()
	_clear_container(_target_menu)

	var group = _battle_controller.get_party() if ally else _battle_controller.get_enemies()
	for c in group:
		if c.get("hp", 0) > 0:
			_target_list.append(c)
			var label = Label.new()
			label.text = "%s (HP: %d/%d)" % [c["name"], c["hp"], c["max_hp"]]
			label.add_theme_font_size_override("font_size", 42)
			_target_menu.add_child(label)

	_menu_state = MenuState.TARGET_ENEMY if not ally else MenuState.TARGET_ALLY
	_selected_index = 0
	_action_menu.visible = false
	_skill_menu.visible = false
	_item_menu.visible = false
	_target_menu.visible = true
	_update_menu_highlight(_target_menu)

func _select_sub_option(idx: int) -> void:
	if idx >= _menu_items.size():
		return

	if _menu_state == MenuState.SKILL:
		var skill_id = _menu_items[idx]
		var skill = DataLoader.get_skill(skill_id)
		if skill:
			_pending_action = { "type": "skill", "skill": skill }
			var is_ally = skill.get("target_type", "") == "single_ally"
			if skill.get("target_type", "") == "all_enemies":
				# No target selection needed
				_battle_controller.player_action(_pending_action)
				_hide_all_menus()
			else:
				_show_target_menu(is_ally)
	elif _menu_state == MenuState.ITEM:
		var item_id = _menu_items[idx]
		var item = DataLoader.get_item(item_id)
		if item:
			_pending_action = { "type": "item", "item": item }
			_show_target_menu(true)  # Items target allies

func _select_target(idx: int) -> void:
	if idx >= _target_list.size():
		return

	_pending_action["target"] = _target_list[idx]
	_battle_controller.player_action(_pending_action)
	_hide_all_menus()

func _back_to_main() -> void:
	_menu_state = MenuState.MAIN
	_selected_index = 0
	_skill_menu.visible = false
	_item_menu.visible = false
	_target_menu.visible = false
	_action_menu.visible = true
	_update_menu_highlight(_action_menu)

func _hide_all_menus() -> void:
	_action_menu.visible = false
	_skill_menu.visible = false
	_item_menu.visible = false
	_target_menu.visible = false

func _on_turn_changed(combatant: Dictionary, is_player: bool) -> void:
	_turn_indicator.text = "Turno: %s" % combatant.get("name", "???")
	if is_player:
		_show_main_menu()
	else:
		_hide_all_menus()
	_update_all_stats()

func _show_main_menu() -> void:
	_clear_container(_action_menu)
	for option in MENU_OPTIONS:
		var label = Label.new()
		label.text = option
		label.add_theme_font_size_override("font_size", 45)
		_action_menu.add_child(label)

	_menu_state = MenuState.MAIN
	_selected_index = 0
	_action_menu.visible = true
	_skill_menu.visible = false
	_item_menu.visible = false
	_target_menu.visible = false
	_update_menu_highlight(_action_menu)

func _update_menu_highlight(container: VBoxContainer) -> void:
	var children = container.get_children()
	for i in range(children.size()):
		if children[i] is Label:
			if i == _selected_index:
				children[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
				children[i].text = "> " + children[i].text.strip_edges().trim_prefix("> ")
			else:
				children[i].add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
				children[i].text = "  " + children[i].text.strip_edges().trim_prefix("> ")

func _on_action_performed(log_text: String) -> void:
	_log_lines.append(log_text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)

func _on_hp_updated() -> void:
	_update_all_stats()
	_update_battle_sprites()

func _on_battle_ended(result: String) -> void:
	_hide_all_menus()

func _update_all_stats() -> void:
	# Party stats
	_clear_container(_party_stats_container)
	if _battle_controller:
		for p in _battle_controller.get_party():
			var label = Label.new()
			var status = " [MUERTO]" if p["hp"] <= 0 else ""
			var def_str = " [DEF]" if p.get("defending", false) else ""
			label.text = "%s  HP:%d/%d  MP:%d/%d%s%s" % [
				p["name"], p["hp"], p["max_hp"], p["mp"], p["max_mp"], def_str, status
			]
			label.add_theme_font_size_override("font_size", 39)
			if p["hp"] <= 0:
				label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
			else:
				label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
			_party_stats_container.add_child(label)

	# Enemy stats
	_clear_container(_enemy_stats_container)
	if _battle_controller:
		for e in _battle_controller.get_enemies():
			var label = Label.new()
			var status = " [MUERTO]" if e["hp"] <= 0 else ""
			label.text = "%s  HP:%d/%d%s" % [e["name"], e["hp"], e["max_hp"], status]
			label.add_theme_font_size_override("font_size", 39)
			if e["hp"] <= 0:
				label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
			else:
				label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
			_enemy_stats_container.add_child(label)

func _update_battle_sprites() -> void:
	pass  # Sprites are static placeholders, created once in setup_sprites

func setup_sprites(party: Array, enemies: Array) -> void:
	_clear_container(_battle_sprites_container)
	_clear_container(_enemy_sprites_container)

	# Party sprites (blue squares)
	for p in party:
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_END
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(64, 80)
		rect.color = Color(0.2, 0.4, 0.9) if p["hp"] > 0 else Color(0.3, 0.3, 0.3)
		vbox.add_child(rect)
		var name_label = Label.new()
		name_label.text = p["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 33)
		vbox.add_child(name_label)
		_battle_sprites_container.add_child(vbox)

	# Enemy sprites (red rectangles)
	for e in enemies:
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_END
		var rect = ColorRect.new()
		# Boss is bigger
		if "guardian" in e.get("base_id", e.get("id", "")):
			rect.custom_minimum_size = Vector2(100, 120)
		else:
			rect.custom_minimum_size = Vector2(64, 80)
		rect.color = Color(0.8, 0.2, 0.15) if e["hp"] > 0 else Color(0.3, 0.3, 0.3)
		vbox.add_child(rect)
		var name_label = Label.new()
		name_label.text = e["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 33)
		vbox.add_child(name_label)
		_enemy_sprites_container.add_child(vbox)

func _clear_container(container) -> void:
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
