extends CanvasLayer
class_name BattleUI
## BattleUI — The complete battle UI

var _battle_controller = null

# UI Nodes
var _party_stats_container: VBoxContainer = null
var _action_menu: VBoxContainer = null
var _skill_menu: VBoxContainer = null
var _item_menu: VBoxContainer = null
var _target_menu: VBoxContainer = null
var _log_label: RichTextLabel = null
var _turn_indicator: Label = null
var _battle_sprites_container: HBoxContainer = null
var _enemy_sprites_container: HBoxContainer = null
var _float_overlay: Control = null

# Initiative panel reference
var _initiative_panel: PanelContainer = null
var _initiative_list: VBoxContainer = null

# HP bar references: array of { "bar": ColorRect, "combatant": Dictionary, "is_player": bool, "max_width": float }
var _hp_bars: Array[Dictionary] = []

# Maps combatant id (String) → sprite VBox node (for floating damage numbers)
var _combatant_sprite_map: Dictionary = {}

# State
enum MenuState { MAIN, SKILL, ITEM, TARGET_ENEMY, TARGET_ALLY }
var _menu_state: MenuState = MenuState.MAIN
var _selected_index: int = 0
var _pending_action: Dictionary = {}
var _menu_items: Array[String] = []
var _target_list: Array[Dictionary] = []
var _log_lines: Array[String] = []
var _is_boss: bool = false
var _current_turn_combatant: Dictionary = {}
var _current_turn_is_player: bool = false

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
	_battle_controller.damage_dealt.connect(_on_damage_dealt)

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
	field.clip_contents = false
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
	
	# Initiative list (top-right)
	var init_panel = PanelContainer.new()
	init_panel.name = "InitiativePanel"
	init_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	init_panel.offset_left = -220
	init_panel.offset_top = 10
	init_panel.offset_right = -10
	init_panel.offset_bottom = 200
	var init_style = StyleBoxFlat.new()
	init_style.bg_color = Color(0.05, 0.05, 0.12, 0.8)
	init_style.border_color = Color(0.3, 0.3, 0.3)
	init_style.set_border_width_all(1)
	init_panel.add_theme_stylebox_override("panel", init_style)
	root.add_child(init_panel)
	_initiative_panel = init_panel
	
	var init_vbox = VBoxContainer.new()
	init_vbox.name = "InitiativeList"
	init_vbox.add_theme_constant_override("separation", 2)
	init_panel.add_child(init_vbox)
	_initiative_list = init_vbox

	# Floating damage number overlay (on top of everything)
	_float_overlay = Control.new()
	_float_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_float_overlay)

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
	var max_index = MENU_OPTIONS.size() - 1
	# In boss fights, cap navigation before "Huir" (index 4)
	if _is_boss:
		max_index = 3
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(_action_menu)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(max_index, _selected_index + 1)
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
	# For enemies: count how many share each base name to decide numbering
	var base_name_counts: Dictionary = {}
	if not ally:
		for c in group:
			if c.get("hp", 0) > 0:
				var bname = c.get("name", "???")
				base_name_counts[bname] = base_name_counts.get(bname, 0) + 1
	var base_name_index: Dictionary = {}
	for c in group:
		if c.get("hp", 0) > 0:
			_target_list.append(c)
			var label = Label.new()
			if ally:
				label.text = "%s (HP: %d/%d)" % [c["name"], c["hp"], c["max_hp"]]
			else:
				var bname = c.get("name", "???")
				if base_name_counts.get(bname, 1) > 1:
					base_name_index[bname] = base_name_index.get(bname, 0) + 1
					label.text = "%s %d" % [bname, base_name_index[bname]]
				else:
					label.text = bname
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
	_current_turn_combatant = combatant
	_current_turn_is_player = is_player
	# Refresh boss flag (encounter data available after start_battle)
	if _battle_controller:
		_is_boss = _battle_controller.is_boss_encounter()
	if is_player:
		_show_main_menu()
	else:
		_hide_all_menus()
	_update_all_stats()
	_update_initiative_list()

func _show_main_menu() -> void:
	_clear_container(_action_menu)
	for i in range(MENU_OPTIONS.size()):
		var option = MENU_OPTIONS[i]
		var label = Label.new()
		label.text = option
		label.add_theme_font_size_override("font_size", 45)
		# Grey out "Huir" (index 4) in boss fights
		if i == 4 and _is_boss:
			label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
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
			# Keep greyed-out "Huir" in boss fights regardless of selection
			var is_disabled = (container == _action_menu and i == 4 and _is_boss)
			if is_disabled:
				children[i].add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
				children[i].text = "  " + children[i].text.strip_edges().trim_prefix("> ")
			elif i == _selected_index:
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
	# Party stats (text in bottom panel)
	_clear_container(_party_stats_container)
	if _battle_controller:
		for p in _battle_controller.get_party():
			var label = Label.new()
			var status = " [MUERTO]" if p["hp"] <= 0 else ""
			var def_str = " [DEF]" if p.get("defending", false) else ""
			var mp = p.get("mp", 0)
			var max_mp = p.get("max_mp", 0)
			label.text = "%s  HP:%d/%d  MP:%d/%d%s%s" % [
				p["name"], p["hp"], p["max_hp"], mp, max_mp, def_str, status
			]
			label.add_theme_font_size_override("font_size", 39)
			# Color logic:
			# - Dead: dim gray
			# - Current turn (only if a player char has the turn): yellow
			# - HP <= 50%: red
			# - Otherwise: white
			if p["hp"] <= 0:
				label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
			elif _current_turn_is_player and p == _current_turn_combatant:
				label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			elif float(p["hp"]) / maxf(float(p["max_hp"]), 1.0) <= 0.5:
				label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))
			else:
				label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
			_party_stats_container.add_child(label)

	# Update HP bars above sprites (enemies only)
	_update_hp_bars()

func _update_initiative_list() -> void:
	if not _battle_controller:
		return
	
	if not _initiative_panel or not _initiative_list:
		return
	
	for child in _initiative_list.get_children():
		child.queue_free()
	
	var turn_system = _battle_controller.get_turn_system()
	if not turn_system:
		return
	
	var queue = turn_system.get_turn_queue()
	var current_id = _current_turn_combatant.get("id", "")
	
	var title = Label.new()
	title.text = "Iniciativa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_initiative_list.add_child(title)
	
	for entry in queue:
		var combatant = entry.get("combatant", {})
		if combatant.get("hp", 0) <= 0:
			continue
		
		var name = combatant.get("name", "???")
		var is_current = combatant.get("id", "") == current_id
		
		var label = Label.new()
		label.text = name
		label.add_theme_font_size_override("font_size", 12)
		if is_current:
			label.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
		elif combatant.get("is_player", false):
			label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
		else:
			label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		_initiative_list.add_child(label)

func _update_battle_sprites() -> void:
	# Update party sprite colors based on alive/dead state
	if _battle_controller:
		var party = _battle_controller.get_party()
		var party_children = _battle_sprites_container.get_children()
		for i in range(mini(party.size(), party_children.size())):
			var vbox = party_children[i]
			# First child is the ColorRect sprite
			if vbox.get_child_count() > 0 and vbox.get_child(0) is ColorRect:
				var rect = vbox.get_child(0) as ColorRect
				rect.color = Color(0.2, 0.4, 0.9) if party[i]["hp"] > 0 else Color(0.3, 0.3, 0.3)
	_update_hp_bars()

func _update_hp_bars() -> void:
	for entry in _hp_bars:
		var bar: ColorRect = entry["bar"]
		var c: Dictionary = entry["combatant"]
		var max_w: float = entry["max_width"]
		var is_player: bool = entry["is_player"]

		var hp = float(c.get("hp", 0))
		var max_hp = float(c.get("max_hp", 1))
		var ratio = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)

		bar.custom_minimum_size.x = max_w * ratio
		bar.size.x = max_w * ratio

		if hp <= 0:
			bar.color = Color(0.3, 0.3, 0.3)
		elif ratio <= 0.5:
			bar.color = Color(0.9, 0.15, 0.1)
		else:
			if is_player:
				bar.color = Color(0.9, 0.9, 0.9)
			else:
				bar.color = Color(0.2, 0.85, 0.2)

func _create_hp_bar(combatant: Dictionary, bar_width: float, is_player: bool) -> Control:
	## Creates an HP bar widget: background (dark) + foreground (colored).
	## Returns the container Control. Stores the foreground ref in _hp_bars.
	var container = Control.new()
	container.custom_minimum_size = Vector2(bar_width, 8)

	# Background
	var bg = ColorRect.new()
	bg.custom_minimum_size = Vector2(bar_width, 8)
	bg.color = Color(0.15, 0.15, 0.15)
	container.add_child(bg)

	# Foreground
	var fg = ColorRect.new()
	fg.custom_minimum_size = Vector2(bar_width, 8)
	fg.color = Color(0.9, 0.9, 0.9) if is_player else Color(0.2, 0.85, 0.2)
	container.add_child(fg)

	_hp_bars.append({
		"bar": fg,
		"combatant": combatant,
		"is_player": is_player,
		"max_width": bar_width,
	})

	return container

func setup_sprites(party: Array, enemies: Array) -> void:
	_clear_container(_battle_sprites_container)
	_clear_container(_enemy_sprites_container)
	_hp_bars.clear()
	_combatant_sprite_map.clear()

	# Party sprites (blue squares) — no HP bar (stats shown in HUD panel)
	for p in party:
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_END
		var sprite_w := 64.0
		# Sprite
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(sprite_w, 80)
		rect.color = Color(0.2, 0.4, 0.9) if p["hp"] > 0 else Color(0.3, 0.3, 0.3)
		vbox.add_child(rect)
		# Name
		var name_label = Label.new()
		name_label.text = p["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 33)
		vbox.add_child(name_label)
		_battle_sprites_container.add_child(vbox)
		_combatant_sprite_map[p.get("id", "")] = vbox

	# Enemy sprites (red rectangles) with HP bar above
	for e in enemies:
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_END
		var is_boss_sprite = "guardian" in e.get("base_id", e.get("id", ""))
		var sprite_w := 100.0 if is_boss_sprite else 64.0
		var sprite_h := 120.0 if is_boss_sprite else 80.0
		# HP bar
		var hp_bar = _create_hp_bar(e, sprite_w, false)
		vbox.add_child(hp_bar)
		# Sprite
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(sprite_w, sprite_h)
		rect.color = Color(0.8, 0.2, 0.15) if e["hp"] > 0 else Color(0.3, 0.3, 0.3)
		vbox.add_child(rect)
		# Name
		var name_label = Label.new()
		name_label.text = e["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 33)
		vbox.add_child(name_label)
		_enemy_sprites_container.add_child(vbox)
		_combatant_sprite_map[e.get("id", "")] = vbox

func _on_damage_dealt(target: Dictionary, amount: int, is_heal: bool) -> void:
	_spawn_floating_number(target, amount, is_heal)

func _spawn_floating_number(target: Dictionary, amount: int, is_heal: bool) -> void:
	if not _float_overlay or amount <= 0:
		return
	var target_id = target.get("id", "")
	var vbox = _combatant_sprite_map.get(target_id)
	if not vbox or not is_instance_valid(vbox):
		return

	var label = Label.new()
	label.text = str(amount) if not is_heal else "+" + str(amount)
	label.add_theme_font_size_override("font_size", 48)
	if is_heal:
		label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	else:
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_float_overlay.add_child(label)
	# Wait one frame so layout resolves and we can read positions
	await label.get_tree().process_frame
	if not is_instance_valid(label):
		return
	var vbox_center_x = vbox.global_position.x + vbox.size.x * 0.5
	var vbox_top_y = vbox.global_position.y
	label.position = Vector2(vbox_center_x - 30, vbox_top_y - 20)

	var start_y = label.position.y
	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y - 50.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(label.queue_free)

func _clear_container(container) -> void:
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
