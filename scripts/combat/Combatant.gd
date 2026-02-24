class_name Combatant
extends Node
## Combatant — Represents a fighter in battle (party member or enemy).
## This is a utility class with static functions for combat calculations.

# --- Damage formulas ---

static func calculate_physical_damage(attacker: Dictionary, defender: Dictionary, skill_power: int = 0) -> int:
	var atk = attacker.get("atk", 1)
	var def_val = defender.get("def", 0)
	var base_damage: int

	if skill_power > 0:
		base_damage = atk + skill_power - def_val / 2
	else:
		base_damage = atk - def_val / 2

	# Check if defender is defending
	if defender.get("defending", false):
		base_damage = base_damage / 2

	# Random variance (+/- 10%)
	var variance = randf_range(0.9, 1.1)
	base_damage = int(base_damage * variance)

	return maxi(1, base_damage)

static func calculate_magical_damage(attacker: Dictionary, defender: Dictionary, skill_power: int) -> int:
	var mag = attacker.get("mag", 1)
	var mdef = defender.get("mdef", 0)
	var base_damage = skill_power + mag - mdef / 2

	if defender.get("defending", false):
		base_damage = base_damage / 2

	var variance = randf_range(0.9, 1.1)
	base_damage = int(base_damage * variance)

	return maxi(1, base_damage)

static func calculate_heal(caster: Dictionary, skill_power: int) -> int:
	var mag = caster.get("mag", 1)
	var heal = skill_power + mag / 2
	var variance = randf_range(0.9, 1.1)
	return maxi(1, int(heal * variance))

static func calculate_flee_chance(party: Array, enemies: Array) -> float:
	var party_spd = 0.0
	var party_count = 0
	for p in party:
		if p.get("hp", 0) > 0:
			party_spd += p.get("spd", 1)
			party_count += 1

	var enemy_spd = 0.0
	var enemy_count = 0
	for e in enemies:
		if e.get("hp", 0) > 0:
			enemy_spd += e.get("spd", 1)
			enemy_count += 1

	var avg_party = party_spd / maxf(1, party_count)
	var avg_enemy = enemy_spd / maxf(1, enemy_count)

	var chance = 0.5 + (avg_party - avg_enemy) * 0.05
	return clampf(chance, 0.1, 0.9)

static func apply_damage(target: Dictionary, damage: int) -> void:
	target["hp"] = maxi(0, target.get("hp", 0) - damage)

static func apply_heal(target: Dictionary, heal: int) -> void:
	target["hp"] = mini(target.get("max_hp", target.get("hp", 0)), target.get("hp", 0) + heal)

static func use_mp(caster: Dictionary, amount: int) -> bool:
	if caster.get("mp", 0) >= amount:
		caster["mp"] = caster["mp"] - amount
		return true
	return false

static func is_dead(combatant: Dictionary) -> bool:
	return combatant.get("hp", 0) <= 0
