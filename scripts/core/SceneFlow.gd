extends Node
## SceneFlow — Autoload singleton
## Handles scene transitions with fade-to-black effect.

var _fade_rect: ColorRect
var _fade_layer: CanvasLayer
var _is_transitioning: bool = false

func _ready() -> void:
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
func change_scene(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	await _fade_out()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame  # Wait one frame for scene to load
	await _fade_in()
	_is_transitioning = false

## Start a battle encounter
func start_battle(encounter_id: String, return_scene: String, return_pos: Vector3) -> void:
	GameState.prepare_combat(encounter_id, return_scene, return_pos)
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
