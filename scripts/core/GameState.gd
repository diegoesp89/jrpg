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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_party()
	_init_inventory()

func _init_party() -> void:
	var chars = DataLoader.get_all_characters()
	for c in chars:
		party.append({
			"id": c["id"],
			"name": c["name"],
			"hp": c["stats"]["hp"],
			"max_hp": c["stats"]["hp"],
			"mp": c["stats"]["mp"],
			"max_mp": c["stats"]["mp"],
			"atk": c["stats"]["atk"],
			"def": c["stats"]["def"],
			"mag": c["stats"]["mag"],
			"mdef": c["stats"]["mdef"],
			"spd": c["stats"]["spd"],
			"skills": c["skills"].duplicate(),
		})

func _init_inventory() -> void:
	inventory.append({ "id": "potion", "name": "Pocion", "quantity": 3 })

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
			m["mp"] = ps["mp"]

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
