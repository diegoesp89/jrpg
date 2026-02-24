class_name EnemyAI
extends Node
## EnemyAI — Simple AI that picks actions for enemies during battle.

static func choose_action(enemy: Dictionary, party: Array, enemies: Array) -> Dictionary:
	# Simple AI: 70% Attack, 30% use skill (if has skills and MP)
	var available_skills: Array = []
	for skill_id in enemy.get("skills", []):
		var skill = DataLoader.get_skill(skill_id)
		if skill and enemy.get("mp", 0) >= skill.get("mp_cost", 0):
			available_skills.append(skill)

	var action: Dictionary = {}

	if available_skills.size() > 0 and randf() < 0.3:
		# Use a skill
		var skill = available_skills[randi_range(0, available_skills.size() - 1)]
		action["type"] = "skill"
		action["skill"] = skill

		# Pick target
		if skill.get("target_type", "") == "single_ally":
			# Heal weakest enemy ally
			action["target"] = _find_weakest(enemies)
		elif skill.get("target_type", "") == "all_enemies":
			action["targets"] = _get_alive(party)
		else:
			action["target"] = _pick_random_alive(party)
	else:
		# Basic attack
		action["type"] = "attack"
		action["target"] = _pick_random_alive(party)

	return action

static func _pick_random_alive(group: Array) -> Dictionary:
	var alive: Array = []
	for c in group:
		if c.get("hp", 0) > 0:
			alive.append(c)
	if alive.is_empty():
		return {}
	return alive[randi_range(0, alive.size() - 1)]

static func _find_weakest(group: Array) -> Dictionary:
	var weakest: Dictionary = {}
	var min_hp_ratio: float = 2.0
	for c in group:
		if c.get("hp", 0) > 0:
			var ratio = float(c["hp"]) / float(c.get("max_hp", c["hp"]))
			if ratio < min_hp_ratio:
				min_hp_ratio = ratio
				weakest = c
	return weakest

static func _get_alive(group: Array) -> Array:
	var alive: Array = []
	for c in group:
		if c.get("hp", 0) > 0:
			alive.append(c)
	return alive
