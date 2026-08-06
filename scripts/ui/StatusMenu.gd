extends CanvasLayer
class_name StatusMenu
## StatusMenu — Exploration pause menu. Opens with Escape or Enter: party status,
## abilities usable out of combat (e.g. Heal), items, and quit game.

## Preloaded by path, not via its class_name — see the note in DungeonBuilder.gd.
const HelpPanelScene = preload("res://scripts/ui/HelpPanel.gd")

enum MenuState { MAIN, STATUS, MESSAGE, ABILITIES, ABILITY_TARGET, ITEMS, ITEM_TARGET, FORMATION, EQUIPMENT, QUIT_CONFIRM }

const MAIN_OPTIONS := ["Estado", "Habilidades", "Objetos", "Equipo", "Formación", "Guardar partida", "Ayuda", "Opciones", "Salir del juego"]

var _is_open: bool = false
var _menu_state: MenuState = MenuState.MAIN
var _selected_index: int = 0
var _selectable_count: int = 0

var _root: Control = null
var _title: Label = null
var _content_container: VBoxContainer = null

var _ability_options: Array = []
var _item_options: Array = []
var _target_options: Array = []
var _pending_ability: Dictionary = {}
var _pending_item: Dictionary = {}
var _options_panel: OptionsPanel
var _help_panel: HelpPanelScene

func _ready() -> void:
	layer = 60
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_title = Label.new()
	_title.text = "Menú"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 60
	_title.offset_bottom = 120
	_root.add_child(_title)

	_content_container = VBoxContainer.new()
	_content_container.set_anchors_preset(Control.PRESET_CENTER)
	_content_container.offset_left = -280
	_content_container.offset_right = 280
	_content_container.offset_top = -160
	_content_container.offset_bottom = 200
	_content_container.add_theme_constant_override("separation", 10)
	_root.add_child(_content_container)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z / Enter: Elegir  |  X / Esc: Volver"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

	_options_panel = OptionsPanel.new()
	add_child(_options_panel)
	_options_panel.closed.connect(_show_main)

	_help_panel = HelpPanelScene.new()
	add_child(_help_panel)
	_help_panel.closed.connect(_show_main)

func _unhandled_input(event: InputEvent) -> void:
	if _options_panel.is_open() or _help_panel.is_open():
		return
	if not _is_open:
		if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")) and _can_open():
			_open_menu()
			get_viewport().set_input_as_handled()
		return

	match _menu_state:
		MenuState.MAIN:
			_handle_selectable_input(event, MAIN_OPTIONS.size(), "_select_main_option")
		MenuState.STATUS, MenuState.MESSAGE:
			_handle_back_only_input(event)
		MenuState.ABILITIES:
			_handle_selectable_input(event, _ability_options.size(), "_select_ability")
		MenuState.ABILITY_TARGET:
			_handle_selectable_input(event, _target_options.size(), "_select_ability_target")
		MenuState.ITEMS:
			_handle_selectable_input(event, _item_options.size(), "_select_item")
		MenuState.ITEM_TARGET:
			_handle_selectable_input(event, _target_options.size(), "_select_item_target")
		MenuState.FORMATION:
			_handle_selectable_input(event, GameState.party.size(), "_cycle_formation")
		MenuState.EQUIPMENT:
			_handle_selectable_input(event, GameState.party.size(), "_cycle_weapon")
		MenuState.QUIT_CONFIRM:
			_handle_selectable_input(event, 2, "_select_quit_option")
	get_viewport().set_input_as_handled()

func _can_open() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return player != null and player.has_method("is_movement_disabled") and not player.is_movement_disabled()

func _open_menu() -> void:
	_is_open = true
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)
	_show_main()

func _close_menu() -> void:
	_is_open = false
	_root.visible = false
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(false)

# --- Generic navigation for a list of `count` selectable rows in _content_container ---

func _handle_selectable_input(event: InputEvent, count: int, select_method: String) -> void:
	_selectable_count = count
	if count == 0:
		if event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
			_show_main()
		return
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_highlight()
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(count - 1, _selected_index + 1)
		_update_highlight()
	elif event.is_action_pressed("action1") or event.is_action_pressed("ui_accept"):
		call(select_method, _selected_index)
	elif event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		if _menu_state == MenuState.MAIN:
			_close_menu()
		else:
			_show_main()

func _handle_back_only_input(event: InputEvent) -> void:
	if event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("action1") or event.is_action_pressed("ui_accept"):
		_show_main()

func _update_highlight() -> void:
	var children = _content_container.get_children()
	for i in range(children.size()):
		if children[i] is Label:
			if i == _selected_index:
				children[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
			else:
				children[i].add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

func _clear_content() -> void:
	for child in _content_container.get_children():
		child.queue_free()

func _add_row(text: String, font_size: int = 24, autowrap: bool = false) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	if autowrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_container.add_child(label)

# --- Main menu ---

func _show_main() -> void:
	_menu_state = MenuState.MAIN
	_selected_index = 0
	_title.text = "Menú"
	_clear_content()
	for opt in MAIN_OPTIONS:
		_add_row(opt, 30)
	_update_highlight()
	_root.visible = true

func _select_main_option(idx: int) -> void:
	match idx:
		0: _show_status()
		1: _show_abilities()
		2: _show_items()
		3: _show_equipment()
		4: _show_formation()
		5: _save_game()
		6: _help_panel.open()
		7: _options_panel.open()
		8: _show_quit_confirm()

# --- Equipo (qué arma legendaria lleva cada uno) ---

## The legendary weapons the party has actually recovered, in a fixed order so the cycling below
## is predictable. Empty until the first one is found in the dungeon.
func _owned_weapons() -> Array:
	var out: Array = []
	for item in DataLoader.get_all_items():
		if str(item.get("effect", "")) == "quest_item" and GameState.has_item(str(item["id"])):
			out.append(str(item["id"]))
	return out

func _show_equipment() -> void:
	_menu_state = MenuState.EQUIPMENT
	_title.text = "Equipo"
	_clear_content()
	var owned := _owned_weapons()
	if owned.is_empty():
		_add_row("Todavía no has encontrado ningún arma legendaria.", 22)
		_selected_index = 0
		_update_highlight()
		_root.visible = true
		return
	for m in GameState.party:
		var wid := str(m.get("weapon", ""))
		# Explicitly typed: Dictionary.get() returns Variant, and inferring from it is a parse
		# error under this project's warnings-as-errors setting.
		var witem: Dictionary = DataLoader.get_item(wid) if wid != "" else {}
		var wname: String = str(witem.get("name", "")) if wid != "" else "-"
		_add_row("%s: %s" % [m["name"], wname], 24)
		var wdesc: String = str(witem.get("description", ""))
		if wdesc != "":
			_add_row(wdesc, 15, true)
	_add_row("Z cambia el arma del personaje marcado. Cada arma la lleva uno solo.", 16)
	_selected_index = 0
	_update_highlight()
	_root.visible = true

## Cycles through the recovered weapons plus "none". A weapon can only be in one pair of hands,
## so taking one off someone else is automatic rather than an error the player has to undo.
func _cycle_weapon(idx: int) -> void:
	var owned := _owned_weapons()
	if owned.is_empty() or idx >= GameState.party.size():
		return
	var m = GameState.party[idx]
	var options: Array = [""] + owned
	var next := (options.find(str(m.get("weapon", ""))) + 1) % options.size()
	var chosen := str(options[next])
	if chosen != "":
		for other in GameState.party:
			if other != m and str(other.get("weapon", "")) == chosen:
				other["weapon"] = ""
	m["weapon"] = chosen
	var keep := idx
	_show_equipment()
	_selected_index = keep
	_update_highlight()

# --- Formación (zona en la que cada personaje entra a combate) ---

## The zone each character deploys into when a battle starts. Chosen out of combat because it's
## a plan, not a turn action: once the fight is on, changing zones costs an action and provokes.
func _show_formation() -> void:
	_menu_state = MenuState.FORMATION
	_title.text = "Formación de combate"
	_clear_content()
	for m in GameState.party:
		var zone := clampi(int(m.get("start_position", 0)), 0, BattleUI.POSITION_NAMES.size() - 1)
		var warning := ""
		# A melee class parked in the back rank can't reach anything at all — worth flagging here
		# rather than letting the player discover it mid-fight.
		if zone == Combatant.POS_BACK and Combatant.is_melee_class(str(m.get("class", ""))):
			warning = "  (no alcanza a nadie desde atrás)"
		_add_row("%s: %s%s" % [m["name"], BattleUI.POSITION_NAMES[zone], warning], 24)
	_add_row("Z cambia la zona del personaje marcado.", 16)
	_selected_index = 0
	_update_highlight()
	_root.visible = true

func _cycle_formation(idx: int) -> void:
	if idx >= GameState.party.size():
		return
	var m = GameState.party[idx]
	m["start_position"] = (int(m.get("start_position", 0)) + 1) % BattleUI.POSITION_NAMES.size()
	var keep := idx
	_show_formation()
	_selected_index = keep
	_update_highlight()

# --- Guardar partida ---

func _save_game() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var pos = player.global_position if player else Vector3.ZERO
	SaveManager.save_game(DataLoader.get_current_map_path(), pos)
	_show_message("Partida guardada.")

# --- Estado ---

func _mod_str(value: int) -> String:
	return ("+%d" % value) if value >= 0 else str(value)

func _show_status() -> void:
	_menu_state = MenuState.STATUS
	_title.text = "Estado de la party"
	_clear_content()
	for m in GameState.party:
		var feat_names: Array = []
		for feat_id in m.get("feats", []):
			feat_names.append(DataLoader.get_feat(feat_id).get("name", feat_id))
		var feats_text = ", ".join(feat_names) if not feat_names.is_empty() else "-"
		_add_row("%s: %s %s (Nivel %d)" % [m["name"], m.get("race", ""), m.get("class", ""), m.get("level", 1)], 22)
		_add_row("HP %d/%d   MP %d/%d   CA %d" % [
			m.get("hp", 0), m.get("max_hp", 0), m.get("mp", 0), m.get("max_mp", 0), m.get("ca", 10)
		], 18)
		_add_row("FUE %s   AGI %s   CON %s   SAB %s   INT %s   CAR %s" % [
			_mod_str(m.get("str_mod", 0)), _mod_str(m.get("dex_mod", 0)), _mod_str(m.get("con_mod", 0)),
			_mod_str(m.get("wis_mod", 0)), _mod_str(m.get("int_mod", 0)), _mod_str(m.get("cha_mod", 0)),
		], 16)
		_add_row("Feats: %s" % feats_text, 16)
	_add_row(_xp_progress_text(), 16)
	_root.visible = true

func _xp_progress_text() -> String:
	var level = int(GameState.party[0].get("level", 1)) if not GameState.party.is_empty() else 1
	if level >= GameState.MAX_LEVEL:
		return "XP total: %d (nivel máximo alcanzado)" % GameState.total_xp
	var next_threshold = GameState.XP_LEVEL_THRESHOLDS[level]
	return "XP: %d / %d para nivel %d" % [GameState.total_xp, next_threshold, level + 1]

# --- Habilidades (solo curación, usable fuera de combate) ---

func _show_abilities() -> void:
	_menu_state = MenuState.ABILITIES
	_title.text = "Habilidades"
	_clear_content()
	_ability_options.clear()
	for m in GameState.party:
		for skill_id in m.get("skills", []):
			var skill = DataLoader.get_skill(skill_id)
			if skill.get("effect_type", "") == "heal":
				_ability_options.append({"member": m, "skill": skill})

	if _ability_options.is_empty():
		_add_row("Nadie tiene habilidades usables fuera de combate.", 20)
	else:
		for opt in _ability_options:
			_add_row("%s: %s (MP %d)" % [opt["member"]["name"], opt["skill"]["name"], opt["skill"].get("mp_cost", 0)])

	_selected_index = 0
	_update_highlight()
	_root.visible = true

func _select_ability(idx: int) -> void:
	if idx >= _ability_options.size():
		return
	_pending_ability = _ability_options[idx]
	_show_ally_targets(MenuState.ABILITY_TARGET, "¿A quién curar?")

func _select_ability_target(idx: int) -> void:
	if idx >= _target_options.size():
		return
	var caster = _pending_ability["member"]
	var skill = _pending_ability["skill"]
	var target = _target_options[idx]
	if not Combatant.use_mp(caster, skill.get("mp_cost", 0)):
		_show_message("%s no tiene suficiente MP." % caster["name"])
		return
	var heal = Combatant.calculate_heal(caster, skill.get("power", 0))
	GameState.heal_party_member(target["id"], heal)
	_show_message("%s usa %s en %s: cura %d HP!" % [caster["name"], skill["name"], target["name"], heal])

# --- Objetos ---

func _show_items() -> void:
	_menu_state = MenuState.ITEMS
	_title.text = "Objetos"
	_clear_content()
	_item_options.clear()
	for item in GameState.inventory:
		if item.get("quantity", 0) > 0:
			_item_options.append(item)

	if _item_options.is_empty():
		_add_row("No tienes objetos.", 20)
	else:
		for item in _item_options:
			_add_row("%s x%d" % [item["name"], item["quantity"]])

	_selected_index = 0
	_update_highlight()
	_root.visible = true

func _select_item(idx: int) -> void:
	if idx >= _item_options.size():
		return
	_pending_item = _item_options[idx]
	_show_ally_targets(MenuState.ITEM_TARGET, "¿A quién usarlo?")

func _select_item_target(idx: int) -> void:
	if idx >= _target_options.size():
		return
	var item_data = DataLoader.get_item(_pending_item.get("id", ""))
	var target = _target_options[idx]
	if item_data.get("effect", "") == "heal":
		var heal_amount = item_data.get("power", 30)
		GameState.heal_party_member(target["id"], heal_amount)
		GameState.remove_item(_pending_item["id"])
		_show_message("Usas %s en %s: cura %d HP!" % [_pending_item["name"], target["name"], heal_amount])
	else:
		_show_message("%s no tiene efecto fuera de combate." % _pending_item["name"])

# --- Shared ally-target picker ---

func _show_ally_targets(next_state: MenuState, title: String) -> void:
	_menu_state = next_state
	_title.text = title
	_clear_content()
	_target_options.clear()
	for m in GameState.party:
		_target_options.append(m)
		_add_row("%s (HP %d/%d)" % [m["name"], m.get("hp", 0), m.get("max_hp", 0)])
	_selected_index = 0
	_update_highlight()
	_root.visible = true

func _show_message(text: String) -> void:
	_menu_state = MenuState.MESSAGE
	_title.text = "Menú"
	_clear_content()
	_add_row(text, 22)
	_root.visible = true

# --- Salir del juego ---

func _show_quit_confirm() -> void:
	_menu_state = MenuState.QUIT_CONFIRM
	_title.text = "¿Salir del juego?"
	_clear_content()
	_add_row("Sí", 26)
	_add_row("No", 26)
	_selected_index = 1  # default a "No" para evitar un cierre accidental
	_update_highlight()
	_root.visible = true

func _select_quit_option(idx: int) -> void:
	if idx == 0:
		get_tree().quit()
	else:
		_show_main()
