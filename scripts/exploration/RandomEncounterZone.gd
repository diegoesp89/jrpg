extends Area3D
class_name RandomEncounterZone
## RandomEncounterZone — while the player stays inside, periodically rolls a chance of
## an ambient combat encounter. No visible sprite trigger, and repeatable (unlike
## CombatTrigger, which is a fixed one-shot encounter tied to a visible map entity).

@export var encounter_ids: Array = []
@export var check_interval: float = 8.0  # seconds between rolls
@export var chance: float = 0.25         # probability per roll

var _player_inside: bool = false
var _timer: Timer = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_timer = Timer.new()
	_timer.wait_time = check_interval
	_timer.autostart = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = true

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = false

func _on_timeout() -> void:
	if not _player_inside or encounter_ids.is_empty():
		return
	if randf() > chance:
		return
	var encounter_id = encounter_ids[randi_range(0, encounter_ids.size() - 1)]
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var dungeon_path = "res://scenes/exploration/Dungeon.tscn"
	SceneFlow.start_battle(encounter_id, dungeon_path, player.global_position)
