extends Node
## DataLoader — Autoload singleton
## Loads all game data from JSON files at startup.

var _characters: Dictionary = {}
var _enemies: Dictionary = {}
var _skills: Dictionary = {}
var _items: Dictionary = {}
var _encounters: Dictionary = {}
var _dialogues: Dictionary = {}

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
