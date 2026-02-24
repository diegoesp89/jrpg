extends Node
## BattleController — Orchestrates the entire battle flow.
## Loaded as part of Battle.tscn.

signal battle_ended(result: String)  # "victory", "defeat", "fled"
signal action_performed(log_text: String)
signal turn_changed(combatant: Dictionary, is_player: bool)
signal hp_updated()

var _party: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []
var _turn_system: TurnSystem = null
var _encounter_data: Dictionary = {}
var _battle_active: bool = false

# Player action selection state
var _waiting_for_player: bool = false
var _selected_action: Dictionary = {}

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
			"hp": enemy_data["stats"]["hp"],
			"max_hp": enemy_data["stats"]["hp"],
			"mp": enemy_data["stats"].get("mp", 0),
			"max_mp": enemy_data["stats"].get("mp", 0),
			"atk": enemy_data["stats"]["atk"],
			"def": enemy_data["stats"]["def"],
			"mag": enemy_data["stats"].get("mag", 0),
			"mdef": enemy_data["stats"].get("mdef", 0),
			"spd": enemy_data["stats"]["spd"],
			"skills": enemy_data.get("skills", []).duplicate(),
			"is_player": false,
			"defending": false,
		}
		_enemies.append(battle_enemy)

func _start_round() -> void:
	# Reset defend flags
	for c in _party + _enemies:
		c["defending"] = false

	_turn_system.start_new_round()
	_process_current_turn()

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
			var dmg = Combatant.calculate_physical_damage(enemy, target)
			Combatant.apply_damage(target, dmg)
			action_performed.emit("%s ataca a %s por %d de dano!" % [enemy["name"], target["name"], dmg])
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
				Combatant.apply_damage(fallback_target, dmg)
				action_performed.emit("%s no tiene MP! Ataca a %s por %d de dano!" % [enemy["name"], fallback_target["name"], dmg])
				hp_updated.emit()
				await get_tree().create_timer(0.8).timeout
				_next_turn()
				return

			if skill.get("target_type", "") == "all_enemies":
				# AoE against party
				var targets = action.get("targets", [])
				for t in targets:
					var dmg = Combatant.calculate_magical_damage(enemy, t, skill.get("power", 0))
					Combatant.apply_damage(t, dmg)
				action_performed.emit("%s usa %s contra todo el grupo!" % [enemy["name"], skill_name])
			else:
				var target = action.get("target", {})
				if target.is_empty():
					_next_turn()
					return
				if skill.get("effect_type", "") == "heal":
					var heal = Combatant.calculate_heal(enemy, skill.get("power", 0))
					Combatant.apply_heal(target, heal)
					action_performed.emit("%s usa %s en %s, cura %d HP!" % [enemy["name"], skill_name, target["name"], heal])
				else:
					var dmg: int
					if skill.get("effect_type", "") == "physical":
						dmg = Combatant.calculate_physical_damage(enemy, target, skill.get("power", 0))
					else:
						dmg = Combatant.calculate_magical_damage(enemy, target, skill.get("power", 0))
					Combatant.apply_damage(target, dmg)
					action_performed.emit("%s usa %s en %s por %d de dano!" % [enemy["name"], skill_name, target["name"], dmg])

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
			var dmg = Combatant.calculate_physical_damage(current, target)
			Combatant.apply_damage(target, dmg)
			action_performed.emit("%s ataca a %s por %d de dano!" % [current["name"], target["name"], dmg])

		"skill":
			var skill = action.get("skill", {})
			if not Combatant.use_mp(current, skill.get("mp_cost", 0)):
				action_performed.emit("No hay suficiente MP!")
				_waiting_for_player = true
				return

			var skill_name = skill.get("name", "???")
			if skill.get("effect_type", "") == "heal":
				var target = action.get("target", {})
				var heal = Combatant.calculate_heal(current, skill.get("power", 0))
				Combatant.apply_heal(target, heal)
				action_performed.emit("%s usa %s en %s, cura %d HP!" % [current["name"], skill_name, target["name"], heal])
			elif skill.get("target_type", "") == "all_enemies":
				for e in _enemies:
					if e.get("hp", 0) > 0:
						var dmg = Combatant.calculate_magical_damage(current, e, skill.get("power", 0))
						Combatant.apply_damage(e, dmg)
				action_performed.emit("%s usa %s contra todos los enemigos!" % [current["name"], skill_name])
			else:
				var target = action.get("target", {})
				var dmg: int
				if skill.get("effect_type", "") == "physical":
					dmg = Combatant.calculate_physical_damage(current, target, skill.get("power", 0))
				else:
					dmg = Combatant.calculate_magical_damage(current, target, skill.get("power", 0))
				Combatant.apply_damage(target, dmg)
				action_performed.emit("%s usa %s en %s por %d de dano!" % [current["name"], skill_name, target["name"], dmg])

		"defend":
			current["defending"] = true
			action_performed.emit("%s se defiende!" % current["name"])

		"item":
			var item = action.get("item", {})
			var target = action.get("target", {})
			if item.get("effect", "") == "heal":
				Combatant.apply_heal(target, item.get("power", 30))
				GameState.remove_item(item["id"])
				action_performed.emit("%s usa %s en %s!" % [current["name"], item["name"], target["name"]])

		"flee":
			var chance = Combatant.calculate_flee_chance(_party, _enemies)
			if randf() < chance:
				action_performed.emit("Huida exitosa!")
				await get_tree().create_timer(0.5).timeout
				_flee()
				return
			else:
				action_performed.emit("No se pudo huir!")

	hp_updated.emit()
	await get_tree().create_timer(0.5).timeout
	_next_turn()

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

	action_performed.emit("--- Victoria! +%d XP, +%d Oro ---" % [xp, gold])

	# Sync party HP/MP back to GameState
	_sync_party_to_gamestate()

	await get_tree().create_timer(1.5).timeout
	battle_ended.emit("victory")

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
			"mp": p["mp"],
		})
	GameState.restore_party_from_combat(party_state)

func get_party() -> Array:
	return _party

func get_enemies() -> Array:
	return _enemies

func is_waiting_for_player() -> bool:
	return _waiting_for_player
