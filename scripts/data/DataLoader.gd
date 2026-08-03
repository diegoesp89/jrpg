extends Node
## DataLoader — Autoload singleton
## Loads all game data from JSON files at startup.

var _characters: Dictionary = {}
var _enemies: Dictionary = {}
var _skills: Dictionary = {}
var _items: Dictionary = {}
var _encounters: Dictionary = {}
var _dialogues: Dictionary = {}
var _feats: Dictionary = {}
var _riddles: Array = []
var _adventure: Array = []
var _current_map: Dictionary = {}
var _current_map_path: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all()

func _load_all() -> void:
	_characters = _load_json_dict("res://data/characters/characters.json")
	_enemies = _load_json_dict("res://data/enemies/enemies.json")
	_skills = _load_json_dict("res://data/skills/skills.json")
	_items = _load_json_dict("res://data/items/items.json")
	_encounters = _load_json_dict("res://data/encounters/encounters.json")
	_dialogues = _load_json_dict("res://data/dialogues/dialogues.json")
	_feats = _load_json_dict("res://data/feats.json")
	_riddles = _load_json_array("res://data/riddles.json")
	_adventure = _load_adventure_scenes("res://data/dialogues/")

## data/dialogues/ holds both dialogues.json (a Dictionary of NPC dialogue_id -> lines,
## loaded separately above) and the narrative waypoint scene files (WP1A.json, WP2.json, ...,
## each a JSON Array of party-specific variants). Skip dialogues.json here since it isn't a
## scene array, or it would trip the "expected Array root" parse error on every boot.
func _load_adventure_scenes(dir_path: String) -> Array:
	var scenes: Array = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataLoader: adventure scenes folder not found: %s" % dir_path)
		return scenes
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") and file_name != "dialogues.json":
			scenes.append_array(_load_json_array(dir_path + file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	return scenes

func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: file not found: %s" % path)
		return []
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open file: %s" % path)
		return []
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("DataLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return []
	var data = json.data
	if data is Array:
		return data
	push_error("DataLoader: expected Array root in %s" % path)
	return []

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: file not found: %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open file: %s" % path)
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("DataLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	var data = json.data
	if data is Dictionary:
		return data
	push_error("DataLoader: expected Dictionary root in %s" % path)
	return {}

# --- Public getters ---

func get_character(char_id: String) -> Dictionary:
	return _characters.get(char_id, {})

func get_all_characters() -> Array:
	return _characters.values()

func get_character_by_name(char_name: String) -> Dictionary:
	for c in _characters.values():
		if c.get("name", "") == char_name:
			return c
	return {}

func get_enemy(enemy_id: String) -> Dictionary:
	return _enemies.get(enemy_id, {})

func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {})

func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {})

func get_all_items() -> Array:
	return _items.values()

func get_encounter(encounter_id: String) -> Dictionary:
	return _encounters.get(encounter_id, {})

func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})

func get_feat(feat_id: String) -> Dictionary:
	return _feats.get(feat_id, {})

func get_all_feats() -> Array:
	return _feats.values()

func get_random_riddle() -> Dictionary:
	if _riddles.is_empty():
		return {}
	return _riddles[randi_range(0, _riddles.size() - 1)]

## Finds the narrative waypoint scene matching event_id (id prefix, e.g. "WP02") whose
## party composition matches party_names (order-independent). Returns {} if none found.
func get_waypoint_scene(event_id: String, party_names: Array) -> Dictionary:
	var target: Array = party_names.duplicate()
	target.sort()
	var prefix = event_id + "_"
	for entry in _adventure:
		var eid = str(entry.get("id", ""))
		if not eid.begins_with(prefix):
			continue
		var entry_party: Array = entry.get("party", []).duplicate()
		entry_party.sort()
		if entry_party == target:
			return entry
	return {}

# --- Maps (res://maps/*.map) ---

const MAPS_DIR := "res://maps/"

## Scans res://maps/ and returns [{"name": <map's "name" field>, "path": <res:// path>}, ...].
func list_maps() -> Array:
	var result: Array = []
	var dir = DirAccess.open(MAPS_DIR)
	if dir == null:
		push_warning("DataLoader: maps folder not found: %s" % MAPS_DIR)
		return result
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".map"):
			var path = MAPS_DIR + file_name
			var data = _load_json_dict(path)
			result.append({"name": data.get("name", file_name), "path": path})
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

## Loads and parses a .map file, storing it as the current map. Returns true on success.
func load_map(path: String) -> bool:
	var data = _load_json_dict(path)
	if data.is_empty():
		push_error("DataLoader: could not load map: %s" % path)
		return false
	_sanitize_map_tiles(data)
	_current_map = data
	_current_map_path = path
	return true

## Godot's JSON parser always returns floats for numbers (even whole ones), but
## DungeonBuilder's `match tile:` against the Tile enum needs real ints — `match` doesn't
## coerce float 2.0 to int 2 the way `==`/`!=` do, so every tile silently failed to match
## and only floor tiles (checked with `!=`) were ever built. Normalize right after parsing.
func _sanitize_map_tiles(data: Dictionary) -> void:
	var tiles: Array = data.get("tiles", [])
	for row in tiles:
		for i in range(row.size()):
			row[i] = int(row[i])

func get_current_map() -> Dictionary:
	return _current_map

func get_current_map_path() -> String:
	return _current_map_path

## Sets the current map from in-memory data without touching disk (used by MapEditor's
## Playtest button, which reloads the dungeon scene against unsaved edits).
func set_current_map(data: Dictionary) -> void:
	_current_map = data

func get_all_dialogue_ids() -> Array:
	return _dialogues.keys()

func get_all_item_ids() -> Array:
	return _items.keys()

func get_all_encounter_ids() -> Array:
	return _encounters.keys()

## Unique event ids (e.g. "WP1A", "WP2", "WP12B") derived from the loaded scene files' own
## "<event_id>_<NN>" ids — this is what StoryTrigger/RiddleGate's event_id fields reference,
## so the map editor can offer a real selectable list instead of free-text.
func get_all_event_ids() -> Array:
	var ids := {}
	for entry in _adventure:
		var full_id = str(entry.get("id", ""))
		var idx = full_id.rfind("_")
		if idx > 0:
			ids[full_id.substr(0, idx)] = true
	var result = ids.keys()
	# Plain string sort puts "WP10" before "WP2" (lexicographic, not numeric). Sort by the
	# zero-padded numeric part instead so the list reads WP1A, WP1B, WP2, ..., WP9, WP10, ...
	result.sort_custom(func(a, b): return _event_sort_key(a) < _event_sort_key(b))
	return result

func _event_sort_key(event_id: String) -> String:
	var regex = RegEx.new()
	regex.compile("^WP(\\d+)(.*)$")
	var m = regex.search(event_id)
	if m:
		return "%03d%s" % [int(m.get_string(1)), m.get_string(2)]
	return event_id

## Returns any one variant of the scene matching event_id, regardless of party composition —
## used for previews (e.g. the map editor showing "what does this event contain") where an
## exact party match isn't the point, unlike get_waypoint_scene.
func get_any_waypoint_variant(event_id: String) -> Dictionary:
	var prefix = event_id + "_"
	for entry in _adventure:
		if str(entry.get("id", "")).begins_with(prefix):
			return entry
	return {}

func get_all_enemy_ids() -> Array:
	return _enemies.keys()

const ENEMIES_PATH := "res://data/enemies/enemies.json"
const ITEMS_PATH := "res://data/items/items.json"
const ENCOUNTERS_PATH := "res://data/encounters/encounters.json"

## Updates one enemy's definition in memory and writes the whole enemies.json back to disk
## (used by the map editor's enemy stat/drop editor — this is global game data, not part of
## any one .map, so it saves immediately rather than waiting on the map's own Guardar button).
func update_enemy(enemy_id: String, data: Dictionary) -> void:
	_enemies[enemy_id] = data
	_write_json_file(ENEMIES_PATH, _enemies)

## Removes an enemy definition entirely and writes enemies.json back to disk. Does not touch
## any encounter that still references this enemy_id — the map editor's orphaned-reference
## check surfaces that at save time instead of blocking the delete here.
func delete_enemy(enemy_id: String) -> void:
	_enemies.erase(enemy_id)
	_write_json_file(ENEMIES_PATH, _enemies)

## Adds or overwrites one encounter definition (id -> {enemies, rewards}) and writes
## encounters.json back to disk, same rationale as update_enemy — encounters are global data
## shared across maps, not part of any one .map file.
func update_encounter(encounter_id: String, data: Dictionary) -> void:
	_encounters[encounter_id] = data
	_write_json_file(ENCOUNTERS_PATH, _encounters)

## Adds or overwrites one item definition (e.g. an auto-generated door key) and writes
## items.json back to disk, same rationale as update_enemy.
func add_item_definition(item_id: String, data: Dictionary) -> void:
	_items[item_id] = data
	_write_json_file(ITEMS_PATH, _items)

## Writes map_data as the .map at path (used by the in-game map editor). Only works when
## running from the Godot editor / a local dev environment — res:// is read-only once exported.
func save_map(path: String, map_data: Dictionary) -> bool:
	return _write_json_file(path, map_data)

func _write_json_file(path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DataLoader: could not open file for writing: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true
