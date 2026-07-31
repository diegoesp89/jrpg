extends StaticBody3D
class_name RestZone
## RestZone — Fully restores the party's HP and MP, consuming one charge from a global pool
## shared by every rest zone on the map (GameState.rest_charges_left, starts at
## GameState.MAX_REST_CHARGES). Once the pool is empty, no rest zone works for the rest of
## this save. Always interactable (even at 0 charges) so the player gets clear feedback
## instead of the prompt silently disappearing.

func interact() -> void:
	if GameState.rest_charges_left <= 0:
		print("No te quedan descansos disponibles.")
		return

	for m in GameState.party:
		m["hp"] = m.get("max_hp", m.get("hp", 0))
		m["mp"] = m.get("max_mp", m.get("mp", 0))

	GameState.rest_charges_left -= 1
	print("Descansaste. HP y MP restaurados. Descansos restantes: %d/%d" % [GameState.rest_charges_left, GameState.MAX_REST_CHARGES])

func get_prompt_text() -> String:
	if GameState.rest_charges_left <= 0:
		return "Sin descansos restantes"
	return "Z: Descansar (%d/%d)" % [GameState.rest_charges_left, GameState.MAX_REST_CHARGES]

func is_available() -> bool:
	return true
