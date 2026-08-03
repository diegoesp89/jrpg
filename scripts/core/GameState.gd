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

## Hit die by class, following the D&D 5e SRD (open content) table: d12 for the Barbarian,
## d10 for martial classes (the Gunslinger being a Fighter archetype), d8 for the standard
## d8 classes, d6 for full arcane casters. This is the source of truth — characters.json's
## own "hit_die" is only the fallback for a class not listed here.
const CLASS_HIT_DICE := {
	"Barbaro": 12,
	"Gunslinger": 10,
	"Monje": 8,
	"Clerigo": 8,
	"Warlock": 8,
	"Hechicera": 6,
}

func hit_die_for_class(clase: String, fallback: int = 8) -> int:
	return int(CLASS_HIT_DICE.get(clase, fallback))

## Flat buffer on top of the SRD formula. Without it a level-1 caster sits at 6 HP and dies to a
## single average hit (1d6+2 averages 5.5), which in a game where defeat restarts the whole run
## is a coin flip rather than a difficulty curve. Measured, not guessed — see the balance sweep.
const HEROIC_HP_BONUS := 4

## How far into the dungeon the party is, measured by legendary weapons recovered (0-3). The
## exit needs all three, so this is the one progress axis that is both meaningful and impossible
## to grind — it only moves when the player actually advances the quest.
func progression_tier() -> int:
	var n := 0
	for item in DataLoader.get_all_items():
		if str(item.get("effect", "")) == "quest_item" and has_item(str(item["id"])):
			n += 1
	return n

## Multiplier applied to a scaling enemy's HP, damage and XP. Deliberately far below the party's
## own growth (their HP roughly quadruples from level 1 to 5), so progress still feels earned —
## this keeps ordinary encounters relevant, it does not chase the player.
const ENEMY_SCALE_PER_TIER := 0.40

## Damage scales more gently than HP. The party's own growth is mostly hit points and feats, not
## raw damage, so scaling enemy damage at the full rate outpaces them: measured at the full rate,
## multi-enemy ranged encounters (manticores, flesh golems) went from winnable to unwinnable at
## level 5. Tuning HP and damage separately keeps fights long without making them lethal.
const ENEMY_DAMAGE_SCALE_RATIO := 0.5

## Named enemies are hand-tuned for the moment you meet them, but leaving them completely flat
## meant several bosses sat at a 100% win rate once the party had the legendary weapons. They now
## ride the same curve at half slope: still authored, no longer irrelevant.
const NAMED_SCALE_RATIO := 0.5

## Ordinary encounters also grow in NUMBER, not just in stats — measured across ~15k simulated
## battles, stat scaling alone could not bring a fully-equipped level 5 party below a 97% win
## rate, because four heroes roll over two enemies no matter how fat they are. Action economy is
## the only lever that moves it. Boss rosters are exempt: they are authored fights, and doubling
## them re-creates exactly the encounters that were tuned down for being unwinnable.
const ENEMY_COUNT_AT_MAX_TIER := 2.0
## Only a sanity bound on the roster, not a balance knob: encounters that must not grow opt out
## individually with "scales_count": false, which is the lever that was actually measured.
const ENEMY_COUNT_CAP := 8

func enemy_count_multiplier() -> float:
	return 1.0 + (ENEMY_COUNT_AT_MAX_TIER - 1.0) * (float(progression_tier()) / 3.0)

func enemy_scale_factor() -> float:
	return 1.0 + ENEMY_SCALE_PER_TIER * float(progression_tier())

## Same curve, flattened for damage only.
func enemy_damage_scale_factor() -> float:
	return 1.0 + ENEMY_SCALE_PER_TIER * ENEMY_DAMAGE_SCALE_RATIO * float(progression_tier())

## Total current HP over total max HP across the whole party, fallen members included (their 0
## drags it down, which is the point). 1.0 when everyone is fresh, 0.0 on a wipe.
func party_health_fraction() -> float:
	var cur := 0.0
	var maximum := 0.0
	for m in party:
		cur += float(m.get("hp", 0))
		maximum += float(m.get("max_hp", 1))
	if maximum <= 0.0:
		return 1.0
	return clampf(cur / maximum, 0.0, 1.0)

## Max HP at a given level, by the SRD's fixed-progression rule: the full hit die at level 1,
## then the die's average roll (half of it, rounded down, plus 1) for every level after, plus
## the Constitution modifier once per level. Always recomputed from these three inputs rather
## than accumulated, so a level-up can't drift out of sync with what a fresh character of the
## same level would have.
func max_hp_for(hit_die: int, con_mod: int, level: int) -> int:
	var per_level_gain = int(hit_die / 2.0) + 1
	var hp = hit_die + (level - 1) * per_level_gain + con_mod * level + HEROIC_HP_BONUS
	return maxi(1, hp)

## Same, for a live party member — including any percentage HP feats they've picked up, which
## scale with the level-appropriate total instead of being frozen at whatever it was when the
## feat was taken.
func max_hp_with_feats(member: Dictionary) -> int:
	var base = max_hp_for(
		hit_die_for_class(str(member.get("class", "")), int(member.get("hit_die", 8))),
		int(member.get("con_mod", 0)),
		int(member.get("level", LEVEL)),
	)
	var pct: float = float(Combatant.sum_feat_value(member, "hp_bonus_pct"))
	return maxi(1, int(base * (1.0 + pct / 100.0)))

func _calculate_stats(char_data: Dictionary) -> Dictionary:
	var attrs = char_data.get("attributes", {})
	var clase = char_data.get("class", "")
	var hit_die = hit_die_for_class(clase, int(char_data.get("hit_die", 8)))

	var str_mod = _get_modifier(attrs.get("fuerza", 10))
	var dex_mod = _get_modifier(attrs.get("agilidad", 10))
	var con_mod = _get_modifier(attrs.get("constitucion", 10))
	var wis_mod = _get_modifier(attrs.get("sabiduria", 10))
	var int_mod = _get_modifier(attrs.get("inteligencia", 10))
	var cha_mod = _get_modifier(attrs.get("carisma", 10))
	
	var max_hp = max_hp_for(hit_die, con_mod, LEVEL)

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
		# Legendary weapon this character carries ("" = none). No attunement, no class gate:
		# any of the three fits any hand, so who carries what is purely the player's call.
		"weapon": "",
		# Zone this character deploys into at the start of every battle, set by the player from
		# the pause menu ("Formación"). Persisted with the rest of the member dict by SaveManager.
		"start_position": 0,
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

	# Levelling up raises the HP ceiling and restores everyone completely, HP and MP alike —
	# done once after the loop, so a multi-level jump still ends at the final level's maximums.
	for member in party:
		member["max_hp"] = max_hp_with_feats(member)
		member["hp"] = member["max_hp"]
		member["mp"] = member.get("max_mp", 0)

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
