extends CanvasLayer
class_name DebugBattleHUD
## DebugBattleHUD — Toggle with F1 during combat

var _battle_controller = null
var _battle_ui = null
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _combatant_list: VBoxContainer = null
var _actions_box: VBoxContainer = null
var _info_label: Label = null

var _selected_combatant: Dictionary = {}
var _selected_index: int = -1
var _all_combatants: Array[Dictionary] = []
var _visible: bool = false

const DMG_AMOUNTS = [1, 5, 10, 25, 50, 100]

func _ready() -> void:
	layer = 99
	_build_panel()
	_panel.visible = false

func setup(battle_ctrl, battle_ui) -> void:
	_battle_controller = battle_ctrl
	_battle_ui = battle_ui

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_toggle()
			get_viewport().set_input_as_handled()

func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_refresh_combatants()

func _build_panel() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Semi-transparent overlay on the left side
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_right = 520
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	style.border_color = Color(0.0, 1.0, 0.0, 0.6)
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	# Title
	var title = Label.new()
	title.text = "DEBUG COMBAT (F1 toggle)"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0))
	_content.add_child(title)

	# Info label
	_info_label = Label.new()
	_info_label.text = "Select a combatant:"
	_info_label.add_theme_font_size_override("font_size", 22)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content.add_child(_info_label)

	# Combatant list
	_combatant_list = VBoxContainer.new()
	_combatant_list.add_theme_constant_override("separation", 2)
	_content.add_child(_combatant_list)

	# Separator
	var sep = HSeparator.new()
	_content.add_child(sep)

	# Actions
	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 4)
	_content.add_child(_actions_box)

func _refresh_combatants() -> void:
	_all_combatants.clear()
	_clear(_combatant_list)

	if not _battle_controller:
		return

	# Party first, then enemies
	var party = _battle_controller.get_party()
	var enemies = _battle_controller.get_enemies()

	var section_party = Label.new()
	section_party.text = "--- PARTY ---"
	section_party.add_theme_font_size_override("font_size", 20)
	section_party.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	_combatant_list.add_child(section_party)

	for p in party:
		_all_combatants.append(p)
		var btn = _make_combatant_button(p, _all_combatants.size() - 1)
		_combatant_list.add_child(btn)

	var section_enemy = Label.new()
	section_enemy.text = "--- ENEMIES ---"
	section_enemy.add_theme_font_size_override("font_size", 20)
	section_enemy.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_combatant_list.add_child(section_enemy)

	for e in enemies:
		_all_combatants.append(e)
		var btn = _make_combatant_button(e, _all_combatants.size() - 1)
		_combatant_list.add_child(btn)

	_rebuild_actions()

func _make_combatant_button(c: Dictionary, idx: int) -> Button:
	var btn = Button.new()
	var hp = c.get("hp", 0)
	var max_hp = c.get("max_hp", 0)
	var mp = c.get("mp", 0)
	var max_mp = c.get("max_mp", 0)
	var dead_str = " [DEAD]" if hp <= 0 else ""
	btn.text = "%s  HP:%d/%d  MP:%d/%d%s" % [c.get("name", "???"), hp, max_hp, mp, max_mp, dead_str]
	btn.add_theme_font_size_override("font_size", 20)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if idx == _selected_index:
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	elif hp <= 0:
		btn.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))

	btn.pressed.connect(_on_combatant_selected.bind(idx))
	return btn

func _on_combatant_selected(idx: int) -> void:
	_selected_index = idx
	if idx >= 0 and idx < _all_combatants.size():
		_selected_combatant = _all_combatants[idx]
		var c = _selected_combatant
		_info_label.text = "Selected: %s (HP:%d/%d MP:%d/%d)" % [
			c.get("name", "???"), c.get("hp", 0), c.get("max_hp", 0),
			c.get("mp", 0), c.get("max_mp", 0)
		]
	_refresh_combatants()

func _rebuild_actions() -> void:
	_clear(_actions_box)

	if _selected_combatant.is_empty():
		var lbl = Label.new()
		lbl.text = "Select a combatant first"
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_actions_box.add_child(lbl)
		return

	var name = _selected_combatant.get("name", "???")

	# --- Quick actions row ---
	var quick_label = Label.new()
	quick_label.text = "Actions for: %s" % name
	quick_label.add_theme_font_size_override("font_size", 22)
	quick_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_actions_box.add_child(quick_label)

	var quick_row = HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 6)
	_actions_box.add_child(quick_row)

	_add_action_button(quick_row, "Kill", _do_kill)
	_add_action_button(quick_row, "Full Heal", _do_full_heal)
	_add_action_button(quick_row, "Revive Full", _do_revive)

	# --- Set HP to % ---
	var hp_pct_label = Label.new()
	hp_pct_label.text = "Set HP %:"
	hp_pct_label.add_theme_font_size_override("font_size", 20)
	hp_pct_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_actions_box.add_child(hp_pct_label)

	var pct_row = HBoxContainer.new()
	pct_row.add_theme_constant_override("separation", 4)
	_actions_box.add_child(pct_row)

	for pct in [10, 25, 50, 75, 100]:
		_add_action_button(pct_row, "%d%%" % pct, _do_set_hp_pct.bind(pct))

	# --- Deal damage ---
	var dmg_label = Label.new()
	dmg_label.text = "Deal damage:"
	dmg_label.add_theme_font_size_override("font_size", 20)
	dmg_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_actions_box.add_child(dmg_label)

	var dmg_row = HBoxContainer.new()
	dmg_row.add_theme_constant_override("separation", 4)
	_actions_box.add_child(dmg_row)

	for amt in DMG_AMOUNTS:
		_add_action_button(dmg_row, "-%d" % amt, _do_damage.bind(amt))

	# --- Heal ---
	var heal_label = Label.new()
	heal_label.text = "Heal:"
	heal_label.add_theme_font_size_override("font_size", 20)
	heal_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_actions_box.add_child(heal_label)

	var heal_row = HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 4)
	_actions_box.add_child(heal_row)

	for amt in DMG_AMOUNTS:
		_add_action_button(heal_row, "+%d" % amt, _do_heal.bind(amt))

	# --- Set MP ---
	var mp_label = Label.new()
	mp_label.text = "Set MP %:"
	mp_label.add_theme_font_size_override("font_size", 20)
	mp_label.add_theme_color_override("font_color", Color(0.5, 0.5, 1.0))
	_actions_box.add_child(mp_label)

	var mp_row = HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 4)
	_actions_box.add_child(mp_row)

	for pct in [0, 25, 50, 75, 100]:
		_add_action_button(mp_row, "%d%%" % pct, _do_set_mp_pct.bind(pct))

func _add_action_button(parent: HBoxContainer, text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(70, 32)
	btn.pressed.connect(callback)
	parent.add_child(btn)

# --- Action callbacks ---

func _do_kill() -> void:
	if _selected_combatant.is_empty():
		return
	_selected_combatant["hp"] = 0
	_after_change()

func _do_full_heal() -> void:
	if _selected_combatant.is_empty():
		return
	_selected_combatant["hp"] = _selected_combatant.get("max_hp", 1)
	_selected_combatant["mp"] = _selected_combatant.get("max_mp", 0)
	_after_change()

func _do_revive() -> void:
	if _selected_combatant.is_empty():
		return
	_selected_combatant["hp"] = _selected_combatant.get("max_hp", 1)
	_after_change()

func _do_set_hp_pct(pct: int) -> void:
	if _selected_combatant.is_empty():
		return
	var max_hp = _selected_combatant.get("max_hp", 1)
	_selected_combatant["hp"] = maxi(0, int(max_hp * pct / 100.0))
	_after_change()

func _do_damage(amount: int) -> void:
	if _selected_combatant.is_empty():
		return
	_selected_combatant["hp"] = maxi(0, _selected_combatant.get("hp", 0) - amount)
	_after_change()

func _do_heal(amount: int) -> void:
	if _selected_combatant.is_empty():
		return
	var max_hp = _selected_combatant.get("max_hp", 1)
	_selected_combatant["hp"] = mini(max_hp, _selected_combatant.get("hp", 0) + amount)
	_after_change()

func _do_set_mp_pct(pct: int) -> void:
	if _selected_combatant.is_empty():
		return
	var max_mp = _selected_combatant.get("max_mp", 0)
	_selected_combatant["mp"] = maxi(0, int(max_mp * pct / 100.0))
	_after_change()

func _after_change() -> void:
	# Notify BattleUI to refresh bars and stats
	if _battle_controller:
		_battle_controller.hp_updated.emit()
	_refresh_combatants()

func _clear(container) -> void:
	if not container:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
