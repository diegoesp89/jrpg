extends Node
## SettingsManager — Autoload singleton. Persists user-configurable settings (resolution,
## fullscreen, key bindings, volume) to user://settings.json (player data, never res://) and
## applies them to the engine. Volume changes are broadcast via volume_changed — AudioManager
## listens and applies it to the Music/SFX buses.

signal volume_changed(value: float)

const SETTINGS_PATH := "user://settings.json"

const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080"]

const REBINDABLE_ACTIONS := ["move_up", "move_down", "move_left", "move_right", "action1", "action2"]

const ACTION_LABELS := {
	"move_up": "Mover arriba",
	"move_down": "Mover abajo",
	"move_left": "Mover izquierda",
	"move_right": "Mover derecha",
	"action1": "Confirmar / Interactuar",
	"action2": "Cancelar / Menú",
}

## Shown as each action's default key label and used by reset_to_defaults() — matches
## project.godot's primary binding for that action (movement also has arrow-key duals in
## project.godot that are left untouched unless the player explicitly rebinds that action).
const DEFAULT_KEYS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"action1": KEY_Z,
	"action2": KEY_X,
}

## Fixed second binding for the movement actions only — the arrow keys always work as a
## permanent alternative, never rebound and never shown as editable. action1/action2 have no
## second option at all, so they're absent from this map.
const SECONDARY_KEYS := {
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
}

var resolution: String = "1920x1080"
var fullscreen: bool = true
var volume: float = 1.0

## action_name -> physical keycode (int). Only contains actions the player has explicitly
## rebound — any action absent here keeps project.godot's original InputMap bindings
## (including movement's WASD+arrow-key duals) untouched.
var key_bindings: Dictionary = {}

## Snapshot of project.godot's original InputMap events per rebindable action, captured once
## before anything is ever rebound, so reset_to_defaults() can restore the exact original
## bindings (e.g. move_up's W + Up-arrow dual) instead of collapsing to a single key.
var _original_events: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			var dup: Array = []
			for e in InputMap.action_get_events(action):
				dup.append(e.duplicate())
			_original_events[action] = dup
	load_settings()

func load_settings() -> void:
	var data = _read_json_file(SETTINGS_PATH)
	resolution = str(data.get("resolution", resolution))
	fullscreen = bool(data.get("fullscreen", fullscreen))
	volume = float(data.get("volume", volume))
	key_bindings = data.get("key_bindings", {})
	_apply_resolution()
	_apply_fullscreen()
	for action in key_bindings.keys():
		_apply_key_binding(action, int(key_bindings[action]))

func save_settings() -> void:
	_write_json_file(SETTINGS_PATH, {
		"resolution": resolution,
		"fullscreen": fullscreen,
		"volume": volume,
		"key_bindings": key_bindings,
	})

func set_resolution(value: String) -> void:
	resolution = value
	_apply_resolution()
	save_settings()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()
	save_settings()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	save_settings()
	volume_changed.emit(volume)

func get_key_for_action(action: String) -> int:
	return int(key_bindings.get(action, DEFAULT_KEYS.get(action, 0)))

func get_key_label(action: String) -> String:
	return OS.get_keycode_string(get_key_for_action(action))

## Empty string for actions with no second option (action1/action2). For movement, always the
## arrow-key label — fixed, regardless of what the player rebinds the first option to.
func get_secondary_key_label(action: String) -> String:
	if not SECONDARY_KEYS.has(action):
		return ""
	return OS.get_keycode_string(SECONDARY_KEYS[action])

## Rebinds `action`'s first option to a single physical keycode, replacing whatever that first
## option was before. The fixed arrow-key second option (SECONDARY_KEYS) is re-added right after
## for movement actions, so rebinding never drops it — action1/action2 have no second option to
## preserve, so they end up with just the one event, same as before.
func apply_key_binding(action: String, physical_keycode: int) -> void:
	key_bindings[action] = physical_keycode
	_apply_key_binding(action, physical_keycode)
	save_settings()

func reset_to_defaults() -> void:
	resolution = "1920x1080"
	fullscreen = true
	volume = 1.0
	key_bindings = {}
	_apply_resolution()
	_apply_fullscreen()
	for action in REBINDABLE_ACTIONS:
		_restore_original_binding(action)
	save_settings()
	volume_changed.emit(volume)

func _apply_resolution() -> void:
	var parts = resolution.split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_key_binding(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev = InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)
	if SECONDARY_KEYS.has(action):
		var secondary_ev = InputEventKey.new()
		secondary_ev.physical_keycode = SECONDARY_KEYS[action]
		InputMap.action_add_event(action, secondary_ev)

## Restores the exact InputMap events project.godot originally had for this action (e.g.
## move_up's W + Up-arrow dual), from the snapshot taken at _ready().
func _restore_original_binding(action: String) -> void:
	if not InputMap.has_action(action) or not _original_events.has(action):
		return
	InputMap.action_erase_events(action)
	for e in _original_events[action]:
		InputMap.action_add_event(action, e)

func _write_json_file(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SettingsManager: could not open file for writing: %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("SettingsManager: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	var data = json.data
	return data if data is Dictionary else {}
