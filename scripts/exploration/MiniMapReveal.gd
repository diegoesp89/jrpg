extends Node
## MiniMapReveal — Converts player world position to grid cell and reveals nearby cells.

const TILE_SIZE: float = 2.0
const REVEAL_RADIUS: int = 3

var _player: Node3D = null

func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		# Find by name
		var root = get_tree().current_scene
		if root:
			_player = root.get_node_or_null("Player")

func _process(_delta: float) -> void:
	if not _player:
		return

	var cell_x = int(round(_player.global_position.x / TILE_SIZE))
	var cell_y = int(round(_player.global_position.z / TILE_SIZE))

	# Reveal cells in radius
	for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy <= REVEAL_RADIUS * REVEAL_RADIUS:
				GameState.reveal_cell(cell_x + dx, cell_y + dy)
