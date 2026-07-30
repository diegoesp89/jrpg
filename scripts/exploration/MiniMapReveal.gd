extends Node
class_name MiniMapReveal
## MiniMapReveal — Reveals minimap cells around the player via a flood fill that stops at
## walls (8-directional, with diagonal corner-cutting blocked), so rooms/corridors behind a
## wall never get revealed just for being within radius — matches what the player could
## actually see/walk through from their current position.

const TILE_SIZE: float = 2.0
const REVEAL_RADIUS: int = 3
const WALL_TILE: int = 2

const DIRECTIONS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _player: Node3D = null
var _dungeon_map: Array = []

func _ready() -> void:
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
	if not _player:
		return

	var cell_x = int(round(_player.global_position.x / TILE_SIZE))
	var cell_y = int(round(_player.global_position.z / TILE_SIZE))
	_reveal_from(cell_x, cell_y)

func _is_wall(row: int, col: int) -> bool:
	if _dungeon_map.is_empty():
		return false
	if row < 0 or row >= _dungeon_map.size():
		return true
	if col < 0 or col >= _dungeon_map[row].size():
		return true
	return int(_dungeon_map[row][col]) == WALL_TILE

func _reveal_from(start_x: int, start_y: int) -> void:
	var visited := {Vector2i(start_x, start_y): 0}
	GameState.reveal_cell(start_x, start_y)

	var queue: Array = [Vector2i(start_x, start_y)]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var dist: int = visited[cur]
		if dist >= REVEAL_RADIUS:
			continue

		for offset in DIRECTIONS:
			var next: Vector2i = cur + offset
			if visited.has(next):
				continue
			if offset.x != 0 and offset.y != 0:
				# Diagonal step: block corner-cutting through a wall corner so you can't
				# "see" diagonally past two walls that only touch at a point.
				if _is_wall(cur.y, cur.x + offset.x) and _is_wall(cur.y + offset.y, cur.x):
					continue

			visited[next] = dist + 1
			GameState.reveal_cell(next.x, next.y)
			# Reveal the wall itself (so it shows as a boundary on the minimap) but don't
			# propagate through it — that's what actually blocks "seeing" past it.
			if not _is_wall(next.y, next.x):
				queue.append(next)
