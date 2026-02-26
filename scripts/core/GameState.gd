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

const LEVEL: int = 1

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
		"ca": stats["ca"],
		"atk": stats["atk"],
		"def": stats["def"],
		"mag": stats["mag"],
		"mdef": stats["mdef"],
		"spd": stats["spd"],
		"skills": char_data.get("skills", []).duplicate(),
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

# --- Combat state ---
func prepare_combat(encounter_id: String, scene_path: String, position: Vector3) -> void:
	current_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position

func restore_party_from_combat(party_state: Array) -> void:
	for ps in party_state:
		var m = get_party_member(ps["id"])
		if m.size() > 0:
			m["hp"] = ps["hp"]

# --- Full reset (used on defeat to restart cleanly) ---
func reset() -> void:
	party.clear()
	inventory.clear()
	gold = 0
	total_xp = 0
	flags.clear()
	revealed_cells.clear()
	return_scene_path = ""
	return_position = Vector3.ZERO
	current_encounter_id = ""
	_init_inventory()

func _init_inventory() -> void:
	inventory.clear()
	var items = DataLoader.get_all_items()
	for item in items:
		inventory.append({
			"id": item["id"],
			"name": item["name"],
			"quantity": 3
		})
