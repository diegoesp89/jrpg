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
	_adventure = _load_adventure_scenes("res://data/adventure/")

func _load_adventure_scenes(dir_path: String) -> Array:
	var scenes: Array = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataLoader: adventure scenes folder not found: %s" % dir_path)
		return scenes
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
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
