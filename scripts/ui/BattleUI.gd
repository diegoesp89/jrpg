extends CanvasLayer
class_name BattleUI
## BattleUI — The complete battle UI

var _battle_controller = null

# UI Nodes
var _party_stats_container: VBoxContainer = null
var _action_menu: VBoxContainer = null
var _skill_menu_wrapper: VBoxContainer = null  # holds _skill_menu + _skill_tooltip_label together
var _skill_menu: VBoxContainer = null
var _skill_tooltip_label: RichTextLabel = null
var _item_menu: VBoxContainer = null
var _target_menu: VBoxContainer = null
var _position_menu: VBoxContainer = null
var _premonition_menu: VBoxContainer = null
var _log_label: RichTextLabel = null
var _turn_indicator: Label = null
var _battle_sprites_container: HBoxContainer = null
var _enemy_sprites_container: HBoxContainer = null

## One VBoxContainer per position zone (index-matched to POSITION_NAMES/combatant["position"]:
## 0=Adelante, 1=Medio, 2=Retaguardia), holding whichever party members currently sit there
## stacked top to bottom. The zones themselves are laid out left to right (see _build_ui).
var _position_zone_boxes: Array[VBoxContainer] = []
## Same three bands for the enemy side, mirrored: their Adelante is the column nearest the party,
## so the two front ranks face each other across the middle of the screen — which is where melee
## actually happens. Index-matched to combatant["position"] exactly like the party's.
var _enemy_zone_boxes: Array[VBoxContainer] = []
## Painted underneath everything: one translucent slab per zone column, warmer on the two facing
## front ranks, so the bands read as places instead of just labels.
var _zone_backdrop: Control = null
var _float_overlay: Control = null

## Transparent Control sitting over the battle field, drawing a line from every combatant to the
## opponent it is locked onto. Redrawn from _update_all_stats(), so it tracks engagements as they
## form and break without needing a signal of its own.
var _engagement_overlay: Control = null

# Initiative panel reference
var _initiative_panel: PanelContainer = null
var _initiative_list: VBoxContainer = null

# HP bar references: array of { "bar": ColorRect, "combatant": Dictionary, "is_player": bool, "max_width": float }
var _hp_bars: Array[Dictionary] = []

# Maps combatant id (String) → sprite VBox node (for floating damage numbers)
var _combatant_sprite_map: Dictionary = {}

# State
enum MenuState { MAIN, SKILL, ITEM, TARGET_ENEMY, TARGET_ALLY, POSITION, PREMONITION }
const POSITION_NAMES := ["Adelante", "Medio", "Retaguardia"]
var _menu_state: MenuState = MenuState.MAIN
var _selected_index: int = 0
var _pending_action: Dictionary = {}
var _menu_items: Array[String] = []
var _target_list: Array[Dictionary] = []
## Zone numbers the "Mover" menu is currently offering, index-matched to its rows (the menu only
## lists zones adjacent to where the current combatant stands, so row 0 is not zone 0).
var _position_destinations: Array[int] = []
var _log_lines: Array[String] = []
var _is_boss: bool = false
var _current_turn_combatant: Dictionary = {}
var _current_turn_is_player: bool = false

const MAX_LOG_LINES = 6
const MENU_OPTIONS = ["Atacar", "Habilidad", "Objeto", "Defender", "Mover", "Huir"]

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
	_battle_controller.attack_started.connect(play_attack_lunge)

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

	# Zone slabs go in first so they sit behind every sprite.
	_zone_backdrop = Control.new()
	_zone_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zone_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_backdrop.draw.connect(_draw_zone_backdrop)
	field.add_child(_zone_backdrop)

	# Party sprites (left side) — the three movement zones are laid out left to right, and the
	# characters standing in each one stack top to bottom inside it. Column order is reversed
	# (Retaguardia leftmost, Adelante rightmost) so the front line ends up closest to the enemy
	# sprites on the right, matching where each zone actually is on the battlefield.
	_battle_sprites_container = HBoxContainer.new()
	# Starts higher up than the enemy row: a zone column holding the whole party needs the room.
	_battle_sprites_container.position = Vector2(120, 90)
	_battle_sprites_container.add_theme_constant_override("separation", 30)
	field.add_child(_battle_sprites_container)

	_position_zone_boxes.clear()
	_position_zone_boxes.resize(POSITION_NAMES.size())
	for i in range(POSITION_NAMES.size() - 1, -1, -1):
		var zone_column = VBoxContainer.new()
		zone_column.add_theme_constant_override("separation", 10)
		var zone_label = Label.new()
		zone_label.text = POSITION_NAMES[i]
		zone_label.custom_minimum_size = Vector2(150, 0)
		zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone_label.add_theme_font_size_override("font_size", 20)
		zone_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		zone_column.add_child(zone_label)
		var chars_box = VBoxContainer.new()
		chars_box.add_theme_constant_override("separation", 14)
		zone_column.add_child(chars_box)
		_battle_sprites_container.add_child(zone_column)
		_position_zone_boxes[i] = chars_box

	# Enemy sprites (right side), in the same three bands as the party but mirrored, so the two
	# Adelante columns end up adjacent in the centre of the screen.
	_enemy_sprites_container = HBoxContainer.new()
	_enemy_sprites_container.position = Vector2(1010, 90)
	_enemy_sprites_container.add_theme_constant_override("separation", 30)
	field.add_child(_enemy_sprites_container)

	_enemy_zone_boxes.clear()
	_enemy_zone_boxes.resize(POSITION_NAMES.size())
	for i in range(POSITION_NAMES.size()):
		var zone_column = VBoxContainer.new()
		zone_column.add_theme_constant_override("separation", 10)
		var zone_label = Label.new()
		zone_label.text = POSITION_NAMES[i]
		zone_label.custom_minimum_size = Vector2(150, 0)
		zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone_label.add_theme_font_size_override("font_size", 20)
		zone_label.add_theme_color_override("font_color", Color(0.62, 0.5, 0.5))
		zone_column.add_child(zone_label)
		var chars_box = VBoxContainer.new()
		chars_box.add_theme_constant_override("separation", 14)
		zone_column.add_child(chars_box)
		_enemy_sprites_container.add_child(zone_column)
		_enemy_zone_boxes[i] = chars_box

	# Added last so the engagement lines land on top of both sprite groups.
	_engagement_overlay = Control.new()
	_engagement_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_engagement_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_engagement_overlay.draw.connect(_draw_engagement_lines)
	field.add_child(_engagement_overlay)

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
	# The skill list and its tooltip are wrapped together so they stack instead of overlapping
	# (menu_panel's other menus are toggled one-at-a-time as direct children; a tooltip sibling
	# next to _skill_menu would render on top of it, not below).
	_skill_menu_wrapper = VBoxContainer.new()
	_skill_menu_wrapper.visible = false
	menu_panel.add_child(_skill_menu_wrapper)

	_skill_menu = VBoxContainer.new()
	_skill_menu_wrapper.add_child(_skill_menu)

	_skill_tooltip_label = RichTextLabel.new()
	_skill_tooltip_label.bbcode_enabled = false
	_skill_tooltip_label.fit_content = true
	_skill_tooltip_label.custom_minimum_size = Vector2(0, 90)
	_skill_tooltip_label.add_theme_font_size_override("normal_font_size", 26)
	_skill_tooltip_label.add_theme_color_override("default_color", Color(0.7, 0.7, 0.75))
	_skill_menu_wrapper.add_child(_skill_tooltip_label)

	_item_menu = VBoxContainer.new()
	_item_menu.visible = false
	menu_panel.add_child(_item_menu)

	_target_menu = VBoxContainer.new()
	_target_menu.visible = false
	menu_panel.add_child(_target_menu)

	_position_menu = VBoxContainer.new()
	_position_menu.visible = false
	menu_panel.add_child(_position_menu)

	_premonition_menu = VBoxContainer.new()
	_premonition_menu.visible = false
	menu_panel.add_child(_premonition_menu)

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
		MenuState.POSITION:
			_handle_position_input(event)
		MenuState.PREMONITION:
			_handle_premonition_input(event)

func _handle_main_menu_input(event: InputEvent) -> void:
	var max_index = MENU_OPTIONS.size() - 1
	# In boss fights, cap navigation before "Huir" (the last option)
	if _is_boss:
		max_index = MENU_OPTIONS.size() - 2
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
		if _menu_state == MenuState.SKILL:
			_update_skill_tooltip()
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_menu_items.size() - 1, _selected_index + 1)
		_update_menu_highlight(container)
		if _menu_state == MenuState.SKILL:
			_update_skill_tooltip()
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
			var current = _battle_controller.get_turn_system().get_current_combatant()
			if current.get("premonition_roll", 0) > 0:
				_show_premonition_menu(current["premonition_roll"])
			else:
				_show_target_menu(false)
		1:  # Skill
			_show_skill_menu()
		2:  # Item
			_show_item_menu()
		3:  # Defend
			_battle_controller.player_action({ "type": "defend" })
			_hide_all_menus()
		4:  # Move
			_show_position_menu()
		5:  # Flee
			_battle_controller.player_action({ "type": "flee" })
			_hide_all_menus()

## Only the zones next to the one you're standing in — you advance or fall back one step, you
## don't teleport from Retaguardia to Adelante. _position_destinations keeps the menu row index
## mapped back to the actual zone number.
func _show_position_menu() -> void:
	_clear_container(_position_menu)
	_position_destinations.clear()
	var current = _battle_controller.get_turn_system().get_current_combatant()
	var here := int(current.get("position", 0))
	for i in range(POSITION_NAMES.size()):
		if absi(i - here) != 1:
			continue
		_position_destinations.append(i)
		var label = Label.new()
		label.text = POSITION_NAMES[i]
		# Leaving a lock hands every opponent engaged with you a free swing — flag it before
		# the player commits, not after.
		if not Combatant.engagement_partners(current, _battle_controller.get_enemies()).is_empty():
			label.text += "  (provoca ataque de oportunidad)"
		label.add_theme_font_size_override("font_size", 42)
		_position_menu.add_child(label)

	_menu_state = MenuState.POSITION
	_selected_index = 0
	_action_menu.visible = false
	_position_menu.visible = true
	_update_menu_highlight(_position_menu)

func _show_premonition_menu(roll: int) -> void:
	_clear_container(_premonition_menu)
	var opt1 = Label.new()
	opt1.text = "Tirar dados"
	opt1.add_theme_font_size_override("font_size", 42)
	_premonition_menu.add_child(opt1)
	var opt2 = Label.new()
	opt2.text = "Usar premonición (%d)" % roll
	opt2.add_theme_font_size_override("font_size", 42)
	_premonition_menu.add_child(opt2)

	_menu_state = MenuState.PREMONITION
	_selected_index = 0
	_action_menu.visible = false
	_premonition_menu.visible = true
	_update_menu_highlight(_premonition_menu)

func _handle_premonition_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(_premonition_menu)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(1, _selected_index + 1)
		_update_menu_highlight(_premonition_menu)
	elif event.is_action_pressed("action1"):
		_pending_action["use_premonition"] = (_selected_index == 1)
		_show_target_menu(false)
	elif event.is_action_pressed("action2"):
		_back_to_main()

func _handle_position_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_menu_highlight(_position_menu)
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_position_destinations.size() - 1, _selected_index + 1)
		_update_menu_highlight(_position_menu)
	elif event.is_action_pressed("action1"):
		if _selected_index < _position_destinations.size():
			_battle_controller.player_action({ "type": "move", "target_position": _position_destinations[_selected_index] })
			_hide_all_menus()
	elif event.is_action_pressed("action2"):
		_back_to_main()

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
	_skill_menu_wrapper.visible = true
	_update_menu_highlight(_skill_menu)
	_update_skill_tooltip()

## Shows the currently-highlighted skill's description below the skill list (empty if there's
## nothing selectable, e.g. "Sin habilidades").
func _update_skill_tooltip() -> void:
	if _menu_items.is_empty() or _selected_index >= _menu_items.size():
		_skill_tooltip_label.text = ""
		return
	var skill = DataLoader.get_skill(_menu_items[_selected_index])
	_skill_tooltip_label.text = skill.get("description", "")

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

## Whether the action awaiting a target resolves as magic (auto-hit, tolled in damage) rather
## than as a roll (tolled in accuracy). Basic attacks and physical skills are rolls.
func _pending_is_magical() -> bool:
	var skill: Dictionary = _pending_action.get("skill", {})
	if skill.is_empty():
		return false
	return str(skill.get("effect_type", "")) == "magical"

func _show_target_menu(ally: bool) -> void:
	_target_list.clear()
	_clear_container(_target_menu)

	var group = _battle_controller.get_party() if ally else _battle_controller.get_enemies()
	var current = _battle_controller.get_turn_system().get_current_combatant()
	# For enemies: count how many share each base name to decide numbering
	var base_name_counts: Dictionary = {}
	if not ally:
		for c in group:
			if c.get("hp", 0) > 0:
				var bname = c.get("name", "???")
				base_name_counts[bname] = base_name_counts.get(bname, 0) + 1
	var base_name_index: Dictionary = {}
	for c in group:
		if c.get("hp", 0) <= 0:
			continue
		# Enemies out of reach (a protected back rank, or anything at all while a melee fighter is
		# stuck in Retaguardia) are left off the list entirely rather than shown and rejected.
		if not ally and not Combatant.can_target(current, c, group):
			continue
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
			# Both tolls get spelled out before the player commits: turning away from your own
			# melee, and reaching past the enemy screen. Which currency the guard toll charges
			# depends on the action — magic pays in damage, everything else in accuracy.
			var notes: Array = []
			if Combatant.breaks_engagement_focus(current, c):
				notes.append("desventaja")
			if Combatant.is_protected(c, group) and not Combatant.ignores_guard(current):
				notes.append("½ daño" if _pending_is_magical() else "desventaja")
			if not notes.is_empty():
				# One "desventaja" is the same as two — it never stacks.
				var seen := {}
				var unique: Array = []
				for note in notes:
					if not seen.has(note):
						seen[note] = true
						unique.append(note)
				label.text += "  (%s)" % ", ".join(unique)
		label.add_theme_font_size_override("font_size", 42)
		_target_menu.add_child(label)

	if _target_list.is_empty():
		var none = Label.new()
		none.text = "Nadie a tu alcance"
		none.add_theme_font_size_override("font_size", 34)
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_target_menu.add_child(none)

	_menu_state = MenuState.TARGET_ENEMY if not ally else MenuState.TARGET_ALLY
	_selected_index = 0
	_action_menu.visible = false
	_skill_menu_wrapper.visible = false
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
	_skill_menu_wrapper.visible = false
	_item_menu.visible = false
	_target_menu.visible = false
	_position_menu.visible = false
	_premonition_menu.visible = false
	_action_menu.visible = true
	_update_menu_highlight(_action_menu)

func _hide_all_menus() -> void:
	_action_menu.visible = false
	_skill_menu_wrapper.visible = false
	_item_menu.visible = false
	_target_menu.visible = false
	_position_menu.visible = false
	_premonition_menu.visible = false

func _on_turn_changed(combatant: Dictionary, is_player: bool) -> void:
	_turn_indicator.text = "Turno: %s" % combatant.get("name", "???")
	_current_turn_combatant = combatant
	_current_turn_is_player = is_player
	# Refresh flee-availability flag (encounter data available after start_battle) — covers
	# both real bosses and the sphinx guardian fight, either of which blocks fleeing.
	if _battle_controller:
		_is_boss = not _battle_controller.can_flee()
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
		# The odds of the "Huir" gamble go right above it, so it's an informed choice instead of
		# a blind one. A RichTextLabel (not a Label) on purpose: _update_menu_highlight only
		# treats Labels as selectable rows, so this line can't be cursored onto.
		if i == MENU_OPTIONS.size() - 1:
			var flee_hint = RichTextLabel.new()
			flee_hint.bbcode_enabled = false
			flee_hint.fit_content = true
			flee_hint.text = _flee_hint_text()
			flee_hint.add_theme_font_size_override("normal_font_size", 22)
			flee_hint.add_theme_color_override("default_color", Color(0.6, 0.6, 0.65))
			_action_menu.add_child(flee_hint)

		var label = Label.new()
		label.text = option
		label.add_theme_font_size_override("font_size", 45)
		# Grey out "Huir" (last option) in boss fights
		if i == MENU_OPTIONS.size() - 1 and _is_boss:
			label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
		_action_menu.add_child(label)

	_menu_state = MenuState.MAIN
	_selected_index = 0
	_action_menu.visible = true
	_skill_menu_wrapper.visible = false
	_item_menu.visible = false
	_target_menu.visible = false
	_position_menu.visible = false
	_premonition_menu.visible = false
	_update_menu_highlight(_action_menu)

## Only Labels count as selectable rows, and the option index is counted over those alone — any
## non-Label child (the flee-odds line above "Huir") is informational and must not shift the
## mapping between _selected_index and the row it highlights.
func _update_menu_highlight(container: VBoxContainer) -> void:
	var option_index = 0
	for child in container.get_children():
		if child is Label:
			# Keep greyed-out "Huir" in boss fights regardless of selection
			var is_disabled = (container == _action_menu and option_index == MENU_OPTIONS.size() - 1 and _is_boss)
			if is_disabled:
				child.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
				child.text = "  " + child.text.strip_edges().trim_prefix("> ")
			elif option_index == _selected_index:
				child.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
				child.text = "> " + child.text.strip_edges().trim_prefix("> ")
			else:
				child.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
				child.text = "  " + child.text.strip_edges().trim_prefix("> ")
			option_index += 1

## Live odds for the "Huir" action, with the formula spelled out so the number is checkable.
func _flee_hint_text() -> String:
	if _is_boss or (_battle_controller and not _battle_controller.can_flee()):
		return "No se puede huir de este combate"
	if not _battle_controller:
		return ""
	var party = _battle_controller.get_party()
	var alive = 0
	for p in party:
		if p.get("hp", 0) > 0:
			alive += 1
	var chance = Combatant.calculate_flee_chance(party, _battle_controller.get_enemies())
	var breakdown = "%d base + %d x %d en pie" % [
		Combatant.FLEE_BASE_CHANCE, Combatant.FLEE_CHANCE_PER_MEMBER, alive,
	]
	# Whatever the formula didn't account for is a feat bonus — shown so the total always adds up.
	var feat_bonus = chance - (Combatant.FLEE_BASE_CHANCE + alive * Combatant.FLEE_CHANCE_PER_MEMBER)
	if feat_bonus > 0:
		breakdown += " + %d feat" % feat_bonus
	return "Huida: %d%%  (%s)" % [chance, breakdown]

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
	_refresh_party_position_zones()
	if _engagement_overlay:
		_engagement_overlay.queue_redraw()
	if _zone_backdrop:
		_zone_backdrop.queue_redraw()

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
	# Update party sprite tint based on alive/dead state. Looked up by id (via
	# _combatant_sprite_map) rather than by container child index — the party sprites now live
	# nested inside position-zone boxes, not as _battle_sprites_container's direct children.
	if _battle_controller:
		for p in _battle_controller.get_party():
			var vbox = _combatant_sprite_map.get(p.get("id", ""))
			if vbox and is_instance_valid(vbox) and vbox.get_child_count() > 0 and vbox.get_child(0) is TextureRect:
				var rect = vbox.get_child(0) as TextureRect
				rect.modulate = Color(1, 1, 1) if p["hp"] > 0 else Color(0.3, 0.3, 0.3)
	_update_hp_bars()

## A translucent slab behind each zone column, so the bands read as ground rather than as three
## floating labels. The two facing front ranks share a warmer tint: that pair of columns is the
## melee zone, and making it one visual space is the whole point.
func _draw_zone_backdrop() -> void:
	if _zone_backdrop == null:
		return
	var to_local := _zone_backdrop.get_global_transform().affine_inverse()
	for side in [_position_zone_boxes, _enemy_zone_boxes]:
		for i in range(side.size()):
			var box: Control = side[i]
			if box == null or not is_instance_valid(box):
				continue
			var column: Control = box.get_parent()
			if column == null:
				continue
			var r := column.get_global_rect().grow(10.0)
			# Columns collapse to nothing before the first layout pass; skip until they have size.
			if r.size.x < 1.0:
				continue
			var rect := Rect2(to_local * r.position, r.size)
			var front := i == Combatant.POS_FRONT
			var fill := Color(0.42, 0.24, 0.14, 0.30) if front else Color(0.14, 0.15, 0.22, 0.30)
			var edge := Color(0.75, 0.45, 0.25, 0.35) if front else Color(0.35, 0.37, 0.48, 0.25)
			_zone_backdrop.draw_rect(rect, fill, true)
			_zone_backdrop.draw_rect(rect, edge, false, 2.0)

## A slow vertical drift so the field is never completely still. Runs on the sprite visual's
## `position:y` only, leaving `position:x` free for the attack lunge — Godot tweens those as
## separate property paths, so the two never fight over the same value.
const IDLE_BOB := 4.0

func _start_idle_bob(vbox: Control) -> void:
	if vbox == null or vbox.get_child_count() == 0:
		return
	var visual = vbox.get_child(0)
	if not (visual is Control):
		return
	var tween := visual.create_tween().set_loops()
	# A random phase keeps the whole party from bobbing in lockstep.
	var period := randf_range(1.4, 2.0)
	tween.tween_property(visual, "position:y", -IDLE_BOB, period * 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, "position:y", 0.0, period * 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

## Draws one line per engagement, hero sprite to enemy sprite, so who is tied up with whom is
## readable at a glance. Direction doesn't need marking: a lock is mutual for every rule that
## matters, and arrowheads on overlapping lines just turn into noise when four heroes pile onto
## one enemy. A dot at each end reads more clearly at this scale.
func _draw_engagement_lines() -> void:
	if not _battle_controller or not _engagement_overlay:
		return
	var all: Array = []
	all.append_array(_battle_controller.get_party())
	all.append_array(_battle_controller.get_enemies())

	var line_color := Color(0.95, 0.45, 0.25, 0.75)
	var to_local := _engagement_overlay.get_global_transform().affine_inverse()
	for c in all:
		if c.get("hp", 0) <= 0:
			continue
		var locked: String = Combatant.engaged_target_id(c)
		if locked == "":
			continue
		var from_node = _combatant_sprite_map.get(c.get("id", ""))
		var to_node = _combatant_sprite_map.get(locked)
		if from_node == null or to_node == null:
			continue
		if not is_instance_valid(from_node) or not is_instance_valid(to_node):
			continue
		var a: Vector2 = to_local * from_node.get_global_rect().get_center()
		var b: Vector2 = to_local * to_node.get_global_rect().get_center()
		_engagement_overlay.draw_line(a, b, line_color, 3.0, true)
		_engagement_overlay.draw_circle(a, 6.0, line_color)
		_engagement_overlay.draw_circle(b, 6.0, line_color)

## Reparents each party member's sprite vbox into the position-zone box matching their CURRENT
## position, whenever it changed since the last refresh (e.g. after a "move" action) — cheap
## no-op if nobody moved, called every _update_all_stats() so it stays in sync automatically.
func _refresh_party_position_zones() -> void:
	if not _battle_controller:
		return
	_reseat_side(_battle_controller.get_party(), _position_zone_boxes)
	_reseat_side(_battle_controller.get_enemies(), _enemy_zone_boxes)

## Moves each combatant's sprite into the band matching their CURRENT zone. Enemies need this as
## much as the party does — their AI repositions them every fight, and until now the enemy row
## never showed it, which made the melee lines look like they connected to nothing in particular.
func _reseat_side(combatants: Array, zone_boxes: Array) -> void:
	if zone_boxes.is_empty():
		return
	for c in combatants:
		var vbox: Control = _combatant_sprite_map.get(c.get("id", ""))
		if vbox == null or not is_instance_valid(vbox):
			continue
		var target_box = zone_boxes[clampi(int(c.get("position", 0)), 0, zone_boxes.size() - 1)]
		if vbox.get_parent() != target_box:
			vbox.get_parent().remove_child(vbox)
			target_box.add_child(vbox)
			_start_idle_bob(vbox)

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
	# Only the per-zone CharsBoxes get cleared here — the zone rows/labels themselves are built
	# once in _build_ui() and persist for the whole battle.
	for chars_box in _position_zone_boxes:
		_clear_container(chars_box)
	for chars_box in _enemy_zone_boxes:
		_clear_container(chars_box)
	_hp_bars.clear()
	_combatant_sprite_map.clear()

	# Party sprites (side-view battle pose) — no HP bar (stats shown in HUD panel), placed in
	# the CharsBox matching their current position zone (see _position_zone_boxes). Font is
	# smaller than the enemy labels' so all four fit stacked in a single zone column.
	for p in party:
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_END
		var sprite_w := 64.0
		vbox.add_theme_constant_override("separation", 0)
		# Sprite
		var rect = TextureRect.new()
		rect.custom_minimum_size = Vector2(sprite_w, 80)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture = CharacterSprites.get_battle_texture(p)
		rect.modulate = Color(1, 1, 1) if p["hp"] > 0 else Color(0.3, 0.3, 0.3)
		vbox.add_child(rect)
		# Name
		var name_label = Label.new()
		name_label.text = p["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 26)
		vbox.add_child(name_label)
		var zone_idx = clampi(int(p.get("position", 0)), 0, _position_zone_boxes.size() - 1)
		_position_zone_boxes[zone_idx].add_child(vbox)
		_combatant_sprite_map[p.get("id", "")] = vbox
		_start_idle_bob(vbox)

	# Enemy sprites (battle art if available, else a red placeholder rectangle) with HP bar above
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
		var alive_tint = Color(1, 1, 1) if e["hp"] > 0 else Color(0.3, 0.3, 0.3)
		var texture = EnemySprites.get_texture(e)
		if texture:
			var rect = TextureRect.new()
			rect.custom_minimum_size = Vector2(sprite_w, sprite_h)
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture = texture
			rect.modulate = alive_tint
			vbox.add_child(rect)
		else:
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
		var zone_idx = clampi(int(e.get("position", 0)), 0, _enemy_zone_boxes.size() - 1)
		_enemy_zone_boxes[zone_idx].add_child(vbox)
		_combatant_sprite_map[e.get("id", "")] = vbox
		_start_idle_bob(vbox)

func _on_damage_dealt(target: Dictionary, amount: int, is_heal: bool) -> void:
	_spawn_floating_number(target, amount, is_heal)
	_flash_sprite(target, is_heal)
	AudioManager.play_sfx("heal" if is_heal else "attack_hit")

## Sprite lookup shared by every bit of combat juice below. Returns the TextureRect (or the
## ColorRect fallback used for enemies with no art) rather than the whole vbox, so tinting the
## sprite doesn't wash out the name label under it.
func _sprite_visual_of(combatant: Dictionary) -> Control:
	var vbox = _combatant_sprite_map.get(combatant.get("id", ""))
	if vbox == null or not is_instance_valid(vbox) or vbox.get_child_count() == 0:
		return null
	var visual = vbox.get_child(0)
	return visual if visual is Control else null

## A short colour punch on whoever just got hit — red for damage, green for healing. Tweens back
## to the sprite's resting tint rather than to white, so a downed combatant stays greyed out.
func _flash_sprite(target: Dictionary, is_heal: bool) -> void:
	var visual := _sprite_visual_of(target)
	if visual == null:
		return
	var resting := Color(1, 1, 1) if target.get("hp", 0) > 0 else Color(0.3, 0.3, 0.3)
	var flash := Color(0.35, 1.0, 0.45) if is_heal else Color(1.0, 0.25, 0.2)
	visual.modulate = flash
	var tween := visual.create_tween()
	tween.tween_property(visual, "modulate", resting, 0.28).set_ease(Tween.EASE_OUT)

## The little lunge an attacker makes toward its target. Party sprites sit on the left and enemies
## on the right, so "forward" is simply a sign flip — no need to read anyone's real position.
## Uses the sprite's own offset via `position`, and always returns to zero, so it can never
## desync the zone containers that own the layout.
const LUNGE_DISTANCE := 34.0

func play_attack_lunge(attacker: Dictionary) -> void:
	var visual := _sprite_visual_of(attacker)
	if visual == null:
		return
	var forward := LUNGE_DISTANCE if attacker.get("is_player", false) else -LUNGE_DISTANCE
	var home := Vector2.ZERO
	var tween := visual.create_tween()
	tween.tween_property(visual, "position", home + Vector2(forward, 0.0), 0.09).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "position", home, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

## Floating combat numbers. Three things were wrong with the previous version and each one on its
## own was enough to make them hard to notice:
##
##   1. The label spawned at (0,0) and only jumped onto the target a frame later, because the
##      position was computed after an `await`. Now it is hidden until placed.
##   2. It was anchored above the sprite BOX, which for party members is a tall zone-column cell —
##      so the number drifted into empty space instead of over the character. Now it uses the
##      sprite visual itself and starts on top of it.
##   3. Plain white text on a dark battlefield with no outline, 48px, gone in 0.8s. Now it is
##      bigger, outlined, colour-coded, pops on arrival, and holds before fading.
const FLOAT_RISE := 90.0
const FLOAT_LIFETIME := 1.1

func _spawn_floating_number(target: Dictionary, amount: int, is_heal: bool) -> void:
	if not _float_overlay or amount <= 0:
		return
	var anchor: Control = _sprite_visual_of(target)
	if anchor == null:
		anchor = _combatant_sprite_map.get(target.get("id", ""))
	if anchor == null or not is_instance_valid(anchor):
		return

	var label = Label.new()
	label.text = ("+" + str(amount)) if is_heal else str(amount)
	label.add_theme_font_size_override("font_size", 64)
	# Damage the player takes reads red, damage they deal reads gold, healing reads green — the
	# colour says whose problem it is before the number is even read.
	var tint := Color(0.35, 1.0, 0.4)
	if not is_heal:
		tint = Color(1.0, 0.35, 0.3) if target.get("is_player", false) else Color(1.0, 0.85, 0.25)
	label.add_theme_color_override("font_color", tint)
	# A hard outline is what makes it readable over sprites of any colour.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false  # stays hidden until it has a real position
	_float_overlay.add_child(label)

	# One frame so the label reports a real size and the sprite's layout has settled.
	await label.get_tree().process_frame
	if not is_instance_valid(label) or not is_instance_valid(anchor):
		return

	var rect := anchor.get_global_rect()
	var to_local := _float_overlay.get_global_transform().affine_inverse()
	var start := to_local * Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.35)
	label.position = start - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)
	label.visible = true

	var tween := label.create_tween()
	# Pop in, drift up the whole time, then fade only at the end so it is legible while it rises.
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_LIFETIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_LIFETIME * 0.4) \
		.set_delay(FLOAT_LIFETIME * 0.6).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func _clear_container(container) -> void:
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
