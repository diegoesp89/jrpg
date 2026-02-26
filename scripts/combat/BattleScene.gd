extends Node
class_name BattleScene
## BattleScene — Root script for the battle scene

var _battle_controller = null
var _battle_ui = null
var _debug_hud = null

func _ready() -> void:
	_setup_battle()

func _setup_battle() -> void:
	# Create BattleController
	var bc_script = load("res://scripts/combat/BattleController.gd")
	_battle_controller = Node.new()
	_battle_controller.name = "BattleController"
	_battle_controller.set_script(bc_script)
	add_child(_battle_controller)

	# Create BattleUI
	var ui_script = load("res://scripts/ui/BattleUI.gd")
	_battle_ui = CanvasLayer.new()
	_battle_ui.name = "BattleUI"
	_battle_ui.set_script(ui_script)
	add_child(_battle_ui)

	# Wire them up
	_battle_ui.setup(_battle_controller)
	_battle_controller.battle_ended.connect(_on_battle_ended)

	# Start the battle
	await get_tree().process_frame
	_battle_controller.start_battle(GameState.current_encounter_id)

	# Setup sprites after battle starts
	await get_tree().process_frame
	_battle_ui.setup_sprites(_battle_controller.get_party(), _battle_controller.get_enemies())
	_battle_ui._update_all_stats()

	# Create DebugBattleHUD
	var dbg_script = load("res://scripts/ui/DebugBattleHUD.gd")
	_debug_hud = CanvasLayer.new()
	_debug_hud.name = "DebugBattleHUD"
	_debug_hud.set_script(dbg_script)
	add_child(_debug_hud)
	_debug_hud.setup(_battle_controller, _battle_ui)

func _on_battle_ended(result: String) -> void:
	match result:
		"victory":
			var flag_id = "combat_" + GameState.current_encounter_id + "_done"
			GameState.set_flag(flag_id)
			await get_tree().create_timer(1.0).timeout
			SceneFlow.end_battle()
		"fled":
			await get_tree().create_timer(1.0).timeout
			SceneFlow.end_battle()
		"defeat":
			await get_tree().create_timer(1.5).timeout
			GameState.reset()
			SceneFlow.change_scene("res://scenes/boot/CharacterSelection.tscn")
