extends Node
## Balance simulator. Runs battles headlessly with no animation waits, calling the REAL combat
## code (Combatant, EnemyAI, TurnSystem) so the numbers describe the game and not a model of it.
## The only thing reimplemented here is BattleController's orchestration, which exists purely for
## pacing — every damage number, roll, toll and AI decision comes from the shipping functions.
##
## Two modes:
##   A) single  — one encounter, party at full HP/MP. Measures per-encounter tuning.
##   B) gauntlet— encounters chained with persistent HP/MP and only GameState.MAX_REST_CHARGES
##                rests for the whole run. Measures whether the dungeon is actually challenging.

const MAX_ROUNDS := 40
const REST_THRESHOLD := 0.35  ## rest when the weakest member drops below this fraction

var _party: Array = []
var _enemies: Array = []
var _ts: TurnSystem = null
var _is_boss := false

# Per-battle telemetry
var _attacks_total := 0
var _attacks_on_protected := 0
var _damage_by_char := {}
var _rounds := 0

func _ready() -> void:
	await get_tree().process_frame
	_ts = TurnSystem.new()
	add_child(_ts)
	_run_sweep()
	get_tree().quit()

# --- Party construction -------------------------------------------------------------------

## Feats follow the real progression: one at chargen, one per level to 4, capstone at 5.
func _build_party(ids: Array, level: int) -> Array:
	var out: Array = []
	for cid in ids:
		var cd = DataLoader.get_character(str(cid))
		var m = GameState.create_party_member(cd)
		var pool: Array = cd.get("feat_pool", []).duplicate()
		pool.shuffle()
		for i in range(mini(level, 4)):
			m["feats"].append(str(pool[i]))
			Combatant.apply_feat_effects(m, str(pool[i]))
		if level >= GameState.MAX_LEVEL:
			var fin := str(cd.get("final_feat", ""))
			if fin != "":
				m["feats"].append(fin)
				Combatant.apply_feat_effects(m, fin)
		m["level"] = level
		m["max_hp"] = GameState.max_hp_with_feats(m)
		m["hp"] = m["max_hp"]
		m["mp"] = m["max_mp"]
		# A sensible default formation: melee up front, everyone else in the middle.
		m["start_position"] = Combatant.POS_FRONT if Combatant.is_melee_class(str(m["class"])) else Combatant.POS_MID
		out.append(m)
	return out

## Mirrors BattleController._setup_party: a battle copy with per-fight counters and charges.
func _battle_copy(persistent: Array) -> Array:
	var out: Array = []
	for member in persistent:
		var b = member.duplicate(true)
		b["is_player"] = true
		b["defending"] = false
		b["position"] = clampi(int(member.get("start_position", 0)), 0, 2)
		b["engaged_with"] = ""
		b["focus"] = 0
		b["blind_turns"] = 0
		b["stunned_turns"] = 0
		b["poison_turns"] = 0
		b["poison_damage"] = 0
		b["burn_turns"] = 0
		b["burn_damage"] = 0
		b["grants_advantage"] = false
		b["marked"] = false
		if b.get("class", "") == "Hechicera":
			b["premonition_roll"] = 20 if Combatant.has_feat_effect(b, "premonition_always_max") else randi_range(1, 20)
		if Combatant.has_feat_effect(b, "reroll_miss_charges"):
			b["lucky_charges"] = Combatant.max_feat_value(b, "reroll_miss_charges", 3)
		if Combatant.has_feat_effect(b, "stun_on_attack_charges"):
			b["martial_adept_charges"] = Combatant.sum_feat_value(b, "stun_on_attack_charges")
		if Combatant.has_feat_effect(b, "immobilize_charges"):
			b["grappler_charges"] = Combatant.sum_feat_value(b, "immobilize_charges")
		out.append(b)
	for m in out:
		if Combatant.has_feat_effect(m, "death_ward_charges"):
			for other in out:
				other["death_ward_charges"] = Combatant.sum_feat_value(m, "death_ward_charges")
			break
	return out

func _build_enemies(encounter_id: String) -> Array:
	var enc = DataLoader.get_encounter(encounter_id)
	var out: Array = []
	var ids = enc.get("enemies", [])
	for i in range(ids.size()):
		var ed = DataLoader.get_enemy(str(ids[i]))
		if ed.is_empty():
			continue
		var profile := str(ed.get("ai_profile", EnemyAI.DEFAULT_PROFILE))
		out.append({
			"id": str(ed["id"]) + "_" + str(i), "base_id": ed["id"], "name": ed["name"],
			"hp": ed.get("hp", 10), "max_hp": ed.get("hp", 10), "ca": ed.get("ca", 10),
			"attributes": ed.get("attributes", {}), "hit_die": ed.get("hit_die", 8),
			"attack_bonus": ed.get("attack_bonus", 0), "damage": ed.get("damage", "1d6"),
			"skills": ed.get("skills", []).duplicate(), "is_player": false, "defending": false,
			"ai_profile": profile, "position": EnemyAI.starting_position(profile),
			"engaged_with": "", "stunned_turns": 0, "poison_turns": 0, "poison_damage": 0,
			"burn_turns": 0, "burn_damage": 0, "mp": 999, "max_mp": 999, "feats": [],
		})
	return out

# --- Battle loop --------------------------------------------------------------------------

func simulate(persistent_party: Array, encounter_id: String) -> Dictionary:
	_party = _battle_copy(persistent_party)
	_enemies = _build_enemies(encounter_id)
	_is_boss = not bool(DataLoader.get_encounter(encounter_id).get("can_flee", true))
	_attacks_total = 0
	_attacks_on_protected = 0
	_damage_by_char = {}
	_rounds = 0

	var all: Array[Dictionary] = []
	all.append_array(_party)
	all.append_array(_enemies)
	_ts.setup(all)
	_apply_alert_feat()

	while _rounds < MAX_ROUNDS:
		if _all_dead(_enemies) or _all_dead(_party):
			break
		_rounds += 1
		_start_round()
		if _all_dead(_enemies) or _all_dead(_party):
			break
		_ts.start_new_round()
		while true:
			var current = _ts.get_current_combatant()
			if current.is_empty():
				break
			_prune_engagements()
			_force_engagement(current)
			if current.get("hp", 0) > 0:
				if current.get("is_player", false):
					_player_turn(current)
				else:
					_enemy_turn(current)
			if _all_dead(_enemies) or _all_dead(_party):
				break
			if not _ts.advance_turn():
				break

	var alive := 0
	var hp_sum := 0.0
	for p in _party:
		if p.get("hp", 0) > 0:
			alive += 1
		hp_sum += float(p.get("hp", 0)) / maxf(1.0, float(p.get("max_hp", 1)))
	# Write the battle's end state back so a gauntlet carries attrition forward.
	for i in range(persistent_party.size()):
		persistent_party[i]["hp"] = _party[i]["hp"]
		persistent_party[i]["mp"] = _party[i]["mp"]

	return {
		"win": _all_dead(_enemies) and not _all_dead(_party),
		"timeout": _rounds >= MAX_ROUNDS,
		"rounds": _rounds,
		"hp_pct": hp_sum / maxf(1.0, float(_party.size())),
		"deaths": _party.size() - alive,
		"attacks": _attacks_total,
		"attacks_protected": _attacks_on_protected,
		"damage_by_char": _damage_by_char.duplicate(),
	}

func _start_round() -> void:
	for c in _party + _enemies:
		c["defending"] = false
		c["grants_advantage"] = false
		if c.get("blind_turns", 0) > 0:
			c["blind_turns"] -= 1
		if c.get("hp", 0) > 0:
			if c.get("poison_turns", 0) > 0:
				Combatant.apply_damage(c, c.get("poison_damage", 0))
				c["poison_turns"] -= 1
			if c.get("hp", 0) > 0 and c.get("burn_turns", 0) > 0:
				Combatant.apply_damage(c, c.get("burn_damage", 0))
				c["burn_turns"] -= 1

func _all_dead(group: Array) -> bool:
	for c in group:
		if c.get("hp", 0) > 0:
			return false
	return true

func _prune_engagements() -> void:
	var all: Array = _party + _enemies
	for c in all:
		var locked := Combatant.engaged_target_id(c)
		if locked == "":
			continue
		var standing := false
		for other in all:
			if str(other.get("id", "")) == locked and other.get("hp", 0) > 0:
				standing = true
				break
		if not standing:
			c["engaged_with"] = ""

func _force_engagement(c: Dictionary) -> void:
	if c.get("hp", 0) <= 0 or Combatant.engaged_target_id(c) != "":
		return
	if int(c.get("position", 0)) != Combatant.POS_FRONT:
		return
	var is_player: bool = c.get("is_player", false)
	var t = Combatant.auto_engage_candidate(c, _enemies if is_player else _party, _party if is_player else _enemies)
	if not t.is_empty():
		c["engaged_with"] = str(t.get("id", ""))

func _apply_alert_feat() -> void:
	for p in _party:
		if not Combatant.has_feat_effect(p, "free_attack_on_start"):
			continue
		var targets := Combatant.legal_targets(p, _enemies)
		if targets.is_empty():
			continue
		var target = targets[randi_range(0, targets.size() - 1)]
		var result = Combatant.attack_roll(p, target, false, 0, _enemies)
		if result.hit:
			_hit(p, target, Combatant.apply_position_modifiers(result.damage, p, target))

func _hit(attacker: Dictionary, target: Dictionary, dmg: int) -> void:
	Combatant.apply_damage(target, dmg)
	if attacker.get("is_player", false):
		var n := str(attacker.get("name", "?"))
		_damage_by_char[n] = int(_damage_by_char.get(n, 0)) + dmg

func _move(c: Dictionary, to_pos: int, opponents: Array) -> void:
	if to_pos == int(c.get("position", 0)):
		return
	var partners := Combatant.engagement_partners(c, opponents)
	c["position"] = to_pos
	if not partners.is_empty():
		Combatant.clear_engagements(c, _party + _enemies)
		if not Combatant.has_feat_effect(c, "no_opportunity_attacks"):
			for a in partners:
				if c.get("hp", 0) <= 0:
					break
				var r = Combatant.attack_roll(a, c) if a.get("is_player", false) else Combatant.enemy_attack(a, c)
				if r.hit:
					_hit(a, c, Combatant.apply_position_modifiers(r.damage, a, c))
	if c.get("hp", 0) > 0 and to_pos == Combatant.POS_FRONT:
		_force_engagement(c)

# --- Player policy ------------------------------------------------------------------------
## Models a competent player: heal when someone is about to drop, keep melee in reach, spend the
## class skill when it beats a basic swing, and finish wounded targets. Not optimal play — the
## win rates below are what a reasonable human gets, which is the number that matters for tuning.

func _player_turn(actor: Dictionary) -> void:
	# 1. Emergency heal.
	var heal_skill := _skill_of(actor, "heal")
	if not heal_skill.is_empty() and int(actor.get("mp", 0)) >= int(heal_skill.get("mp_cost", 0)):
		var hurt = _most_hurt(_party)
		if not hurt.is_empty() and float(hurt["hp"]) / float(hurt["max_hp"]) < 0.45:
			Combatant.use_mp(actor, int(heal_skill.get("mp_cost", 0)))
			Combatant.apply_heal(hurt, Combatant.calculate_heal(actor, int(heal_skill.get("power", 0))))
			return

	# 2. A melee fighter stranded in the back rank walks forward instead of wasting the turn.
	if Combatant.is_melee_class(str(actor.get("class", ""))) and int(actor.get("position", 0)) == Combatant.POS_BACK:
		_move(actor, Combatant.POS_MID, _enemies)
		return

	var targets := Combatant.legal_targets(actor, _enemies)
	if targets.is_empty():
		# Nothing in reach: push forward if that could open something up, else brace.
		if Combatant.is_melee_class(str(actor.get("class", ""))) and int(actor.get("position", 0)) > Combatant.POS_FRONT:
			_move(actor, int(actor.get("position", 0)) - 1, _enemies)
		else:
			actor["defending"] = true
		return

	var target := _best_target(actor, targets)
	_attacks_total += 1
	if Combatant.is_protected(target, _enemies):
		_attacks_on_protected += 1

	# 3. Class skill when the MP is there and it beats a swing.
	var skill := _pick_offensive_skill(actor, targets.size())
	if not skill.is_empty() and Combatant.use_mp(actor, int(skill.get("mp_cost", 0))):
		_resolve_skill(actor, skill, target)
		return
	_basic_attack(actor, target)

func _basic_attack(actor: Dictionary, target: Dictionary) -> void:
	var use_prem: bool = str(actor.get("class", "")) == "Hechicera" and int(actor.get("premonition_roll", 0)) >= 15
	var forced: int = int(actor.get("premonition_roll", 0)) if use_prem else 0
	var result = Combatant.attack_roll(actor, target, false, forced, _enemies)
	if use_prem:
		actor["premonition_roll"] = 20 if Combatant.has_feat_effect(actor, "premonition_always_max") else randi_range(1, 20)
	if not result.hit and int(actor.get("lucky_charges", 0)) > 0:
		actor["lucky_charges"] = int(actor["lucky_charges"]) - 1
		result = Combatant.attack_roll(actor, target, false, 0, _enemies)
	if not result.hit:
		return
	var dmg = Combatant.apply_position_modifiers(result.damage, actor, target)
	if str(actor.get("class", "")) == "Warlock":
		dmg *= 2
	if str(actor.get("class", "")) == "Monje":
		actor["focus"] = mini(5, int(actor.get("focus", 0)) + 1)
	if str(actor.get("class", "")) == "Gunslinger":
		for e in _enemies:
			e["marked"] = (str(e.get("id", "")) == str(target.get("id", "")))
	_hit(actor, target, dmg)
	if int(actor.get("martial_adept_charges", 0)) > 0:
		actor["martial_adept_charges"] = int(actor["martial_adept_charges"]) - 1
		target["stunned_turns"] = int(target.get("stunned_turns", 0)) + 1
	elif int(actor.get("grappler_charges", 0)) > 0:
		actor["grappler_charges"] = int(actor["grappler_charges"]) - 1
		target["stunned_turns"] = int(target.get("stunned_turns", 0)) + 1

func _resolve_skill(actor: Dictionary, skill: Dictionary, target: Dictionary) -> void:
	var et := str(skill.get("effect_type", ""))
	var power := int(skill.get("power", 0))
	match et:
		"reckless":
			var r = Combatant.attack_roll(actor, target, true, 0, _enemies)
			if r.hit:
				_hit(actor, target, Combatant.apply_position_modifiers(r.damage, actor, target))
			actor["grants_advantage"] = true
		"flurry":
			var hits = maxi(1, int(actor.get("focus", 0)))
			actor["focus"] = 0
			for i in range(hits):
				if target.get("hp", 0) <= 0:
					break
				var r = Combatant.attack_roll(actor, target, false, 0, _enemies)
				if r.hit:
					_hit(actor, target, Combatant.apply_position_modifiers(r.damage, actor, target))
		"recoil":
			var r = Combatant.attack_roll(actor, target, false, 0, _enemies)
			if not r.hit:
				return
			var main = Combatant.apply_position_modifiers(r.damage, actor, target)
			for e in _enemies:
				e["marked"] = (str(e.get("id", "")) == str(target.get("id", "")))
			_hit(actor, target, main)
			var splash = maxi(1, main / 2)
			var others: Array = []
			for e in _enemies:
				if e.get("hp", 0) > 0 and str(e.get("id", "")) != str(target.get("id", "")):
					others.append(e)
			if others.size() > 0:
				_hit(actor, others[randi_range(0, others.size() - 1)], splash)
			elif target.get("hp", 0) > 0:
				_hit(actor, target, splash)
		"shadow":
			var r = Combatant.attack_roll(actor, target, true, 0, _enemies)
			if r.hit:
				_hit(actor, target, Combatant.apply_position_modifiers(r.damage, actor, target))
				if r.crit:
					target["blind_turns"] = randi_range(1, 3)
		"call_lathander":
			if randi_range(1, 20) == 20 and not _is_boss:
				var alive: Array = []
				for e in _enemies:
					if e.get("hp", 0) > 0:
						alive.append(e)
				if alive.size() > 0:
					var v = alive[randi_range(0, alive.size() - 1)]
					_hit(actor, v, int(v.get("hp", 0)))
		"physical":
			var r = Combatant.attack_roll(actor, target, false, 0, _enemies)
			if r.hit:
				_hit(actor, target, Combatant.apply_position_modifiers(r.damage + power, actor, target))
				_apply_dot(skill, target)
		_:
			if str(skill.get("target_type", "")) == "all_enemies":
				for e in _enemies:
					if e.get("hp", 0) <= 0:
						continue
					var d = Combatant.calculate_magical_damage(actor, e, power)
					d = int(d * Combatant.guard_damage_multiplier(actor, e, _enemies))
					_hit(actor, e, Combatant.apply_position_modifiers(d, actor, e))
					_apply_dot(skill, e)
			else:
				var d = Combatant.calculate_magical_damage(actor, target, power)
				d = int(d * Combatant.guard_damage_multiplier(actor, target, _enemies))
				_hit(actor, target, Combatant.apply_position_modifiers(d, actor, target))
				_apply_dot(skill, target)

func _apply_dot(skill: Dictionary, target: Dictionary) -> void:
	match str(skill.get("id", "")):
		"poison_blade":
			target["poison_turns"] = BattleController.POISON_DURATION
			target["poison_damage"] = BattleController.POISON_DAMAGE
		"fireball", "fire_breath":
			target["burn_turns"] = BattleController.BURN_DURATION
			target["burn_damage"] = BattleController.BURN_DAMAGE

func _skill_of(actor: Dictionary, effect_type: String) -> Dictionary:
	for sid in actor.get("skills", []):
		var s = DataLoader.get_skill(str(sid))
		if str(s.get("effect_type", "")) == effect_type:
			return s
	return {}

## Which class skill is worth the MP this turn. Deliberately conservative: the cleric hoards MP
## for heals, and the monk banks focus before spending it.
func _pick_offensive_skill(actor: Dictionary, enemy_count: int) -> Dictionary:
	var mp := int(actor.get("mp", 0))
	var best := {}
	for sid in actor.get("skills", []):
		var s = DataLoader.get_skill(str(sid))
		var et := str(s.get("effect_type", ""))
		if et in ["heal", "call_lathander"]:
			continue
		if mp < int(s.get("mp_cost", 0)):
			continue
		if et == "flurry" and int(actor.get("focus", 0)) < 3:
			continue
		if et == "recoil" and enemy_count < 2:
			continue
		# Keep enough in reserve to heal once more.
		if not _skill_of(actor, "heal").is_empty() and mp - int(s.get("mp_cost", 0)) < 8:
			continue
		best = s
	return best

func _most_hurt(group: Array) -> Dictionary:
	var out := {}
	var worst := 2.0
	for c in group:
		if c.get("hp", 0) <= 0:
			continue
		var r := float(c["hp"]) / maxf(1.0, float(c.get("max_hp", 1)))
		if r < worst:
			worst = r
			out = c
	return out

## Same shape as the enemy AI's reasoning: a kill beats everything, then the toll, then how hurt.
func _best_target(actor: Dictionary, targets: Array) -> Dictionary:
	var est := 8.0
	var best := {}
	var best_score := -INF
	for t in targets:
		var toll := Combatant.guard_damage_multiplier(actor, t, _enemies)
		var hp := maxf(1.0, float(t.get("hp", 1)))
		var score := 0.0
		if est * toll >= hp:
			score = 2.0
		else:
			score = toll * (1.0 + (1.0 - hp / maxf(1.0, float(t.get("max_hp", 1)))) * 0.5)
		if score > best_score:
			best_score = score
			best = t
	return best

# --- Enemy turn ---------------------------------------------------------------------------

func _enemy_turn(enemy: Dictionary) -> void:
	var action = EnemyAI.choose_action(enemy, _party, _enemies)
	match str(action.get("type", "attack")):
		"move":
			_move(enemy, int(action.get("target_position", 0)), _party)
		"pass":
			pass
		"attack":
			var t = action.get("target", {})
			if t.is_empty():
				return
			var r = Combatant.enemy_attack(enemy, t, _party)
			if r.hit:
				Combatant.apply_damage(t, Combatant.apply_position_modifiers(r.damage, enemy, t))
		"skill":
			var skill = action.get("skill", {})
			if not Combatant.use_mp(enemy, int(skill.get("mp_cost", 0))):
				return
			var power := int(skill.get("power", 0))
			var et := str(skill.get("effect_type", ""))
			if str(skill.get("target_type", "")) == "all_enemies":
				for t in _party:
					if t.get("hp", 0) <= 0:
						continue
					var d = Combatant.calculate_magical_damage(enemy, t, power)
					d = int(d * Combatant.guard_damage_multiplier(enemy, t, _party))
					Combatant.apply_damage(t, Combatant.apply_position_modifiers(d, enemy, t))
					_apply_dot(skill, t)
			else:
				var t = action.get("target", {})
				if t.is_empty():
					return
				if et == "heal":
					Combatant.apply_heal(t, Combatant.calculate_heal(enemy, power))
				elif et == "physical":
					var r = Combatant.attack_roll(enemy, t, false, 0, _party)
					if r.hit:
						Combatant.apply_damage(t, Combatant.apply_position_modifiers(r.damage + power, enemy, t))
						_apply_dot(skill, t)
				else:
					var d = Combatant.calculate_magical_damage(enemy, t, power)
					d = int(d * Combatant.guard_damage_multiplier(enemy, t, _party))
					Combatant.apply_damage(t, Combatant.apply_position_modifiers(d, enemy, t))
					_apply_dot(skill, t)

# --- Sweep --------------------------------------------------------------------------------

func _all_combos() -> Array:
	var ids: Array = []
	for c in DataLoader.get_all_characters():
		ids.append(str(c["id"]))
	ids.sort()
	var out: Array = []
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			for c in range(b + 1, ids.size()):
				for d in range(c + 1, ids.size()):
					out.append([ids[a], ids[b], ids[c], ids[d]])
	return out

func _run_sweep() -> void:
	seed(20260802)
	var combos := _all_combos()
	var encounters: Array = DataLoader.get_all_encounter_ids()
	encounters.sort()

	# --- Mode A: single encounter, rested party ---
	print("### MODE_A")
	for level in [1, 3, 5]:
		for enc in encounters:
			for combo in combos:
				var party := _build_party(combo, level)
				var r := simulate(party, str(enc))
				print("A|%d|%s|%s|%d|%d|%.3f|%d|%d|%d" % [
					level, enc, ",".join(combo), 1 if r["win"] else 0, r["rounds"],
					r["hp_pct"], r["deaths"], r["attacks"], r["attacks_protected"]])

	# --- Mode B: gauntlet with persistent attrition and 3 rests ---
	print("### MODE_B")
	var run_order: Array = [
		"encounter_green_slime", "encounter_hallway", "encounter_giant_crayfish",
		"encounter_bugbears", "encounter_gray_ooze", "encounter_sphinx",
		"encounter_giant_scorpions", "encounter_shadows", "encounter_ogres",
		"encounter_gargoyles", "encounter_wights", "encounter_ghouls",
		"encounter_snarla", "encounter_kelpies", "encounter_golem",
		"encounter_manticores", "encounter_flesh_golems", "encounter_burket",
		"encounter_sir_bluto", "encounter_qesnef", "encounter_vampire_ctenmiir",
		"encounter_boss", "encounter_efreet_duo",
	]
	for combo in combos:
		for attempt in range(6):
			var party := _build_party(combo, 1)
			var rests := GameState.MAX_REST_CHARGES
			var xp := 0
			var cleared := 0
			var died_at := ""
			var potions := 3
			for enc in run_order:
				# Between fights a real player patches up from the pause menu before spending a
				# rest charge: the cleric's heal costs MP, potions are a limited stock of 3, and
				# only when both are exhausted is a rest worth burning.
				potions = _recover_between_fights(party, potions)
				var weakest := _most_hurt(party)
				if rests > 0 and not weakest.is_empty() \
						and float(weakest["hp"]) / float(weakest["max_hp"]) < REST_THRESHOLD:
					rests -= 1
					for m in party:
						m["hp"] = m["max_hp"]
						m["mp"] = m["max_mp"]
				var r := simulate(party, str(enc))
				if not r["win"]:
					died_at = str(enc)
					break
				cleared += 1
				xp += int(DataLoader.get_encounter(str(enc)).get("rewards", {}).get("xp", 0))
				# Level up: HP/MP fully restored, feats gained (mirrors GameState.check_level_ups).
				var target_level := 1
				for i in range(1, GameState.XP_LEVEL_THRESHOLDS.size()):
					if xp >= GameState.XP_LEVEL_THRESHOLDS[i]:
						target_level = i + 1
				if target_level > int(party[0].get("level", 1)):
					party = _relevel(party, target_level)
			print("B|%s|%d|%d|%d|%d|%s" % [",".join(combo), attempt, cleared, run_order.size(), rests, died_at])

## Out-of-combat patching up, in the order a player would actually do it: free-ish MP healing
## first, then the finite potions, leaving rest charges as the last resort. Returns potions left.
func _recover_between_fights(party: Array, potions: int) -> int:
	for i in range(12):
		var hurt := _most_hurt(party)
		if hurt.is_empty() or float(hurt["hp"]) / float(hurt["max_hp"]) >= 0.6:
			break
		var healer := {}
		for m in party:
			var hs := _skill_of(m, "heal")
			if m.get("hp", 0) > 0 and not hs.is_empty() and int(m.get("mp", 0)) >= int(hs.get("mp_cost", 0)):
				healer = m
				break
		if healer.is_empty():
			break
		var skill := _skill_of(healer, "heal")
		Combatant.use_mp(healer, int(skill.get("mp_cost", 0)))
		Combatant.apply_heal(hurt, Combatant.calculate_heal(healer, int(skill.get("power", 0))))
	while potions > 0:
		var hurt := _most_hurt(party)
		if hurt.is_empty() or float(hurt["hp"]) / float(hurt["max_hp"]) >= 0.5:
			break
		Combatant.apply_heal(hurt, 30)
		potions -= 1
	return potions

## Rebuilds the party at a higher level, keeping the feats already chosen and adding the new ones,
## then fully restoring — same as the real level-up.
func _relevel(party: Array, level: int) -> Array:
	for m in party:
		var cd = DataLoader.get_character(str(m["id"]))
		var owned: Array = m.get("feats", [])
		var want := mini(level, 4)
		var pool: Array = cd.get("feat_pool", []).duplicate()
		pool.shuffle()
		for fid in pool:
			if owned.size() >= want:
				break
			if not owned.has(str(fid)):
				owned.append(str(fid))
				Combatant.apply_feat_effects(m, str(fid))
		if level >= GameState.MAX_LEVEL:
			var fin := str(cd.get("final_feat", ""))
			if fin != "" and not owned.has(fin):
				owned.append(fin)
				Combatant.apply_feat_effects(m, fin)
		m["level"] = level
		m["max_hp"] = GameState.max_hp_with_feats(m)
		m["hp"] = m["max_hp"]
		m["mp"] = m["max_mp"]
	return party
