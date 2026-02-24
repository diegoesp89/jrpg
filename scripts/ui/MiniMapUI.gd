extends Control
## MiniMapUI — Draws the minimap with fog-of-war and player marker.

const CELL_SIZE: int = 5
const MAP_SIZE: int = 130  # pixels
const MAP_MARGIN: int = 10
const TILE_SIZE: float = 2.0

# Map bounds (from DungeonBuilder layout)
const MAP_COLS: int = 25
const MAP_ROWS: int = 20

var _player: Node3D = null
var _dungeon_map: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(MAP_SIZE + MAP_MARGIN * 2, MAP_SIZE + MAP_MARGIN * 2)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-MAP_SIZE - MAP_MARGIN * 2 - 10, 10)
	size = custom_minimum_size

	# Try to get dungeon map data
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		var root = get_tree().current_scene
		if root:
			_player = root.get_node_or_null("Player")

	var builder = get_tree().current_scene.get_node_or_null("DungeonBuilder")
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

	if _dungeon_map.is_empty():
		return

	# Draw revealed cells
	for row in range(MAP_ROWS):
		for col in range(MAP_COLS):
			if GameState.is_cell_revealed(col, row):
				var tile = 0
				if row < _dungeon_map.size() and col < _dungeon_map[row].size():
					tile = _dungeon_map[row][col]

				var cell_rect = Rect2(
					Vector2(MAP_MARGIN + col * CELL_SIZE, MAP_MARGIN + row * CELL_SIZE),
					Vector2(CELL_SIZE, CELL_SIZE)
				)

				var color: Color
				match tile:
					0:  # EMPTY
						continue
					2:  # WALL
						color = Color(0.5, 0.5, 0.55)
					3:  # DOOR
						color = Color(0.6, 0.4, 0.2)
					_:  # FLOOR and others
						color = Color(0.3, 0.28, 0.25)

				draw_rect(cell_rect, color)

	# Draw player marker
	if _player:
		var px = int(round(_player.global_position.x / TILE_SIZE))
		var py = int(round(_player.global_position.z / TILE_SIZE))
		var player_pos = Vector2(
			MAP_MARGIN + px * CELL_SIZE + CELL_SIZE / 2.0,
			MAP_MARGIN + py * CELL_SIZE + CELL_SIZE / 2.0
		)
		draw_circle(player_pos, 3.0, Color(0.2, 0.8, 1.0))
