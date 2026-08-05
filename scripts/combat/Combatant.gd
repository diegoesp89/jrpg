class_name Combatant
extends Node
## Combatant — Utility class for combat calculations with D&D-style system.

# --- Feat helpers ---
## A combatant can now own several feats at once (chargen pick + one gained per level-up, see
## GameState.check_level_ups). These read member["feats"]: Array[String] live, every time —
## nothing here is precomputed, so multiple feats with the same effect just combine naturally
## (sum/max/best-of), with no order-of-acquisition footgun.

static func _owned_feats(member: Dictionary) -> Array:
	var result: Array = []
	for feat_id in member.get("feats", []):
		var feat = DataLoader.get_feat(feat_id)
		if not feat.is_empty():
			result.append(feat)
	return result

static func has_feat(member: Dictionary, feat_id: String) -> bool:
	return member.get("feats", []).has(feat_id)

static func has_feat_effect(member: Dictionary, effect: String) -> bool:
	for feat in _owned_feats(member):
		if feat.get("effect", "") == effect:
			return true
	return false

## Adds up `value` across every owned feat whose effect matches — how flat bonuses (e.g.
## magical_damage_bonus_flat) stack when a level-up feat reuses an effect already owned.
static func sum_feat_value(member: Dictionary, effect: String) -> int:
	var total = 0
	for feat in _owned_feats(member):
		if feat.get("effect", "") == effect:
			total += int(feat.get("value", 0))
	return total

## Best (largest) value across owned feats with this effect — for charge counts where a
## stronger later feat (e.g. a capstone) should simply replace a weaker earlier one, not stack.
static func max_feat_value(member: Dictionary, effect: String, default_value: int = 0) -> int:
	var best = default_value
	var found = false
	for feat in _owned_feats(member):
		if feat.get("effect", "") == effect:
			var value = int(feat.get("value", 0))
			best = value if not found else maxi(best, value)
			found = true
	return best

## Smallest (easiest to reach) crit threshold among owned crit_range_bonus feats; 20 (only a
## natural 20 crits) if none.
static func crit_threshold(member: Dictionary) -> int:
	var best = 20
	for feat in _owned_feats(member):
		if feat.get("effect", "") == "crit_range_bonus":
			best = mini(best, int(feat.get("value", 19)))
	return best

## Applies the feats whose effect can be resolved once, into a derived stat field (a flat stat
## change or a bonus skill), at the moment the feat is gained (chargen pick or a level-up
## choice — see GameState.apply_level_up_choice). The rest (per-battle charges, combat-time
## hooks) are read live from member["feats"] via the helpers above, wherever relevant. Combines
## with `+=`/`*=` rather than overwriting, so gaining a second feat with the same effect later
## (e.g. Daragat's healer + inspiring_leader, both touching heal_multiplier) stacks correctly
## regardless of which order they were acquired in.
static func apply_feat_effects(member: Dictionary, feat_id: String) -> void:
	if feat_id == "":
		return
	var feat = DataLoader.get_feat(feat_id)
	match feat.get("effect", ""):
		"hp_bonus_pct":
			var bonus: float = feat.get("value", 0)
			member["max_hp"] = int(member["max_hp"] * (1.0 + bonus / 100.0))
			member["hp"] = member["max_hp"]
		"ca_bonus_flat":
			member["ca"] = member.get("ca", 10) + int(feat.get("value", 0))
		"damage_bonus_flat":
			member["damage_bonus_flat"] = member.get("damage_bonus_flat", 0) + int(feat.get("value", 0))
		"heal_double":
			member["heal_multiplier"] = member.get("heal_multiplier", 1.0) * 2.0
		"heal_bonus_pct":
			var heal_bonus: float = feat.get("value", 20)
			member["heal_multiplier"] = member.get("heal_multiplier", 1.0) * (1.0 + heal_bonus / 100.0)
		"bonus_skill":
			var skill_id = str(feat.get("value", ""))
			if skill_id != "" and not member["skills"].has(skill_id):
				member["skills"].append(skill_id)

# --- Legendary weapons ---
## One weapon per character, held in member["weapon"] as an item id ("" when unarmed). There is
## no attunement and no class restriction: any of the three fits any hand, which is the whole
## point of letting the player choose who carries what.

static func weapon_of(member: Dictionary) -> Dictionary:
	var wid := str(member.get("weapon", ""))
	if wid == "":
		return {}
	return DataLoader.get_item(wid).get("weapon", {})

static func weapon_attack_bonus(member: Dictionary) -> int:
	return int(weapon_of(member).get("attack_bonus", 0))

static func weapon_damage_bonus(attacker: Dictionary, defender: Dictionary) -> int:
	var w := weapon_of(attacker)
	if w.is_empty():
		return 0
	var bonus := int(w.get("damage_bonus", 0))
	# Whelm was forged to break giants and goblinoids, and it hits them noticeably harder.
	var tag := str(w.get("bonus_vs_tag", ""))
	if tag != "" and str(defender.get("tag", "")) == tag:
		bonus += int(w.get("bonus_vs_damage", 0))
	return bonus

static func has_weapon_ability(member: Dictionary, ability: String) -> bool:
	return str(weapon_of(member).get("ability", "")) == ability

## Public wrapper around the D&D attribute-modifier table below, for callers outside this file
## (e.g. Trap's saving throw) that need a single attribute's modifier without duplicating it.
static func attribute_modifier(value: int) -> int:
	return _get_modifier(value)

static func _get_modifier(attribute_value: int) -> int:
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

static func _roll_dice(dice_str: String) -> int:
	var total = 0
	var parts = dice_str.split("+")
	for part in parts:
		part = part.strip_edges()
		if part.find("d") != -1:
			var dice_parts = part.split("d")
			var num_dice = 1
			if dice_parts[0].is_valid_int():
				num_dice = dice_parts[0].to_int()
			var die_size = dice_parts[1].to_int()
			for i in range(num_dice):
				total += randi_range(1, die_size)
		elif part.is_valid_int():
			total += part.to_int()
	return total

static func _max_roll_dice(dice_str: String) -> int:
	var total = 0
	var parts = dice_str.split("+")
	for part in parts:
		part = part.strip_edges()
		if part.find("d") != -1:
			var dice_parts = part.split("d")
			var num_dice = 1
			if dice_parts[0].is_valid_int():
				num_dice = dice_parts[0].to_int()
			var die_size = dice_parts[1].to_int()
			total += num_dice * die_size
		elif part.is_valid_int():
			total += part.to_int()
	return total

## Average of a dice string like "2d6+3", for the AI to reason about kill potential without
## actually rolling. 1d6 -> 3.5, 2d8+2 -> 11.0.
static func average_damage(dice_str: String) -> float:
	var total := 0.0
	for part in dice_str.split("+"):
		part = part.strip_edges()
		if part.find("d") != -1:
			var dice_parts = part.split("d")
			var num_dice := 1
			if dice_parts[0].is_valid_int():
				num_dice = dice_parts[0].to_int()
			total += num_dice * (dice_parts[1].to_int() + 1) / 2.0
		elif part.is_valid_int():
			total += float(part.to_int())
	return total

static func get_attack_modifier(attacker: Dictionary) -> int:
	var clase = attacker.get("class", "")
	var attrs = attacker.get("attributes", {})
	var str_val = attrs.get("fuerza", 10)
	var dex_val = attrs.get("agilidad", 10)
	
	if clase == "Monje" or clase == "Gunslinger":
		return _get_modifier(dex_val) + weapon_attack_bonus(attacker)
	return _get_modifier(str_val) + weapon_attack_bonus(attacker)

static func get_damage_dice(attacker: Dictionary) -> String:
	var clase = attacker.get("class", "")
	
	match clase:
		"Barbaro":
			return "1d12"
		"Monje":
			return "1d8"
		"Gunslinger":
			return "1d8"
		"Warlock":
			return "1d10"
		"Clerigo":
			return "1d8"
		"Hechicera":
			return "1d6"
		_:
			return "1d8"

## Rolls 1d20 applying advantage/disadvantage from status effects (blind, Reckless' granted
## advantage) plus an optional explicit force_advantage (e.g. Barbara's own Reckless attack,
## Azafran's Shadow). forced_roll (if > 0) bypasses rolling entirely (Solana's Premonition).
static func _roll_attack_d20(attacker: Dictionary, defender: Dictionary, force_advantage: bool, forced_roll: int, defenders: Array = []) -> int:
	if forced_roll > 0:
		return forced_roll
	var advantage = force_advantage or defender.get("blind_turns", 0) > 0 \
		or defender.get("grants_advantage", false) \
		or (int(attacker.get("temp_hp", 0)) > 0 and has_weapon_ability(attacker, "devour_soul"))
	# Defend action: everything aimed at a defending combatant rolls at disadvantage, until the
	# flag is cleared at the start of the next round (BattleController._start_round).
	# Engagement: swinging at anyone but the opponent you're locked onto exposes you.
	# Skulker feat: natural evasion forces attackers targeting you to roll with disadvantage.
	# Guard toll: shooting past a standing screen. `defenders` is empty for rolls that never
	# picked a target through the menu (opportunity attacks), which are melee by definition and
	# so can never be tolled anyway.
	var disadvantage = attacker.get("blind_turns", 0) > 0 \
		or defender.get("defending", false) \
		or breaks_engagement_focus(attacker, defender) \
		or (not defenders.is_empty() and is_protected(defender, defenders) and not ignores_guard(attacker)) \
		or has_feat_effect(defender, "attacker_disadvantage")
	# "Puntería Legendaria": a pulse that never wavers — disadvantage simply doesn't apply.
	if disadvantage and has_feat_effect(attacker, "ignore_disadvantage"):
		disadvantage = false
	if advantage and not disadvantage:
		return maxi(randi_range(1, 20), randi_range(1, 20))
	elif disadvantage and not advantage:
		return mini(randi_range(1, 20), randi_range(1, 20))
	return randi_range(1, 20)

static func attack_roll(attacker: Dictionary, defender: Dictionary, force_advantage: bool = false, forced_roll: int = 0, defenders: Array = []) -> Dictionary:
	var attack_bonus = get_attack_modifier(attacker)
	var roll = _roll_attack_d20(attacker, defender, force_advantage, forced_roll, defenders)
	var total_attack = roll + attack_bonus
	
	var defender_ca = defender.get("ca", 10)
	var is_crit = roll >= crit_threshold(attacker)
	var is_fumble = roll == 1

	var damage_dice = get_damage_dice(attacker)
	
	var result = {
		"roll": roll,
		"bonus": attack_bonus,
		"total": total_attack,
		"hit": false,
		"crit": false,
		"damage": 0,
		"damage_dice": damage_dice,
		"message": ""
	}
	
	if is_fumble:
		result.message = "FALLO CRITICO!"
	elif is_crit:
		result.hit = true
		result.crit = true

		var attrs = attacker.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var dex_val = attrs.get("agilidad", 10)
		var clase = attacker.get("class", "")

		var stat_mod = _get_modifier(str_val)
		if clase == "Monje" or clase == "Gunslinger":
			stat_mod = _get_modifier(dex_val)

		var max_damage = _max_roll_dice(damage_dice) + stat_mod
		var extra_damage = _roll_dice(damage_dice) + stat_mod
		result.damage = max_damage + extra_damage
		result.message = "GOLPE CRITICO!"
	elif total_attack >= defender_ca:
		result.hit = true

		var attrs = attacker.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var dex_val = attrs.get("agilidad", 10)
		var clase = attacker.get("class", "")
		
		var stat_mod = _get_modifier(str_val)
		if clase == "Monje" or clase == "Gunslinger":
			stat_mod = _get_modifier(dex_val)

		# Savage Attacker feat: never stuck with a low damage roll — roll the die twice, keep the better.
		if has_feat_effect(attacker, "reroll_damage_best_of_two"):
			result.damage = maxi(_roll_dice(damage_dice), _roll_dice(damage_dice)) + stat_mod
		else:
			result.damage = _roll_dice(damage_dice) + stat_mod
		result.message = "Golpe!"
	else:
		result.message = "Fallo (AC: %d)" % defender_ca

	# Mage Slayer feat: flat bonus on basic-attack hits against enemies with special abilities
	# (their skills[] list) — the closest existing stand-in for "spellcaster" in this data model.
	if result.hit and defender.get("skills", []).size() > 0:
		result.damage += sum_feat_value(attacker, "bonus_vs_casters")

	return result

static func enemy_attack(enemy: Dictionary, defender: Dictionary, defenders: Array = []) -> Dictionary:
	var enemy_attack_bonus = enemy.get("attack_bonus", 0)
	var roll = _roll_attack_d20(enemy, defender, false, 0, defenders)
	var total_attack = roll + enemy_attack_bonus
	
	var defender_ca = defender.get("ca", 10)
	var is_crit = roll >= crit_threshold(enemy)
	var is_fumble = roll == 1

	var damage_dice = enemy.get("damage", "1d6")
	
	var result = {
		"roll": roll,
		"bonus": enemy_attack_bonus,
		"total": total_attack,
		"hit": false,
		"crit": false,
		"damage": 0,
		"damage_dice": damage_dice,
		"message": ""
	}
	
	if is_fumble:
		result.message = "El enemigo falla criticamente!"
	elif is_crit:
		result.hit = true
		result.crit = true

		var attrs = enemy.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var stat_mod = _get_modifier(str_val)

		var max_damage = _max_roll_dice(damage_dice) + stat_mod
		var extra_damage = _roll_dice(damage_dice) + stat_mod
		result.damage = max_damage + extra_damage
		result.message = "Golpe critico del enemigo!"
	elif total_attack >= defender_ca:
		result.hit = true

		var attrs = enemy.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var stat_mod = _get_modifier(str_val)
		
		result.damage = _roll_dice(damage_dice) + stat_mod
		result.message = "El enemigo golpea!"
	else:
		result.message = "El enemigo falla (AC: %d)" % defender_ca
	
	return result

static func apply_damage(target: Dictionary, damage: int) -> void:
	var reduced = damage
	var reduction = sum_feat_value(target, "damage_reduction_flat")
	if reduction > 0:
		reduced = maxi(1, damage - reduction)
	# Blackrazor's devoured souls sit in front of real hit points and burn off first.
	var temp := int(target.get("temp_hp", 0))
	if temp > 0:
		var absorbed := mini(temp, reduced)
		target["temp_hp"] = temp - absorbed
		reduced -= absorbed
	var new_hp = maxi(0, target.get("hp", 0) - reduced)
	# Debug Panel's "Modo invencible" — checked before death_ward_charges so testing with it on
	# doesn't burn Daragat's real charge for nothing.
	if new_hp <= 0 and bool(target.get("is_player", false)) and GameState.invincible_mode:
		new_hp = 1
	# "Bendición de Lathander": granted to the whole party in _setup_party when Daragat has the
	# feat, spent here the first time a blow would put someone down.
	elif new_hp <= 0 and int(target.get("death_ward_charges", 0)) > 0:
		target["death_ward_charges"] = int(target["death_ward_charges"]) - 1
		new_hp = 1
	target["hp"] = new_hp

static func apply_heal(target: Dictionary, heal: int) -> void:
	target["hp"] = mini(target.get("max_hp", target.get("hp", 0)), target.get("hp", 0) + heal)

static func use_mp(caster: Dictionary, amount: int) -> bool:
	# "Pacto Definitivo": the patron picks up the tab, every skill is free.
	if has_feat_effect(caster, "free_skills"):
		return true
	if caster.get("mp", 0) >= amount:
		caster["mp"] = caster["mp"] - amount
		return true
	return false

static func is_dead(combatant: Dictionary) -> bool:
	return combatant.get("hp", 0) <= 0

# --- Position system (0 = adelante, 1 = medio, 2 = retaguardia) ---

const MELEE_CLASSES: Array[String] = ["Barbaro", "Monje"]

static func is_melee_class(class_name_str: String) -> bool:
	return class_name_str in MELEE_CLASSES

## Position itself no longer scales damage — what a zone controls is who you can reach and who
## can reach you (see can_target / engagement below). This only applies the always-on passives
## that do scale damage: Barbara's Rage (double dealt AND double taken) and Rosa's "Mystra
## Wanted" mark (+25% taken).
static func apply_position_modifiers(damage: int, attacker: Dictionary, defender: Dictionary) -> int:
	var result: float = float(damage)
	# Tier scaling for enemies deep in the dungeon. Every damage site on both sides already funnels
	# through here, so this is the one place it needs to exist; party members never carry the key,
	# so it is a no-op for them.
	result *= float(attacker.get("damage_scale", 1.0))
	if attacker.get("class", "") == "Barbaro":
		result *= 2.0
	if defender.get("class", "") == "Barbaro":
		result *= 2.0
	if defender.get("marked", false):
		result *= 1.25
	result += attacker.get("damage_bonus_flat", 0)  # Great Weapon Master / Dual Wielder feats
	result += weapon_damage_bonus(attacker, defender)
	return maxi(1, int(round(result)))

# --- Engagement ("estar a melee", in the player-facing text) ---
## A combatant locks onto exactly ONE opponent — member["engaged_with"] holds that opponent's id,
## "" when free — but any number of opponents can be locked onto the same target, so four heroes
## can all pile onto one ogre. That asymmetry is the whole point: the front rank is where you
## tie enemies up, and breaking a lock costs you an opportunity attack (see BattleController).

const POS_FRONT := 0
const POS_MID := 1
const POS_BACK := 2

static func engaged_target_id(c: Dictionary) -> String:
	return str(c.get("engaged_with", ""))

static func is_engaged_with(a: Dictionary, b: Dictionary) -> bool:
	return engaged_target_id(a) == str(b.get("id", "")) or engaged_target_id(b) == str(a.get("id", ""))

## Is anyone in `pool` locked onto `c`, or `c` onto someone? Used for "is this one tied up".
static func is_engaged(c: Dictionary, pool: Array) -> bool:
	return not engagement_partners(c, pool).is_empty()

## Everyone still standing in `pool` involved in a lock with `c` — both the opponent `c` holds
## and every opponent holding onto `c`. Exactly the set that gets an opportunity attack when `c`
## walks away.
static func engagement_partners(c: Dictionary, pool: Array) -> Array:
	var out: Array = []
	var my_target := engaged_target_id(c)
	var my_id := str(c.get("id", ""))
	for other in pool:
		if other.get("hp", 0) <= 0:
			continue
		if (my_target != "" and str(other.get("id", "")) == my_target) or engaged_target_id(other) == my_id:
			out.append(other)
	return out

## Breaks every lock involving `c`, in both directions. Called when it changes zone or dies, so
## nothing is ever left engaged with someone who is no longer there to fight.
static func clear_engagements(c: Dictionary, all_combatants: Array) -> void:
	c["engaged_with"] = ""
	var my_id := str(c.get("id", ""))
	for other in all_combatants:
		if engaged_target_id(other) == my_id:
			other["engaged_with"] = ""

## Who a front-rank combatant with no lock should be forced onto: the opposing front-ranker with
## the fewest attackers on them already, so a pile-up spreads out instead of dogpiling one enemy.
## Empty when the opposing front rank has nobody left standing.
static func auto_engage_candidate(c: Dictionary, opponents: Array, allies: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_load := 999
	for o in opponents:
		if o.get("hp", 0) <= 0 or int(o.get("position", 0)) != POS_FRONT:
			continue
		var load := 0
		for a in allies:
			if a.get("hp", 0) > 0 and engaged_target_id(a) == str(o.get("id", "")):
				load += 1
		if load < best_load:
			best_load = load
			best = o
	return best

# --- Targeting legality ---

## True once nobody on this side is left standing ahead of the back rank.
static func back_rank_exposed(defenders: Array) -> bool:
	for d in defenders:
		if d.get("hp", 0) > 0 and int(d.get("position", 0)) < POS_BACK:
			return false
	return true

# --- Guard toll ---
## "Protegido": standing in Retaguardia while at least one ally still holds Adelante or Medio.
## Reaching past that screen is possible but it costs — a roll made at disadvantage, or half
## damage for magic, which lands automatically and would otherwise pay nothing at all. Only ONE
## threshold exists in the whole system: Adelante and Medio are never tolled.
static func is_protected(defender: Dictionary, defenders: Array) -> bool:
	return int(defender.get("position", 0)) == POS_BACK and not back_rank_exposed(defenders)

## "Vuelo del Búho" flies over the screen: full reach, and no toll of either kind.
static func ignores_guard(attacker: Dictionary) -> bool:
	return has_feat_effect(attacker, "ignore_back_rank")

## Half damage against a Protegido, for the magic that never has to roll. Physical attacks pay
## in accuracy instead (see _roll_attack_d20), so they must NOT go through here.
static func guard_damage_multiplier(attacker: Dictionary, defender: Dictionary, defenders: Array) -> float:
	if is_protected(defender, defenders) and not ignores_guard(attacker):
		return 0.5
	return 1.0

## Whether this combatant fights hand to hand, for both sides of the field. Heroes go by class;
## enemies have no class at all, so they go by temperament — an `aggressive` brawler is melee,
## while `cautious` skirmishers and `ranged` artillery are not. Without this, every one of the 31
## enemies would count as ranged and could reach past your screen, which would make the whole
## starting-formation decision pointless.
static func is_melee_combatant(c: Dictionary) -> bool:
	var clase := str(c.get("class", ""))
	if clase != "":
		return is_melee_class(clase)
	return str(c.get("ai_profile", "aggressive")) == "aggressive"

## Can `attacker` legally aim at `defender`? Reach is now almost unrestricted — the toll replaced
## the old hard gate — so all that remains is the melee limitation: a hand-to-hand fighter has no
## way to reach past a standing screen, and none at all from the back rank themselves. That
## exception is what keeps clearing the enemy front line worth doing, on both sides.
static func can_target(attacker: Dictionary, defender: Dictionary, defenders: Array) -> bool:
	if defender.get("hp", 0) <= 0:
		return false
	if not is_melee_combatant(attacker):
		return true
	if ignores_guard(attacker):
		return true
	if int(attacker.get("position", 0)) == POS_BACK:
		return false
	return not is_protected(defender, defenders)

## Every legal target for `attacker` out of `defenders`.
static func legal_targets(attacker: Dictionary, defenders: Array) -> Array:
	var out: Array = []
	for d in defenders:
		if can_target(attacker, d, defenders):
			out.append(d)
	return out

## Swinging at anyone other than the opponent you're locked onto means turning your back on them
## — that's the disadvantage applied in _roll_attack_d20.
static func breaks_engagement_focus(attacker: Dictionary, defender: Dictionary) -> bool:
	var locked := engaged_target_id(attacker)
	return locked != "" and locked != str(defender.get("id", ""))

static func calculate_physical_damage(attacker: Dictionary, defender: Dictionary, power: int = 0) -> int:
	var result = attack_roll(attacker, defender)
	if power > 0:
		return result.damage + power
	return result.damage

## Devuelve el mayor entre el modificador de inteligencia y sabiduría — el "casting stat"
## compartido por hechizos y curaciones en este sistema simplificado.
static func get_caster_stat_mod(caster: Dictionary) -> int:
	var attrs = caster.get("attributes", {})
	var int_mod = _get_modifier(attrs.get("inteligencia", 10))
	var wis_mod = _get_modifier(attrs.get("sabiduria", 10))
	return max(int_mod, wis_mod)

static func calculate_magical_damage(attacker: Dictionary, defender: Dictionary, power: int) -> int:
	var stat_mod = get_caster_stat_mod(attacker)
	var damage = power + stat_mod + sum_feat_value(attacker, "magical_damage_bonus_flat")
	return max(1, damage)

static func calculate_heal(caster: Dictionary, power: int) -> int:
	var stat_mod = get_caster_stat_mod(caster)
	var heal = power + stat_mod
	return int(heal * caster.get("heal_multiplier", 1.0))  # Healer feat

## Returns a percentage (0-100) chance to flee combat. Callers must compare against a 0-1 roll
## as `chance / 100.0`, not the raw int.
##
## Counts LIVING members, not the party array's size: fleeing is meant to be a real gamble you
## take while you still can, so it gets worse as people go down, and the number BattleUI shows
## above the "Huir" option actually moves during the fight instead of being a constant.
const FLEE_BASE_CHANCE := 30
const FLEE_CHANCE_PER_MEMBER := 5

static func calculate_flee_chance(party: Array, enemies: Array) -> int:
	var alive = 0
	for p in party:
		if p.get("hp", 0) > 0:
			alive += 1
	var chance = FLEE_BASE_CHANCE + (alive * FLEE_CHANCE_PER_MEMBER)
	for p in party:
		if has_feat_effect(p, "flee_bonus_flat"):
			chance += sum_feat_value(p, "flee_bonus_flat")
			break
	return clampi(chance, 0, 100)
