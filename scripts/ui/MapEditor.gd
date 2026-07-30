extends CanvasLayer
class_name MapEditor
## MapEditor — In-game 2D top-down map editor. Edits the currently loaded map's tiles and
## entity placements (NPCs, chests, traps, combat/boss triggers, riddle gates, random-encounter
## zones, story triggers, player start) and can save to res://maps/*.map, load another map,
## start a blank one, or playtest in-memory edits without saving.

const MAPS_DIR := "res://maps/"

const TOOLS := [
	{"id": "erase", "label": "Vacío", "tile": 0},
	{"id": "floor", "label": "Piso", "tile": 1},
	{"id": "wall", "label": "Pared", "tile": 2},
	{"id": "door", "label": "Puerta", "tile": 3},
	{"id": "npc", "label": "NPC", "tile": 4, "list": "npcs"},
	{"id": "chest", "label": "Cofre", "tile": 5, "list": "chests"},
	{"id": "combat_trigger", "label": "Trigger Combate", "tile": 6, "list": "combat_triggers"},
	{"id": "trap", "label": "Trampa", "tile": 7, "list": "traps"},
	{"id": "boss_trigger", "label": "Trigger Jefe", "tile": 8, "list": "boss_triggers"},
	{"id": "exit", "label": "Salida", "tile": 9},
	{"id": "riddle_gate", "label": "Puerta Enigma", "tile": 10, "list": "riddle_gates"},
	{"id": "player_start", "label": "Inicio Jugador"},
	{"id": "zone", "label": "Zona Encuentros"},
	{"id": "story_trigger", "label": "Story Trigger"},
]

## Set to true by MapEditorScreen when opened directly from MapSelection's "Editar"
## button, with no dungeon/player in the scene. Changes Cerrar/Playtest to navigate
## between boot screens instead of resuming/reloading an in-game exploration session.
var standalone: bool = false

var _is_open: bool = false
var _map_data: Dictionary = {}
var _map_path: String = ""
var _tiles: Array = []
var _entities: Dictionary = {}

var _current_tool: Dictionary = TOOLS[0]
var _drag_start_cell: Vector2i = Vector2i(-1, -1)
var _editing_existing_zone: bool = false

var _selected_kind: String = ""
var _selected_list_key: String = ""
var _selected_entry: Dictionary = {}
var _prop_fields: Dictionary = {}

var _root: Control
var _grid: MapEditorGrid
var _grid_scroll: ScrollContainer
var _palette_container: VBoxContainer
var _props_container: VBoxContainer
var _status_label: Label
var _tool_buttons: Array = []

var _prompt_panel: Control
var _prompt_title: Label
var _prompt_line_edit: LineEdit
var _prompt_callback: Callable = Callable()

var _load_panel: Control
var _load_list_container: VBoxContainer

func _ready() -> void:
	layer = 70
	var current = DataLoader.get_current_map()
	_map_data = current.duplicate(true) if not current.is_empty() else {"name": "Sin nombre", "tile_size": 2.0, "tiles": [], "entities": {}}
	_map_path = DataLoader.get_current_map_path()
	_tiles = _map_data.get("tiles", [])
	_entities = _map_data.get("entities", {})
	_build_ui()
	if standalone:
		_is_open = true
		_grid.set_data(_tiles, _entities)
		_root.visible = true

# --- Open / close ---

func open_editor() -> void:
	if _is_open:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("is_movement_disabled") and player.is_movement_disabled():
		return
	_is_open = true
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)
	_grid.set_data(_tiles, _entities)
	_root.visible = true

func close_editor() -> void:
	if standalone:
		SceneFlow.change_scene("res://scenes/boot/MapSelection.tscn")
		return
	_is_open = false
	_root.visible = false
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(false)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _prompt_panel.visible:
			_on_prompt_cancelled()
		elif _load_panel.visible:
			_load_panel.visible = false
		else:
			close_editor()
		get_viewport().set_input_as_handled()

# --- UI construction ---

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title = Label.new()
	title.text = "Editor de Mapa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12
	title.offset_bottom = 50
	_root.add_child(title)

	var hint = Label.new()
	hint.text = "Click: pintar/colocar  |  Click derecho o del medio + arrastrar: mover vista  |  Scroll: zoom"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 50
	hint.offset_bottom = 74
	_root.add_child(hint)

	# Main row fills all remaining space between the title and the action bar, so the layout
	# scales with the window instead of sitting at fixed pixel offsets (which left everything
	# crammed in a corner on large windows).
	var main_row = HBoxContainer.new()
	main_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_row.offset_left = 16
	main_row.offset_right = -16
	main_row.offset_top = 82
	main_row.offset_bottom = -104
	main_row.add_theme_constant_override("separation", 14)
	_root.add_child(main_row)

	# --- Palette (left, fixed width) ---
	var palette_panel = PanelContainer.new()
	palette_panel.custom_minimum_size = Vector2(190, 0)
	palette_panel.add_theme_stylebox_override("panel", _make_panel_style())
	main_row.add_child(palette_panel)

	var palette_scroll = ScrollContainer.new()
	palette_panel.add_child(palette_scroll)

	_palette_container = VBoxContainer.new()
	_palette_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_container.add_theme_constant_override("separation", 4)
	palette_scroll.add_child(_palette_container)
	_build_palette()

	# --- Grid (center, expands to fill available space) ---
	var grid_panel = PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.add_theme_stylebox_override("panel", _make_panel_style())
	main_row.add_child(grid_panel)

	_grid_scroll = ScrollContainer.new()
	grid_panel.add_child(_grid_scroll)

	_grid = MapEditorGrid.new()
	_grid.drag_started.connect(_on_grid_drag_started)
	_grid.drag_moved.connect(_on_grid_drag_moved)
	_grid.drag_ended.connect(_on_grid_drag_ended)
	_grid.pan_requested.connect(_on_grid_pan_requested)
	_grid_scroll.add_child(_grid)

	# --- Properties (right, fixed width) ---
	var props_panel = PanelContainer.new()
	props_panel.custom_minimum_size = Vector2(320, 0)
	props_panel.add_theme_stylebox_override("panel", _make_panel_style())
	main_row.add_child(props_panel)

	var props_scroll = ScrollContainer.new()
	props_panel.add_child(props_scroll)

	_props_container = VBoxContainer.new()
	_props_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props_container.add_theme_constant_override("separation", 8)
	props_scroll.add_child(_props_container)
	_show_no_selection()

	var action_bar = HBoxContainer.new()
	action_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	action_bar.offset_top = -90
	action_bar.offset_bottom = -50
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("separation", 16)
	_root.add_child(action_bar)

	_add_action_button(action_bar, "Guardar", _on_save_pressed)
	_add_action_button(action_bar, "Guardar como", _on_save_as_pressed)
	_add_action_button(action_bar, "Nuevo mapa", _on_new_map_pressed)
	_add_action_button(action_bar, "Cargar mapa", _on_load_map_pressed)
	_add_action_button(action_bar, "Redimensionar", _on_resize_pressed)
	_add_action_button(action_bar, "Playtest", _on_playtest_pressed)
	_add_action_button(action_bar, "Cerrar", close_editor)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_top = -45
	_status_label.offset_bottom = -15
	_root.add_child(_status_label)

	_build_prompt_panel()
	_build_load_panel()

func _make_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.14)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _add_action_button(parent: HBoxContainer, text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _build_palette() -> void:
	for tool in TOOLS:
		var btn = Button.new()
		btn.text = tool["label"]
		btn.icon = _make_color_icon(_tool_color(tool))
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 18)
		btn.toggle_mode = true
		btn.button_pressed = (tool["id"] == _current_tool["id"])
		btn.pressed.connect(_select_tool.bind(tool, btn))
		_palette_container.add_child(btn)
		_tool_buttons.append(btn)

## The exact color this tool paints on the grid, so the palette doubles as a legend.
func _tool_color(tool: Dictionary) -> Color:
	if tool.has("tile"):
		return MapEditorGrid.TILE_COLORS.get(tool["tile"], Color.WHITE)
	match tool.get("id", ""):
		"player_start":
			return MapEditorGrid.PLAYER_START_COLOR
		"zone":
			return MapEditorGrid.ZONE_BORDER_COLOR
		"story_trigger":
			return MapEditorGrid.STORY_TRIGGER_COLOR
		_:
			return Color.WHITE

func _make_color_icon(color: Color, size: int = 16) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var border = Color(1, 1, 1, 0.6)
	for x in range(size):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, size - 1, border)
	for y in range(size):
		img.set_pixel(0, y, border)
		img.set_pixel(size - 1, y, border)
	return ImageTexture.create_from_image(img)

func _select_tool(tool: Dictionary, btn: Button) -> void:
	_current_tool = tool
	for b in _tool_buttons:
		b.button_pressed = (b == btn)
	_set_status("Herramienta: %s" % tool["label"])

# --- Grid interaction ---

func _tool_category(tool: Dictionary) -> String:
	match tool.get("id", ""):
		"erase", "floor", "wall", "door", "exit":
			return "tile"
		"player_start":
			return "player_start"
		"zone":
			return "zone"
		"story_trigger":
			return "story"
		_:
			return "entity"

func _on_grid_drag_started(row: int, col: int) -> void:
	_drag_start_cell = Vector2i(col, row)
	match _tool_category(_current_tool):
		"tile":
			_paint_tile(row, col)
		"entity":
			_place_or_select_entity(_current_tool, row, col)
		"player_start":
			_set_player_start(row, col)
		"story":
			_place_or_select_entity({"id": "story_trigger", "list": "story_triggers"}, row, col)
		"zone":
			# Clicking inside an already-placed zone selects it for editing/deletion instead
			# of always stamping a new one on top — otherwise there was no way to get back
			# to an existing zone once you'd clicked past it.
			var existing = _find_zone_at(row, col)
			_editing_existing_zone = not existing.is_empty()
			if _editing_existing_zone:
				_open_property_panel("zone", "random_encounter_zones", existing)

func _on_grid_drag_moved(row: int, col: int) -> void:
	match _tool_category(_current_tool):
		"tile":
			_paint_tile(row, col)
		"zone":
			if _editing_existing_zone:
				return
			var min_c = mini(_drag_start_cell.x, col)
			var max_c = maxi(_drag_start_cell.x, col)
			var min_r = mini(_drag_start_cell.y, row)
			var max_r = maxi(_drag_start_cell.y, row)
			_grid.highlight_rect = Rect2i(min_c, min_r, max_c - min_c + 1, max_r - min_r + 1)
			_grid.queue_redraw()

func _on_grid_drag_ended(row: int, col: int) -> void:
	if _tool_category(_current_tool) == "zone":
		if not _editing_existing_zone:
			_place_zone(_drag_start_cell, Vector2i(col, row))
		_grid.highlight_rect = Rect2i(-1, -1, 0, 0)
		_grid.queue_redraw()

## Returns the zone entry (if any) whose rectangle contains (row, col), for click-to-select.
func _find_zone_at(row: int, col: int) -> Dictionary:
	for zone in _entities.get("random_encounter_zones", []):
		var zr = float(zone.get("row", 0))
		var zc = float(zone.get("col", 0))
		var w = float(zone.get("width", 1))
		var h = float(zone.get("height", 1))
		var min_c = zc - (w - 1.0) / 2.0
		var max_c = zc + (w - 1.0) / 2.0
		var min_r = zr - (h - 1.0) / 2.0
		var max_r = zr + (h - 1.0) / 2.0
		if col >= min_c - 0.01 and col <= max_c + 0.01 and row >= min_r - 0.01 and row <= max_r + 0.01:
			return zone
	return {}

## Middle-click-drag or right-click-drag pans the view (grab-and-drag: content follows
## the cursor, so the scroll offset moves opposite the mouse delta).
func _on_grid_pan_requested(delta: Vector2) -> void:
	_grid_scroll.scroll_horizontal -= int(delta.x)
	_grid_scroll.scroll_vertical -= int(delta.y)

func _paint_tile(row: int, col: int) -> void:
	if row < 0 or row >= _tiles.size() or col < 0 or col >= _tiles[row].size():
		return
	_tiles[row][col] = _current_tool.get("tile", 0)
	_remove_entities_at(row, col)
	_grid.set_data(_tiles, _entities)
	_set_status("(%d,%d) -> %s" % [row, col, _current_tool["label"]])

func _remove_entities_at(row: int, col: int) -> void:
	for list_key in ["npcs", "chests", "traps", "combat_triggers", "riddle_gates", "boss_triggers", "story_triggers"]:
		var list: Array = _entities.get(list_key, [])
		for i in range(list.size() - 1, -1, -1):
			var entry = list[i]
			if int(entry.get("row", -1)) == row and int(entry.get("col", -1)) == col:
				list.remove_at(i)
		_entities[list_key] = list

func _find_entity_at(list_key: String, row: int, col: int) -> Dictionary:
	for entry in _entities.get(list_key, []):
		if int(entry.get("row", -1)) == row and int(entry.get("col", -1)) == col:
			return entry
	return {}

func _apply_default_props(kind: String, entry: Dictionary) -> void:
	match kind:
		"npc":
			var ids = DataLoader.get_all_dialogue_ids()
			entry["dialogue_id"] = ids[0] if ids.size() > 0 else ""
		"chest":
			entry["item_id"] = "potion"
			entry["quantity"] = 1
			entry["chest_id"] = "chest_%d_%d" % [entry["row"], entry["col"]]
		"combat_trigger", "boss_trigger":
			var ids = DataLoader.get_all_encounter_ids()
			entry["encounter_id"] = ids[0] if ids.size() > 0 else ""
		"trap":
			entry["damage"] = 10
		"riddle_gate":
			entry["encounter_id"] = "encounter_sphinx"
			entry["success_event_id"] = ""
			entry["combat_event_id"] = ""
		"story_trigger":
			entry["event_id"] = ""
			entry["requires_flag"] = ""

func _place_or_select_entity(tool: Dictionary, row: int, col: int) -> void:
	var kind = tool["id"]
	var list_key = tool["list"]
	var existing = _find_entity_at(list_key, row, col)
	if existing.is_empty():
		existing = {"row": row, "col": col}
		_apply_default_props(kind, existing)
		var list: Array = _entities.get(list_key, [])
		list.append(existing)
		_entities[list_key] = list
		if tool.has("tile"):
			_tiles[row][col] = tool["tile"]
		elif row < _tiles.size() and col < _tiles[row].size() and _tiles[row][col] == 0:
			_tiles[row][col] = 1
	_grid.set_data(_tiles, _entities)
	_open_property_panel(kind, list_key, existing)

func _set_player_start(row: int, col: int) -> void:
	if row < _tiles.size() and col < _tiles[row].size() and _tiles[row][col] == 0:
		_tiles[row][col] = 1
	_entities["player_start"] = {"row": row, "col": col}
	_grid.set_data(_tiles, _entities)
	_set_status("Inicio del jugador: (%d, %d)" % [row, col])
	_show_no_selection()

func _place_zone(start: Vector2i, end: Vector2i) -> void:
	var min_c = mini(start.x, end.x)
	var max_c = maxi(start.x, end.x)
	var min_r = mini(start.y, end.y)
	var max_r = maxi(start.y, end.y)
	var zone = {
		"row": (min_r + max_r) / 2.0,
		"col": (min_c + max_c) / 2.0,
		"width": max_c - min_c + 1,
		"height": max_r - min_r + 1,
		"encounter_ids": [],
		"chance": 0.25,
		"interval": 8.0,
	}
	var list: Array = _entities.get("random_encounter_zones", [])
	list.append(zone)
	_entities["random_encounter_zones"] = list
	_grid.set_data(_tiles, _entities)
	_open_property_panel("zone", "random_encounter_zones", zone)

# --- Property panel ---

func _show_no_selection() -> void:
	_selected_kind = ""
	_selected_list_key = ""
	_selected_entry = {}
	for child in _props_container.get_children():
		child.queue_free()
	var lbl = Label.new()
	lbl.text = "Elegí una herramienta y hacé click en la grilla."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_props_container.add_child(lbl)

func _open_property_panel(kind: String, list_key: String, entry: Dictionary) -> void:
	_selected_kind = kind
	_selected_list_key = list_key
	_selected_entry = entry
	_prop_fields.clear()
	for child in _props_container.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "%s (%s, %s)" % [kind.capitalize(), str(entry.get("row", "")), str(entry.get("col", ""))]
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_props_container.add_child(header)

	match kind:
		"npc":
			_add_option_field("dialogue_id", "Dialogo", DataLoader.get_all_dialogue_ids(), str(entry.get("dialogue_id", "")))
		"chest":
			_add_option_field("item_id", "Item", DataLoader.get_all_item_ids(), str(entry.get("item_id", "")))
			_add_text_field("quantity", "Cantidad", str(entry.get("quantity", 1)))
			_add_text_field("chest_id", "ID del cofre", str(entry.get("chest_id", "")))
		"combat_trigger", "boss_trigger":
			_add_option_field("encounter_id", "Encuentro", DataLoader.get_all_encounter_ids(), str(entry.get("encounter_id", "")))
		"trap":
			_add_text_field("damage", "Daño", str(entry.get("damage", 10)))
		"riddle_gate":
			_add_option_field("encounter_id", "Encuentro (guardiana)", DataLoader.get_all_encounter_ids(), str(entry.get("encounter_id", "")))
			_add_text_field("success_event_id", "Evento (éxito)", str(entry.get("success_event_id", "")))
			_add_text_field("combat_event_id", "Evento (post-combate)", str(entry.get("combat_event_id", "")))
		"zone":
			_add_text_field("encounter_ids", "Encuentros (separados por coma)", ",".join(entry.get("encounter_ids", [])))
			_add_text_field("chance", "Probabilidad (0-1)", str(entry.get("chance", 0.25)))
			_add_text_field("interval", "Intervalo (seg)", str(entry.get("interval", 8.0)))
		"story_trigger":
			_add_text_field("event_id", "ID de evento", str(entry.get("event_id", "")))
			_add_text_field("requires_flag", "Flag requerido (opcional)", str(entry.get("requires_flag", "")))

	var apply_btn = Button.new()
	apply_btn.text = "Aplicar"
	apply_btn.pressed.connect(_apply_property_changes)
	_props_container.add_child(apply_btn)

	var delete_btn = Button.new()
	delete_btn.text = "Eliminar"
	delete_btn.pressed.connect(_delete_selected_entity)
	_props_container.add_child(delete_btn)

func _add_text_field(key: String, label_text: String, default_value: String) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	_props_container.add_child(lbl)
	var edit = LineEdit.new()
	edit.text = default_value
	_props_container.add_child(edit)
	_prop_fields[key] = edit

func _add_option_field(key: String, label_text: String, options: Array, current_value: String) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	_props_container.add_child(lbl)
	var opt = OptionButton.new()
	if options.is_empty():
		opt.add_item("(sin datos)")
		opt.disabled = true
	else:
		for i in range(options.size()):
			opt.add_item(str(options[i]))
			if str(options[i]) == current_value:
				opt.select(i)
	_props_container.add_child(opt)
	_prop_fields[key] = opt

func _apply_property_changes() -> void:
	if _selected_entry.is_empty():
		return
	for key in _prop_fields.keys():
		var field = _prop_fields[key]
		var raw: String
		if field is OptionButton:
			raw = field.get_item_text(field.selected) if field.selected >= 0 else ""
		else:
			raw = field.text
		match key:
			"quantity", "damage":
				_selected_entry[key] = int(raw) if raw.is_valid_int() else 0
			"chance", "interval":
				_selected_entry[key] = float(raw) if raw.is_valid_float() else 0.0
			"encounter_ids":
				var parts = raw.split(",")
				var clean: Array = []
				for p in parts:
					var trimmed = p.strip_edges()
					if trimmed != "":
						clean.append(trimmed)
				_selected_entry[key] = clean
			_:
				_selected_entry[key] = raw
	_grid.set_data(_tiles, _entities)
	_set_status("Propiedades actualizadas")

func _delete_selected_entity() -> void:
	if _selected_list_key == "":
		return
	var list: Array = _entities.get(_selected_list_key, [])
	list.erase(_selected_entry)
	_entities[_selected_list_key] = list
	if _selected_kind in ["npc", "chest", "trap", "combat_trigger", "boss_trigger", "riddle_gate"]:
		var row = int(_selected_entry.get("row", -1))
		var col = int(_selected_entry.get("col", -1))
		if row >= 0 and row < _tiles.size() and col >= 0 and col < _tiles[row].size():
			_tiles[row][col] = 1
	_grid.set_data(_tiles, _entities)
	_set_status("Eliminado")
	_show_no_selection()

# --- Resize (grow/shrink the tileset, no upper limit) ---

func _on_resize_pressed() -> void:
	var current_cols = _tiles[0].size() if _tiles.size() > 0 else 25
	var current_rows = _tiles.size()
	_show_text_prompt("Redimensionar (columnas x filas)", "%dx%d" % [current_cols, current_rows], _do_resize)

func _do_resize(text: String) -> void:
	var parts = text.strip_edges().to_lower().replace(" ", "").split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		_set_status("Formato inválido, usá ColumnasxFilas (ej: 30x25)")
		return
	_resize_map(int(parts[0]), int(parts[1]))

## Grows or shrinks the tile grid to new_cols x new_rows (no upper limit — only clamped to a
## minimum of 1x1). Existing tiles are preserved where the old and new bounds overlap; any
## entity that falls outside the new bounds after a shrink is dropped instead of left dangling.
func _resize_map(new_cols: int, new_rows: int) -> void:
	new_cols = maxi(1, new_cols)
	new_rows = maxi(1, new_rows)

	var new_tiles: Array = []
	for r in range(new_rows):
		var row: Array = []
		for c in range(new_cols):
			if r < _tiles.size() and c < _tiles[r].size():
				row.append(_tiles[r][c])
			else:
				row.append(0)
		new_tiles.append(row)
	_tiles = new_tiles

	for list_key in ["npcs", "chests", "traps", "combat_triggers", "riddle_gates", "boss_triggers", "story_triggers"]:
		var list: Array = _entities.get(list_key, [])
		var kept: Array = []
		for entry in list:
			var r = int(entry.get("row", -1))
			var c = int(entry.get("col", -1))
			if r >= 0 and r < new_rows and c >= 0 and c < new_cols:
				kept.append(entry)
		_entities[list_key] = kept

	var zones: Array = _entities.get("random_encounter_zones", [])
	var kept_zones: Array = []
	for zone in zones:
		var zr = float(zone.get("row", 0))
		var zc = float(zone.get("col", 0))
		if zr >= 0 and zr < new_rows and zc >= 0 and zc < new_cols:
			kept_zones.append(zone)
	_entities["random_encounter_zones"] = kept_zones

	var start = _entities.get("player_start", {})
	if start.has("row"):
		var r = int(start.get("row", -1))
		var c = int(start.get("col", -1))
		if r < 0 or r >= new_rows or c < 0 or c >= new_cols:
			_entities.erase("player_start")

	_grid.set_data(_tiles, _entities)
	_show_no_selection()
	_set_status("Mapa redimensionado a %dx%d" % [new_cols, new_rows])

# --- Text prompt modal (Guardar como / Nuevo mapa) ---

func _build_prompt_panel() -> void:
	_prompt_panel = Control.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt_panel.visible = false
	_root.add_child(_prompt_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -70
	box.offset_bottom = 70
	_prompt_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	_prompt_title = Label.new()
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_title)

	_prompt_line_edit = LineEdit.new()
	vbox.add_child(_prompt_line_edit)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	vbox.add_child(buttons)

	var ok_btn = Button.new()
	ok_btn.text = "Aceptar"
	ok_btn.pressed.connect(_on_prompt_confirmed)
	buttons.add_child(ok_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(_on_prompt_cancelled)
	buttons.add_child(cancel_btn)

func _show_text_prompt(title: String, default_text: String, callback: Callable) -> void:
	_prompt_title.text = title
	_prompt_line_edit.text = default_text
	_prompt_callback = callback
	_prompt_panel.visible = true
	_prompt_line_edit.grab_focus()

func _on_prompt_confirmed() -> void:
	var text = _prompt_line_edit.text
	_prompt_panel.visible = false
	if _prompt_callback.is_valid():
		_prompt_callback.call(text)

func _on_prompt_cancelled() -> void:
	_prompt_panel.visible = false

# --- Load-map modal ---

func _build_load_panel() -> void:
	_load_panel = Control.new()
	_load_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_panel.visible = false
	_root.add_child(_load_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -200
	box.offset_right = 200
	box.offset_top = -180
	box.offset_bottom = 180
	_load_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	box.add_child(vbox)

	var title = Label.new()
	title.text = "Cargar mapa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_load_list_container = VBoxContainer.new()
	vbox.add_child(_load_list_container)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func(): _load_panel.visible = false)
	vbox.add_child(cancel_btn)

func _on_load_map_pressed() -> void:
	for child in _load_list_container.get_children():
		child.queue_free()
	var maps = DataLoader.list_maps()
	if maps.is_empty():
		var lbl = Label.new()
		lbl.text = "No hay mapas en res://maps/"
		_load_list_container.add_child(lbl)
	else:
		for m in maps:
			var btn = Button.new()
			btn.text = str(m.get("name", "?"))
			btn.pressed.connect(_load_map_into_editor.bind(str(m.get("path", ""))))
			_load_list_container.add_child(btn)
	_load_panel.visible = true

func _load_map_into_editor(path: String) -> void:
	_load_panel.visible = false
	if not DataLoader.load_map(path):
		_set_status("Error al cargar %s" % path)
		return
	var data = DataLoader.get_current_map().duplicate(true)
	_map_data = data
	_tiles = data.get("tiles", [])
	_entities = data.get("entities", {})
	_map_path = path
	_grid.set_data(_tiles, _entities)
	_show_no_selection()
	_set_status("Mapa cargado: %s" % str(data.get("name", path)))

# --- Save / New / Playtest ---

func _on_save_pressed() -> void:
	if _map_path == "":
		_on_save_as_pressed()
		return
	_write_current_map_to(_map_path)

func _on_save_as_pressed() -> void:
	_show_text_prompt("Guardar como (nombre del mapa)", str(_map_data.get("name", "Nuevo Mapa")), _do_save_as)

func _do_save_as(map_name: String) -> void:
	_map_data["name"] = map_name
	var regex = RegEx.new()
	regex.compile("[^a-z0-9_]")
	var slug = regex.sub(map_name.strip_edges().to_lower().replace(" ", "_"), "", true)
	if slug == "":
		slug = "mapa"
	_write_current_map_to(MAPS_DIR + slug + ".map")

func _write_current_map_to(path: String) -> void:
	_map_data["tiles"] = _tiles
	_map_data["entities"] = _entities
	if not _map_data.has("name") or str(_map_data["name"]) == "":
		_map_data["name"] = path.get_file().get_basename()
	if not _entities.has("player_start"):
		_set_status("Guardado (advertencia: sin player_start)")
	elif not _has_exit_tile():
		_set_status("Guardado (advertencia: sin salida/Exit)")
	else:
		_set_status("Mapa guardado: %s" % path)
	DataLoader.save_map(path, _map_data)
	DataLoader.load_map(path)
	_map_path = path

func _has_exit_tile() -> bool:
	for row in _tiles:
		if 9 in row:
			return true
	return false

func _on_new_map_pressed() -> void:
	_show_text_prompt("Nuevo mapa (nombre)", "Nuevo Mapa", _do_new_map)

func _do_new_map(map_name: String) -> void:
	_tiles = []
	for r in range(20):
		var row: Array = []
		for c in range(25):
			row.append(0)
		_tiles.append(row)
	_entities = {}
	_map_data = {"name": map_name, "tile_size": 2.0}
	_map_path = ""
	_grid.set_data(_tiles, _entities)
	_show_no_selection()
	_set_status("Mapa nuevo: %s (recordá Guardar como)" % map_name)

func _on_playtest_pressed() -> void:
	_map_data["tiles"] = _tiles
	_map_data["entities"] = _entities
	DataLoader.set_current_map(_map_data)
	if standalone:
		SceneFlow.change_scene("res://scenes/boot/CharacterSelection.tscn")
	else:
		get_tree().reload_current_scene()

func _set_status(text: String) -> void:
	_status_label.text = text
