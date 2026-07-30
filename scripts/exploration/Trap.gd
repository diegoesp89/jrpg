extends Area3D
class_name Trap
## Trap — Damages the party leader

@export var damage: int = 10

var _triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if body is CharacterBody3D:
		_triggered = true
		# Damage leader
		if GameState.party.size() > 0:
			var leader = GameState.party[0]
			leader["hp"] = maxi(leader["hp"] - damage, 0)
			print("Trampa! %s recibe %d de dano!" % [leader["name"], damage])
