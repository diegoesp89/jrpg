extends Area3D
class_name Trap
## Trap — When the party walks over it, whoever has the highest Agilidad rolls a saving throw
## (1d20 + modifier) against `dc`. The DC, who's attempting it, and the result are shown through
## the same DialogueController/DialogueBox flow used for narrative beats (see StoryTrigger for
## the identical find-controller/await pattern) — then the trap disables permanently, whether the
## save succeeds or not.

@export var damage: int = 10
@export var dc: int = 12  # Dificultad de Salvación (Agilidad)
@export var trap_id: String = ""

## Assigned by DungeonBuilder — hidden by default so an armed trap looks like ordinary floor;
## made visible once triggered, as a permanent "already sprung" indicator (same idea as
## Door.gd's locked/unlocked texture swap).
var triggered_marker: MeshInstance3D = null

var _triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if trap_id != "" and GameState.get_flag(trap_id + "_triggered"):
		_triggered = true
		_show_triggered_marker()

func _on_body_entered(body: Node3D) -> void:
	if _triggered or GameState.party.is_empty():
		return
	if body is CharacterBody3D:
		_triggered = true
		if trap_id != "":
			GameState.set_flag(trap_id + "_triggered")
		_show_triggered_marker()
		_resolve_trap()

func _show_triggered_marker() -> void:
	if triggered_marker:
		triggered_marker.visible = true

## Highest-Agilidad party member — the one best suited to notice/dodge the trap, and the one
## who takes the damage if the roll fails.
func _best_saver() -> Dictionary:
	var best = GameState.party[0]
	var best_mod = Combatant.attribute_modifier(best.get("attributes", {}).get("agilidad", 10))
	for m in GameState.party:
		var mod = Combatant.attribute_modifier(m.get("attributes", {}).get("agilidad", 10))
		if mod > best_mod:
			best = m
			best_mod = mod
	return best

func _resolve_trap() -> void:
	var saver = _best_saver()
	var mod = Combatant.attribute_modifier(saver.get("attributes", {}).get("agilidad", 10))
	var roll = randi_range(1, 20)
	var total = roll + mod
	var success = total >= dc
	var mod_str = "+%d" % mod if mod >= 0 else str(mod)

	var lines: Array = []
	lines.append("Trampa: ¡Trampa detectada! Dificultad de Salvación %d (Agilidad). %s (mayor Agilidad de la party) intenta esquivarla..." % [dc, saver["name"]])

	if success:
		lines.append("Trampa: %s tira 1d20%s = %d vs DC %d -> ¡Supera la salvación!" % [saver["name"], mod_str, total, dc])
		lines.append("Trampa: %s esquiva la trampa sin recibir daño!" % saver["name"])
	else:
		var final_damage = damage
		if Combatant.has_feat_effect(saver, "trap_damage_half"):
			final_damage = int(ceil(damage / 2.0))
		saver["hp"] = maxi(saver.get("hp", 0) - final_damage, 0)
		lines.append("Trampa: %s tira 1d20%s = %d vs DC %d -> ¡Falla la salvación!" % [saver["name"], mod_str, total, dc])
		lines.append("Trampa: %s recibe %d de daño!" % [saver["name"], final_damage])

	var dialogue_controller = _find_dialogue_controller()
	if not dialogue_controller:
		push_warning("Trap: no DialogueController found in scene — resolved silently")
		return

	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)

	dialogue_controller.start_waypoint({"id": "trap_result", "dialogue": lines, "mood": "tense"})
	await dialogue_controller.dialogue_finished
	# DialogueController._end_dialogue() already re-enables player movement.

func _find_dialogue_controller():
	var controllers = get_tree().get_nodes_in_group("dialogue_controller")
	if controllers.size() > 0:
		return controllers[0]
	return null
