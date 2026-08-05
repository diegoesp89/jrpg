extends CanvasLayer
class_name DebugPanel
## DebugPanel — In-game debug tools, gated behind GameState.admin_mode (secret directional code
## on the main menu, see ContinueScreen.gd). Mouse-driven like MapEditor.gd (the other admin-only
## tool) rather than the arrow-key row navigation OptionsPanel/StatusMenu use for player-facing
## screens — editing raw numbers/ids by hand needs real text fields, and both admin tools are
## already exempt from the game's "no mouse during actual play" rule for exactly that reason.
##
## Every list here (party, inventory, flags) is rebuilt fresh in open(), since all three can
## change at any time during exploration and the player might reopen this panel much later.

var _is_open: bool = false
var _root: Control
var _party_container: VBoxContainer
var _inventory_container: VBoxContainer
var _add_item_field: LineEdit
var _flags_container: VBoxContainer
var _add_flag_field: LineEdit
var _status_label: Label

func _ready() -> void:
	layer = 65
	_build_ui()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)
	_refresh_party()
	_refresh_inventory()
	_refresh_flags()
	_status_label.text = ""
	_root.visible = true

func close() -> void:
	_is_open = false
	_root.visible = false
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(false)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.03, 0.03, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title = Label.new()
	title.text = "Panel de Debug"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12
	title.offset_bottom = 50
	_root.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 60
	scroll.offset_right = -60
	scroll.offset_top = 60
	scroll.offset_bottom = -90
	_root.add_child(scroll)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 20)
	scroll.add_child(main_vbox)

	_build_section(main_vbox, "HP / MP")
	_party_container = VBoxContainer.new()
	_party_container.add_theme_constant_override("separation", 6)
	main_vbox.add_child(_party_container)

	_build_section(main_vbox, "Inventario")
	_inventory_container = VBoxContainer.new()
	_inventory_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_inventory_container)

	var add_item_row = HBoxContainer.new()
	add_item_row.add_theme_constant_override("separation", 8)
	main_vbox.add_child(add_item_row)
	_add_item_field = LineEdit.new()
	_add_item_field.placeholder_text = "id de item"
	_add_item_field.custom_minimum_size = Vector2(200, 0)
	add_item_row.add_child(_add_item_field)
	var add_item_btn = Button.new()
	add_item_btn.text = "Agregar item"
	add_item_btn.pressed.connect(_on_add_item_pressed)
	add_item_row.add_child(add_item_btn)

	var item_hint = Label.new()
	item_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_hint.add_theme_font_size_override("font_size", 12)
	item_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	var ids: Array = []
	for item_def in DataLoader.get_all_items():
		ids.append(str(item_def.get("id", "")))
	item_hint.text = "Items disponibles: %s" % ", ".join(ids)
	main_vbox.add_child(item_hint)

	_build_section(main_vbox, "Flags")
	_flags_container = VBoxContainer.new()
	_flags_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_flags_container)

	var add_flag_row = HBoxContainer.new()
	add_flag_row.add_theme_constant_override("separation", 8)
	main_vbox.add_child(add_flag_row)
	_add_flag_field = LineEdit.new()
	_add_flag_field.placeholder_text = "nombre de flag"
	_add_flag_field.custom_minimum_size = Vector2(200, 0)
	add_flag_row.add_child(_add_flag_field)
	var add_flag_btn = Button.new()
	add_flag_btn.text = "Activar flag"
	add_flag_btn.pressed.connect(_on_add_flag_pressed)
	add_flag_row.add_child(add_flag_btn)

	_build_section(main_vbox, "Accesos rápidos")
	var quick_row = HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(quick_row)
	var heal_all_btn = Button.new()
	heal_all_btn.text = "Curar party completa"
	heal_all_btn.pressed.connect(_on_heal_all_pressed)
	quick_row.add_child(heal_all_btn)
	var credits_btn = Button.new()
	credits_btn.text = "Ir a Créditos"
	credits_btn.pressed.connect(_on_go_to_credits_pressed)
	quick_row.add_child(credits_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	main_vbox.add_child(_status_label)

	var hint = Label.new()
	hint.text = "X / Esc: Cerrar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func _build_section(parent: VBoxContainer, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	parent.add_child(lbl)

func _set_status(text: String) -> void:
	_status_label.text = text

# --- Party HP/MP ---

func _refresh_party() -> void:
	for child in _party_container.get_children():
		child.queue_free()
	for member in GameState.party:
		_party_container.add_child(_build_party_row(member))

func _build_party_row(member: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_lbl = Label.new()
	name_lbl.text = str(member.get("name", "???"))
	name_lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_lbl)

	var hp_field = LineEdit.new()
	hp_field.text = str(member.get("hp", 0))
	hp_field.custom_minimum_size = Vector2(60, 0)
	row.add_child(hp_field)

	var hp_slash = Label.new()
	hp_slash.text = "/ %d HP" % int(member.get("max_hp", 0))
	row.add_child(hp_slash)

	var mp_field = LineEdit.new()
	mp_field.text = str(member.get("mp", 0))
	mp_field.custom_minimum_size = Vector2(60, 0)
	row.add_child(mp_field)

	var mp_slash = Label.new()
	mp_slash.text = "/ %d MP" % int(member.get("max_mp", 0))
	row.add_child(mp_slash)

	var apply_btn = Button.new()
	apply_btn.text = "Aplicar"
	apply_btn.pressed.connect(_on_apply_hp_mp.bind(member, hp_field, mp_field))
	row.add_child(apply_btn)

	var heal_btn = Button.new()
	heal_btn.text = "Curar"
	heal_btn.pressed.connect(_on_heal_member.bind(member, hp_field, mp_field))
	row.add_child(heal_btn)

	return row

func _on_apply_hp_mp(member: Dictionary, hp_field: LineEdit, mp_field: LineEdit) -> void:
	var max_hp := int(member.get("max_hp", 0))
	var max_mp := int(member.get("max_mp", 0))
	member["hp"] = clampi(hp_field.text.to_int(), 0, max_hp)
	member["mp"] = clampi(mp_field.text.to_int(), 0, max_mp)
	hp_field.text = str(member["hp"])
	mp_field.text = str(member["mp"])
	_set_status("%s actualizado." % member.get("name", "???"))

func _on_heal_member(member: Dictionary, hp_field: LineEdit, mp_field: LineEdit) -> void:
	member["hp"] = int(member.get("max_hp", 0))
	member["mp"] = int(member.get("max_mp", 0))
	hp_field.text = str(member["hp"])
	mp_field.text = str(member["mp"])
	_set_status("%s curado por completo." % member.get("name", "???"))

# --- Inventory ---

func _refresh_inventory() -> void:
	for child in _inventory_container.get_children():
		child.queue_free()
	if GameState.inventory.is_empty():
		var lbl = Label.new()
		lbl.text = "Inventario vacío."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_inventory_container.add_child(lbl)
		return
	for item in GameState.inventory:
		_inventory_container.add_child(_build_inventory_row(item))

func _build_inventory_row(item: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.text = "%s (%s)" % [str(item.get("name", "???")), str(item.get("id", ""))]
	lbl.custom_minimum_size = Vector2(240, 0)
	row.add_child(lbl)

	var qty_field = LineEdit.new()
	qty_field.text = str(item.get("quantity", 0))
	qty_field.custom_minimum_size = Vector2(60, 0)
	row.add_child(qty_field)

	var apply_btn = Button.new()
	apply_btn.text = "Aplicar"
	apply_btn.pressed.connect(_on_apply_quantity.bind(item, qty_field))
	row.add_child(apply_btn)

	var remove_btn = Button.new()
	remove_btn.text = "Quitar"
	remove_btn.pressed.connect(_on_remove_item.bind(item))
	row.add_child(remove_btn)

	return row

func _on_apply_quantity(item: Dictionary, qty_field: LineEdit) -> void:
	var qty := qty_field.text.to_int()
	if qty <= 0:
		GameState.inventory.erase(item)
	else:
		item["quantity"] = qty
	_refresh_inventory()
	_set_status("Inventario actualizado.")

func _on_remove_item(item: Dictionary) -> void:
	GameState.inventory.erase(item)
	_refresh_inventory()
	_set_status("Item eliminado.")

func _on_add_item_pressed() -> void:
	var id := _add_item_field.text.strip_edges()
	if id == "":
		return
	if DataLoader.get_item(id).is_empty():
		_set_status("Item desconocido: %s" % id)
		return
	GameState.add_item(id, 1)
	_add_item_field.text = ""
	_refresh_inventory()
	_set_status("Agregado: %s" % id)

# --- Flags ---

func _refresh_flags() -> void:
	for child in _flags_container.get_children():
		child.queue_free()
	var keys := GameState.flags.keys()
	keys.sort()
	if keys.is_empty():
		var lbl = Label.new()
		lbl.text = "No hay flags activas."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_flags_container.add_child(lbl)
		return
	for key in keys:
		var cb = CheckBox.new()
		cb.text = str(key)
		cb.button_pressed = bool(GameState.flags.get(key, false))
		cb.toggled.connect(func(pressed): GameState.flags[key] = pressed)
		_flags_container.add_child(cb)

func _on_add_flag_pressed() -> void:
	var flag_name := _add_flag_field.text.strip_edges()
	if flag_name == "":
		return
	GameState.set_flag(flag_name)
	_add_flag_field.text = ""
	_refresh_flags()
	_set_status("Flag activada: %s" % flag_name)

# --- Quick actions ---

func _on_heal_all_pressed() -> void:
	for member in GameState.party:
		member["hp"] = int(member.get("max_hp", 0))
		member["mp"] = int(member.get("max_mp", 0))
	_refresh_party()
	_set_status("Party curada por completo.")

func _on_go_to_credits_pressed() -> void:
	SceneFlow.change_scene("res://scenes/boot/CreditsScreen.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
