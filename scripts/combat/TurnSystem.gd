class_name TurnSystem
extends Node
## TurnSystem — Manages turn order based on dexterity + random factor.

signal turn_order_ready(order: Array)
signal turn_started(combatant: Dictionary)
signal round_started(round_num: int)

var _combatants: Array[Dictionary] = []
var _turn_queue: Array[Dictionary] = []
var _current_turn_index: int = 0
var _round_number: int = 0

const LEVEL: int = 1

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

func _get_initiative(c: Dictionary) -> int:
	var attrs = c.get("attributes", {})
	var dex = attrs.get("agilidad", 10)
	var dex_mod = _get_modifier(dex)
	return LEVEL + dex_mod + randi_range(0, 5)

func setup(combatants: Array[Dictionary]) -> void:
	_combatants = combatants
	_round_number = 0

func start_new_round() -> void:
	_round_number += 1
	_calculate_turn_order()
	_current_turn_index = 0
	round_started.emit(_round_number)
	turn_order_ready.emit(_turn_queue)

func _calculate_turn_order() -> void:
	_turn_queue.clear()
	for c in _combatants:
		if c.get("hp", 0) > 0:
			var initiative = _get_initiative(c)
			_turn_queue.append({
				"combatant": c,
				"initiative": initiative
			})
	_turn_queue.sort_custom(func(a, b): return a["initiative"] > b["initiative"])

func get_current_combatant() -> Dictionary:
	if _current_turn_index < _turn_queue.size():
		return _turn_queue[_current_turn_index]["combatant"]
	return {}

func advance_turn() -> bool:
	_current_turn_index += 1
	# Skip dead combatants
	while _current_turn_index < _turn_queue.size():
		var c = _turn_queue[_current_turn_index]["combatant"]
		if c.get("hp", 0) > 0:
			return true
		_current_turn_index += 1
	# All turns exhausted, need new round
	return false

func is_round_over() -> bool:
	return _current_turn_index >= _turn_queue.size()

func get_round_number() -> int:
	return _round_number
