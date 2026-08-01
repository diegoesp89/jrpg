extends Node
class_name BattleController
## BattleController — Orchestrates the entire battle flow

signal battle_ended(result: String)  # "victory", "defeat", "fled"
signal action_performed(log_text: String)
signal turn_changed(combatant: Dictionary, is_player: bool)
signal hp_updated()
signal damage_dealt(target: Dictionary, amount: int, is_heal: bool)

var _party: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []
var _turn_system: TurnSystem = null
var _encounter_data: Dictionary = {}
var _battle_active: bool = false

# Player action selection state
var _waiting_for_player: bool = false
var _selected_action: Dictionary = {}

# Persistent damage-over-time durations/amounts, applied once per round in _start_round()
# alongside blind_turns — see _apply_dot_from_skill().
const POISON_DURATION := 3
const POISON_DAMAGE := 4
const BURN_DURATION := 3
const BURN_DAMAGE := 6

func _ready() -> void:
	_turn_system = TurnSystem.new()
	add_child(_turn_system)

func start_battle(encounter_id: String) -> void:
	_encounter_data = DataLoader.get_encounter(encounter_id)
	if _encounter_data.is_empty():
		push_error("BattleController: encounter not found: %s" % encounter_id)
		battle_ended.emit("victory")
		return

	_setup_party()
	_setup_enemies()
	_battle_active = true

	action_performed.emit("--- Comienza el combate! ---")
	if GameState.current_intro_message != "":
		action_performed.emit(GameState.current_intro_message)
	_apply_alert_feat()

	# Combine all combatants for turn system
	var all_combatants: Array[Dictionary] = []
	all_combatants.append_array(_party)
	all_combatants.append_array(_enemies)
	_turn_system.setup(all_combatants)

	_start_round()

func _setup_party() -> void:
	_party.clear()
	for member in GameState.party:
		# Create battle copy
		var battle_member = member.duplicate(true)
		battle_member["is_player"] = true
		battle_member["defending"] = false
		battle_member["position"] = 0  # adelante, por defecto al empezar cada combate
		battle_member["focus"] = 0
		battle_member["blind_turns"] = 0
		battle_member["stunned_turns"] = 0
		battle_member["poison_turns"] = 0
		battle_member["poison_damage"] = 0
		battle_member["burn_turns"] = 0
		battle_member["burn_damage"] = 0
		battle_member["grants_advantage"] = false
		battle_member["marked"] = false
		if battle_member.get("class", "") == "Hechicera":
			battle_member["premonition_roll"] = randi_range(1, 20)
		if Combatant.has_feat_effect(battle_member, "reroll_miss_charges"):
			battle_member["lucky_charges"] = Combatant.max_feat_value(battle_member, "reroll_miss_charges", 3)
		if Combatant.has_feat_effect(battle_member, "stun_on_attack_charges"):
			battle_member["martial_adept_charges"] = Combatant.sum_feat_value(battle_member, "stun_on_attack_charges")
		if Combatant.has_feat_effect(battle_member, "immobilize_charges"):
			battle_member["grappler_charges"] = Combatant.sum_feat_value(battle_member, "immobilize_charges")
		_party.append(battle_member)

func _setup_enemies() -> void:
	_enemies.clear()
	var enemy_ids = _encounter_data.get("enemies", [])
	for i in range(enemy_ids.size()):
		var enemy_data = DataLoader.get_enemy(enemy_ids[i])
		if enemy_data.is_empty():
			continue
		var battle_enemy = {
			"id": enemy_data["id"] + "_" + str(i),
			"base_id": enemy_data["id"],
			"name": enemy_data["name"],
			"hp": enemy_data.get("hp", 10),
			"max_hp": enemy_data.get("hp", 10),
			"ca": enemy_data.get("ca", 10),
			"attributes": enemy_data.get("attributes", {}),
			"hit_die": enemy_data.get("hit_die", 8),
			"attack_bonus": enemy_data.get("attack_bonus", 0),
			"damage": enemy_data.get("damage", "1d6"),
			"skills": enemy_data.get("skills", []).duplicate(),
			"is_player": false,
			"defending": false,
			"position": 0,
			"stunned_turns": 0,
			"poison_turns": 0,
			"poison_damage": 0,
			"burn_turns": 0,
			"burn_damage": 0,
			# Enemies don't manage MP as a real resource (no regen, no player-facing bar) — some
			# of their skills are shared with player classes (smash, fireball, fire_breath) which
			# now cost MP for balance reasons. Without this, Combatant.use_mp's check against a
			# missing "mp" key (defaults to 0) would silently block enemies from ever casting them.
			"mp": 999,
			"max_mp": 999,
		}
		_enemies.append(battle_enemy)

func _start_round() -> void:
	# Reset defend flags and per-round status effects
	for c in _party + _enemies:
		c["defending"] = false
		c["grants_advantage"] = false
		if c.get("blind_turns", 0) > 0:
			c["blind_turns"] -= 1
		if c.get("hp", 0) > 0:
			if c.get("poison_turns", 0) > 0:
				Combatant.apply_damage(c, c.get("poison_damage", 0))
				damage_dealt.emit(c, c.get("poison_damage", 0), false)
				c["poison_turns"] -= 1
				action_performed.emit("%s sufre %d de daño por veneno! (%d turno(s) restante(s))" % [c["name"], c.get("poison_damage", 0), c["poison_turns"]])
			if c.get("hp", 0) > 0 and c.get("burn_turns", 0) > 0:
				Combatant.apply_damage(c, c.get("burn_damage", 0))
				damage_dealt.emit(c, c.get("burn_damage", 0), false)
				c["burn_turns"] -= 1
				action_performed.emit("%s sufre %d de daño por quemadura! (%d turno(s) restante(s))" % [c["name"], c.get("burn_damage", 0), c["burn_turns"]])
	hp_updated.emit()

	_turn_system.start_new_round()
	_process_current_turn()

## poison_blade inflicts poison, fireball/fire_breath inflict burn — checked by skill id (not
## effect_type, which is shared by many non-DOT skills). Returns a short suffix to append to
## the existing damage log line, or "" if this skill doesn't apply a DOT.
func _apply_dot_from_skill(skill: Dictionary, target: Dictionary) -> String:
	match skill.get("id", ""):
		"poison_blade":
			target["poison_turns"] = POISON_DURATION
			target["poison_damage"] = POISON_DAMAGE
			return " (envenenada)"
		"fireball", "fire_breath":
			target["burn_turns"] = BURN_DURATION
			target["burn_damage"] = BURN_DAMAGE
			return " (quemada)"
	return ""

func _process_current_turn() -> void:
	if not _battle_active:
		return

	# Check win/lose
	if _all_enemies_dead():
		_victory()
		return
	if _all_party_dead():
		_defeat()
		return

	var current = _turn_system.get_current_combatant()
	if current.is_empty():
		_start_round()
		return

	if current.get("is_player", false):
		# Player turn - wait for input
		_waiting_for_player = true
		turn_changed.emit(current, true)
	else:
		# Enemy turn - AI decides
		_waiting_for_player = false
		turn_changed.emit(current, false)
		await get_tree().create_timer(0.5).timeout
		_execute_enemy_turn(current)

func _execute_enemy_turn(enemy: Dictionary) -> void:
	var action = EnemyAI.choose_action(enemy, _party, _enemies)

	match action.get("type", "attack"):
		"attack":
			var target = action.get("target", {})
			if target.is_empty():
				_next_turn()
				return
			
			var result = Combatant.enemy_attack(enemy, target)
			
			if result.hit:
				var final_dmg = Combatant.apply_position_modifiers(result.damage, enemy, target)
				Combatant.apply_damage(target, final_dmg)
				damage_dealt.emit(target, final_dmg, false)
				var dmg_str = "daño!" if not result.crit else "daño CRÍTICO!"
				action_performed.emit("%s: %d(1d20)+%d = %d vs %d CA -> Golpe! Dañó %d a %s" % [enemy["name"], result.roll, result.bonus, result.total, target.get("ca", 10), final_dmg, target["name"]])
			else:
				action_performed.emit("%s: %d(1d20)+%d = %d vs %d CA -> %s" % [enemy["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])
		"skill":
			var skill = action.get("skill", {})
			var skill_name = skill.get("name", "???")
			if not Combatant.use_mp(enemy, skill.get("mp_cost", 0)):
				# Not enough MP — fall back to basic attack
				var fallback_target = action.get("target", {})
				if fallback_target.is_empty():
					fallback_target = action.get("targets", [{}])[0] if action.get("targets", []).size() > 0 else {}
				if fallback_target.is_empty():
					_next_turn()
					return
				var dmg = Combatant.calculate_physical_damage(enemy, fallback_target)
				dmg = Combatant.apply_position_modifiers(dmg, enemy, fallback_target)
				Combatant.apply_damage(fallback_target, dmg)
				damage_dealt.emit(fallback_target, dmg, false)
				action_performed.emit("%s no tiene MP! Ataca a %s por %d de daño!" % [enemy["name"], fallback_target["name"], dmg])
				hp_updated.emit()
				await get_tree().create_timer(0.8).timeout
				_next_turn()
				return

			var skill_power = skill.get("power", 0)
			if skill.get("target_type", "") == "all_enemies":
				# AoE against party
				var stat_mod = Combatant.get_caster_stat_mod(enemy)
				var targets = action.get("targets", [])
				var hit_log: Array = []
				for t in targets:
					var dmg = Combatant.calculate_magical_damage(enemy, t, skill_power)
					dmg = Combatant.apply_position_modifiers(dmg, enemy, t)
					Combatant.apply_damage(t, dmg)
					damage_dealt.emit(t, dmg, false)
					hit_log.append("%s -%d%s" % [t["name"], dmg, _apply_dot_from_skill(skill, t)])
				action_performed.emit("%s usa %s (%d poder+%d mod cada uno): %s" % [enemy["name"], skill_name, skill_power, stat_mod, ", ".join(hit_log)])
			else:
				var target = action.get("target", {})
				if target.is_empty():
					_next_turn()
					return
				if skill.get("effect_type", "") == "heal":
					var stat_mod = Combatant.get_caster_stat_mod(enemy)
					var heal = Combatant.calculate_heal(enemy, skill_power)
					Combatant.apply_heal(target, heal)
					damage_dealt.emit(target, heal, true)
					action_performed.emit("%s usa %s en %s: %d(poder)+%d(mod) = %d HP curados!" % [enemy["name"], skill_name, target["name"], skill_power, stat_mod, heal])
				elif skill.get("effect_type", "") == "physical":
					var result = Combatant.attack_roll(enemy, target)
					if result.hit:
						var dmg = Combatant.apply_position_modifiers(result.damage + skill_power, enemy, target)
						Combatant.apply_damage(target, dmg)
						damage_dealt.emit(target, dmg, false)
						var dot_suffix = _apply_dot_from_skill(skill, target)
						action_performed.emit("%s usa %s en %s: %d(1d20)+%d = %d vs %d CA -> Golpe! %d de daño!%s" % [enemy["name"], skill_name, target["name"], result.roll, result.bonus, result.total, target.get("ca", 10), dmg, dot_suffix])
					else:
						action_performed.emit("%s usa %s en %s: %d(1d20)+%d = %d vs %d CA -> %s" % [enemy["name"], skill_name, target["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])
				else:
					var stat_mod = Combatant.get_caster_stat_mod(enemy)
					var dmg = Combatant.calculate_magical_damage(enemy, target, skill_power)
					dmg = Combatant.apply_position_modifiers(dmg, enemy, target)
					Combatant.apply_damage(target, dmg)
					damage_dealt.emit(target, dmg, false)
					var dot_suffix = _apply_dot_from_skill(skill, target)
					action_performed.emit("%s usa %s en %s: %d(poder)+%d(mod) = %d de daño!%s" % [enemy["name"], skill_name, target["name"], skill_power, stat_mod, dmg, dot_suffix])

	hp_updated.emit()
	await get_tree().create_timer(0.8).timeout
	_next_turn()

## Called by BattleUI when player selects an action
func player_action(action: Dictionary) -> void:
	if not _waiting_for_player:
		return
	_waiting_for_player = false

	var current = _turn_system.get_current_combatant()

	match action.get("type", ""):
		"attack":
			var target = action.get("target", {})
			if target.is_empty():
				_waiting_for_player = true
				return
			
			if Combatant.is_melee_class(current.get("class", "")) and current.get("position", 0) == 2:
				action_performed.emit("%s no puede atacar cuerpo a cuerpo desde la retaguardia!" % current["name"])
				_waiting_for_player = true
				return

			var use_premonition = action.get("use_premonition", false)
			var forced_roll = current.get("premonition_roll", 0) if use_premonition else 0
			var result = Combatant.attack_roll(current, target, false, forced_roll)
			if use_premonition and current.get("class", "") == "Hechicera":
				current["premonition_roll"] = randi_range(1, 20)

			if not result.hit and current.get("lucky_charges", 0) > 0:
				current["lucky_charges"] -= 1
				action_performed.emit("%s usa Afortunada para re-tirar el fallo!" % current["name"])
				result = Combatant.attack_roll(current, target)

			if result.hit:
				var final_dmg = Combatant.apply_position_modifiers(result.damage, current, target)
				if current.get("class", "") == "Warlock":
					final_dmg *= 2  # Spiritual Weapon
				if current.get("class", "") == "Monje":
					current["focus"] = mini(5, current.get("focus", 0) + 1)
				if current.get("class", "") == "Gunslinger":
					for e in _enemies:
						e["marked"] = (e.get("id", "") == target.get("id", ""))
				Combatant.apply_damage(target, final_dmg)
				damage_dealt.emit(target, final_dmg, false)
				var dmg_str = "daño!" if not result.crit else "daño CRÍTICO!"
				action_performed.emit("%s: %d(1d20)+%d(Fue) = %d vs %d CA -> Golpe! Dañó %d a %s" % [current["name"], result.roll, result.bonus, result.total, target.get("ca", 10), final_dmg, target["name"]])
				if current.get("martial_adept_charges", 0) > 0:
					current["martial_adept_charges"] -= 1
					target["stunned_turns"] = target.get("stunned_turns", 0) + 1
					action_performed.emit("%s usa Adepta Marcial: %s queda aturdida y pierde su próximo turno!" % [current["name"], target["name"]])
				elif current.get("grappler_charges", 0) > 0:
					current["grappler_charges"] -= 1
					target["stunned_turns"] = target.get("stunned_turns", 0) + 1
					action_performed.emit("%s usa Forcejeadora: %s queda inmovilizada y pierde su próximo turno!" % [current["name"], target["name"]])
			else:
				action_performed.emit("%s: %d(1d20)+%d(Fue) = %d vs %d CA -> %s" % [current["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])

		"skill":
			var skill = action.get("skill", {})
			if not Combatant.use_mp(current, skill.get("mp_cost", 0)):
				action_performed.emit("No hay suficiente MP!")
				_waiting_for_player = true
				return

			var skill_name = skill.get("name", "???")
			var effect_type = skill.get("effect_type", "")
			var power = skill.get("power", 0)
			if effect_type == "heal":
				var target = action.get("target", {})
				var stat_mod = Combatant.get_caster_stat_mod(current)
				var heal = Combatant.calculate_heal(current, power)
				Combatant.apply_heal(target, heal)
				damage_dealt.emit(target, heal, true)
				action_performed.emit("%s usa %s en %s: %d(poder)+%d(mod) = %d HP curados!" % [current["name"], skill_name, target["name"], power, stat_mod, heal])
			elif effect_type == "reckless":
				_do_reckless(current, action.get("target", {}))
			elif effect_type == "flurry":
				_do_flurry(current, action.get("target", {}))
			elif effect_type == "recoil":
				_do_recoil(current, action.get("target", {}))
			elif effect_type == "shadow":
				_do_shadow(current, action.get("target", {}))
			elif effect_type == "call_lathander":
				_do_call_lathander(current)
			elif skill.get("target_type", "") == "all_enemies":
				var stat_mod = Combatant.get_caster_stat_mod(current)
				var hit_log: Array = []
				for e in _enemies:
					if e.get("hp", 0) > 0:
						var dmg = Combatant.calculate_magical_damage(current, e, power)
						dmg = Combatant.apply_position_modifiers(dmg, current, e)
						Combatant.apply_damage(e, dmg)
						damage_dealt.emit(e, dmg, false)
						hit_log.append("%s -%d%s" % [e["name"], dmg, _apply_dot_from_skill(skill, e)])
				action_performed.emit("%s usa %s (%d poder+%d mod cada uno): %s" % [current["name"], skill_name, power, stat_mod, ", ".join(hit_log)])
			else:
				var target = action.get("target", {})
				if effect_type == "physical":
					var result = Combatant.attack_roll(current, target)
					if result.hit:
						var dmg = Combatant.apply_position_modifiers(result.damage + power, current, target)
						Combatant.apply_damage(target, dmg)
						damage_dealt.emit(target, dmg, false)
						var dot_suffix = _apply_dot_from_skill(skill, target)
						action_performed.emit("%s usa %s en %s: %d(1d20)+%d = %d vs %d CA -> Golpe! %d de daño!%s" % [current["name"], skill_name, target["name"], result.roll, result.bonus, result.total, target.get("ca", 10), dmg, dot_suffix])
					else:
						action_performed.emit("%s usa %s en %s: %d(1d20)+%d = %d vs %d CA -> %s" % [current["name"], skill_name, target["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])
				else:
					var stat_mod = Combatant.get_caster_stat_mod(current)
					var dmg = Combatant.calculate_magical_damage(current, target, power)
					dmg = Combatant.apply_position_modifiers(dmg, current, target)
					Combatant.apply_damage(target, dmg)
					damage_dealt.emit(target, dmg, false)
					var dot_suffix = _apply_dot_from_skill(skill, target)
					action_performed.emit("%s usa %s en %s: %d(poder)+%d(mod) = %d de daño!%s" % [current["name"], skill_name, target["name"], power, stat_mod, dmg, dot_suffix])

		"defend":
			current["defending"] = true
			action_performed.emit("%s se defiende!" % current["name"])

		"move":
			var target_position: int = action.get("target_position", 0)
			var position_names = ["adelante", "medio", "retaguardia"]
			current["position"] = target_position
			action_performed.emit("%s se mueve a la posición %s!" % [current["name"], position_names[target_position]])
			if Combatant.has_feat_effect(current, "free_move"):
				action_performed.emit("%s usa Móvil: cambiar de posición no gasta el turno!" % current["name"])
				_waiting_for_player = true
				return

		"item":
			var item = action.get("item", {})
			var target = action.get("target", {})
			if item.get("effect", "") == "heal":
				var heal_amount = int(item.get("power", 30) * current.get("heal_multiplier", 1.0))
				Combatant.apply_heal(target, heal_amount)
				damage_dealt.emit(target, heal_amount, true)
				GameState.remove_item(item["id"])
				action_performed.emit("%s usa %s en %s!" % [current["name"], item["name"], target["name"]])

		"flee":
			if not can_flee():
				action_performed.emit("No se puede huir de este combate!")
				_waiting_for_player = true
				return
			var chance = Combatant.calculate_flee_chance(_party, _enemies)
			if randf() < chance / 100.0:
				action_performed.emit("Huida exitosa!")
				await get_tree().create_timer(0.5).timeout
				_flee()
				return
			else:
				action_performed.emit("No se pudo huir!")

	hp_updated.emit()
	await get_tree().create_timer(0.5).timeout
	_next_turn()

## "Alerta" feat: at the very start of the battle, before initiative even matters, each
## party member with this feat gets one free basic attack against a random alive enemy.
func _apply_alert_feat() -> void:
	for p in _party:
		if not Combatant.has_feat_effect(p, "free_attack_on_start"):
			continue
		var alive_enemies: Array = []
		for e in _enemies:
			if e.get("hp", 0) > 0:
				alive_enemies.append(e)
		if alive_enemies.is_empty():
			return
		var target = alive_enemies[randi_range(0, alive_enemies.size() - 1)]
		var result = Combatant.attack_roll(p, target)
		if result.hit:
			var final_dmg = Combatant.apply_position_modifiers(result.damage, p, target)
			Combatant.apply_damage(target, final_dmg)
			damage_dealt.emit(target, final_dmg, false)
			action_performed.emit("%s (Alerta): %d(1d20)+%d = %d vs %d CA -> Golpe! %d de daño de sorpresa a %s" % [p["name"], result.roll, result.bonus, result.total, target.get("ca", 10), final_dmg, target["name"]])
		else:
			action_performed.emit("%s (Alerta): %d(1d20)+%d = %d vs %d CA -> %s" % [p["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])

# --- Signature class abilities ---

func _do_reckless(attacker: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var result = Combatant.attack_roll(attacker, target, true)
	if result.hit:
		var final_dmg = Combatant.apply_position_modifiers(result.damage, attacker, target)
		Combatant.apply_damage(target, final_dmg)
		damage_dealt.emit(target, final_dmg, false)
		action_performed.emit("%s (Temerario, ventaja): %d(1d20)+%d = %d vs %d CA -> Golpe! %d de daño a %s" % [attacker["name"], result.roll, result.bonus, result.total, target.get("ca", 10), final_dmg, target["name"]])
	else:
		action_performed.emit("%s (Temerario, ventaja): %d(1d20)+%d = %d vs %d CA -> %s" % [attacker["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])
	attacker["grants_advantage"] = true

func _do_flurry(attacker: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var hits = maxi(1, attacker.get("focus", 0))
	attacker["focus"] = 0
	var total_dmg = 0
	var rolls_log: Array = []
	for i in range(hits):
		if target.get("hp", 0) <= 0:
			break
		var result = Combatant.attack_roll(attacker, target)
		if result.hit:
			var final_dmg = Combatant.apply_position_modifiers(result.damage, attacker, target)
			Combatant.apply_damage(target, final_dmg)
			damage_dealt.emit(target, final_dmg, false)
			total_dmg += final_dmg
			rolls_log.append("%d(1d20)+%d=%d✓-%d" % [result.roll, result.bonus, result.total, final_dmg])
		else:
			rolls_log.append("%d(1d20)+%d=%d✗" % [result.roll, result.bonus, result.total])
	action_performed.emit("%s desata Ráfaga (%d golpes) en %s: [%s] -> %d de daño total" % [attacker["name"], hits, target["name"], ", ".join(rolls_log), total_dmg])

func _do_recoil(attacker: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var result = Combatant.attack_roll(attacker, target)
	if not result.hit:
		action_performed.emit("%s (Retroceso): %d(1d20)+%d = %d vs %d CA -> %s" % [attacker["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])
		return

	var main_dmg = Combatant.apply_position_modifiers(result.damage, attacker, target)
	for e in _enemies:
		e["marked"] = (e.get("id", "") == target.get("id", ""))
	Combatant.apply_damage(target, main_dmg)
	damage_dealt.emit(target, main_dmg, false)

	var recoil_dmg = maxi(1, main_dmg / 2)
	var other_targets: Array = []
	for e in _enemies:
		if e.get("hp", 0) > 0 and e.get("id", "") != target.get("id", ""):
			other_targets.append(e)

	var roll_str = "%d(1d20)+%d = %d vs %d CA -> Golpe!" % [result.roll, result.bonus, result.total, target.get("ca", 10)]
	if other_targets.size() > 0:
		var other = other_targets[randi_range(0, other_targets.size() - 1)]
		Combatant.apply_damage(other, recoil_dmg)
		damage_dealt.emit(other, recoil_dmg, false)
		action_performed.emit("%s (Retroceso): %s %d daño a %s. El retroceso (mitad) golpea a %s: %d daño extra!" % [attacker["name"], roll_str, main_dmg, target["name"], other["name"], recoil_dmg])
	elif target.get("hp", 0) > 0:
		Combatant.apply_damage(target, recoil_dmg)
		damage_dealt.emit(target, recoil_dmg, false)
		action_performed.emit("%s (Retroceso): %s %d daño a %s. Al ser el único enemigo, el retroceso (mitad) también lo golpea: %d daño extra!" % [attacker["name"], roll_str, main_dmg, target["name"], recoil_dmg])
	else:
		action_performed.emit("%s (Retroceso): %s %d daño a %s!" % [attacker["name"], roll_str, main_dmg, target["name"]])

func _do_shadow(attacker: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var result = Combatant.attack_roll(attacker, target, true)
	if result.hit:
		var final_dmg = Combatant.apply_position_modifiers(result.damage, attacker, target)
		Combatant.apply_damage(target, final_dmg)
		damage_dealt.emit(target, final_dmg, false)
		var crit_str = " ¡CRÍTICO!" if result.crit else ""
		var blind_msg = ""
		if result.crit:
			target["blind_turns"] = randi_range(1, 3)
			blind_msg = " ¡%s queda ciego %d turnos!" % [target["name"], target["blind_turns"]]
		action_performed.emit("%s (Sombra, ventaja): %d(1d20)+%d = %d vs %d CA -> Golpe!%s %d de daño a %s.%s" % [attacker["name"], result.roll, result.bonus, result.total, target.get("ca", 10), crit_str, final_dmg, target["name"], blind_msg])
	else:
		action_performed.emit("%s (Sombra, ventaja): %d(1d20)+%d = %d vs %d CA -> %s" % [attacker["name"], result.roll, result.bonus, result.total, target.get("ca", 10), result.message])

func _do_call_lathander(caster: Dictionary) -> void:
	var roll = randi_range(1, 20)
	if roll == 20 and not is_boss_encounter():
		var alive_enemies: Array = []
		for e in _enemies:
			if e.get("hp", 0) > 0:
				alive_enemies.append(e)
		if alive_enemies.size() > 0:
			var victim = alive_enemies[randi_range(0, alive_enemies.size() - 1)]
			var victim_hp = victim.get("hp", 0)
			Combatant.apply_damage(victim, victim_hp)
			damage_dealt.emit(victim, victim_hp, false)
			action_performed.emit("%s invoca a Lathander (¡20 natural!) y elimina a %s al instante!" % [caster["name"], victim["name"]])
			return
	action_performed.emit("%s invoca a Lathander... (tirada: %d, sin efecto)" % [caster["name"], roll])

func _next_turn() -> void:
	if not _battle_active:
		return

	if _all_enemies_dead():
		_victory()
		return
	if _all_party_dead():
		_defeat()
		return

	if _turn_system.advance_turn():
		_process_current_turn()
	else:
		_start_round()

func _all_enemies_dead() -> bool:
	for e in _enemies:
		if e.get("hp", 0) > 0:
			return false
	return true

func _all_party_dead() -> bool:
	for p in _party:
		if p.get("hp", 0) > 0:
			return false
	return true

func _victory() -> void:
	_battle_active = false
	var rewards = _encounter_data.get("rewards", {})
	var xp = rewards.get("xp", 0)
	var gold = rewards.get("gold", 0)
	GameState.add_xp(xp)
	GameState.add_gold(gold)
	GameState.check_level_ups()

	action_performed.emit("--- Victoria! +%d XP, +%d Oro ---" % [xp, gold])
	if GameState.current_death_message != "":
		action_performed.emit(GameState.current_death_message)

	_grant_enemy_drops()

	# Sync party HP/MP back to GameState
	_sync_party_to_gamestate()

	# Auto-save at this safe checkpoint. return_position is exactly where exploration will
	# resume (set by GameState.prepare_combat before the battle started), so no scene-tree
	# player lookup is needed here.
	SaveManager.save_game(DataLoader.get_current_map_path(), GameState.return_position)

	await get_tree().create_timer(1.5).timeout
	battle_ended.emit("victory")

## Guaranteed item drops per defeated enemy INSTANCE (not per unique enemy type) — if the
## encounter had 2 skeletons and each drops a potion, the player gets 2 potions.
func _grant_enemy_drops() -> void:
	for enemy in _enemies:
		var enemy_def = DataLoader.get_enemy(enemy.get("base_id", ""))
		for item_id in enemy_def.get("item_drops", []):
			GameState.add_item(item_id, 1)
			action_performed.emit("%s dropea: %s" % [enemy["name"], DataLoader.get_item(item_id).get("name", item_id)])

func _defeat() -> void:
	_battle_active = false
	action_performed.emit("--- Derrota... ---")
	await get_tree().create_timer(1.5).timeout
	battle_ended.emit("defeat")

func _flee() -> void:
	_battle_active = false
	_sync_party_to_gamestate()
	battle_ended.emit("fled")

func _sync_party_to_gamestate() -> void:
	var party_state: Array = []
	for p in _party:
		party_state.append({
			"id": p["id"],
			"hp": p["hp"],
			"mp": p.get("mp", 0),
		})
	GameState.restore_party_from_combat(party_state)

func get_party() -> Array:
	return _party

func get_enemies() -> Array:
	return _enemies

func get_turn_system() -> Node:
	return _turn_system

func is_waiting_for_player() -> bool:
	return _waiting_for_player

func is_boss_encounter() -> bool:
	return bool(_encounter_data.get("is_boss", false))

## Whether the Flee action is usable in this encounter. Bosses and the sphinx guardian fight
## are both unfleeable (set via "can_flee": false in encounters.json) even though the sphinx
## isn't itself a boss (is_boss_encounter() stays false for her — she's not immune to the
## natural-20 Call Lathander instakill, just not something you can run away from).
func can_flee() -> bool:
	return bool(_encounter_data.get("can_flee", true))
