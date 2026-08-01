extends Node
## GameState — Autoload singleton
## Manages party, inventory, dungeon flags, minimap state, combat return info.

var party: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var gold: int = 0
var total_xp: int = 0
var flags: Dictionary = {}
var revealed_cells: Dictionary = {}
var return_scene_path: String = ""
var return_position: Vector3 = Vector3.ZERO
var current_encounter_id: String = ""
var current_intro_message: String = ""
var current_death_message: String = ""

## Global pool shared across every rest zone on the map — not per-zone. Once it hits 0, no
## rest zone anywhere restores HP/MP for the rest of this save.
const MAX_REST_CHARGES: int = 3
var rest_charges_left: int = MAX_REST_CHARGES

const LEVEL: int = 1

# --- Level progression ---
## Party-wide level (every member levels together — total_xp is a shared pool, not tracked per
## character). Index i -> total_xp required to reach level i+1. Level 5 (the cap) sits at ~45%
## of the ~1319 XP available across every fixed encounter in the game, leaving random-encounter
## XP as margin, so it's reachable without requiring every fight in the dungeon.
const XP_LEVEL_THRESHOLDS: Array[int] = [0, 80, 200, 380, 600]
const MAX_LEVEL: int = 5

## Queue of level-ups still awaiting a feat choice from the player, filled by check_level_ups()
## and drained one entry at a time by LevelUpPanel via apply_level_up_choice().
var pending_level_ups: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_inventory()

func _get_modifier(attribute_value: int) -> int:
	if attribute_value >= 18:
		return +4
	elif attribute_value >= 16:
		return +3
	elif attribute_value >= 14:
		return +2
	elif attribute_value >= 12:
		return +1
	elif attribute_value >= 10:
		return 0
	elif attribute_value >= 8:
		return -1
	else:
		return -2

func _calculate_stats(char_data: Dictionary) -> Dictionary:
	var attrs = char_data.get("attributes", {})
	var hit_die = char_data.get("hit_die", 8)
	var clase = char_data.get("class", "")
	
	var str_mod = _get_modifier(attrs.get("fuerza", 10))
	var dex_mod = _get_modifier(attrs.get("agilidad", 10))
	var con_mod = _get_modifier(attrs.get("constitucion", 10))
	var wis_mod = _get_modifier(attrs.get("sabiduria", 10))
	var int_mod = _get_modifier(attrs.get("inteligencia", 10))
	var cha_mod = _get_modifier(attrs.get("carisma", 10))
	
	var con_bonus = con_mod * LEVEL
	var max_hp = hit_die + con_bonus
	if max_hp < 1:
		max_hp = 1

	var max_mp = 10 + maxi(maxi(int_mod, wis_mod), cha_mod) * 2
	if max_mp < 10:
		max_mp = 10

	var ca = 10 + dex_mod
	
	if clase == "Barbaro":
		ca += 2
	elif clase == "Clerigo":
		ca += 2
	elif clase == "Gunslinger":
		ca += 2
	
	return {
		"class": clase,
		"race": char_data.get("race", ""),
		"hit_die": hit_die,
		"attributes": attrs,
		"str_mod": str_mod,
		"dex_mod": dex_mod,
		"con_mod": con_mod,
		"wis_mod": wis_mod,
		"int_mod": int_mod,
		"cha_mod": cha_mod,
		"hp": max_hp,
		"max_hp": max_hp,
		"mp": max_mp,
		"max_mp": max_mp,
		"ca": ca,
		"atk": 0,
		"def": 0,
		"mag": 0,
		"mdef": 0,
		"spd": 10 + dex_mod,
	}

func create_party_member(char_data: Dictionary) -> Dictionary:
	var stats = _calculate_stats(char_data)
	return {
		"id": char_data["id"],
		"name": char_data["name"],
		"class": stats["class"],
		"race": stats["race"],
		"level": LEVEL,
		"hit_die": stats["hit_die"],
		"attributes": stats["attributes"],
		"str_mod": stats["str_mod"],
		"dex_mod": stats["dex_mod"],
		"con_mod": stats["con_mod"],
		"wis_mod": stats["wis_mod"],
		"int_mod": stats["int_mod"],
		"cha_mod": stats["cha_mod"],
		"hp": stats["hp"],
		"max_hp": stats["max_hp"],
		"mp": stats["mp"],
		"max_mp": stats["max_mp"],
		"ca": stats["ca"],
		"atk": stats["atk"],
		"def": stats["def"],
		"mag": stats["mag"],
		"mdef": stats["mdef"],
		"spd": stats["spd"],
		"skills": char_data.get("skills", []).duplicate(),
		"feats": [],
		"sprite_path": char_data.get("sprite_path", CharacterSprites.DEFAULT_SHEET_PATH),
	}

# --- Flag helpers ---
func set_flag(flag_name: String, value: bool = true) -> void:
	flags[flag_name] = value

func get_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)

# --- Inventory helpers ---
func add_item(item_id: String, qty: int = 1) -> void:
	for item in inventory:
		if item["id"] == item_id:
			item["quantity"] += qty
			return
	var item_data = DataLoader.get_item(item_id)
	if item_data:
		inventory.append({ "id": item_id, "name": item_data["name"], "quantity": qty })

func remove_item(item_id: String, qty: int = 1) -> bool:
	for i in range(inventory.size()):
		if inventory[i]["id"] == item_id:
			inventory[i]["quantity"] -= qty
			if inventory[i]["quantity"] <= 0:
				inventory.remove_at(i)
			return true
	return false

func has_item(item_id: String) -> bool:
	for item in inventory:
		if item["id"] == item_id and item["quantity"] > 0:
			return true
	return false

func get_item_quantity(item_id: String) -> int:
	for item in inventory:
		if item["id"] == item_id:
			return item["quantity"]
	return 0

# --- Minimap helpers ---
func reveal_cell(x: int, y: int) -> void:
	var key = "%d,%d" % [x, y]
	revealed_cells[key] = true

func is_cell_revealed(x: int, y: int) -> bool:
	var key = "%d,%d" % [x, y]
	return revealed_cells.has(key)

# --- Party helpers ---
func get_party_member(member_id: String) -> Dictionary:
	for m in party:
		if m["id"] == member_id:
			return m
	return {}

func heal_party_member(member_id: String, amount: int) -> void:
	var m = get_party_member(member_id)
	if m.size() > 0:
		m["hp"] = mini(m["hp"] + amount, m["max_hp"])

func damage_party_member(member_id: String, amount: int) -> void:
	var m = get_party_member(member_id)
	if m.size() > 0:
		m["hp"] = maxi(m["hp"] - amount, 0)

func is_party_alive() -> bool:
	for m in party:
		if m["hp"] > 0:
			return true
	return false

func add_xp(amount: int) -> void:
	total_xp += amount

func add_gold(amount: int) -> void:
	gold += amount

func _level_for_xp(xp: int) -> int:
	var lvl = 1
	for i in range(1, XP_LEVEL_THRESHOLDS.size()):
		if xp >= XP_LEVEL_THRESHOLDS[i]:
			lvl = i + 1
	return lvl

## Called after add_xp(). Bumps every party member's level to match total_xp (they always level
## together — see XP_LEVEL_THRESHOLDS) and queues one pending_level_ups entry per member per
## level gained, for LevelUpPanel to resolve one feat choice at a time. Can cross several levels
## in a single call if a big XP reward jumps past more than one threshold at once — the actual
## feat *options* for each queued step are deliberately NOT computed here (see
## get_level_up_options): a multi-level jump queues several steps for the same member before any
## of them are resolved, so precomputing options against member["feats"] here would show the same
## stale, not-yet-narrowed pool at every one of those steps instead of a properly shrinking list.
func check_level_ups() -> void:
	if party.is_empty():
		return
	var target_level = _level_for_xp(total_xp)
	var current_level = int(party[0].get("level", 1))
	if target_level <= current_level:
		return
	for lvl in range(current_level + 1, target_level + 1):
		for member in party:
			member["level"] = lvl
			pending_level_ups.append({
				"member_id": member["id"],
				"member_name": member["name"],
				"level": lvl,
			})

## Computes, at display time, which feats a pending_level_ups step should offer — always against
## the member's CURRENT feats, so a step queued behind an already-resolved one in the same batch
## correctly excludes whatever was just picked. Empty if the member already owns everything
## available at this level (LevelUpPanel skips straight past such a step).
func get_level_up_options(member_id: String, level: int) -> Array[String]:
	var member = get_party_member(member_id)
	if member.is_empty():
		return []
	var char_data = DataLoader.get_character(member.get("id", ""))
	var owned: Array = member.get("feats", [])
	var options: Array[String] = []
	if level >= MAX_LEVEL:
		var final_feat = str(char_data.get("final_feat", ""))
		if final_feat != "" and not owned.has(final_feat):
			options = [final_feat]
	else:
		for feat_id in char_data.get("feat_pool", []):
			if not owned.has(feat_id):
				options.append(feat_id)
	return options

## Called by LevelUpPanel when the player confirms one pending_level_ups step.
func apply_level_up_choice(member_id: String, feat_id: String) -> void:
	var member = get_party_member(member_id)
	if member.is_empty() or feat_id == "":
		return
	if not member.get("feats", []).has(feat_id):
		member["feats"].append(feat_id)
		Combatant.apply_feat_effects(member, feat_id)

# --- Combat state ---
func prepare_combat(encounter_id: String, scene_path: String, position: Vector3, intro_message: String = "", death_message: String = "") -> void:
	current_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position
	# Reset every time so a message from a previous fixed encounter never leaks into the next.
	current_intro_message = intro_message
	current_death_message = death_message

func restore_party_from_combat(party_state: Array) -> void:
	for ps in party_state:
		var m = get_party_member(ps["id"])
		if m.size() > 0:
			m["hp"] = ps["hp"]

# --- Full reset (used on defeat to restart cleanly) ---
func reset() -> void:
	party.clear()
	inventory.clear()
	pending_level_ups.clear()
	gold = 0
	total_xp = 0
	flags.clear()
	revealed_cells.clear()
	return_scene_path = ""
	return_position = Vector3.ZERO
	current_encounter_id = ""
	current_intro_message = ""
	current_death_message = ""
	rest_charges_left = MAX_REST_CHARGES
	_init_inventory()

func _init_inventory() -> void:
	inventory.clear()
	var items = DataLoader.get_all_items()
	for item in items:
		# Quest items (e.g. the legendary weapons) must be found in the dungeon, not
		# handed to the player for free at the start — skip them here.
		if item.get("effect", "") == "quest_item":
			continue
		inventory.append({
			"id": item["id"],
			"name": item["name"],
			"quantity": 3
		})
