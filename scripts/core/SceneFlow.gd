extends Node
## SceneFlow — Autoload singleton
## Handles scene transitions with fade-to-black effect.

var _fade_rect: ColorRect
var _fade_layer: CanvasLayer
var _is_transitioning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_fade_overlay()

func _setup_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100  # On top of everything
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)  # Start transparent
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

# --- Public API ---

## Transition to a scene with fade-to-black
##
## Waits for an in-flight transition rather than dropping the call: a scene's own _ready() calling
## this immediately after being loaded (Boot.tscn's redirect into ContinueScreen.tscn is the one
## real example) lands while the transition that loaded it is still mid fade-in. Returning early
## used to silently swallow that second call, leaving the player stuck on whatever stub scene
## triggered it — reachable only through this exact reentrant pattern, so nothing else exercised
## it, but this waits instead so any future caller in the same shape doesn't hit it either.
func change_scene(scene_path: String) -> void:
	while _is_transitioning:
		await get_tree().process_frame
	_is_transitioning = true
	AudioManager.play_music(_music_track_for_scene(scene_path))
	await _fade_out()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame  # Wait one frame for scene to load
	await _fade_in()
	_is_transitioning = false

## Every scene transition in the game passes through change_scene() (including
## start_battle/end_battle below), so this is the single place background music gets decided.
func _music_track_for_scene(scene_path: String) -> String:
	if "Battle.tscn" in scene_path:
		return "battle"
	if "Dungeon.tscn" in scene_path:
		return "exploration"
	return "menu"

## Start a battle encounter
func start_battle(encounter_id: String, return_scene: String, return_pos: Vector3, intro_message: String = "", death_message: String = "") -> void:
	GameState.prepare_combat(encounter_id, return_scene, return_pos, intro_message, death_message)
	await change_scene("res://scenes/combat/Battle.tscn")

## Return from battle to exploration
func end_battle() -> void:
	await change_scene(GameState.return_scene_path)

# --- Fade helpers ---

func _fade_out(duration: float = 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, duration)
	await tween.finished

func _fade_in(duration: float = 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, duration)
	await tween.finished
