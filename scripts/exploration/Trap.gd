extends Area3D
## Trap — Damages the party leader when stepped on.

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
			var dmg = 10
			leader["hp"] = maxi(leader["hp"] - dmg, 0)
			print("Trampa! %s recibe %d de dano!" % [leader["name"], dmg])
