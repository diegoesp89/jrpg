class_name Combatant
extends Node
## Combatant — Utility class for combat calculations with D&D-style system.

const LEVEL: int = 1

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

static func attack_roll(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var attack_bonus = get_attack_modifier(attacker)
	var roll = randi_range(1, 20)
	var total_attack = roll + attack_bonus
	
	var defender_ca = defender.get("ca", 10)
	var is_crit = roll == 20
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
		
		var damage_dice = get_damage_dice(attacker)
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
		
		var damage_dice = get_damage_dice(attacker)
		var attrs = attacker.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var dex_val = attrs.get("agilidad", 10)
		var clase = attacker.get("class", "")
		
		var stat_mod = _get_modifier(str_val)
		if clase == "Monje" or clase == "Gunslinger":
			stat_mod = _get_modifier(dex_val)
		
		result.damage = _roll_dice(damage_dice) + stat_mod
		result.message = "Golpe!"
	else:
		result.message = "Fallo (AC: %d)" % defender_ca
	
	return result

static func enemy_attack(enemy: Dictionary, defender: Dictionary) -> Dictionary:
	var enemy_attack_bonus = enemy.get("attack_bonus", 0)
	var roll = randi_range(1, 20)
	var total_attack = roll + enemy_attack_bonus
	
	var defender_ca = defender.get("ca", 10)
	var is_crit = roll == 20
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
		
		var damage_dice = enemy.get("damage", "1d6")
		var attrs = enemy.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var stat_mod = _get_modifier(str_val)
		
		var max_damage = _max_roll_dice(damage_dice) + stat_mod
		var extra_damage = _roll_dice(damage_dice) + stat_mod
		result.damage = max_damage + extra_damage
		result.message = "Golpe critico del enemigo!"
	elif total_attack >= defender_ca:
		result.hit = true
		
		var damage_dice = enemy.get("damage", "1d6")
		var attrs = enemy.get("attributes", {})
		var str_val = attrs.get("fuerza", 10)
		var stat_mod = _get_modifier(str_val)
		
		result.damage = _roll_dice(damage_dice) + stat_mod
		result.message = "El enemigo golpea!"
	else:
		result.message = "El enemigo falla (AC: %d)" % defender_ca
	
	return result

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

static func calculate_physical_damage(attacker: Dictionary, defender: Dictionary, power: int = 0) -> int:
	var result = attack_roll(attacker, defender)
	if power > 0:
		return result.damage + power
	return result.damage

static func calculate_magical_damage(attacker: Dictionary, defender: Dictionary, power: int) -> int:
	var attrs = attacker.get("attributes", {})
	var int_mod = _get_modifier(attrs.get("inteligencia", 10))
	var wis_mod = _get_modifier(attrs.get("sabiduria", 10))
	var stat_mod = max(int_mod, wis_mod)
	var damage = power + stat_mod
	return max(1, damage)

static func calculate_heal(caster: Dictionary, power: int) -> int:
	var attrs = caster.get("attributes", {})
	var wis_mod = _get_modifier(attrs.get("sabiduria", 10))
	var int_mod = _get_modifier(attrs.get("inteligencia", 10))
	var stat_mod = max(wis_mod, int_mod)
	return power + stat_mod

static func calculate_flee_chance(party: Array, enemies: Array) -> int:
	var base = 50
	var party_size = party.size()
	return base + (party_size * 10)
