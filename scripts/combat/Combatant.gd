class_name Combatant
extends Node
## Combatant — Utility class for combat calculations with D&D-style system.

const LEVEL: int = 1

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

static func get_attack_modifier(attacker: Dictionary) -> int:
	var clase = attacker.get("class", "")
	var attrs = attacker.get("attributes", {})
	var str_val = attrs.get("fuerza", 10)
	var dex_val = attrs.get("agilidad", 10)
	
	var base = LEVEL
	
	if clase == "Monje" or clase == "Gunslinger":
		return base + _get_modifier(dex_val)
	else:
		return base + _get_modifier(str_val)

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
static func _roll_attack_d20(attacker: Dictionary, defender: Dictionary, force_advantage: bool, forced_roll: int) -> int:
	if forced_roll > 0:
		return forced_roll
	var advantage = force_advantage or defender.get("blind_turns", 0) > 0 or defender.get("grants_advantage", false)
	# Skulker feat: natural evasion forces attackers targeting you to roll with disadvantage.
	var disadvantage = attacker.get("blind_turns", 0) > 0 or has_feat_effect(defender, "attacker_disadvantage")
	if advantage and not disadvantage:
		return maxi(randi_range(1, 20), randi_range(1, 20))
	elif disadvantage and not advantage:
		return mini(randi_range(1, 20), randi_range(1, 20))
	return randi_range(1, 20)

static func attack_roll(attacker: Dictionary, defender: Dictionary, force_advantage: bool = false, forced_roll: int = 0) -> Dictionary:
	var attack_bonus = get_attack_modifier(attacker)
	var roll = _roll_attack_d20(attacker, defender, force_advantage, forced_roll)
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

static func enemy_attack(enemy: Dictionary, defender: Dictionary) -> Dictionary:
	var enemy_attack_bonus = enemy.get("attack_bonus", 0)
	var roll = _roll_attack_d20(enemy, defender, false, 0)
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
	target["hp"] = maxi(0, target.get("hp", 0) - reduced)

static func apply_heal(target: Dictionary, heal: int) -> void:
	target["hp"] = mini(target.get("max_hp", target.get("hp", 0)), target.get("hp", 0) + heal)

static func use_mp(caster: Dictionary, amount: int) -> bool:
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

## Adelante: sin cambios. Medio: da y recibe la mitad de daño. Retaguardia: sin cambio de daño
## (solo restringe qué acciones puede hacer el propio combatiente, ver is_melee_class).
## También aplica pasivas siempre-activas que afectan daño: Rage de Barbara (doble daño dado
## Y doble daño recibido) y la marca de "Mystra Wanted" de Rosa (+25% daño recibido).
static func apply_position_modifiers(damage: int, attacker: Dictionary, defender: Dictionary) -> int:
	var result: float = float(damage)
	if attacker.get("position", 0) == 1:
		result *= 0.5
	if defender.get("position", 0) == 1:
		result *= 0.5
	if attacker.get("class", "") == "Barbaro":
		result *= 2.0
	if defender.get("class", "") == "Barbaro":
		result *= 2.0
	if defender.get("marked", false):
		result *= 1.25
	result += attacker.get("damage_bonus_flat", 0)  # Great Weapon Master / Dual Wielder feats
	return maxi(1, int(round(result)))

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
static func calculate_flee_chance(party: Array, enemies: Array) -> int:
	var base = 50
	var party_size = party.size()
	var chance = base + (party_size * 10)
	for p in party:
		if has_feat_effect(p, "flee_bonus_flat"):
			chance += sum_feat_value(p, "flee_bonus_flat")
			break
	return mini(100, chance)
