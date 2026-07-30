extends Control
class_name MiniMapUI
## MiniMapUI — Draws the minimap. Player is always rendered dead-center; the revealed
## cells around them scroll instead, so this works the same regardless of overall map size
## (the map editor now allows arbitrarily large/small maps — there's no total-size constant
## to iterate here anymore, only a fixed-size window around the player).

const CELL_SIZE: int = 5
const MAP_SIZE: int = 130  # pixels
const MAP_MARGIN: int = 10
const TILE_SIZE: float = 2.0

var _player: Node3D = null
var _dungeon_map: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_size = MAP_SIZE + MAP_MARGIN * 2
	custom_minimum_size = Vector2(box_size, box_size)
	# Explicit offsets (not position/size) — a bare Control has no content to
	# auto-size from, so anchors alone can leave it with a zero-size rect.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -box_size - 10
	offset_top = 10
	offset_right = -10
	offset_bottom = 10 + box_size

	# Try to get dungeon map data
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		var root = get_tree().current_scene
		if root:
			_player = root.get_node_or_null("Player")

	var builder = get_tree().current_scene.get_node_or_null("DungeonBuilder") if get_tree().current_scene else null
	if builder and "dungeon_map" in builder:
		_dungeon_map = builder.dungeon_map

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Background
	var bg_rect = Rect2(Vector2.ZERO, size)
	draw_rect(bg_rect, Color(0, 0, 0, 0.7))

	# Border
	draw_rect(bg_rect, Color(0.5, 0.45, 0.25), false, 2.0)

	if _dungeon_map.is_empty() or not _player:
		return

	var px = int(round(_player.global_position.x / TILE_SIZE))
	var py = int(round(_player.global_position.z / TILE_SIZE))
	var center = Vector2(MAP_MARGIN + MAP_SIZE / 2.0, MAP_MARGIN + MAP_SIZE / 2.0)
	var half_cells = int(MAP_SIZE / float(CELL_SIZE) / 2.0)

	# Draw revealed cells in a window around the player (player is always at dx=0, dy=0 —
	# the window scrolls with them instead of drawing the whole map at fixed positions).
	for dy in range(-half_cells, half_cells + 1):
		for dx in range(-half_cells, half_cells + 1):
			var col = px + dx
			var row = py + dy
			if not GameState.is_cell_revealed(col, row):
				continue

			var tile = 0
			if row >= 0 and row < _dungeon_map.size() and col >= 0 and col < _dungeon_map[row].size():
				tile = int(_dungeon_map[row][col])
			if tile == 0:  # EMPTY
				continue

			var color: Color
			match tile:
				2:  # WALL
					color = Color(0.5, 0.5, 0.55)
				3:  # DOOR
					color = Color(0.6, 0.4, 0.2)
				_:  # FLOOR and others
					color = Color(0.3, 0.28, 0.25)

			var cell_rect = Rect2(
				center + Vector2(dx * CELL_SIZE - CELL_SIZE / 2.0, dy * CELL_SIZE - CELL_SIZE / 2.0),
				Vector2(CELL_SIZE, CELL_SIZE)
			)
			draw_rect(cell_rect, color)

	# Player marker — always exactly centered
	draw_circle(center, 3.0, Color(0.2, 0.8, 1.0))
