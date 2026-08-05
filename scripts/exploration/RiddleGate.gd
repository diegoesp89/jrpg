extends StaticBody3D
class_name RiddleGate
## RiddleGate — Entrance puzzle: type the answer to a riddle (picked at random from
## data/riddles.json) to pass peacefully (plays success_event_id), or fail your attempts and
## fight the guardian instead (plays combat_event_id on victory). Blocks the corridor until
## resolved; stays open permanently afterward.

@export var encounter_id: String = "encounter_sphinx"
@export var success_event_id: String = "WP1A"
@export var combat_event_id: String = "WP1B"

## Preloaded by path rather than through its class_name — see the note in DungeonBuilder.gd.
const NarrativeToastScript = preload("res://scripts/ui/NarrativeToast.gd")
const AchievementsScript = preload("res://scripts/core/Achievements.gd")

## Shown after winning the guardian fight (i.e. NOT solving the riddle peacefully) — a warning
## that something harsher is waiting further in. Deliberately doesn't name what: same spoiler
## discipline as the Ayuda pages, and it's the answer to a puzzle the player just failed.
const NEW_GUARDIAN_WARNING := "Al vencer a la guardiana, algo más ha despertado en las profundidades para ocupar su lugar. Prepárate — no será tan piadoso como ella."

const FLAG_OPEN := "riddle_gate_open"
const ACCENTED := "áéíóúñ"
const PLAIN := "aeioun"
const BASE_ATTEMPTS := 1

var _collision: CollisionShape3D = null
var _riddle: Dictionary = {}
var _input_box: RiddleInputBox = null
var _awaiting_answer: bool = false
var _attempts_left: int = 0

func _ready() -> void:
	add_to_group("riddle_gate")
	for child in get_children():
		if child is CollisionShape3D:
			_collision = child

	_riddle = DataLoader.get_random_riddle()

	if GameState.get_flag(FLAG_OPEN):
		_set_open(true)
		return

	if GameState.get_flag("combat_" + encounter_id + "_done"):
		# The player already won the guardian fight in a previous load of this scene.
		GameState.set_flag(FLAG_OPEN)
		_set_open(true)
		_play_and_warn()

## Plays the post-fight banter, then the warning that a new guardian replaced this one — in that
## order, so the warning reads as the last, ominous word rather than getting talked over by the
## party's in-character reactions. Split out from _ready() (rather than awaited inline there) only
## because the FLAG_OPEN early-return above guarantees this whole branch runs exactly once per
## save, so there is nothing time-sensitive about it not being awaited by the caller.
func _play_and_warn() -> void:
	await _play_scene(combat_event_id, {})
	await NarrativeToastScript.show_at(self, NEW_GUARDIAN_WARNING)
	await AchievementsScript.unlock(self, "cuando_las_palabras_fallan")

func interact() -> void:
	if GameState.get_flag(FLAG_OPEN):
		return

	_input_box = _find_or_create_input_box()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_disabled"):
		player.set_movement_disabled(true)

	# Mente Aguda: one extra wrong guess allowed before the guardian fight is forced —
	# it doesn't reveal the answer, just buys you a second try.
	_attempts_left = BASE_ATTEMPTS + (1 if _party_has_feat("keen_mind") else 0)
	_awaiting_answer = true
	if not _input_box.answered.is_connected(_on_answered):
		_input_box.answered.connect(_on_answered)
	if not _input_box.cancelled.is_connected(_on_cancelled):
		_input_box.cancelled.connect(_on_cancelled)
	_input_box.show_riddle(_riddle.get("question", "¿?"))

func _party_has_feat(feat_id: String) -> bool:
	for member in GameState.party:
		if Combatant.has_feat(member, feat_id):
			return true
	return false

func _on_answered(text: String) -> void:
	if not _awaiting_answer:
		return
	var normalized = _normalize(text)
	var accepted: Array = _riddle.get("accepted", [])
	var correct = false
	for a in accepted:
		if _normalize(str(a)) == normalized:
			correct = true
			break

	if correct:
		_awaiting_answer = false
		_input_box.hide_box()
		_resolve_success()
		return

	AudioManager.play_sfx("riddle_wrong")
	_attempts_left -= 1
	if _attempts_left > 0:
		var word = "intento" if _attempts_left == 1 else "intentos"
		_input_box.show_feedback("No es correcto... te queda %d %s más." % [_attempts_left, word])
	else:
		_awaiting_answer = false
		_input_box.hide_box()
		_start_combat()

func _on_cancelled() -> void:
	if not _awaiting_answer:
		return
	_awaiting_answer = false
	_input_box.hide_box()
	_start_combat()

func _normalize(s: String) -> String:
	var result = s.strip_edges().to_lower()
	for i in range(ACCENTED.length()):
		result = result.replace(ACCENTED[i], PLAIN[i])
	return result

func _resolve_success() -> void:
	AudioManager.play_sfx("riddle_correct")
	GameState.set_flag(FLAG_OPEN)
	_set_open(true)
	_play_scene(success_event_id, {"respuesta": _riddle.get("answer_display", "")})
	AchievementsScript.unlock(self, "voz_de_la_razon")

func _start_combat() -> void:
	var dungeon_path = "res://scenes/exploration/Dungeon.tscn"
	var player = get_tree().get_first_node_in_group("player")
	var pos = player.global_position if player else global_position
	SceneFlow.start_battle(encounter_id, dungeon_path, pos)

func _set_open(open: bool) -> void:
	if _collision:
		_collision.disabled = open

func _play_scene(event_id: String, substitutions: Dictionary) -> void:
	var trigger_script = load("res://scripts/exploration/StoryTrigger.gd")
	var trigger = Area3D.new()
	trigger.set_script(trigger_script)
	trigger.event_id = event_id
	trigger.auto_trigger = false
	add_child(trigger)
	await trigger.play_for_current_party(substitutions)

func _find_or_create_input_box() -> RiddleInputBox:
	var existing = get_tree().get_first_node_in_group("riddle_input_box")
	if existing:
		return existing
	var script = load("res://scripts/ui/RiddleInputBox.gd")
	var box = CanvasLayer.new()
	box.set_script(script)
	box.add_to_group("riddle_input_box")
	add_child(box)
	return box

func get_prompt_text() -> String:
	if GameState.get_flag(FLAG_OPEN):
		return ""
	return "Z: Enfrentar a la guardiana"

## Debug Panel's "Revelar respuesta del enigma" — the only public way to read this riddle's
## answer from outside the file.
func get_answer_display() -> String:
	return str(_riddle.get("answer_display", ""))

func is_available() -> bool:
	return not GameState.get_flag(FLAG_OPEN)
