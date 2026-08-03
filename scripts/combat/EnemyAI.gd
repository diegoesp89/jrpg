class_name EnemyAI
extends Node
## EnemyAI — Picks an action for an enemy, driven by its temperament.
##
## Every enemy carries an `ai_profile` (see data/enemies/enemies.json) that decides both where it
## starts the fight and what it wants to do with its turn:
##
##   aggressive — brawlers. Start in Adelante, hold the front rank, and keep swinging at whoever
##                they're locked onto. The wall the party has to chew through.
##   cautious   — skittish things. Start in Medio and break for Retaguardia once they're hurt,
##                even though bailing out of a lock hands the party a free opportunity attack.
##   ranged     — artillery and casters. Start in Retaguardia and stay there, leaning on skills.
##                Untouchable while anything is still standing in front of them, which is exactly
##                why clearing the front rank matters.
##
## Targeting runs through Combatant.legal_targets, so the AI obeys the same reach and back-rank
## rules the player does — it can't reach into Retaguardia either.

const DEFAULT_PROFILE := "aggressive"

const PROFILE_START_POSITION := {
	"aggressive": Combatant.POS_FRONT,
	"cautious": Combatant.POS_MID,
	"ranged": Combatant.POS_BACK,
}

## HP fraction below which a cautious enemy starts wanting to run for the back rank.
const CAUTIOUS_RETREAT_HP := 0.5

## How willing each profile is to actually give up its turn to reposition, once it decides it
## would rather be somewhere else. Wanting to move and doing it are separate: a brawler pushed
## out of the front line mostly just keeps swinging at whoever is in reach, while a hurt coward
## nearly always bolts. Rolling this every turn also stops any profile from locking into a
## move / move-back loop, since the desire has to win the roll twice in a row to oscillate.
const PROFILE_REPOSITION_CHANCE := {
	"aggressive": 0.10,
	"cautious": 0.75,
	"ranged": 0.50,
}

static func reposition_chance(profile: String) -> float:
	return float(PROFILE_REPOSITION_CHANCE.get(profile, 0.10))

static func starting_position(profile: String) -> int:
	return int(PROFILE_START_POSITION.get(profile, Combatant.POS_FRONT))

static func choose_action(enemy: Dictionary, party: Array, enemies: Array) -> Dictionary:
	# Move one zone at a time, toward where it would rather be, and only if the roll says so.
	var desired := _desired_position(enemy)
	var here := int(enemy.get("position", 0))
	if desired != here and randf() < reposition_chance(str(enemy.get("ai_profile", DEFAULT_PROFILE))):
		return {"type": "move", "target_position": here + signi(desired - here)}

	var targets := Combatant.legal_targets(enemy, party)
	if targets.is_empty():
		return {"type": "pass"}

	var available_skills: Array = []
	for skill_id in enemy.get("skills", []):
		var skill = DataLoader.get_skill(skill_id)
		if skill and enemy.get("mp", 0) >= skill.get("mp_cost", 0):
			available_skills.append(skill)

	# Artillery leans on its skills; everyone else mostly swings.
	var skill_chance := 0.6 if str(enemy.get("ai_profile", DEFAULT_PROFILE)) == "ranged" else 0.3

	if available_skills.size() > 0 and randf() < skill_chance:
		var skill = available_skills[randi_range(0, available_skills.size() - 1)]
		var action := {"type": "skill", "skill": skill}
		if skill.get("target_type", "") == "single_ally":
			action["target"] = _find_weakest(enemies)
		elif skill.get("target_type", "") == "all_enemies":
			# Area damage ignores the screen entirely (the screened ones just take half), so the
			# payload is every living hero, not only the reachable ones.
			action["targets"] = _get_alive(party)
		else:
			action["target"] = _pick_attack_target(enemy, targets, party, _estimate_damage(enemy, skill))
		return action

	return {"type": "attack", "target": _pick_attack_target(enemy, targets, party, _estimate_damage(enemy, {}))}

## Where this enemy wants to be standing right now.
static func _desired_position(enemy: Dictionary) -> int:
	match str(enemy.get("ai_profile", DEFAULT_PROFILE)):
		"ranged":
			return Combatant.POS_BACK
		"cautious":
			var ratio: float = float(enemy.get("hp", 1)) / maxf(1.0, float(enemy.get("max_hp", 1)))
			return Combatant.POS_BACK if ratio < CAUTIOUS_RETREAT_HP else Combatant.POS_MID
		_:
			return Combatant.POS_FRONT

## Picks by what the hit actually accomplishes, not at random — this is what makes ranged enemies
## punish a soft back rank on their own, with no scripting.
##
## The key judgement is whether the blow FINISHES the target. Half damage through a screen is
## still a kill if the target is nearly down, and removing a combatant beats chipping a healthy
## one, so a kill outranks everything regardless of the toll. Failing that, the toll and the
## target's remaining HP decide. Being locked in melee overrides all of it: swinging elsewhere
## costs disadvantage for nothing.
static func _pick_attack_target(enemy: Dictionary, targets: Array, defenders: Array = [], est_damage: float = 0.0) -> Dictionary:
	var locked := Combatant.engaged_target_id(enemy)
	if locked != "":
		for t in targets:
			if str(t.get("id", "")) == locked:
				return t

	var best: Dictionary = {}
	var best_score := -INF
	for t in targets:
		var toll := 1.0
		if not defenders.is_empty() and Combatant.is_protected(t, defenders) and not Combatant.ignores_guard(enemy):
			toll = 0.5
		var hp: float = maxf(1.0, float(t.get("hp", 1)))
		var hp_ratio: float = hp / maxf(1.0, float(t.get("max_hp", 1)))

		var score := 0.0
		if est_damage * toll >= hp:
			score = 2.0  # a kill is a kill, screen or no screen
		else:
			score = toll * (1.0 + (1.0 - hp_ratio) * 0.5)
		# The healer is the priority target, but only once they're hurt enough to be worth
		# spending a turn on — a full-health cleric shouldn't be an automatic magnet.
		if str(t.get("class", "")) == "Clerigo" and hp_ratio < 0.6:
			score *= 1.3

		if score > best_score:
			best_score = score
			best = t
	return best if not best.is_empty() else targets[randi_range(0, targets.size() - 1)]

## Rough damage this enemy is about to deal, for the kill check above.
static func _estimate_damage(enemy: Dictionary, skill: Dictionary) -> float:
	if not skill.is_empty():
		return float(skill.get("power", 0)) + float(Combatant.get_caster_stat_mod(enemy))
	var attrs: Dictionary = enemy.get("attributes", {})
	return Combatant.average_damage(str(enemy.get("damage", "1d6"))) \
		+ float(Combatant.attribute_modifier(int(attrs.get("fuerza", 10))))

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
