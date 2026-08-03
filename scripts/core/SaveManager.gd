extends Node
## SaveManager — Autoload singleton
## Handles the single continuous save slot (user://save.json, player data — never res://,
## which is dev-only project data and read-only in an exported build) and the persistent
## cross-playthrough profile (user://profile.json: winning party combinations + stats).

const SAVE_PATH := "user://save.json"
const PROFILE_PATH := "user://profile.json"

# --- Save slot ---

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(map_path: String, player_position: Vector3) -> void:
	var data = {
		"map_path": map_path,
		"player_position": {"x": player_position.x, "y": player_position.y, "z": player_position.z},
		"party": GameState.party,
		"inventory": GameState.inventory,
		"gold": GameState.gold,
		"total_xp": GameState.total_xp,
		"flags": GameState.flags,
		"revealed_cells": GameState.revealed_cells,
		"rest_charges_left": GameState.rest_charges_left,
	}
	_write_json_file(SAVE_PATH, data)

## Restores GameState from the save file and returns {"map_path":, "player_position":} for the
## caller to act on (load the map, position the player, change scene) — or {} if there's no save.
func load_game() -> Dictionary:
	var data = _read_json_file(SAVE_PATH)
	if data.is_empty():
		return {}

	GameState.party.clear()
	for m in data.get("party", []):
		GameState.party.append(m)
	GameState.inventory.clear()
	for i in data.get("inventory", []):
		GameState.inventory.append(i)
	GameState.gold = int(data.get("gold", 0))
	GameState.total_xp = int(data.get("total_xp", 0))
	GameState.flags = data.get("flags", {})
	GameState.revealed_cells = data.get("revealed_cells", {})
	GameState.rest_charges_left = int(data.get("rest_charges_left", GameState.MAX_REST_CHARGES))

	var pos = data.get("player_position", {})
	return {
		"map_path": str(data.get("map_path", "")),
		"player_position": Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0)),
	}

## "Resetear progreso" — clears the save slot and resets in-memory GameState. Does NOT touch
## the profile (completed party combos are an accumulated achievement, not part of the run).
## Wipes everything: the save AND the cross-run profile. The profile used to survive this, which
## meant "Resetear progreso" left the won-combination stars lit on the character-selection screen
## — progress the player had explicitly asked to erase. If the achievement log should ever be
## preserved again, split this into two options rather than making the reset lie about its name.
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	GameState.reset()

# --- Profile (persists across saves/resets) ---

func get_profile() -> Dictionary:
	var data = _read_json_file(PROFILE_PATH)
	if data.is_empty():
		return {
			"completed_party_combos": [],
			"total_completions": 0,
			"character_usage_counts": {},
			"total_gold_earned": 0,
			"total_xp_earned": 0,
		}
	return data

## Called when the party actually wins (reaches the exit with every required item). Records
## the party's character-id combination (sorted, same order-independent convention already
## used by DataLoader.get_waypoint_scene) and rolls up the profile-wide stats.
func record_profile_completion() -> void:
	var profile = get_profile()

	var combo: Array = []
	for m in GameState.party:
		combo.append(str(m.get("id", "")))
	combo.sort()
	var combo_key = ",".join(combo)

	var combos: Array = profile.get("completed_party_combos", [])
	if not combos.has(combo_key):
		combos.append(combo_key)
	profile["completed_party_combos"] = combos

	profile["total_completions"] = int(profile.get("total_completions", 0)) + 1

	var usage: Dictionary = profile.get("character_usage_counts", {})
	for char_id in combo:
		usage[char_id] = int(usage.get(char_id, 0)) + 1
	profile["character_usage_counts"] = usage

	profile["total_gold_earned"] = int(profile.get("total_gold_earned", 0)) + GameState.gold
	profile["total_xp_earned"] = int(profile.get("total_xp_earned", 0)) + GameState.total_xp

	_write_json_file(PROFILE_PATH, profile)

# --- JSON helpers (same FileAccess + JSON.stringify pattern as DataLoader, but user:// data) ---

func _write_json_file(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open file for writing: %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("SaveManager: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	var data = json.data
	return data if data is Dictionary else {}
