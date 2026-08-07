extends CanvasLayer
class_name MapEditor
## MapEditor — In-game 2D top-down map editor. Edits the currently loaded map's tiles and
## entity placements (NPCs, chests, traps, combat/boss triggers, riddle gates, random-encounter
## zones, story triggers, player start) and can save to res://maps/*.map, load another map,
## start a blank one, or playtest in-memory edits without saving.

const MAPS_DIR := "res://maps/"

const TOOLS := [
	{"id": "select", "label": "Seleccionar"},
	{"id": "erase", "label": "Vacío", "tile": 0},
	{"id": "floor", "label": "Piso", "tile": 1},
	{"id": "wall", "label": "Pared", "tile": 2},
	{"id": "door_h", "label": "Puerta —", "tile": 3, "list": "doors"},
	{"id": "door_v", "label": "Puerta |", "tile": 3, "list": "doors"},
	{"id": "npc", "label": "NPC", "tile": 4, "list": "npcs"},
	{"id": "chest", "label": "Cofre", "tile": 5, "list": "chests"},
	{"id": "combat_trigger", "label": "Trigger Combate", "tile": 6, "list": "combat_triggers"},
	{"id": "trap", "label": "Trampa", "tile": 7, "list": "traps"},
	{"id": "boss_trigger", "label": "Trigger Jefe", "tile": 8, "list": "boss_triggers"},
	{"id": "exit", "label": "Salida", "tile": 9, "list": "exits"},
	{"id": "riddle_gate", "label": "Esfinge (Puerta Enigma)", "tile": 10, "list": "riddle_gates"},
	{"id": "floor_item", "label": "Item en el Suelo", "tile": 11, "list": "floor_items"},
	{"id": "rest_zone", "label": "Zona de Descanso", "tile": 12, "list": "rest_zones"},
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
## Ending-credits text for this map (scripts/core/CreditsScreen.gd). Plain array of strings, same
## save-alongside-tiles/entities convention — see _write_current_map_to()/_on_playtest_pressed().
var _credits: Array = []

var _current_tool: Dictionary = TOOLS[0]
var _drag_start_cell: Vector2i = Vector2i(-1, -1)
var _editing_existing_zone: bool = false

var _selected_kind: String = ""
var _selected_list_key: String = ""
var _selected_entry: Dictionary = {}
var _prop_fields: Dictionary = {}
var _enemies_section: VBoxContainer = null
var _event_preview_section: VBoxContainer = null

## Set by the door key-location flow when "Suelo" is chosen — the next floor_item placed
## uses this as its item_id (instead of the "potion" default) and then clears itself.
var _pending_key_item_id: String = ""

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

var _key_location_panel: Control
var _key_location_title: Label
var _key_location_list_container: VBoxContainer

var _enemy_editor_panel: Control
var _enemy_editor_fields_container: VBoxContainer
var _enemy_editor_fields: Dictionary = {}
var _enemy_editor_current_id: String = ""
var _enemy_editor_delete_btn: Button
var _enemy_editor_delete_armed: bool = false

var _new_encounter_panel: Control
var _new_encounter_id_field: LineEdit
var _new_encounter_enemies_field: LineEdit
var _new_encounter_hint_label: Label

var _credits_panel: Control
var _credits_text_edit: TextEdit

func _ready() -> void:
	layer = 70
	var current = DataLoader.get_current_map()
	_map_data = current.duplicate(true) if not current.is_empty() else {"name": "Sin nombre", "tile_size": 2.0, "tiles": [], "entities": {}}
	_map_path = DataLoader.get_current_map_path()
	_tiles = _map_data.get("tiles", [])
	_entities = _map_data.get("entities", {})
	_credits = _map_data.get("credits", [])
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
	_add_action_button(action_bar, "Nuevo Enemigo", _on_new_enemy_pressed)
	_add_action_button(action_bar, "Nuevo Encuentro", _on_new_encounter_pressed)
	_add_action_button(action_bar, "Créditos", _on_credits_pressed)
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
	_build_key_location_panel()
	_build_enemy_editor_panel()
	_build_new_encounter_panel()
	_build_credits_panel()

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
		"select":
			return Color(0.5, 0.85, 1.0)
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
		"select":
			return "select"
		"erase", "floor", "wall":
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
		"select":
			_inspect_tile(row, col)
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
	for list_key in ["npcs", "chests", "doors", "floor_items", "rest_zones", "traps", "combat_triggers", "riddle_gates", "boss_triggers", "story_triggers", "exits"]:
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
		"door_h", "door_v":
			entry["door_id"] = "door_%d_%d" % [entry["row"], entry["col"]]
			entry["locked"] = false
			entry["required_item_id"] = ""
			entry["edge"] = "center"
			# The tool picked at placement time IS the orientation — "Puerta —" (blocks
			# north-south, the wall it's set into runs east-west) or "Puerta |" (blocks
			# east-west, wall runs north-south). No more guessing from neighbor tiles.
			entry["vertical"] = (kind == "door_v")
		"floor_item":
			entry["item_id"] = _pending_key_item_id if _pending_key_item_id != "" else "potion"
			entry["quantity"] = 1
			entry["chest_id"] = "floor_item_%d_%d" % [entry["row"], entry["col"]]
			_pending_key_item_id = ""
		"combat_trigger", "boss_trigger":
			var ids = DataLoader.get_all_encounter_ids()
			entry["encounter_id"] = ids[0] if ids.size() > 0 else ""
			entry["intro_message"] = ""
			entry["death_message"] = ""
		"trap":
			entry["damage"] = 10
			entry["dc"] = 12
			entry["trap_id"] = "trap_%d_%d" % [entry["row"], entry["col"]]
		"riddle_gate":
			entry["encounter_id"] = "encounter_sphinx"
			entry["success_event_id"] = ""
			entry["combat_event_id"] = ""
		"story_trigger":
			entry["event_id"] = ""
			entry["requires_flag"] = ""
		"exit":
			entry["requires_items"] = []

## "door_h"/"door_v" are two placement tools for the same "doors" list — the tool used only
## decides a new door's initial orientation (see _apply_default_props), it isn't a distinct
## entity kind. Normalize to plain "door" before touching the property panel or anything else
## that expects the kinds already used elsewhere ("chest", "npc", etc.).
func _normalize_kind(kind: String) -> String:
	if kind == "door_h" or kind == "door_v":
		return "door"
	return kind

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
	_open_property_panel(_normalize_kind(kind), list_key, existing)

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

## "Seleccionar" tool: click any tile to see what's there, without placing or erasing anything.
## Entity-owning tiles (door, npc, chest, etc.) get the exact same editable panel as clicking
## them with their own tool selected. Overlays that share the floor tile instead of owning a
## distinct tile number (zone, story trigger) reuse their panel too. Player start and plain
## floor/wall/empty tiles have nothing to edit, so they just get a read-only info line.
func _inspect_tile(row: int, col: int) -> void:
	if row < 0 or row >= _tiles.size() or col < 0 or col >= _tiles[row].size():
		return

	var tile_num: int = _tiles[row][col]

	for tool in TOOLS:
		if tool.get("tile", -1) == tile_num and tool.has("list"):
			var existing = _find_entity_at(tool["list"], row, col)
			if not existing.is_empty():
				# door_h/door_v share one tile number and list — whichever of the two matches
				# first here isn't necessarily this door's actual orientation, so normalize the
				# kind and use a generic label rather than trusting the matched tool's own.
				var kind = _normalize_kind(tool["id"])
				var label: String = "Puerta" if kind == "door" else str(tool["label"])
				_open_property_panel(kind, tool["list"], existing)
				_set_status("(%d,%d): %s" % [row, col, label])
				return
			break

	var player_start = _entities.get("player_start", {})
	if int(player_start.get("row", -1)) == row and int(player_start.get("col", -1)) == col:
		_show_read_only_info(row, col, "Inicio del jugador")
		_set_status("(%d,%d): Inicio del jugador" % [row, col])
		return

	var zone = _find_zone_at(row, col)
	if not zone.is_empty():
		_open_property_panel("zone", "random_encounter_zones", zone)
		_set_status("(%d,%d): Zona de Encuentros" % [row, col])
		return

	var story_trigger = _find_entity_at("story_triggers", row, col)
	if not story_trigger.is_empty():
		_open_property_panel("story_trigger", "story_triggers", story_trigger)
		_set_status("(%d,%d): Story Trigger" % [row, col])
		return

	var label = _tile_type_label(tile_num)
	_show_read_only_info(row, col, label)
	_set_status("(%d,%d): %s" % [row, col, label])

## Label for a plain tile (no entity attached) — Vacío/Piso/Pared.
func _tile_type_label(tile_num: int) -> String:
	for tool in TOOLS:
		if tool.get("tile", -1) == tile_num and not tool.has("list"):
			return str(tool.get("label", "?"))
	return "?"

func _show_read_only_info(row: int, col: int, label: String) -> void:
	_selected_kind = ""
	_selected_list_key = ""
	_selected_entry = {}
	_enemies_section = null
	_event_preview_section = null
	for child in _props_container.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "%s (%d, %d)" % [label, row, col]
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_props_container.add_child(header)

# --- Property panel ---

func _show_no_selection() -> void:
	_selected_kind = ""
	_selected_list_key = ""
	_selected_entry = {}
	_enemies_section = null
	_event_preview_section = null
	for child in _props_container.get_children():
		child.queue_free()
	var lbl = Label.new()
	lbl.text = "Elige una herramienta y haz click en la grilla."
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
		"floor_item":
			_add_option_field("item_id", "Item", DataLoader.get_all_item_ids(), str(entry.get("item_id", "")))
			_add_text_field("quantity", "Cantidad", str(entry.get("quantity", 1)))
		"door":
			# No "vertical" toggle here — that's fixed by which tool ("Puerta —" / "Puerta |")
			# placed this door in the first place, not something to flip afterward.
			_add_option_field("edge", "Posición en el tile", ["center", "top", "bottom", "left", "right"], str(entry.get("edge", "center")))
			_add_bool_field("locked", "Bloqueada", bool(entry.get("locked", false)))
			_add_text_field("required_item_id", "ID de la llave requerida", str(entry.get("required_item_id", "")))
			var gen_key_btn = Button.new()
			gen_key_btn.text = "Generar llave nueva"
			gen_key_btn.pressed.connect(_on_generate_key_pressed)
			_props_container.add_child(gen_key_btn)
			var locate_key_btn = Button.new()
			locate_key_btn.text = "Ubicar la llave..."
			locate_key_btn.pressed.connect(_on_locate_key_pressed)
			_props_container.add_child(locate_key_btn)
		"combat_trigger", "boss_trigger":
			_add_option_field("encounter_id", "Encuentro", DataLoader.get_all_encounter_ids(), str(entry.get("encounter_id", "")), func(_idx): _refresh_encounter_enemies_section())
			_add_text_field("intro_message", "Mensaje de bienvenida (antes del combate)", str(entry.get("intro_message", "")))
			_add_text_field("death_message", "Mensaje de muerte", str(entry.get("death_message", "")))
			_enemies_section = VBoxContainer.new()
			_enemies_section.add_theme_constant_override("separation", 4)
			_props_container.add_child(_enemies_section)
			_refresh_encounter_enemies_section()
		"trap":
			_add_text_field("damage", "Daño", str(entry.get("damage", 10)))
			_add_text_field("dc", "Dificultad de Salvación", str(entry.get("dc", 12)))
		"riddle_gate":
			_add_option_field("encounter_id", "Encuentro (guardiana)", DataLoader.get_all_encounter_ids(), str(entry.get("encounter_id", "")))
			_add_option_field("success_event_id", "Evento (éxito)", DataLoader.get_all_event_ids(), str(entry.get("success_event_id", "")))
			_add_option_field("combat_event_id", "Evento (post-combate)", DataLoader.get_all_event_ids(), str(entry.get("combat_event_id", "")))
		"zone":
			_add_multi_checkbox_field("encounter_ids", "Encuentros", entry.get("encounter_ids", []), DataLoader.get_all_encounter_ids())
			_add_text_field("chance", "Probabilidad (0-1)", str(entry.get("chance", 0.25)))
			_add_text_field("interval", "Intervalo (seg)", str(entry.get("interval", 8.0)))
		"story_trigger":
			_add_option_field("event_id", "ID de evento", DataLoader.get_all_event_ids(), str(entry.get("event_id", "")), func(_idx): _refresh_event_preview_section())
			_add_text_field("requires_flag", "Flag requerido (opcional)", str(entry.get("requires_flag", "")))
			_event_preview_section = VBoxContainer.new()
			_event_preview_section.add_theme_constant_override("separation", 4)
			_props_container.add_child(_event_preview_section)
			_refresh_event_preview_section()
		"exit":
			_add_text_field("requires_items", "Items requeridos (separados por coma, opcional)", ",".join(entry.get("requires_items", [])))
		"rest_zone":
			var info = Label.new()
			info.text = "Restaura HP y MP completos a la party. Comparte un pool GLOBAL de %d descansos con todas las zonas de descanso del mapa (no es por zona individual)." % GameState.MAX_REST_CHARGES
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_theme_font_size_override("font_size", 13)
			info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			_props_container.add_child(info)

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

func _add_option_field(key: String, label_text: String, options: Array, current_value: String, on_change: Callable = Callable()) -> void:
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
	if on_change.is_valid():
		opt.item_selected.connect(on_change)

## Checklist of CheckBox rows, one per entry in all_options, pre-ticked if present in
## current_values. Registered in _prop_fields like every other field, but as the VBoxContainer
## itself — _apply_property_changes special-cases VBoxContainer fields to read ticked boxes
## instead of a single text/OptionButton value.
func _add_multi_checkbox_field(key: String, label_text: String, current_values: Array, all_options: Array) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	_props_container.add_child(lbl)
	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 2)
	if all_options.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "(sin encuentros definidos todavía)"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		list_box.add_child(empty_lbl)
	else:
		for option_id in all_options:
			var cb = CheckBox.new()
			cb.text = str(option_id)
			cb.set_meta("value", option_id)
			cb.button_pressed = current_values.has(option_id)
			list_box.add_child(cb)
	_props_container.add_child(list_box)
	_prop_fields[key] = list_box

func _add_bool_field(key: String, label_text: String, current_value: bool) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	_props_container.add_child(lbl)
	var opt = OptionButton.new()
	opt.add_item("No")
	opt.add_item("Sí")
	opt.select(1 if current_value else 0)
	_props_container.add_child(opt)
	_prop_fields[key] = opt

func _apply_property_changes() -> void:
	if _selected_entry.is_empty():
		return
	for key in _prop_fields.keys():
		var field = _prop_fields[key]
		if field is VBoxContainer:
			var checked: Array = []
			for cb in field.get_children():
				if cb is CheckBox and cb.button_pressed:
					checked.append(cb.get_meta("value"))
			_selected_entry[key] = checked
			continue
		var raw: String
		if field is OptionButton:
			raw = field.get_item_text(field.selected) if field.selected >= 0 else ""
		else:
			raw = field.text
		match key:
			"locked", "vertical":
				_selected_entry[key] = (raw == "Sí")
			"quantity", "damage", "dc":
				_selected_entry[key] = int(raw) if raw.is_valid_int() else 0
			"chance", "interval":
				_selected_entry[key] = float(raw) if raw.is_valid_float() else 0.0
			"requires_items":
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
	if _selected_kind == "door":
		_maybe_delete_orphaned_key(_selected_entry)
	if _selected_kind in ["npc", "chest", "door", "floor_item", "rest_zone", "trap", "combat_trigger", "boss_trigger", "riddle_gate", "exit"]:
		var row = int(_selected_entry.get("row", -1))
		var col = int(_selected_entry.get("col", -1))
		if row >= 0 and row < _tiles.size() and col >= 0 and col < _tiles[row].size():
			_tiles[row][col] = 1
	_grid.set_data(_tiles, _entities)
	_set_status("Eliminado")
	_show_no_selection()

## Deletes a door's auto-generated key item definition when the door that used it is deleted,
## so "Generar llave nueva" leftovers don't linger in items.json forever (a stale key definition
## is one exclusion-list change away from being handed out for free at the start of every run,
## like the free-keys bug). Only removes item_ids matching the exact "key_<row>_<col>" pattern
## the generator itself produces, and only if no other remaining door still references it, so a
## hand-authored or shared key item is never touched.
func _maybe_delete_orphaned_key(door_entry: Dictionary) -> void:
	var item_id: String = str(door_entry.get("required_item_id", ""))
	if item_id == "" or not _is_auto_generated_key_id(item_id):
		return
	for other in _entities.get("doors", []):
		if str(other.get("required_item_id", "")) == item_id:
			return
	DataLoader.delete_item_definition(item_id)

func _is_auto_generated_key_id(item_id: String) -> bool:
	var parts = item_id.split("_")
	if parts.size() != 3 or parts[0] != "key":
		return false
	return parts[1].is_valid_int() and parts[2].is_valid_int()

# --- Enemies-in-encounter list + Enemy Editor modal (combat_trigger / boss_trigger) ---

## Rebuilds the "Enemigos en este encuentro" section live, reading whatever encounter_id is
## currently selected in the dropdown (even before Aplicar is pressed).
func _refresh_encounter_enemies_section() -> void:
	if _enemies_section == null or not is_instance_valid(_enemies_section):
		return
	for child in _enemies_section.get_children():
		child.queue_free()

	var opt = _prop_fields.get("encounter_id")
	if opt == null or not (opt is OptionButton) or opt.selected < 0:
		return
	var encounter_id = opt.get_item_text(opt.selected)
	var encounter = DataLoader.get_encounter(encounter_id)
	var enemy_ids: Array = encounter.get("enemies", [])

	var header = Label.new()
	header.text = "Enemigos en este encuentro:"
	header.add_theme_font_size_override("font_size", 14)
	_enemies_section.add_child(header)

	var seen := {}
	for enemy_id in enemy_ids:
		if seen.has(enemy_id):
			continue
		seen[enemy_id] = true
		var enemy_def = DataLoader.get_enemy(enemy_id)
		var btn = Button.new()
		btn.text = "Editar %s" % str(enemy_def.get("name", enemy_id))
		btn.pressed.connect(_open_enemy_editor.bind(enemy_id))
		_enemies_section.add_child(btn)

# --- Event preview (story_trigger) ---

## Rebuilds a short preview of whatever event_id is currently selected in the dropdown — party
## example, leader, mood, and the first line of dialogue — so you don't have to open the JSON
## to know what a scene actually contains before wiring it to a trigger.
func _refresh_event_preview_section() -> void:
	if _event_preview_section == null or not is_instance_valid(_event_preview_section):
		return
	for child in _event_preview_section.get_children():
		child.queue_free()

	var opt = _prop_fields.get("event_id")
	if opt == null or not (opt is OptionButton) or opt.selected < 0:
		return
	var event_id = opt.get_item_text(opt.selected)

	var header = Label.new()
	header.text = "Vista previa de %s:" % event_id
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_event_preview_section.add_child(header)

	var sample = DataLoader.get_any_waypoint_variant(event_id)
	if sample.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "(sin datos de diálogo para este evento)"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_event_preview_section.add_child(empty_lbl)
		return

	var party: Array = sample.get("party", [])
	var info_lbl = Label.new()
	info_lbl.text = "Party ejemplo: %s\nLíder: %s | Mood: %s" % [", ".join(party), str(sample.get("leader", "")), str(sample.get("mood", ""))]
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 12)
	_event_preview_section.add_child(info_lbl)

	var dialogue: Array = sample.get("dialogue", [])
	if dialogue.size() > 0:
		var line_lbl = Label.new()
		line_lbl.text = "\"%s\"" % str(dialogue[0])
		line_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line_lbl.add_theme_font_size_override("font_size", 12)
		line_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_event_preview_section.add_child(line_lbl)

func _build_enemy_editor_panel() -> void:
	_enemy_editor_panel = Control.new()
	_enemy_editor_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_editor_panel.visible = false
	_root.add_child(_enemy_editor_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_editor_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -320
	box.offset_bottom = 320
	box.add_theme_stylebox_override("panel", _make_panel_style())
	_enemy_editor_panel.add_child(box)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	box.add_child(outer_vbox)

	var title = Label.new()
	title.text = "Editor de Enemigo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	outer_vbox.add_child(title)

	var note = Label.new()
	note.text = "Los enemigos son data global: esto afecta a TODOS los encuentros que usen este enemigo."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.7, 0.6, 0.3))
	outer_vbox.add_child(note)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 480)
	outer_vbox.add_child(scroll)

	_enemy_editor_fields_container = VBoxContainer.new()
	_enemy_editor_fields_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_editor_fields_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_enemy_editor_fields_container)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	outer_vbox.add_child(buttons)

	var save_btn = Button.new()
	save_btn.text = "Guardar"
	save_btn.pressed.connect(_on_enemy_editor_save)
	buttons.add_child(save_btn)

	_enemy_editor_delete_btn = Button.new()
	_enemy_editor_delete_btn.text = "Eliminar enemigo"
	_enemy_editor_delete_btn.pressed.connect(_on_enemy_editor_delete_pressed)
	buttons.add_child(_enemy_editor_delete_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func():
		_enemy_editor_delete_armed = false
		_enemy_editor_panel.visible = false
	)
	buttons.add_child(cancel_btn)

func _open_enemy_editor(enemy_id: String) -> void:
	_enemy_editor_current_id = enemy_id
	var enemy = DataLoader.get_enemy(enemy_id)
	_enemy_editor_fields.clear()
	for child in _enemy_editor_fields_container.get_children():
		child.queue_free()

	_add_enemy_field("name", "Nombre", str(enemy.get("name", enemy_id)))
	_add_enemy_field("hp", "HP", str(enemy.get("hp", 10)))
	_add_enemy_field("ca", "CA", str(enemy.get("ca", 10)))
	_add_enemy_field("hit_die", "Dado de golpe", str(enemy.get("hit_die", 8)))
	_add_enemy_field("attack_bonus", "Bono de ataque", str(enemy.get("attack_bonus", 0)))
	_add_enemy_field("damage", "Daño (dado, ej: 1d6+2)", str(enemy.get("damage", "1d6")))
	_add_enemy_option_field("ai_profile", "Temperamento (dónde pelea)",
		["aggressive", "cautious", "ranged"],
		str(enemy.get("ai_profile", EnemyAI.DEFAULT_PROFILE)))
	var attrs: Dictionary = enemy.get("attributes", {})
	for attr_key in ["fuerza", "agilidad", "constitucion", "sabiduria", "inteligencia", "carisma"]:
		_add_enemy_field("attr_%s" % attr_key, attr_key.capitalize(), str(attrs.get(attr_key, 10)))
	_add_enemy_field("xp_reward", "XP otorgada", str(enemy.get("xp_reward", 0)))
	_add_enemy_field("gold_reward", "Oro otorgado", str(enemy.get("gold_reward", 0)))
	_add_enemy_field("skills", "Skills (separadas por coma)", ",".join(enemy.get("skills", [])))
	_add_enemy_field("item_drops", "Items que dropea (separados por coma, garantizado)", ",".join(enemy.get("item_drops", [])))

	_enemy_editor_delete_armed = false
	_enemy_editor_delete_btn.text = "Eliminar enemigo"
	_enemy_editor_panel.visible = true

func _add_enemy_field(key: String, label_text: String, default_value: String) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	_enemy_editor_fields_container.add_child(lbl)
	var edit = LineEdit.new()
	edit.text = default_value
	_enemy_editor_fields_container.add_child(edit)
	_enemy_editor_fields[key] = edit

## Same contract as _add_enemy_field, but a fixed set of choices instead of free text. Read back
## through OptionButton.text (the selected item's label), so _on_enemy_editor_save needs no
## special case for it.
func _add_enemy_option_field(key: String, label_text: String, options: Array, current_value: String) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	_enemy_editor_fields_container.add_child(lbl)
	var opt = OptionButton.new()
	for i in range(options.size()):
		opt.add_item(str(options[i]))
		if str(options[i]) == current_value:
			opt.select(i)
	if opt.selected < 0:
		opt.select(0)
	_enemy_editor_fields_container.add_child(opt)
	_enemy_editor_fields[key] = opt

func _on_enemy_editor_save() -> void:
	if _enemy_editor_current_id == "":
		return
	var data = DataLoader.get_enemy(_enemy_editor_current_id).duplicate(true)
	data["id"] = _enemy_editor_current_id
	for key in _enemy_editor_fields.keys():
		var raw: String = _enemy_editor_fields[key].text
		if key.begins_with("attr_"):
			if not data.has("attributes"):
				data["attributes"] = {}
			data["attributes"][key.substr(5)] = int(raw) if raw.is_valid_int() else 10
			continue
		match key:
			"hp", "ca", "hit_die", "attack_bonus", "xp_reward", "gold_reward":
				data[key] = int(raw) if raw.is_valid_int() else 0
			"skills", "item_drops":
				var parts = raw.split(",")
				var clean: Array = []
				for p in parts:
					var trimmed = p.strip_edges()
					if trimmed != "":
						clean.append(trimmed)
				data[key] = clean
			_:
				data[key] = raw

	DataLoader.update_enemy(_enemy_editor_current_id, data)
	_enemy_editor_panel.visible = false
	_set_status("Enemigo actualizado: %s" % str(data.get("name", _enemy_editor_current_id)))
	_refresh_encounter_enemies_section()

## Two-click confirm (no extra modal): first click arms it and relabels the button; a second
## click actually deletes. Closing the panel without a second click discards the armed state.
func _on_enemy_editor_delete_pressed() -> void:
	if _enemy_editor_current_id == "":
		return
	if not _enemy_editor_delete_armed:
		_enemy_editor_delete_armed = true
		_enemy_editor_delete_btn.text = "¿Confirmar eliminación?"
		return
	var deleted_id = _enemy_editor_current_id
	DataLoader.delete_enemy(deleted_id)
	_enemy_editor_delete_armed = false
	_enemy_editor_panel.visible = false
	_set_status("Enemigo eliminado: %s" % deleted_id)
	_refresh_encounter_enemies_section()

# --- Crear enemigo nuevo ---

## _open_enemy_editor already handles a non-existent id gracefully (DataLoader.get_enemy
## returns {} and every field falls back to a sane default), so "create" and "edit" are the
## same modal — we only need an entry point that asks for a fresh id first.
func _on_new_enemy_pressed() -> void:
	_show_text_prompt("Nuevo enemigo (ID)", "nuevo_enemigo", _do_new_enemy)

func _do_new_enemy(raw_id: String) -> void:
	var regex = RegEx.new()
	regex.compile("[^a-z0-9_]")
	var slug = regex.sub(raw_id.strip_edges().to_lower().replace(" ", "_"), "", true)
	if slug == "":
		_set_status("ID de enemigo inválido")
		return
	_open_enemy_editor(slug)

# --- Crear encuentro nuevo ---

func _build_new_encounter_panel() -> void:
	_new_encounter_panel = Control.new()
	_new_encounter_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_new_encounter_panel.visible = false
	_root.add_child(_new_encounter_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_new_encounter_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -240
	box.offset_right = 240
	box.offset_top = -160
	box.offset_bottom = 160
	box.add_theme_stylebox_override("panel", _make_panel_style())
	_new_encounter_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	var title = Label.new()
	title.text = "Nuevo Encuentro"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	vbox.add_child(title)

	var id_lbl = Label.new()
	id_lbl.text = "ID del encuentro"
	vbox.add_child(id_lbl)
	_new_encounter_id_field = LineEdit.new()
	vbox.add_child(_new_encounter_id_field)

	var enemies_lbl = Label.new()
	enemies_lbl.text = "Enemigos (ids separados por coma)"
	vbox.add_child(enemies_lbl)
	_new_encounter_enemies_field = LineEdit.new()
	vbox.add_child(_new_encounter_enemies_field)

	_new_encounter_hint_label = Label.new()
	_new_encounter_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_new_encounter_hint_label.add_theme_font_size_override("font_size", 12)
	_new_encounter_hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_new_encounter_hint_label)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	vbox.add_child(buttons)

	var save_btn = Button.new()
	save_btn.text = "Crear"
	save_btn.pressed.connect(_on_new_encounter_save)
	buttons.add_child(save_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func(): _new_encounter_panel.visible = false)
	buttons.add_child(cancel_btn)

func _on_new_encounter_pressed() -> void:
	_new_encounter_id_field.text = ""
	_new_encounter_enemies_field.text = ""
	_new_encounter_hint_label.text = "Enemigos disponibles: %s" % ", ".join(DataLoader.get_all_enemy_ids())
	_new_encounter_panel.visible = true

func _on_new_encounter_save() -> void:
	var id = _new_encounter_id_field.text.strip_edges()
	if id == "":
		_set_status("El encuentro necesita un ID")
		return

	var enemy_ids: Array = []
	var xp := 0
	var gold := 0
	for p in _new_encounter_enemies_field.text.split(","):
		var trimmed = p.strip_edges()
		if trimmed == "":
			continue
		var e = DataLoader.get_enemy(trimmed)
		if e.is_empty():
			_set_status("Enemigo desconocido: %s" % trimmed)
			return
		enemy_ids.append(trimmed)
		xp += int(e.get("xp_reward", 0))
		gold += int(e.get("gold_reward", 0))

	if enemy_ids.is_empty():
		_set_status("El encuentro necesita al menos un enemigo")
		return

	DataLoader.update_encounter(id, {"id": id, "enemies": enemy_ids, "rewards": {"xp": xp, "gold": gold}})
	_new_encounter_panel.visible = false
	_set_status("Encuentro creado: %s (xp %d, oro %d)" % [id, xp, gold])

	# Refresh the currently-open panel's "Encuentro" dropdown so the new option shows up
	# immediately, instead of only after reselecting the tile.
	if _selected_kind in ["combat_trigger", "boss_trigger", "riddle_gate"]:
		_open_property_panel(_selected_kind, _selected_list_key, _selected_entry)

# --- Credits editor ("Créditos") ---

## Same modal shape as _build_new_encounter_panel(), but with a real multiline TextEdit instead
## of a LineEdit — the only place in this file that needs one, since _credits is a whole block of
## text rather than a handful of short fields. One line in the box = one entry of data.credits,
## read by scripts/core/CreditsScreen.gd: a line starting with "# " renders as a big title, an
## empty line is a blank spacer, anything else is a normal line.
func _build_credits_panel() -> void:
	_credits_panel = Control.new()
	_credits_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_panel.visible = false
	_root.add_child(_credits_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -320
	box.offset_right = 320
	box.offset_top = -280
	box.offset_bottom = 280
	box.add_theme_stylebox_override("panel", _make_panel_style())
	_credits_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	var title = Label.new()
	title.text = "Créditos"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "Una línea por entrada. '# Texto' = título grande. Línea vacía = espacio."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(hint)

	_credits_text_edit = TextEdit.new()
	_credits_text_edit.custom_minimum_size = Vector2(560, 380)
	_credits_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_credits_text_edit)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	vbox.add_child(buttons)

	var save_btn = Button.new()
	save_btn.text = "Guardar"
	save_btn.pressed.connect(_on_credits_save)
	buttons.add_child(save_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func(): _credits_panel.visible = false)
	buttons.add_child(cancel_btn)

func _on_credits_pressed() -> void:
	_credits_text_edit.text = "\n".join(_credits)
	_credits_panel.visible = true

func _on_credits_save() -> void:
	_credits = _credits_text_edit.text.split("\n")
	_credits_panel.visible = false
	_set_status("Créditos actualizados (%d línea(s)); se guardan con el mapa" % _credits.size())

# --- Door key-location modal ("Ubicar la llave...") ---

func _on_generate_key_pressed() -> void:
	if _selected_entry.is_empty() or _selected_kind != "door":
		return
	var row = int(_selected_entry.get("row", 0))
	var col = int(_selected_entry.get("col", 0))
	var item_id = "key_%d_%d" % [row, col]
	DataLoader.add_item_definition(item_id, {
		"id": item_id,
		"name": "Llave (%d,%d)" % [row, col],
		"effect": "key",
		"power": 0,
		"description": "Abre una puerta bloqueada.",
	})
	_selected_entry["required_item_id"] = item_id
	if _prop_fields.has("required_item_id"):
		_prop_fields["required_item_id"].text = item_id
	_set_status("Llave generada: %s" % item_id)

func _build_key_location_panel() -> void:
	_key_location_panel = Control.new()
	_key_location_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_key_location_panel.visible = false
	_root.add_child(_key_location_panel)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_key_location_panel.add_child(dim)

	var box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -200
	box.offset_bottom = 200
	box.add_theme_stylebox_override("panel", _make_panel_style())
	_key_location_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	box.add_child(vbox)

	_key_location_title = Label.new()
	_key_location_title.text = "¿Dónde está la llave?"
	_key_location_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_location_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_key_location_title)

	_key_location_list_container = VBoxContainer.new()
	vbox.add_child(_key_location_list_container)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancelar"
	cancel_btn.pressed.connect(func(): _key_location_panel.visible = false)
	vbox.add_child(cancel_btn)

func _on_locate_key_pressed() -> void:
	if _selected_entry.is_empty() or _selected_kind != "door":
		return
	var required_item_id = str(_selected_entry.get("required_item_id", ""))
	if required_item_id == "":
		_set_status("Primero generá o asigná una llave.")
		return

	for child in _key_location_list_container.get_children():
		child.queue_free()

	var chest_btn = Button.new()
	chest_btn.text = "Cofre existente"
	chest_btn.pressed.connect(_show_key_chest_list.bind(required_item_id))
	_key_location_list_container.add_child(chest_btn)

	var floor_btn = Button.new()
	floor_btn.text = "Suelo (colocar con un click)"
	floor_btn.pressed.connect(_place_key_on_floor.bind(required_item_id))
	_key_location_list_container.add_child(floor_btn)

	var enemy_btn = Button.new()
	enemy_btn.text = "La dropea un enemigo"
	enemy_btn.pressed.connect(_show_key_enemy_list.bind(required_item_id))
	_key_location_list_container.add_child(enemy_btn)

	_key_location_title.text = "¿Dónde está la llave? (%s)" % required_item_id
	_key_location_panel.visible = true

func _show_key_chest_list(item_id: String) -> void:
	for child in _key_location_list_container.get_children():
		child.queue_free()
	var chests: Array = _entities.get("chests", [])
	if chests.is_empty():
		var lbl = Label.new()
		lbl.text = "No hay cofres en el mapa todavía."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_key_location_list_container.add_child(lbl)
	else:
		for chest in chests:
			var btn = Button.new()
			btn.text = "Cofre (%s, %s)" % [str(chest.get("row", "")), str(chest.get("col", ""))]
			btn.pressed.connect(_assign_key_to_chest.bind(chest, item_id))
			_key_location_list_container.add_child(btn)

func _assign_key_to_chest(chest: Dictionary, item_id: String) -> void:
	chest["item_id"] = item_id
	chest["quantity"] = 1
	_key_location_panel.visible = false
	_grid.set_data(_tiles, _entities)
	_set_status("Llave asignada al cofre (%s, %s)" % [str(chest.get("row", "")), str(chest.get("col", ""))])

func _place_key_on_floor(item_id: String) -> void:
	_pending_key_item_id = item_id
	_select_tool_by_id("floor_item")
	_key_location_panel.visible = false
	_set_status("Hacé click en el piso para colocar la llave (%s)" % item_id)

func _show_key_enemy_list(item_id: String) -> void:
	for child in _key_location_list_container.get_children():
		child.queue_free()
	var ids = DataLoader.get_all_enemy_ids()
	if ids.is_empty():
		var lbl = Label.new()
		lbl.text = "No hay enemigos definidos."
		_key_location_list_container.add_child(lbl)
	else:
		for enemy_id in ids:
			var enemy_def = DataLoader.get_enemy(enemy_id)
			var btn = Button.new()
			btn.text = str(enemy_def.get("name", enemy_id))
			btn.pressed.connect(_assign_key_to_enemy.bind(enemy_id, item_id))
			_key_location_list_container.add_child(btn)

func _assign_key_to_enemy(enemy_id: String, item_id: String) -> void:
	var data = DataLoader.get_enemy(enemy_id).duplicate(true)
	var drops: Array = data.get("item_drops", []).duplicate()
	if not drops.has(item_id):
		drops.append(item_id)
	data["item_drops"] = drops
	DataLoader.update_enemy(enemy_id, data)
	_key_location_panel.visible = false
	_set_status("Llave agregada a los drops de %s" % str(data.get("name", enemy_id)))

## Programmatically selects a tool by id (used by the key-location flow to arm "floor_item"
## without a real button click).
func _select_tool_by_id(tool_id: String) -> void:
	for i in range(TOOLS.size()):
		if TOOLS[i]["id"] == tool_id:
			_select_tool(TOOLS[i], _tool_buttons[i])
			return

# --- Resize (grow/shrink the tileset, no upper limit) ---

func _on_resize_pressed() -> void:
	var current_cols = _tiles[0].size() if _tiles.size() > 0 else 25
	var current_rows = _tiles.size()
	_show_text_prompt("Redimensionar (columnas x filas)", "%dx%d" % [current_cols, current_rows], _do_resize)

func _do_resize(text: String) -> void:
	var parts = text.strip_edges().to_lower().replace(" ", "").split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		_set_status("Formato inválido, usa ColumnasxFilas (ej: 30x25)")
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

	for list_key in ["npcs", "chests", "doors", "floor_items", "rest_zones", "traps", "combat_triggers", "riddle_gates", "boss_triggers", "story_triggers", "exits"]:
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
	_credits = data.get("credits", [])
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
	_map_data["credits"] = _credits
	if not _map_data.has("name") or str(_map_data["name"]) == "":
		_map_data["name"] = path.get_file().get_basename()

	var warnings: Array = []
	if not _entities.has("player_start"):
		warnings.append("sin player_start")
	if not _has_exit_tile():
		warnings.append("sin salida/Exit")
	warnings.append_array(_find_orphaned_warnings())

	if warnings.is_empty():
		_set_status("Mapa guardado: %s" % path)
	else:
		_set_status("Guardado (advertencias: %s)" % " | ".join(warnings))

	DataLoader.save_map(path, _map_data)
	DataLoader.load_map(path)
	_map_path = path

func _has_exit_tile() -> bool:
	for row in _tiles:
		if 9 in row:
			return true
	return false

## Warn-only (never blocks saving, same convention as the player_start/exit checks above):
## scans every placed entity for a reference (item/encounter/enemy/event id) that no longer
## exists in the corresponding global data file — most likely because it was deleted or
## renamed after the entity was placed.
func _find_orphaned_warnings() -> Array:
	var warnings: Array = []
	var item_ids = DataLoader.get_all_item_ids()
	var encounter_ids = DataLoader.get_all_encounter_ids()
	var event_ids = DataLoader.get_all_event_ids()

	for door in _entities.get("doors", []):
		var req = str(door.get("required_item_id", ""))
		if req != "" and not item_ids.has(req):
			warnings.append("Puerta (%s,%s): item '%s' no existe" % [str(door.get("row", "")), str(door.get("col", "")), req])

	for list_key in ["chests", "floor_items"]:
		for entry in _entities.get(list_key, []):
			var item_id = str(entry.get("item_id", ""))
			if item_id != "" and not item_ids.has(item_id):
				warnings.append("%s (%s,%s): item '%s' no existe" % [list_key, str(entry.get("row", "")), str(entry.get("col", "")), item_id])

	for list_key in ["combat_triggers", "boss_triggers", "riddle_gates"]:
		for entry in _entities.get(list_key, []):
			var encounter_id = str(entry.get("encounter_id", ""))
			if encounter_id == "":
				continue
			if not encounter_ids.has(encounter_id):
				warnings.append("%s (%s,%s): encuentro '%s' no existe" % [list_key, str(entry.get("row", "")), str(entry.get("col", "")), encounter_id])
			else:
				warnings.append_array(_check_encounter_enemies(encounter_id))

	for zone in _entities.get("random_encounter_zones", []):
		for eid in zone.get("encounter_ids", []):
			var encounter_id = str(eid)
			if not encounter_ids.has(encounter_id):
				warnings.append("Zona (%s,%s): encuentro '%s' no existe" % [str(zone.get("row", "")), str(zone.get("col", "")), encounter_id])
			else:
				warnings.append_array(_check_encounter_enemies(encounter_id))

	for entry in _entities.get("riddle_gates", []):
		for field in ["success_event_id", "combat_event_id"]:
			var event_id = str(entry.get(field, ""))
			if event_id != "" and not event_ids.has(event_id):
				warnings.append("Esfinge (%s,%s): evento '%s' no existe" % [str(entry.get("row", "")), str(entry.get("col", "")), event_id])

	for entry in _entities.get("story_triggers", []):
		var event_id = str(entry.get("event_id", ""))
		if event_id != "" and not event_ids.has(event_id):
			warnings.append("Story trigger (%s,%s): evento '%s' no existe" % [str(entry.get("row", "")), str(entry.get("col", "")), event_id])

	var unique: Array = []
	for w in warnings:
		if not unique.has(w):
			unique.append(w)
	return unique

## Checks one encounter's own enemies[] against DataLoader.get_all_enemy_ids() — catches an
## enemy that was deleted (via the Enemy Editor's "Eliminar enemigo") while an encounter still
## references it.
func _check_encounter_enemies(encounter_id: String) -> Array:
	var warnings: Array = []
	var encounter = DataLoader.get_encounter(encounter_id)
	var enemy_ids = DataLoader.get_all_enemy_ids()
	var seen := {}
	for enemy_id in encounter.get("enemies", []):
		var eid = str(enemy_id)
		if seen.has(eid):
			continue
		seen[eid] = true
		if not enemy_ids.has(eid):
			warnings.append("Encuentro '%s': enemigo '%s' no existe" % [encounter_id, eid])
	return warnings

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
	_credits = []
	_map_data = {"name": map_name, "tile_size": 2.0}
	_map_path = ""
	_grid.set_data(_tiles, _entities)
	_show_no_selection()
	_set_status("Mapa nuevo: %s (recordá Guardar como)" % map_name)

func _on_playtest_pressed() -> void:
	_map_data["tiles"] = _tiles
	_map_data["entities"] = _entities
	_map_data["credits"] = _credits
	DataLoader.set_current_map(_map_data)
	if standalone:
		SceneFlow.change_scene("res://scenes/boot/CharacterSelection.tscn")
	else:
		get_tree().reload_current_scene()

func _set_status(text: String) -> void:
	_status_label.text = text
