extends Node3D
class_name DungeonBuilder
## DungeonBuilder — Generates the dungeon layout

## Preloaded by path rather than referenced through its `class_name`: a script whose global class
## was registered after the editor session started is not yet in that session's class cache, and
## the parse fails until the project is reloaded. preload() resolves at compile time from the
## path, so it works on the very first run after the file is created.
const EasterEggsData = preload("res://scripts/data/EasterEggs.gd")
const AchievementsScript = preload("res://scripts/core/Achievements.gd")

const TILE_SIZE: float = 2.0

# Tile types
enum Tile { EMPTY = 0, FLOOR = 1, WALL = 2, DOOR = 3, NPC = 4, CHEST = 5, COMBAT_TRIGGER = 6, TRAP = 7, BOSS_TRIGGER = 8, EXIT = 9, RIDDLE_GATE = 10, FLOOR_ITEM = 11, REST_ZONE = 12 }

# Colors for placeholder sprites not yet reskinned with real/downloaded art
const REST_ZONE_COLOR = Color(1.0, 0.85, 0.4)
const REST_ZONE_BORDER = Color(0.7, 0.55, 0.1)

# Dungeon layout is data-driven: loaded from the current map (res://maps/*.map, selected at
# MapSelection) via DataLoader.get_current_map(). See _load_map_data(). Falls back to the
# default shipped map if none was selected (e.g. testing this scene directly).
const DEFAULT_MAP_PATH := "res://maps/white_plume_mountain.map"

var dungeon_map: Array = []
var _entities: Dictionary = {}

var _wall_nodes: Array[Node3D] = []
var _floor_mesh: MeshInstance3D = null
var _wall_texture: Texture2D = null

## Debug Panel's "Mostrar triggers en el mapa" — one entry per non-wall, non-floor, non-trap
## entity created below, {"node": Node3D, "kind": String, "config": Dictionary}. Traps are
## deliberately excluded: they're hidden until sprung, same spoiler-free rule as the Ayuda pages.
var _debug_entities: Array = []
var _debug_labels: Array[Label3D] = []

# Dungeon dressing textures (placeholder art — see assets/sprites/dungeon/CREDITS.txt),
# loaded once and reused across every tile/entity instance.
var _floor_texture_a: Texture2D = null
var _floor_texture_b: Texture2D = null
var _npc_texture: Texture2D = null
var _chest_closed_texture: Texture2D = null
var _chest_open_texture: Texture2D = null
var _floor_item_texture: Texture2D = null
var _trap_texture: Texture2D = null
var _door_texture: Texture2D = null
var _door_locked_texture: Texture2D = null

# Shared shader instances (created once, reused)
var _fog_shader_color: Shader = null
var _fog_shader_textured: Shader = null
var _fog_shader_textured_alpha: Shader = null  # transparent variant for occlusion fade

static var _fog_globals_registered: bool = false

func _ready() -> void:
	_load_map_data()
	_init_fog_shaders()
	_register_fog_globals()
	_build_dungeon()

func _load_map_data() -> void:
	var map_data = DataLoader.get_current_map()
	if map_data.is_empty():
		DataLoader.load_map(DEFAULT_MAP_PATH)
		map_data = DataLoader.get_current_map()
	dungeon_map = map_data.get("tiles", [])
	_entities = map_data.get("entities", {})

## Finds the entity config placed at (row, col) within one of the lists in `_entities`
## (e.g. "npcs", "chests"). Returns {} if none is configured there.
func _get_entity_at(list_key: String, row: int, col: int) -> Dictionary:
	for entry in _entities.get(list_key, []):
		if int(entry.get("row", -1)) == row and int(entry.get("col", -1)) == col:
			return entry
	return {}

func _register_fog_globals() -> void:
	# Register global shader params only once (persists across scene reloads).
	if not _fog_globals_registered:
		RenderingServer.global_shader_parameter_add("player_world_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
		RenderingServer.global_shader_parameter_add("fog_start", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 6.0)
		RenderingServer.global_shader_parameter_add("fog_end", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 10.0)
		_fog_globals_registered = true

func _build_dungeon() -> void:
	_wall_texture = load("res://assets/sprites/dungeon/wall_gray.png")
	_floor_texture_a = load("res://assets/sprites/dungeon/floor_gray0.png")
	_floor_texture_b = load("res://assets/sprites/dungeon/floor_gray1.png")
	_npc_texture = load("res://assets/sprites/dungeon/npc_human.png")
	_chest_closed_texture = load("res://assets/sprites/dungeon/chest_closed.png")
	_chest_open_texture = load("res://assets/sprites/dungeon/chest_open.png")
	_floor_item_texture = load("res://assets/sprites/dungeon/floor_item_box.png")
	_trap_texture = load("res://assets/sprites/dungeon/trap_spear.png")
	_door_texture = load("res://assets/sprites/dungeon/door.png")
	_door_locked_texture = load("res://assets/sprites/dungeon/door_locked.png")
	_build_floor()
	_build_walls_and_entities()
	_create_random_encounter_zones()
	_create_standalone_story_triggers()

## Story triggers co-located with an Exit tile are handled specially inside _create_exit
## (auto_trigger=false, invoked directly to avoid a body_entered race). Any other entry in
## "story_triggers" is a standalone narrative beat placed anywhere on the map — it gets its
## own self-triggering Area3D, so future scenes can be added purely through map data.
func _create_standalone_story_triggers() -> void:
	var trigger_script = load("res://scripts/exploration/StoryTrigger.gd")
	for cfg in _entities.get("story_triggers", []):
		var row = int(cfg.get("row", -1))
		var col = int(cfg.get("col", -1))
		if row >= 0 and row < dungeon_map.size() and col >= 0 and col < dungeon_map[row].size():
			if dungeon_map[row][col] == Tile.EXIT:
				continue  # handled inside _create_exit
		var trigger = Area3D.new()
		trigger.name = "StoryTrigger_%s" % cfg.get("event_id", "")
		trigger.position = Vector3(col * TILE_SIZE, 0, row * TILE_SIZE)
		trigger.collision_layer = 8
		trigger.collision_mask = 2

		var col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(TILE_SIZE, 2.0, TILE_SIZE)
		col_shape.shape = box
		col_shape.position = Vector3(0, 1.0, 0)
		trigger.add_child(col_shape)

		if trigger_script:
			trigger.set_script(trigger_script)
			trigger.event_id = cfg.get("event_id", "")
			trigger.requires_flag = cfg.get("requires_flag", "")
			trigger.auto_trigger = true

		add_child(trigger)
		_debug_entities.append({"node": trigger, "kind": "story_trigger", "config": cfg})

func _build_floor() -> void:
	# Count floor tiles to determine floor extent
	var min_x: int = 999
	var max_x: int = -999
	var min_z: int = 999
	var max_z: int = -999

	for row in range(dungeon_map.size()):
		for col in range(dungeon_map[row].size()):
			if dungeon_map[row][col] != Tile.EMPTY:
				min_x = mini(min_x, col)
				max_x = maxi(max_x, col)
				min_z = mini(min_z, row)
				max_z = maxi(max_z, row)

	# Create individual floor tiles for grid look
	for row in range(dungeon_map.size()):
		for col in range(dungeon_map[row].size()):
			var tile = dungeon_map[row][col]
			if tile != Tile.EMPTY and tile != Tile.WALL:
				_create_floor_tile(col, row)

func _create_floor_tile(col: int, row: int) -> void:
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(TILE_SIZE - 0.05, TILE_SIZE - 0.05)
	mesh_instance.mesh = plane_mesh

	# Checkerboard pattern with fog shader
	var texture = _floor_texture_a if (col + row) % 2 == 0 else _floor_texture_b
	mesh_instance.material_override = _make_fog_textured_material(texture)

	mesh_instance.position = Vector3(col * TILE_SIZE, 0, row * TILE_SIZE)
	add_child(mesh_instance)

func _build_walls_and_entities() -> void:
	for row in range(dungeon_map.size()):
		for col in range(dungeon_map[row].size()):
			var tile = dungeon_map[row][col]
			var pos = Vector3(col * TILE_SIZE, 0, row * TILE_SIZE)

			match tile:
				Tile.WALL:
					_create_wall(pos, col, row)
				Tile.DOOR:
					_create_door(pos, row, col, _get_entity_at("doors", row, col))
				Tile.NPC:
					_create_npc(pos, _get_entity_at("npcs", row, col))
				Tile.CHEST:
					_create_chest(pos, _get_entity_at("chests", row, col))
				Tile.COMBAT_TRIGGER:
					_create_combat_trigger(pos, _get_entity_at("combat_triggers", row, col))
				Tile.TRAP:
					_create_trap(pos, _get_entity_at("traps", row, col))
				Tile.BOSS_TRIGGER:
					_create_boss_trigger(pos, _get_entity_at("boss_triggers", row, col))
				Tile.EXIT:
					_create_exit(pos, row, col)
				Tile.RIDDLE_GATE:
					_create_riddle_gate(pos, _get_entity_at("riddle_gates", row, col))
				Tile.FLOOR_ITEM:
					_create_floor_item(pos, _get_entity_at("floor_items", row, col))
				Tile.REST_ZONE:
					_create_rest_zone(pos, _get_entity_at("rest_zones", row, col))

func _create_wall(pos: Vector3, col: int, row: int) -> void:
	var wall = StaticBody3D.new()
	wall.name = "Wall_%d_%d" % [col, row]
	wall.position = pos

	# Collision
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 3.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.5, 0)
	wall.add_child(col_shape)

	# Collision layers: world (1) + occluder (5)
	wall.collision_layer = 1 | 16  # bits 0 and 4
	wall.collision_mask = 0

	# Material per wall (own instance so Occludable fade is independent)
	# Uses fog textured shader — already cull_disabled + unshaded
	var mat = _make_fog_textured_material(_wall_texture)

	# Create one vertical quad per exposed face (adjacent to non-wall)
	var face_idx := 0
	# Check 4 neighbors: north (row-1), south (row+1), west (col-1), east (col+1)
	var neighbors = [
		{"dr": -1, "dc": 0, "offset": Vector3(0, 1.5, -TILE_SIZE / 2.0), "rot": 0.0},       # north face
		{"dr": 1,  "dc": 0, "offset": Vector3(0, 1.5,  TILE_SIZE / 2.0), "rot": 0.0},       # south face
		{"dr": 0,  "dc": -1, "offset": Vector3(-TILE_SIZE / 2.0, 1.5, 0), "rot": PI / 2.0}, # west face
		{"dr": 0,  "dc": 1,  "offset": Vector3( TILE_SIZE / 2.0, 1.5, 0), "rot": PI / 2.0}, # east face
	]

	for n in neighbors:
		var nr = row + n["dr"]
		var nc = col + n["dc"]
		if _is_open_tile(nr, nc):
			var mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "WallFace_%d" % face_idx
			var quad = QuadMesh.new()
			quad.size = Vector2(TILE_SIZE, 3.0)
			mesh_instance.mesh = quad
			mesh_instance.material_override = mat
			mesh_instance.position = n["offset"]
			mesh_instance.rotation.y = n["rot"]
			wall.add_child(mesh_instance)
			face_idx += 1

	# A wall tile with no exposed faces is fully surrounded by other walls — no floor tile
	# is ever adjacent to it, so the player can never be next to it. Skip it entirely:
	# the old "top cap so it's visible from above" fallback rendered a lone floating plane
	# with no wall geometry beneath it, showing up as a stray panel from oblique angles.
	if face_idx == 0:
		return

	# Add Occludable as child node
	var occludable_script = load("res://scripts/exploration/Occludable.gd")
	if occludable_script:
		var occludable = Node.new()
		occludable.name = "Occludable"
		occludable.set_script(occludable_script)
		wall.add_child(occludable)

	add_child(wall)
	_wall_nodes.append(wall)

## True if (row, col) is a wall tile or off the edge of the map — either way, nothing can walk
## through it, so it counts as "wall" for the purposes of figuring out a door's orientation below.
func _is_wall_or_edge(row: int, col: int) -> bool:
	if row < 0 or row >= dungeon_map.size() or col < 0 or col >= dungeon_map[row].size():
		return true
	return dungeon_map[row][col] == Tile.WALL

func _create_door(pos: Vector3, row: int, col: int, config: Dictionary = {}) -> void:
	var door_scene_script = load("res://scripts/exploration/Door.gd")
	var door = StaticBody3D.new()
	door.name = "Door"
	door.position = pos
	door.collision_layer = 1 | 4  # world + interactable
	door.collision_mask = 0

	# A door sits inside what would otherwise be a wall segment. The Map Editor's "Pared vertical"
	# checkbox lets a mapper set this explicitly (config["vertical"]); if it's absent (older maps,
	# or a door placed by hand outside the editor) fall back to auto-detecting from neighbor
	# tiles — if the door's ABOVE/BELOW neighbors are wall (or the map edge), that wall's solid
	# tiles only differ by row, so the wall itself runs north-south, and the gap in it is crossed
	# by walking east-west. Door blocks east-west traffic in that case, not the default
	# north-south-blocking orientation (which is for a wall whose solid tiles differ by column —
	# LEFT/RIGHT neighbors — i.e. a wall that runs east-west, crossed by walking north-south).
	var vertical_wall: bool
	if config.has("vertical"):
		vertical_wall = bool(config["vertical"])
	else:
		vertical_wall = _is_wall_or_edge(row - 1, col) and _is_wall_or_edge(row + 1, col)

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 3.0, TILE_SIZE) if vertical_wall else Vector3(TILE_SIZE, 3.0, 0.4)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.5, 0)
	door.add_child(col_shape)

	# Looks like a wall (same quad-face geometry _create_wall gives an exposed wall face), just
	# textured with door.png/door_locked.png instead of stone — one face on each side actually
	# facing the corridor, matching whichever pair of neighbors the box above just blocked
	# traffic between.
	var face_configs: Array
	if vertical_wall:
		face_configs = [
			{"offset": Vector3(-TILE_SIZE / 2.0, 1.5, 0), "rot": PI / 2.0},
			{"offset": Vector3( TILE_SIZE / 2.0, 1.5, 0), "rot": PI / 2.0},
		]
	else:
		face_configs = [
			{"offset": Vector3(0, 1.5, -TILE_SIZE / 2.0), "rot": 0.0},
			{"offset": Vector3(0, 1.5,  TILE_SIZE / 2.0), "rot": 0.0},
		]

	var unlocked_material = _make_fog_textured_material(_door_texture)
	var locked_material = _make_fog_textured_material(_door_locked_texture)

	for i in range(face_configs.size()):
		var fc = face_configs[i]
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "DoorFace_%d" % i
		var quad = QuadMesh.new()
		quad.size = Vector2(TILE_SIZE, 3.0)
		mesh_instance.mesh = quad
		mesh_instance.position = fc["offset"]
		mesh_instance.rotation.y = fc["rot"]
		door.add_child(mesh_instance)

	if door_scene_script:
		door.set_script(door_scene_script)
		door.door_id = config.get("door_id", "")
		door.locked = bool(config.get("locked", false))
		door.required_item_id = config.get("required_item_id", "")
		door.unlocked_material = unlocked_material
		door.locked_material = locked_material
	else:
		for child in door.get_children():
			if child is MeshInstance3D:
				child.material_override = unlocked_material

	add_child(door)
	_debug_entities.append({"node": door, "kind": "door", "config": config})

func _create_npc(pos: Vector3, config: Dictionary = {}) -> void:
	var npc_script = load("res://scripts/exploration/NPCIntro.gd")
	var npc = StaticBody3D.new()
	npc.name = "NPCIntro"
	npc.position = pos
	npc.collision_layer = 1 | 4  # world (blocks player) + interactable
	npc.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.8, 1.6, 0.8)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.8, 0)
	npc.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _npc_texture
	sprite.position = Vector3(0, 0.8, 0)
	npc.add_child(sprite)

	if npc_script:
		npc.set_script(npc_script)
		if config.has("dialogue_id"):
			npc.dialogue_id = config["dialogue_id"]

	add_child(npc)
	_debug_entities.append({"node": npc, "kind": "npc", "config": config})

func _create_rest_zone(pos: Vector3, config: Dictionary = {}) -> void:
	var rest_script = load("res://scripts/exploration/RestZone.gd")
	var rest = StaticBody3D.new()
	rest.name = "RestZone"
	rest.position = pos
	rest.collision_layer = 1 | 4  # world (blocks player) + interactable
	rest.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.7, 0.7, 0.7)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.35, 0)
	rest.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _create_rect_texture(REST_ZONE_COLOR, REST_ZONE_BORDER, 32, 32)
	sprite.position = Vector3(0, 0.5, 0)
	rest.add_child(sprite)

	if rest_script:
		rest.set_script(rest_script)

	add_child(rest)
	_debug_entities.append({"node": rest, "kind": "rest_zone", "config": config})

func _create_chest(pos: Vector3, config: Dictionary = {}) -> void:
	var pickup_script = load("res://scripts/exploration/Pickup.gd")
	var chest = StaticBody3D.new()
	chest.name = "Chest"
	chest.position = pos
	chest.collision_layer = 1 | 4  # world (blocks player) + interactable
	chest.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.8, 0.6, 0.8)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.3, 0)
	chest.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _chest_closed_texture
	sprite.position = Vector3(0, 0.5, 0)
	chest.add_child(sprite)

	if pickup_script:
		chest.set_script(pickup_script)
		chest.closed_texture = _chest_closed_texture
		chest.open_texture = _chest_open_texture
		if config.has("item_id"):
			chest.item_id = config["item_id"]
		if config.has("quantity"):
			chest.item_quantity = int(config["quantity"])
		if config.has("chest_id"):
			chest.chest_id = config["chest_id"]

	add_child(chest)
	_debug_entities.append({"node": chest, "kind": "chest", "config": config})

## An item lying directly on the floor (no chest) — same Pickup.gd logic as a chest, just a
## smaller, differently-colored sprite so it reads as a loose item rather than a container.
func _create_floor_item(pos: Vector3, config: Dictionary = {}) -> void:
	var pickup_script = load("res://scripts/exploration/Pickup.gd")
	var item = StaticBody3D.new()
	item.name = "FloorItem"
	item.position = pos
	item.collision_layer = 1 | 4  # world (blocks player) + interactable
	item.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.2, 0)
	item.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _floor_item_texture
	sprite.position = Vector3(0, 0.3, 0)
	item.add_child(sprite)

	if pickup_script:
		item.set_script(pickup_script)
		if config.has("item_id"):
			item.item_id = config["item_id"]
		if config.has("quantity"):
			item.item_quantity = int(config["quantity"])
		if config.has("chest_id"):
			item.chest_id = config["chest_id"]

	add_child(item)
	_debug_entities.append({"node": item, "kind": "floor_item", "config": config})

func _create_combat_trigger(pos: Vector3, config: Dictionary = {}) -> void:
	var trigger_script = load("res://scripts/exploration/CombatTrigger.gd")
	var trigger = Area3D.new()
	var encounter_id = config.get("encounter_id", "encounter_hallway")
	trigger.name = "CombatTrigger_%s" % encounter_id
	trigger.position = pos
	trigger.collision_layer = 8  # trigger layer
	trigger.collision_mask = 2  # detect player

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 2.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.0, 0)
	trigger.add_child(col_shape)

	if trigger_script:
		trigger.set_script(trigger_script)
		trigger.encounter_id = encounter_id
		trigger.intro_message = config.get("intro_message", "")
		trigger.death_message = config.get("death_message", "")

	add_child(trigger)
	_debug_entities.append({"node": trigger, "kind": "combat_trigger", "config": {"encounter_id": encounter_id}})

func _create_trap(pos: Vector3, config: Dictionary = {}) -> void:
	# Trap: an area that damages player on enter
	var trap = Area3D.new()
	trap.name = "Trap"
	trap.position = pos
	trap.collision_layer = 8
	trap.collision_mask = 2

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 1.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.5, 0)
	trap.add_child(col_shape)

	# Sprung-trap marker (spike floor decal) — stays hidden until the trap actually triggers
	# (see Trap.gd), so an armed trap looks like ordinary floor to the player and doesn't give
	# itself away; only reveals itself once triggered, as a permanent "already dealt with" marker.
	var mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(TILE_SIZE - 0.1, TILE_SIZE - 0.1)
	mesh.mesh = plane
	mesh.material_override = _make_fog_textured_material(_trap_texture)
	mesh.position = Vector3(0, 0.01, 0)
	mesh.visible = false
	trap.add_child(mesh)

	# Use proper script file for trap logic
	var trap_script = load("res://scripts/exploration/Trap.gd")
	if trap_script:
		trap.set_script(trap_script)
		trap.triggered_marker = mesh
		trap.trap_id = str(config.get("trap_id", "trap_%d_%d" % [int(config.get("row", -1)), int(config.get("col", -1))]))
		if config.has("damage"):
			trap.damage = int(config["damage"])
		if config.has("dc"):
			trap.dc = int(config["dc"])

	add_child(trap)

func _create_riddle_gate(pos: Vector3, config: Dictionary = {}) -> void:
	var gate_script = load("res://scripts/exploration/RiddleGate.gd")
	var gate = StaticBody3D.new()
	gate.name = "RiddleGate"
	gate.position = pos
	gate.collision_layer = 1 | 4  # world (blocks player) + interactable
	gate.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 3.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.5, 0)
	gate.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _create_rect_texture(Color(0.55, 0.15, 0.55), Color(0.3, 0.05, 0.3), 32, 48)
	sprite.position = Vector3(0, 1.2, 0)
	gate.add_child(sprite)

	if gate_script:
		gate.set_script(gate_script)
		if config.has("encounter_id"):
			gate.encounter_id = config["encounter_id"]
		if config.has("success_event_id"):
			gate.success_event_id = config["success_event_id"]
		if config.has("combat_event_id"):
			gate.combat_event_id = config["combat_event_id"]

	add_child(gate)
	_debug_entities.append({"node": gate, "kind": "riddle_gate", "config": config})

func _create_random_encounter_zones() -> void:
	var zone_script = load("res://scripts/exploration/RandomEncounterZone.gd")
	var zones_config: Array = _entities.get("random_encounter_zones", [])
	for cfg in zones_config:
		var zone = Area3D.new()
		var row = float(cfg.get("row", 0))
		var col = float(cfg.get("col", 0))
		var width = float(cfg.get("width", 1))
		var height = float(cfg.get("height", 1))
		zone.name = "RandomEncounterZone_%d_%d" % [int(row), int(col)]
		zone.position = Vector3(col * TILE_SIZE, 0, row * TILE_SIZE)
		zone.collision_layer = 8
		zone.collision_mask = 2

		var col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(width * TILE_SIZE, 2.0, height * TILE_SIZE)
		col_shape.shape = box
		col_shape.position = Vector3(0, 1.0, 0)
		zone.add_child(col_shape)

		if zone_script:
			zone.set_script(zone_script)
			zone.encounter_ids = cfg.get("encounter_ids", [])
			zone.chance = float(cfg.get("chance", 0.25))
			zone.check_interval = float(cfg.get("interval", 8.0))

		add_child(zone)
		_debug_entities.append({"node": zone, "kind": "random_encounter_zone", "config": cfg})

func _create_boss_trigger(pos: Vector3, config: Dictionary = {}) -> void:
	var trigger_script = load("res://scripts/exploration/CombatTrigger.gd")
	var trigger = Area3D.new()
	var encounter_id = config.get("encounter_id", "encounter_boss")
	trigger.name = "CombatTrigger_%s" % encounter_id
	trigger.position = pos
	trigger.collision_layer = 8
	trigger.collision_mask = 2

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 2.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.0, 0)
	trigger.add_child(col_shape)

	if trigger_script:
		trigger.set_script(trigger_script)
		trigger.encounter_id = encounter_id
		trigger.intro_message = config.get("intro_message", "")
		trigger.death_message = config.get("death_message", "")

	add_child(trigger)
	_debug_entities.append({"node": trigger, "kind": "boss_trigger", "config": {"encounter_id": encounter_id}})

func _create_exit(pos: Vector3, row: int, col: int) -> void:
	# Exit: touching this ends the slice with victory
	var exit_area = Area3D.new()
	exit_area.name = "Exit"
	exit_area.position = pos
	exit_area.collision_layer = 8
	exit_area.collision_mask = 2

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 2.0, TILE_SIZE)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.0, 0)
	exit_area.add_child(col_shape)

	# Bright floor
	var mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(TILE_SIZE - 0.1, TILE_SIZE - 0.1)
	mesh.mesh = plane
	mesh.material_override = _make_fog_color_material(Color(0.9, 0.85, 0.5))
	mesh.position = Vector3(0, 0.02, 0)
	exit_area.add_child(mesh)

	exit_area.body_entered.connect(_on_exit_entered)
	add_child(exit_area)
	_debug_entities.append({"node": exit_area, "kind": "exit", "config": {}})

	# Co-located story trigger: plays the exit banter (matched to the current party) before the
	# victory screen. auto_trigger=false avoids a body_entered race with exit_area; _on_exit_entered
	# invokes it directly and awaits completion. Config comes from the map's "story_triggers" list
	# (falls back to the classic WP30/boss-defeated defaults if the map doesn't define one here).
	var story_cfg = _get_entity_at("story_triggers", row, col)
	var trigger_script = load("res://scripts/exploration/StoryTrigger.gd")
	_wp30_trigger = Area3D.new()
	_wp30_trigger.set_script(trigger_script)
	_wp30_trigger.event_id = story_cfg.get("event_id", "WP30")
	_wp30_trigger.requires_flag = story_cfg.get("requires_flag", "combat_encounter_boss_done")
	_wp30_trigger.auto_trigger = false
	add_child(_wp30_trigger)

	# Exit condition: the map can require holding specific items (e.g. the 3 legendary
	# weapons) before stepping on the exit actually ends the run. Missing items = the tile
	# is just floor, nothing happens yet.
	var exit_cfg = _get_entity_at("exits", row, col)
	_exit_required_items = exit_cfg.get("requires_items", [])

var _exit_triggered: bool = false
var _wp30_trigger: Area3D = null
var _exit_required_items: Array = []

func _on_exit_entered(body: Node3D) -> void:
	if _exit_triggered:
		return
	if body is CharacterBody3D:
		for item_id in _exit_required_items:
			if not GameState.has_item(item_id):
				var item = DataLoader.get_item(item_id)
				print("Te falta: %s" % item.get("name", item_id))
				return
		_exit_triggered = true
		# Disable player movement
		if body.has_method("set_movement_disabled"):
			body.set_movement_disabled(true)
		if _wp30_trigger:
			await _wp30_trigger.play_for_current_party()
		print("Victory! You have escaped White Plume Mountain!")
		SaveManager.record_profile_completion()
		await _check_run_completion_achievements()
		# Show victory screen
		_show_victory_screen()

## Run-completion achievement checkpoint — right after record_profile_completion() and before the
## victory screen, so GameState.party/rest_charges_left/run_flawless/flags still hold this run's
## real values (GameState.reset() only happens once the player dismisses the victory screen).
## Sequenced with await so several unlocks queue one after another instead of overlapping.
func _check_run_completion_achievements() -> void:
	await AchievementsScript.unlock(self, "primer_paso")

	var party_ids: Array = []
	for m in GameState.party:
		party_ids.append(str(m.get("id", "")))
	if party_ids.has("huguito") and party_ids.has("lulu"):
		await AchievementsScript.unlock(self, "garras_gemelas")

	if GameState.rest_charges_left == GameState.MAX_REST_CHARGES:
		await AchievementsScript.unlock(self, "sin_descanso")

	if GameState.run_flawless:
		await AchievementsScript.unlock(self, "nadie_se_queda_atras")

	if _all_35_combos_completed():
		await AchievementsScript.unlock(self, "todas_las_caras_del_destino")

## Same C(7,4)=35 combination key convention as CharacterSelection._generate_all_combos() and
## SaveManager.record_profile_completion() (sorted ids joined by ","), reimplemented here since
## CharacterSelection isn't in the scene tree during exploration.
func _all_35_combos_completed() -> bool:
	var ids: Array = []
	for c in DataLoader.get_all_characters():
		ids.append(str(c.get("id", "")))
	ids.sort()
	var completed: Array = SaveManager.get_profile().get("completed_party_combos", [])
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			for c_idx in range(b + 1, ids.size()):
				for d in range(c_idx + 1, ids.size()):
					var key = ",".join([ids[a], ids[b], ids[c_idx], ids[d]])
					if not completed.has(key):
						return false
	return true

func _show_victory_screen() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 90

	# Dark overlay
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bg)

	# Center container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.offset_left = -300
	vbox.offset_right = 300
	vbox.offset_top = -200
	vbox.offset_bottom = 200
	canvas.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "VICTORIA!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 144)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	vbox.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Has escapado de White Plume Mountain"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 60)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(subtitle)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Stats
	var stats = Label.new()
	stats.text = "XP Total: %d\nOro: %d\nGrupo: %s" % [
		GameState.total_xp,
		GameState.gold,
		", ".join(GameState.party.map(func(m): return "%s (HP %d/%d)" % [m["name"], m["hp"], m["max_hp"]]))
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 48)
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(stats)

	# Spacer 2
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)

	# Easter egg: a phrase unique to this exact party combination, so finishing the game with a
	# different four earns a different one to report back to your DM.
	var blessing: String = EasterEggsData.party_blessing(GameState.party)
	if blessing != "":
		var egg = Label.new()
		egg.text = "Dile a tu DM que %s" % blessing
		egg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		egg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		egg.add_theme_font_size_override("font_size", 40)
		egg.add_theme_color_override("font_color", Color(0.65, 0.55, 0.85))
		vbox.add_child(egg)

		var spacer3 = Control.new()
		spacer3.custom_minimum_size = Vector2(0, 30)
		vbox.add_child(spacer3)

	# Prompt
	var prompt = Label.new()
	prompt.text = "Presiona Z para volver al inicio"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 42)
	prompt.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(prompt)

	add_child(canvas)

	# Wait for action1 to restart
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if _exit_triggered and event.is_action_pressed("action1"):
		get_viewport().set_input_as_handled()
		# Straight to the credits scene rather than back through Boot.tscn. Boot only exists as
		# the engine's own startup stub — it works there because nothing else is transitioning yet
		# — but reached via change_scene() its own redirect fired while THIS transition was still
		# fading in, and the old reentrancy guard silently dropped it, leaving the run stuck on a
		# blank scene forever with no way out but killing the game.
		# GameState.reset() does NOT happen here anymore — CreditsScreen needs GameState.party
		# intact to know who to draw walking, and does the reset itself once it's dismissed.
		SceneFlow.change_scene("res://scenes/boot/CreditsScreen.tscn")

# --- Fog shader helpers ---

func _init_fog_shaders() -> void:
	_fog_shader_color = Shader.new()
	_fog_shader_color.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec3 player_world_pos;
global uniform float fog_start;
global uniform float fog_end;

uniform vec4 base_color : source_color = vec4(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist_xz = length(world_pos.xz - player_world_pos.xz);
	float fog = smoothstep(fog_start, fog_end, dist_xz);
	ALBEDO = mix(base_color.rgb, vec3(0.0), fog);
}
"""
	_fog_shader_textured = Shader.new()
	_fog_shader_textured.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec3 player_world_pos;
global uniform float fog_start;
global uniform float fog_end;

uniform sampler2D base_texture : source_color, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(base_texture, UV);
	float dist_xz = length(world_pos.xz - player_world_pos.xz);
	float fog = smoothstep(fog_start, fog_end, dist_xz);
	ALBEDO = mix(tex.rgb, vec3(0.0), fog);
}
"""
	# Transparent variant — same as textured but writes ALPHA for occlusion fade
	_fog_shader_textured_alpha = Shader.new()
	_fog_shader_textured_alpha.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

global uniform vec3 player_world_pos;
global uniform float fog_start;
global uniform float fog_end;

uniform sampler2D base_texture : source_color, filter_nearest;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(base_texture, UV);
	float dist_xz = length(world_pos.xz - player_world_pos.xz);
	float fog = smoothstep(fog_start, fog_end, dist_xz);
	ALBEDO = mix(tex.rgb, vec3(0.0), fog);
	ALPHA = alpha;
}
"""

func _make_fog_color_material(color: Color) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = _fog_shader_color
	mat.set_shader_parameter("base_color", color)
	return mat

func _make_fog_textured_material(texture: Texture2D) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = _fog_shader_textured
	mat.set_shader_parameter("base_texture", texture)
	return mat

# --- Texture helpers ---

static func _create_rect_texture(fill: Color, border: Color, w: int, h: int) -> ImageTexture:
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for x in range(w):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h - 1, border)
	for y in range(h):
		img.set_pixel(0, y, border)
		img.set_pixel(w - 1, y, border)
	return ImageTexture.create_from_image(img)

## Returns true if the tile at (row, col) is walkable/open (not a wall, not out of bounds).
func _is_open_tile(row: int, col: int) -> bool:
	if row < 0 or row >= dungeon_map.size():
		return false
	if col < 0 or col >= dungeon_map[row].size():
		return false
	var tile = dungeon_map[row][col]
	return tile != Tile.EMPTY and tile != Tile.WALL

func get_player_start_position() -> Vector3:
	var start = _entities.get("player_start", {})
	var row = float(start.get("row", 17))
	var col = float(start.get("col", 4))
	return Vector3(col * TILE_SIZE, 0, row * TILE_SIZE)

func get_wall_nodes() -> Array[Node3D]:
	return _wall_nodes

## Debug Panel's "Mostrar triggers en el mapa" — a floating Label3D above every tracked entity.
## Rebuilds from scratch each call: cheap, and avoids having to reconcile with entities that may
## have been freed (e.g. a picked-up chest) since the last toggle.
func set_debug_labels_visible(show: bool) -> void:
	for lbl in _debug_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_debug_labels.clear()
	if not show:
		return
	for entry in _debug_entities:
		var node = entry.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var label = Label3D.new()
		label.text = _debug_label_text(str(entry.get("kind", "")), entry.get("config", {}))
		label.font_size = 48
		label.outline_size = 8
		label.modulate = Color(1.0, 0.9, 0.3)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = node.global_position + Vector3(0, 2.2, 0)
		add_child(label)
		_debug_labels.append(label)

func _debug_label_text(kind: String, config: Dictionary) -> String:
	match kind:
		"door":
			var required := str(config.get("required_item_id", ""))
			if bool(config.get("locked", false)) and required != "":
				var item = DataLoader.get_item(required)
				return "Puerta (requiere: %s)" % str(item.get("name", required))
			return "Puerta"
		"npc":
			return "NPC"
		"rest_zone":
			return "Zona de Descanso"
		"chest":
			var item = DataLoader.get_item(str(config.get("item_id", "")))
			return "Cofre: %s x%d" % [str(item.get("name", config.get("item_id", "?"))), int(config.get("quantity", 1))]
		"floor_item":
			var item = DataLoader.get_item(str(config.get("item_id", "")))
			return "Item: %s x%d" % [str(item.get("name", config.get("item_id", "?"))), int(config.get("quantity", 1))]
		"combat_trigger":
			return "Combate: %s" % str(config.get("encounter_id", "?"))
		"boss_trigger":
			return "Jefe: %s" % str(config.get("encounter_id", "?"))
		"riddle_gate":
			return "Enigma (esfinge)"
		"random_encounter_zone":
			var ids: Array = config.get("encounter_ids", [])
			return "Zona aleatoria: %s" % ", ".join(ids)
		"exit":
			return "Salida"
		"story_trigger":
			return "Evento: %s" % str(config.get("event_id", "?"))
	return kind
