extends Node
## EventBus — Global signal bus for decoupled communication

signal player_moved(position: Vector3)
signal player_interact_requested(target: Node)

signal combat_started(encounter_id: String)
signal combat_ended(result: String)

signal item_collected(item_id: String, quantity: int)
signal flag_set(flag_name: String, value: bool)

signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String)

signal scene_changed(scene_path: String)
