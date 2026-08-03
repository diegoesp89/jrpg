extends CanvasLayer
class_name BattleUI
## BattleUI — The complete battle UI

## Preloaded by path rather than referenced by class_name: a class_name added in the same change
## as the code using it is not in the editor's cache yet, and a stale cache shows up as
## "Identifier not declared" at startup rather than as anything useful.
const Theme_ = preload("res://scripts/ui/BattleTheme.gd")
const BackdropScript = preload("res://scripts/ui/BattleBackdrop.gd")

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

# Maps combatant id (String) → sprite VBox node (used for the engagement lines, which want the
# whole cell). The two maps below point INTO that vbox, because its children are not laid out the
# same way on both sides: a party cell is [sprite, name] while an enemy cell is [hp bar, sprite,
# name]. Anything that wants the artwork or the name specifically has to be told which is which
# instead of guessing by index.
var _combatant_sprite_map: Dictionary = {}
## id → the sprite itself (TextureRect, or the ColorRect stand-in for enemies with no art). Every
## bit of combat juice hangs off this: the damage number anchors to it, the hit flash tints it,
## the attack lunge moves it, the idle bob drifts it.
var _combatant_visual_map: Dictionary = {}
## id → the name Label under the sprite, so the combatant whose turn it is can be lit up.
var _combatant_name_map: Dictionary = {}

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

	# --- Battle field (top 60%) ---
	var field = Control.new()
	field.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Height via the anchor offset, NOT `size`. TOP_WIDE already stretches the width to the
	# parent, so assigning `size.x = 1920` on top of it stored a 1920px offset as well and the
	# field came out 3840 wide — which is why anything anchored to its centre landed off-screen.
	field.offset_bottom = 645
	field.clip_contents = false
	root.add_child(field)

	# The cave itself, behind everything else in the field. Anchored from out here, before it is
	# added, exactly like every other full-rect overlay in this function — a Control that sets its
	# own anchors from _ready() misses the parent's first layout pass and stays 0x0.
	var backdrop = BackdropScript.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	field.add_child(backdrop)

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
	# Sits low enough that a damage number rising off a front-row sprite still lands inside the
	# battlefield instead of in the "Turno: X" title. A party is always three (the 35 combos are
	# C(7,3)), so the tallest column is three cells and there is room to spare below.
	_battle_sprites_container.position = Vector2(120, 140)
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
	_enemy_sprites_container.position = Vector2(1010, 140)
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

	# --- Bottom bar (40%) — three separately framed panels on a dark plinth, rather than one slab
	# with invisible seams: each one is a different job (who you are / what you do / what
	# happened) and the frames say so.
	var bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -435
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.02, 0.02, 0.05, 0.98)
	bottom_style.border_color = Theme_.GOLD_DIM
	bottom_style.border_width_top = 2
	bottom_style.set_content_margin_all(14)
	bottom.add_theme_stylebox_override("panel", bottom_style)
	root.add_child(bottom)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_hbox.add_theme_constant_override("separation", 14)
	bottom.add_child(bottom_hbox)

	# Left: the party — portrait, name, and bars per member (see _build_party_row).
	var stats_panel = PanelContainer.new()
	stats_panel.custom_minimum_size = Vector2(660, 0)
	stats_panel.add_theme_stylebox_override("panel", Theme_.panel(12))
	bottom_hbox.add_child(stats_panel)

	_party_stats_container = VBoxContainer.new()
	_party_stats_container.add_theme_constant_override("separation", 10)
	stats_panel.add_child(_party_stats_container)

	# Center: Action menu
	var menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(450, 0)
	menu_panel.add_theme_stylebox_override("panel", Theme_.panel_active(12))
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

	# Right: the log, on parchment. It is the one panel that is read as prose rather than glanced
	# at, and dark ink on a light page is easier for that than the reverse.
	var log_panel = PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.add_theme_stylebox_override("panel", Theme_.parchment(16))
	bottom_hbox.add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = false
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 34)
	_log_label.add_theme_color_override("default_color", Theme_.INK)
	log_panel.add_child(_log_label)

	# Turn indicator, centred over the field on its own small plaque.
	var turn_plaque = PanelContainer.new()
	turn_plaque.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_plaque.offset_left = -300
	turn_plaque.offset_right = 300
	turn_plaque.offset_top = 10
	var turn_style := Theme_.panel(8)
	turn_style.bg_color = Color(0.03, 0.03, 0.07, 0.85)
	turn_plaque.add_theme_stylebox_override("panel", turn_style)
	field.add_child(turn_plaque)

	_turn_indicator = Label.new()
	_turn_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_indicator.add_theme_font_size_override("font_size", 46)
	_turn_indicator.add_theme_color_override("font_color", Theme_.GOLD_TEXT)
	_turn_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_turn_indicator.add_theme_constant_override("outline_size", 8)
	turn_plaque.add_child(_turn_indicator)

	# Initiative list (top-right)
	var init_panel = PanelContainer.new()
	init_panel.name = "InitiativePanel"
	init_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	init_panel.offset_left = -260
	init_panel.offset_top = 14
	init_panel.offset_right = -14
	init_panel.offset_bottom = 250
	init_panel.add_theme_stylebox_override("panel", Theme_.panel(10))
	root.add_child(init_panel)
	_initiative_panel = init_panel

	var init_vbox = VBoxContainer.new()
	init_vbox.name = "InitiativeList"
	init_vbox.add_theme_constant_override("separation", 4)
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
			# The selected row gets a lit plate behind it as well as the colour change. The
			# unselected rows get the SAME box with everything transparent, so selecting a row
			# doesn't shift the whole list sideways as the plate's margins appear.
			if is_disabled:
				child.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
				child.add_theme_stylebox_override("normal", Theme_.menu_idle())
				child.text = MENU_CURSOR_BLANK + _row_text(child)
			elif option_index == _selected_index:
				child.add_theme_color_override("font_color", Theme_.GOLD_TEXT)
				child.add_theme_stylebox_override("normal", Theme_.menu_selection())
				child.text = MENU_CURSOR + _row_text(child)
			else:
				child.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
				child.add_theme_stylebox_override("normal", Theme_.menu_idle())
				child.text = MENU_CURSOR_BLANK + _row_text(child)
			option_index += 1

## The cursor is written into the row's text rather than drawn as a separate node, so it can never
## fall out of sync with which row is selected. The blank is the same width as the glyph.
const MENU_CURSOR := "▸ "
const MENU_CURSOR_BLANK := "   "

func _row_text(label: Label) -> String:
	return label.text.strip_edges().trim_prefix(MENU_CURSOR.strip_edges()).strip_edges().trim_prefix("> ")

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
	_update_turn_name_highlight()
	if _engagement_overlay:
		_engagement_overlay.queue_redraw()
	if _zone_backdrop:
		_zone_backdrop.queue_redraw()

	# Party panel
	_clear_container(_party_stats_container)
	if _battle_controller:
		for p in _battle_controller.get_party():
			_party_stats_container.add_child(_build_party_row(p))

	# Update HP bars above sprites (enemies only)
	_update_hp_bars()

## One party member's card: portrait, name, HP figure, and a bar each for HP and MP.
##
## This used to be a single line of text ("Rosa  HP:3/13  MP:14/14"), which meant reading four
## numbers to answer "who is about to die". The bars answer that at a glance and the colour
## carries the warning — green, amber under half, red under a quarter — so the digits are there
## for when the exact number matters rather than for the routine check.
const PORTRAIT_SIZE := 74.0
const BAR_WIDTH := 300.0
const BAR_HEIGHT := 16.0

func _build_party_row(p: Dictionary) -> Control:
	var alive: bool = int(p.get("hp", 0)) > 0
	var is_turn: bool = _current_turn_is_player and str(p.get("id", "")) == str(_current_turn_combatant.get("id", ""))

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = CharacterSprites.get_portrait_texture(p)
	portrait.modulate = Color(1, 1, 1) if alive else Color(0.35, 0.35, 0.35)
	row.add_child(portrait)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	col.add_child(header)

	var name_label = Label.new()
	name_label.text = str(p.get("name", "?"))
	name_label.add_theme_font_size_override("font_size", 32)
	if not alive:
		name_label.add_theme_color_override("font_color", Theme_.TEXT_DEAD)
	elif is_turn:
		name_label.add_theme_color_override("font_color", TURN_NAME_COLOR)
	else:
		name_label.add_theme_color_override("font_color", Theme_.TEXT)
	header.add_child(name_label)

	# Whatever is true about this member right now, in the space the old line spent on "MP:14/14".
	var tags: Array[String] = []
	if not alive:
		tags.append("CAIDO")
	if p.get("defending", false):
		tags.append("DEF")
	if int(p.get("poison_damage", 0)) > 0:
		tags.append("VENENO")
	if int(p.get("burn_damage", 0)) > 0:
		tags.append("QUEMADURA")
	if int(p.get("stunned_turns", 0)) > 0:
		tags.append("ATURDIDO")
	if not tags.is_empty():
		var tag_label = Label.new()
		tag_label.text = "  ".join(tags)
		tag_label.add_theme_font_size_override("font_size", 22)
		tag_label.add_theme_color_override("font_color", Theme_.HP_HURT if alive else Theme_.TEXT_DEAD)
		header.add_child(tag_label)

	var hp: int = int(p.get("hp", 0))
	var max_hp: int = maxi(int(p.get("max_hp", 1)), 1)
	var mp: int = int(p.get("mp", 0))
	var max_mp: int = int(p.get("max_mp", 0))

	var hp_frac := float(hp) / float(max_hp)
	col.add_child(_build_stat_bar("HP", hp, max_hp, hp_frac, Theme_.hp_color(hp_frac)))
	if max_mp > 0:
		col.add_child(_build_stat_bar("MP", mp, max_mp, float(mp) / float(max_mp), Theme_.MP_COLOR))

	return row

## A labelled bar. The fill is a plain ColorRect sized by fraction rather than a ProgressBar,
## to match how the enemy HP bars above the sprites are already drawn.
func _build_stat_bar(tag: String, value: int, maximum: int, fraction: float, fill: Color) -> Control:
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)

	var tag_label = Label.new()
	tag_label.text = tag
	tag_label.custom_minimum_size = Vector2(46, 0)
	tag_label.add_theme_font_size_override("font_size", 21)
	tag_label.add_theme_color_override("font_color", Theme_.TEXT_DIM)
	line.add_child(tag_label)

	var track = PanelContainer.new()
	track.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Theme_.BAR_TRACK
	track_style.border_color = Color(0, 0, 0, 0.6)
	track_style.set_border_width_all(1)
	track_style.set_corner_radius_all(4)
	track.add_theme_stylebox_override("panel", track_style)
	line.add_child(track)

	var bar = ColorRect.new()
	bar.color = fill
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.custom_minimum_size = Vector2(BAR_WIDTH * clampf(fraction, 0.0, 1.0), BAR_HEIGHT)
	track.add_child(bar)

	var value_label = Label.new()
	value_label.text = "%d/%d" % [value, maximum]
	value_label.add_theme_font_size_override("font_size", 21)
	value_label.add_theme_color_override("font_color", Theme_.TEXT_DIM)
	line.add_child(value_label)

	return line

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
	title.text = "INICIATIVA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Theme_.GOLD_TEXT)
	_initiative_list.add_child(title)

	var rule = ColorRect.new()
	rule.color = Theme_.GOLD_DIM
	rule.custom_minimum_size = Vector2(0, 2)
	_initiative_list.add_child(rule)

	for entry in queue:
		var combatant = entry.get("combatant", {})
		if combatant.get("hp", 0) <= 0:
			continue

		var name = combatant.get("name", "???")
		var is_current = combatant.get("id", "") == current_id

		var label = Label.new()
		# The one acting gets the cursor here too, so the panel and the battlefield agree.
		label.text = (MENU_CURSOR if is_current else MENU_CURSOR_BLANK) + str(name)
		label.add_theme_font_size_override("font_size", 22)
		if is_current:
			label.add_theme_color_override("font_color", Theme_.GOLD_TEXT)
			label.add_theme_stylebox_override("normal", Theme_.menu_selection())
		elif combatant.get("is_player", false):
			label.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
		else:
			label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.5))
		_initiative_list.add_child(label)

## Greys out whoever is down, on BOTH sides — enemies used to keep their living tint forever,
## because only the party was walked here and the enemy tint was set once at setup time.
func _update_battle_sprites() -> void:
	if _battle_controller:
		for c in _battle_controller.get_party() + _battle_controller.get_enemies():
			var visual := _sprite_visual_of(c)
			if visual == null:
				continue
			# A hit flash owns modulate for a moment and tweens back to the resting tint itself;
			# overwriting it here would cut the flash short.
			if visual.get_meta("flashing", false):
				continue
			visual.modulate = Color(1, 1, 1) if c.get("hp", 0) > 0 else Color(0.3, 0.3, 0.3)
	_update_hp_bars()

## Lights up the name under whoever is acting, in the same yellow the menu cursor and the
## initiative list already use for "this one" — so the turn is readable on the battlefield itself
## and not only in the panels at the edges of the screen. The dead go grey alongside their sprite.
const TURN_NAME_COLOR := Color(1, 0.9, 0.2)

func _update_turn_name_highlight() -> void:
	if not _battle_controller:
		return
	var current_id := str(_current_turn_combatant.get("id", ""))
	for c in _battle_controller.get_party() + _battle_controller.get_enemies():
		var cid := str(c.get("id", ""))
		var label = _combatant_name_map.get(cid)
		if label == null or not is_instance_valid(label):
			continue
		if int(c.get("hp", 0)) <= 0:
			label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		elif cid == current_id:
			label.add_theme_color_override("font_color", TURN_NAME_COLOR)
		else:
			label.add_theme_color_override("font_color", Color(1, 1, 1))

## A translucent slab behind each zone column, so the bands read as ground rather than as three
## floating labels. The two facing front ranks share a warmer tint: that pair of columns is the
## melee zone, and making it one visual space is the whole point.
func _draw_zone_backdrop() -> void:
	if _zone_backdrop == null:
		return
	var to_local := _zone_backdrop.get_global_transform().affine_inverse()
	var size_of_field: float = _zone_backdrop.size.y
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
			# Grown downward as well as outward: over a lit floor the bands need to read as a
			# standing area, not as a tight box cropped to whatever sprites happen to be in it.
			var rect := Rect2(to_local * r.position, r.size)
			rect.size.y = maxf(rect.size.y, size_of_field * 0.62 - rect.position.y)
			var front := i == Combatant.POS_FRONT
			var fill := Theme_.ZONE_FRONT_FILL if front else Theme_.ZONE_BACK_FILL
			var edge := Theme_.ZONE_FRONT_EDGE if front else Theme_.ZONE_BACK_EDGE
			_zone_backdrop.draw_rect(rect, fill, true)
			_zone_backdrop.draw_rect(rect, edge, false, 2.0)

## A slow vertical drift so the field is never completely still. Runs on the sprite visual's
## `position:y` only, leaving `position:x` free for the attack lunge — Godot tweens those as
## separate property paths, so the two never fight over the same value.
const IDLE_BOB := 4.0

func _start_idle_bob(visual: Control) -> void:
	if visual == null:
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
		# Three passes, wide-and-faint to thin-and-bright, so the line reads as a glowing tether
		# rather than as a flat 3px stroke laid over the art. Cheaper and steadier than a shader,
		# and it survives whatever ends up behind it.
		for pass_i in range(GLOW_PASSES.size()):
			var spec: Array = GLOW_PASSES[pass_i]
			_engagement_overlay.draw_line(a, b, Color(ENGAGE_COLOR, float(spec[1])), float(spec[0]), true)
		_engagement_overlay.draw_circle(a, 11.0, Color(ENGAGE_COLOR, 0.22))
		_engagement_overlay.draw_circle(b, 11.0, Color(ENGAGE_COLOR, 0.22))
		_engagement_overlay.draw_circle(a, 5.0, Color(ENGAGE_COLOR, 0.95))
		_engagement_overlay.draw_circle(b, 5.0, Color(ENGAGE_COLOR, 0.95))

## width, alpha — outermost first.
const ENGAGE_COLOR := Color(1.0, 0.62, 0.32)
const GLOW_PASSES := [[13.0, 0.13], [7.0, 0.28], [2.5, 0.95]]

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
	_combatant_visual_map.clear()
	_combatant_name_map.clear()

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
		_combatant_visual_map[p.get("id", "")] = rect
		_combatant_name_map[p.get("id", "")] = name_label
		_start_idle_bob(rect)

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
		var visual: Control
		if texture:
			var rect = TextureRect.new()
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture = texture
			visual = rect
		else:
			var rect = ColorRect.new()
			rect.color = Color(0.8, 0.2, 0.15)
			visual = rect
		visual.custom_minimum_size = Vector2(sprite_w, sprite_h)
		visual.modulate = alive_tint
		vbox.add_child(visual)
		# Name
		var name_label = Label.new()
		name_label.text = e["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 33)
		vbox.add_child(name_label)
		var zone_idx = clampi(int(e.get("position", 0)), 0, _enemy_zone_boxes.size() - 1)
		_enemy_zone_boxes[zone_idx].add_child(vbox)
		_combatant_sprite_map[e.get("id", "")] = vbox
		_combatant_visual_map[e.get("id", "")] = visual
		_combatant_name_map[e.get("id", "")] = name_label
		_start_idle_bob(visual)

func _on_damage_dealt(target: Dictionary, amount: int, is_heal: bool) -> void:
	_spawn_impact_burst(target, is_heal)
	_spawn_floating_number(target, amount, is_heal)
	_flash_sprite(target, is_heal)
	AudioManager.play_sfx("heal" if is_heal else "attack_hit")

## A starburst on the struck sprite, thrown in the same overlay as the damage numbers and gone in
## a quarter of a second. It exists to give the hit a moment of contact — the number tells you how
## much, the flash tells you who, and neither tells you *when* on its own.
const BURST_SPIKES := 9
const BURST_LIFETIME := 0.26

func _spawn_impact_burst(target: Dictionary, is_heal: bool) -> void:
	if not _float_overlay:
		return
	var anchor: Control = _sprite_visual_of(target)
	if anchor == null or not is_instance_valid(anchor):
		return

	var burst = Control.new()
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := Color(0.45, 1.0, 0.55) if is_heal else Color(1.0, 0.72, 0.25)
	var seed_angle := randf() * TAU
	burst.draw.connect(func():
		var pts: PackedVector2Array = []
		for i in range(BURST_SPIKES * 2):
			var r := 58.0 if i % 2 == 0 else 22.0
			var a := seed_angle + TAU * float(i) / float(BURST_SPIKES * 2)
			pts.append(Vector2(cos(a) * r, sin(a) * r))
		burst.draw_colored_polygon(pts, Color(tint, 0.75))
	)
	_float_overlay.add_child(burst)

	var to_local := _float_overlay.get_global_transform().affine_inverse()
	burst.position = to_local * anchor.get_global_rect().get_center()
	burst.scale = Vector2(0.35, 0.35)

	var tween := burst.create_tween()
	tween.tween_property(burst, "scale", Vector2(1.25, 1.25), BURST_LIFETIME).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(burst, "modulate:a", 0.0, BURST_LIFETIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(burst.queue_free)

## Sprite lookup shared by every bit of combat juice below. Reads the map filled in by
## setup_sprites rather than taking the vbox's first child: an enemy cell leads with its HP bar,
## so "first child" meant every flash, lunge and damage number on the enemy side was landing on an
## 8px bar floating above the monster instead of on the monster.
func _sprite_visual_of(combatant: Dictionary) -> Control:
	var visual = _combatant_visual_map.get(combatant.get("id", ""))
	if visual == null or not is_instance_valid(visual):
		return null
	return visual

## A short colour punch on whoever just got hit — red for damage, green for healing. Tweens back
## to the sprite's resting tint rather than to white, so a downed combatant stays greyed out.
func _flash_sprite(target: Dictionary, is_heal: bool) -> void:
	var visual := _sprite_visual_of(target)
	if visual == null:
		return
	var resting := Color(1, 1, 1) if target.get("hp", 0) > 0 else Color(0.3, 0.3, 0.3)
	var flash := Color(0.35, 1.0, 0.45) if is_heal else Color(1.0, 0.25, 0.2)
	visual.modulate = flash
	# Claimed for the duration so the alive/dead tint pass, which runs on the same hp_updated that
	# triggered this flash, doesn't immediately paint over it.
	visual.set_meta("flashing", true)
	var tween := visual.create_tween()
	tween.tween_property(visual, "modulate", resting, 0.28).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): visual.set_meta("flashing", false))

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
	# `position:x` only: the idle bob owns `position:y` on this same node, and writing the whole
	# Vector2 here would snap the bob back to zero mid-drift and fight it for the rest of the fight.
	var tween := visual.create_tween()
	tween.tween_property(visual, "position:x", forward, 0.09).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "position:x", 0.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

## Floating combat numbers.
##
## The sprite rows sit near the top of the battlefield, with only ~110px of screen above them, so
## a number that starts at the sprite's head and climbs 90px lands in the "Turno: X" title and the
## zone headers — reading as UI chrome rather than as a hit, which is why they kept going
## unnoticed even though they were being drawn. It now starts low on the sprite and rises just far
## enough to clear its head, so the whole arc happens inside the character's own cell.
##
## Several numbers can land on ONE target in the same instant — the Monk's flurry, a weapon's
## recoil, a crit plus its on-hit rider. Printed at the same spot they smear into each other, so
## each one after the first starts a full label-height lower and a beat later: a legible cascade
## running down the target. Downward rather than fanned sideways on purpose — a horizontal fan
## wide enough to clear a three-digit number would throw it into the neighbouring zone column and
## make it look like someone else's damage. The count is per target (taken by walking the labels
## already in flight), so numbers on DIFFERENT combatants are unaffected and stay centred.
const FLOAT_RISE := 50.0
const FLOAT_LIFETIME := 1.25
const FLOAT_JITTER := 16.0
const FLOAT_STACK := 112.0  ## must exceed a label's height (~105 at this font size)
const FLOAT_STACK_SLOTS := 4  ## beyond this the cascade would run off the battlefield
const FLOAT_STAGGER := 0.11

func _spawn_floating_number(target: Dictionary, amount: int, is_heal: bool) -> void:
	if not _float_overlay or amount <= 0:
		return
	var tid := str(target.get("id", ""))
	var anchor: Control = _sprite_visual_of(target)
	if anchor == null:
		anchor = _combatant_sprite_map.get(tid)
	if anchor == null or not is_instance_valid(anchor):
		return

	var stack := 0
	for other in _float_overlay.get_children():
		if str(other.get_meta("target_id", "")) == tid:
			stack += 1

	var label = Label.new()
	label.set_meta("target_id", tid)
	label.text = ("+" + str(amount)) if is_heal else str(amount)
	label.add_theme_font_size_override("font_size", 76)
	# Damage the player takes reads red, damage they deal reads gold, healing reads green — the
	# colour says whose problem it is before the number is even read.
	var tint := Color(0.35, 1.0, 0.4)
	if not is_heal:
		tint = Color(1.0, 0.3, 0.25) if target.get("is_player", false) else Color(1.0, 0.86, 0.2)
	label.add_theme_color_override("font_color", tint)
	# A hard outline is what keeps it readable over sprites and over the name labels it crosses.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false  # stays hidden until it has a real position
	_float_overlay.add_child(label)

	# One frame so the label reports a real size and the sprite's layout has settled — plus the
	# stagger, if this target is already showing a number. It waits with the label in the tree but
	# hidden, so a number queued behind it still counts it and lands one slot further down.
	await label.get_tree().process_frame
	if stack > 0:
		await get_tree().create_timer(FLOAT_STAGGER * stack).timeout
	if not is_instance_valid(label) or not is_instance_valid(anchor):
		return

	var rect := anchor.get_global_rect()
	var to_local := _float_overlay.get_global_transform().affine_inverse()
	# Start at the sprite's feet: the rise then carries it up across the body, ending about level
	# with its head instead of sailing off past it into the title bar.
	var slot := mini(stack, FLOAT_STACK_SLOTS - 1)
	var offset_x := 0.0 if stack == 0 else (FLOAT_JITTER if stack % 2 == 1 else -FLOAT_JITTER)
	var start := to_local * Vector2(
		rect.get_center().x + offset_x,
		rect.position.y + rect.size.y + float(slot) * FLOAT_STACK,
	)
	label.position = start - label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)
	label.visible = true

	var tween := label.create_tween()
	# Pop in, drift up the whole time, then fade only at the end so it is legible while it rises.
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_LIFETIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_LIFETIME * 0.3) \
		.set_delay(FLOAT_LIFETIME * 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func _clear_container(container) -> void:
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
