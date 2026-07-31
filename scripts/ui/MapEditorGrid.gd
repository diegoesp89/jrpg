extends Control
class_name MapEditorGrid
## MapEditorGrid — 2D top-down clickable representation of a map's tiles + entities.
## Pure rendering/input widget; MapEditor.gd owns the actual map data and edit logic.

signal drag_started(row: int, col: int)
signal drag_moved(row: int, col: int)
signal drag_ended(row: int, col: int)
signal pan_requested(delta: Vector2)

var _panning: bool = false

const MIN_CELL_SIZE := 6.0
const MAX_CELL_SIZE := 64.0
const ZOOM_STEP := 1.05  # gentle per-tick factor — a trackpad fires many wheel events per gesture

var cell_size: float = 24.0

const TILE_COLORS := {
	0: Color(0.08, 0.08, 0.08),
	1: Color(0.25, 0.22, 0.2),
	2: Color(0.4, 0.4, 0.45),
	3: Color(0.55, 0.35, 0.15),
	4: Color(0.2, 0.7, 0.3),
	5: Color(0.85, 0.7, 0.1),
	6: Color(0.8, 0.2, 0.2),
	7: Color(0.9, 0.5, 0.1),
	8: Color(0.6, 0.05, 0.05),
	9: Color(0.2, 0.8, 0.8),
	10: Color(0.6, 0.3, 0.8),
	11: Color(0.3, 0.9, 0.8),
	12: Color(1.0, 0.85, 0.4),
}

# Marker/zone colors — shared with MapEditor's palette legend so the swatches always match
# what's actually drawn on the grid.
const PLAYER_START_COLOR := Color(1, 1, 0)
const STORY_TRIGGER_COLOR := Color(1, 0.4, 0.8)
const ZONE_FILL_COLOR := Color(0.2, 0.4, 0.9, 0.35)
const ZONE_BORDER_COLOR := Color(0.3, 0.6, 1.0, 0.9)

var tiles: Array = []
var entities: Dictionary = {}
var highlight_rect: Rect2i = Rect2i(-1, -1, 0, 0)

func set_data(new_tiles: Array, new_entities: Dictionary) -> void:
	tiles = new_tiles
	entities = new_entities
	_update_size()
	queue_redraw()

func _update_size() -> void:
	var rows = tiles.size()
	var cols = tiles[0].size() if rows > 0 else 0
	custom_minimum_size = Vector2(cols * cell_size, rows * cell_size)
	size = custom_minimum_size

func _draw() -> void:
	for row in range(tiles.size()):
		for col in range(tiles[row].size()):
			var tile = int(tiles[row][col])
			var color = TILE_COLORS.get(tile, Color(0.08, 0.08, 0.08))
			draw_rect(Rect2(col * cell_size, row * cell_size, cell_size - 1, cell_size - 1), color)

	for zone in entities.get("random_encounter_zones", []):
		var row = float(zone.get("row", 0))
		var col = float(zone.get("col", 0))
		var w = float(zone.get("width", 1))
		var h = float(zone.get("height", 1))
		# "row"/"col" are the CENTER of the zone; a zone of width w spans w cells whose
		# leftmost edge is (w-1)/2 cells to the left of center — not w/2, which is off by
		# half a cell (that's the "not centered" bug: it always drew half a cell too far
		# up-left).
		var left = (col - (w - 1.0) / 2.0) * cell_size
		var top = (row - (h - 1.0) / 2.0) * cell_size
		var r = Rect2(left, top, w * cell_size, h * cell_size)
		draw_rect(r, ZONE_FILL_COLOR)
		draw_rect(r, ZONE_BORDER_COLOR, false, 2.0)

	for st in entities.get("story_triggers", []):
		_draw_marker(int(st.get("row", -1)), int(st.get("col", -1)), STORY_TRIGGER_COLOR)

	var start = entities.get("player_start", {})
	if start.has("row"):
		_draw_marker(int(start["row"]), int(start["col"]), PLAYER_START_COLOR)

	if highlight_rect.size.x > 0:
		var hr = Rect2(highlight_rect.position.x * cell_size, highlight_rect.position.y * cell_size, highlight_rect.size.x * cell_size, highlight_rect.size.y * cell_size)
		draw_rect(hr, Color(1, 1, 1, 0.25))

func _draw_marker(row: int, col: int, color: Color) -> void:
	if row < 0 or col < 0:
		return
	var center = Vector2(col * cell_size + cell_size / 2.0, row * cell_size + cell_size / 2.0)
	draw_circle(center, cell_size * 0.3, color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(ZOOM_STEP)
			accept_event()
			return
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / ZOOM_STEP)
			accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cell = _cell_at(event.position)
			if cell.x < 0:
				return
			if event.pressed:
				drag_started.emit(cell.y, cell.x)
			else:
				drag_ended.emit(cell.y, cell.x)
			accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			pan_requested.emit(event.relative)
			accept_event()
			return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var cell = _cell_at(event.position)
			if cell.x >= 0:
				drag_moved.emit(cell.y, cell.x)
			accept_event()

func _zoom(factor: float) -> void:
	cell_size = clampf(cell_size * factor, MIN_CELL_SIZE, MAX_CELL_SIZE)
	_update_size()
	queue_redraw()

func _cell_at(pos: Vector2) -> Vector2i:
	var col = int(pos.x / cell_size)
	var row = int(pos.y / cell_size)
	if row < 0 or row >= tiles.size():
		return Vector2i(-1, -1)
	if col < 0 or col >= tiles[row].size():
		return Vector2i(-1, -1)
	return Vector2i(col, row)
