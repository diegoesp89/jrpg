extends Node3D
## DungeonBuilder — Generates the dungeon layout procedurally from a tile map definition.
## This approach is more robust than hand-crafting .tscn nodes for walls/floor.

const TILE_SIZE: float = 2.0

# Tile types
enum Tile { EMPTY = 0, FLOOR = 1, WALL = 2, DOOR = 3, NPC = 4, CHEST = 5, COMBAT_TRIGGER = 6, TRAP = 7, BOSS_TRIGGER = 8, EXIT = 9 }

# Colors for placeholder sprites
const WALL_COLOR = Color(0.4, 0.4, 0.45)
const WALL_BORDER = Color(0.25, 0.25, 0.3)
const NPC_COLOR = Color(0.2, 0.7, 0.3)
const NPC_BORDER = Color(0.1, 0.5, 0.15)
const CHEST_COLOR = Color(0.85, 0.7, 0.1)
const CHEST_BORDER = Color(0.6, 0.5, 0.05)
const DOOR_COLOR = Color(0.55, 0.35, 0.15)
const DOOR_BORDER = Color(0.35, 0.2, 0.05)
const FLOOR_COLOR = Color(0.25, 0.22, 0.2)
const FLOOR_ALT_COLOR = Color(0.28, 0.25, 0.22)

# Dungeon map: 25 columns x 20 rows
# Layout:
#   Sala 1 (Entrada + NPC) top-left
#   Pasillo Norte (vertical going down)
#   CombatTrigger #1 in hallway
#   Sala 2 (Bifurcación) center
#   Sala 3 (left branch: Door + Chest)
#   Sala 4 (right branch: Trap + CombatTrigger #2)
#   Sala 5 (Boss room) bottom center
var dungeon_map: Array = [
	#  0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 24
	[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 0
	[2, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 1 - Sala 1
	[2, 1, 4, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 2 - NPC
	[2, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 3
	[2, 2, 2, 1, 1, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 4
	[0, 0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 5 - Pasillo
	[0, 0, 2, 6, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 6 - Combat #1
	[0, 0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 7
	[2, 2, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 8 - Sala 2 top
	[2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 9
	[2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 10 - Sala 2
	[2, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 11
	[2, 1, 1, 2, 0, 0, 0, 0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 12 - Branches
	[2, 1, 5, 2, 0, 0, 0, 0, 2, 7, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 13 - Sala3: Chest | Sala4: Trap
	[2, 3, 1, 2, 0, 0, 0, 0, 2, 6, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 14 - Door | Combat #2
	[2, 1, 1, 2, 0, 0, 0, 0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 15
	[2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 16 - Reconnect
	[0, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 17 - Sala 5 top
	[0, 0, 2, 1, 1, 8, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 18 - Boss
	[0, 0, 2, 2, 2, 9, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], # row 19 - Exit
]

var _wall_nodes: Array[Node3D] = []
var _floor_mesh: MeshInstance3D = null
var _wall_texture: ImageTexture = null

# Shared shader instances (created once, reused)
var _fog_shader_color: Shader = null
var _fog_shader_textured: Shader = null
var _fog_shader_textured_alpha: Shader = null  # transparent variant for occlusion fade

func _ready() -> void:
	_init_fog_shaders()
	_register_fog_globals()
	_build_dungeon()

func _register_fog_globals() -> void:
	# Ensure global shader params exist before any shader uses them.
	# DungeonManager will update player_world_pos and fog values every frame.
	if not RenderingServer.global_shader_parameter_get_list().has("player_world_pos"):
		RenderingServer.global_shader_parameter_add("player_world_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	if not RenderingServer.global_shader_parameter_get_list().has("fog_start"):
		RenderingServer.global_shader_parameter_add("fog_start", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 6.0)
	if not RenderingServer.global_shader_parameter_get_list().has("fog_end"):
		RenderingServer.global_shader_parameter_add("fog_end", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 10.0)

func _build_dungeon() -> void:
	_wall_texture = _create_rect_texture(WALL_COLOR, WALL_BORDER, 32, 48)
	_build_floor()
	_build_walls_and_entities()

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
	var color: Color
	if (col + row) % 2 == 0:
		color = FLOOR_COLOR
	else:
		color = FLOOR_ALT_COLOR
	mesh_instance.material_override = _make_fog_color_material(color)

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
					_create_door(pos)
				Tile.NPC:
					_create_npc(pos)
				Tile.CHEST:
					_create_chest(pos)
				Tile.COMBAT_TRIGGER:
					_create_combat_trigger(pos, col, row)
				Tile.TRAP:
					_create_trap(pos)
				Tile.BOSS_TRIGGER:
					_create_boss_trigger(pos)
				Tile.EXIT:
					_create_exit(pos)

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

	# If no exposed faces (surrounded by walls), add a top cap so it's visible from above
	if face_idx == 0:
		var cap = MeshInstance3D.new()
		cap.name = "WallCap"
		var plane = PlaneMesh.new()
		plane.size = Vector2(TILE_SIZE - 0.05, TILE_SIZE - 0.05)
		cap.mesh = plane
		cap.material_override = _make_fog_color_material(WALL_COLOR * 0.8)
		cap.position = Vector3(0, 3.0, 0)
		wall.add_child(cap)

	# Add Occludable as child node
	var occludable_script = load("res://scripts/exploration/Occludable.gd")
	if occludable_script:
		var occludable = Node.new()
		occludable.name = "Occludable"
		occludable.set_script(occludable_script)
		wall.add_child(occludable)

	add_child(wall)
	_wall_nodes.append(wall)

func _create_door(pos: Vector3) -> void:
	var door_scene_script = load("res://scripts/exploration/Door.gd")
	var door = StaticBody3D.new()
	door.name = "Door"
	door.position = pos
	door.collision_layer = 1 | 4  # world + interactable
	door.collision_mask = 0

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, 3.0, 0.4)
	col_shape.shape = box
	col_shape.position = Vector3(0, 1.5, 0)
	door.add_child(col_shape)

	var sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.pixel_size = 0.03
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _create_rect_texture(DOOR_COLOR, DOOR_BORDER, 32, 48)
	sprite.position = Vector3(0, 1.2, 0)
	door.add_child(sprite)

	if door_scene_script:
		door.set_script(door_scene_script)

	add_child(door)

func _create_npc(pos: Vector3) -> void:
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
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _create_rect_texture(NPC_COLOR, NPC_BORDER, 32, 32)
	sprite.position = Vector3(0, 0.8, 0)
	npc.add_child(sprite)

	if npc_script:
		npc.set_script(npc_script)

	add_child(npc)

func _create_chest(pos: Vector3) -> void:
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
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture = _create_rect_texture(CHEST_COLOR, CHEST_BORDER, 32, 24)
	sprite.position = Vector3(0, 0.5, 0)
	chest.add_child(sprite)

	if pickup_script:
		chest.set_script(pickup_script)

	add_child(chest)

func _create_combat_trigger(pos: Vector3, col: int, row: int) -> void:
	var trigger_script = load("res://scripts/exploration/CombatTrigger.gd")
	var trigger = Area3D.new()
	# Determine encounter based on position
	if row == 6:
		trigger.name = "CombatTrigger_hallway"
	elif row == 14:
		trigger.name = "CombatTrigger_golem"
	else:
		trigger.name = "CombatTrigger_%d_%d" % [col, row]
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

	add_child(trigger)

func _create_trap(pos: Vector3) -> void:
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

	# Visual indicator (red-ish floor)
	var mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(TILE_SIZE - 0.1, TILE_SIZE - 0.1)
	mesh.mesh = plane
	mesh.material_override = _make_fog_color_material(Color(0.5, 0.15, 0.1))
	mesh.position = Vector3(0, 0.01, 0)
	trap.add_child(mesh)

	# Use proper script file for trap logic
	var trap_script = load("res://scripts/exploration/Trap.gd")
	if trap_script:
		trap.set_script(trap_script)

	add_child(trap)

func _create_boss_trigger(pos: Vector3) -> void:
	var trigger_script = load("res://scripts/exploration/CombatTrigger.gd")
	var trigger = Area3D.new()
	trigger.name = "CombatTrigger_boss"
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

	add_child(trigger)

func _create_exit(pos: Vector3) -> void:
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

var _exit_triggered: bool = false

func _on_exit_entered(body: Node3D) -> void:
	if _exit_triggered:
		return
	if body is CharacterBody3D:
		_exit_triggered = true
		print("Victory! You have escaped White Plume Mountain!")
		# Disable player movement
		if body.has_method("set_movement_disabled"):
			body.set_movement_disabled(true)
		# Show victory screen
		_show_victory_screen()

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
		SceneFlow.change_scene("res://scenes/boot/Boot.tscn")

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

uniform sampler2D base_texture : source_color;

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

uniform sampler2D base_texture : source_color;
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
	# Center of Sala 1 (row 2, col 4)
	return Vector3(4 * TILE_SIZE, 0, 2 * TILE_SIZE)

func get_wall_nodes() -> Array[Node3D]:
	return _wall_nodes
