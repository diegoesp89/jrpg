extends CanvasLayer
class_name OptionsPanel
## OptionsPanel — Reusable settings overlay (resolution, fullscreen, key rebinding, volume).
## Self-contained: builds its own root + input handling, so it can be instanced as a plain
## child from anywhere — ContinueScreen at boot (no player/dungeon in the scene) or StatusMenu
## mid-game — without either host needing its own copy of this UI. Same row-list + arrow-key +
## action1/action2 navigation idiom as StatusMenu/ContinueScreen (this game has no mouse cursor
## during actual play, so sliders/OptionButtons would be unusable here — MapEditor is the only
## mouse-driven screen, and only because it's a dev tool).
##
## The host must check `is_open()` at the top of its own _unhandled_input and skip its own
## handling while true, and should listen for the `closed` signal to know when to resume.

signal closed

enum RowKind { RESOLUTION, FULLSCREEN, VOLUME, KEYBIND, RESET, BACK }

const VOLUME_STEPS := [0.0, 0.25, 0.5, 0.75, 1.0]

var _is_open: bool = false
var _selected_index: int = 0
var _rows: Array = []
var _awaiting_rebind_action: String = ""

var _root: Control
var _title: Label
var _list_container: VBoxContainer
var _row_labels: Array[Label] = []

func _ready() -> void:
	layer = 90
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_title = Label.new()
	_title.text = "Opciones"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 50
	_title.offset_bottom = 110
	_root.add_child(_title)

	_list_container = VBoxContainer.new()
	_list_container.set_anchors_preset(Control.PRESET_CENTER)
	_list_container.offset_left = -280
	_list_container.offset_right = 280
	_list_container.offset_top = -240
	_list_container.offset_bottom = 240
	_list_container.add_theme_constant_override("separation", 12)
	_list_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_list_container)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z: Elegir  |  X/Esc: Volver"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	_selected_index = 0
	_awaiting_rebind_action = ""
	_refresh_rows()
	_root.visible = true

func _close() -> void:
	_is_open = false
	_root.visible = false
	closed.emit()

func _refresh_rows() -> void:
	for child in _list_container.get_children():
		child.queue_free()
	_row_labels.clear()
	_rows.clear()

	_rows.append({"kind": RowKind.RESOLUTION})
	_rows.append({"kind": RowKind.FULLSCREEN})
	_rows.append({"kind": RowKind.VOLUME})
	for action in SettingsManager.REBINDABLE_ACTIONS:
		_rows.append({"kind": RowKind.KEYBIND, "action": action})
	_rows.append({"kind": RowKind.RESET})
	_rows.append({"kind": RowKind.BACK})

	for row in _rows:
		var lbl = Label.new()
		lbl.text = _row_text(row)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 22)
		_list_container.add_child(lbl)
		_row_labels.append(lbl)
	_update_highlight()

func _row_text(row: Dictionary) -> String:
	match row["kind"]:
		RowKind.RESOLUTION:
			return "Resolución: %s" % SettingsManager.resolution
		RowKind.FULLSCREEN:
			return "Pantalla completa: %s" % ("Sí" if SettingsManager.fullscreen else "No")
		RowKind.VOLUME:
			return "Volumen: %d%% (sin efecto todavía, no hay audio)" % int(round(SettingsManager.volume * 100))
		RowKind.KEYBIND:
			var action = row["action"]
			if _awaiting_rebind_action == action:
				return "%s: presioná una tecla nueva... (Esc cancela)" % SettingsManager.ACTION_LABELS.get(action, action)
			return "%s: %s" % [SettingsManager.ACTION_LABELS.get(action, action), SettingsManager.get_key_label(action)]
		RowKind.RESET:
			return "Restablecer valores por defecto"
		RowKind.BACK:
			return "Volver"
	return ""

func _update_highlight() -> void:
	for i in range(_row_labels.size()):
		if i == _selected_index:
			_row_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			_row_labels[i].add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _awaiting_rebind_action != "":
		if event.is_action_pressed("ui_cancel"):
			_awaiting_rebind_action = ""
			_refresh_rows()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			SettingsManager.apply_key_binding(_awaiting_rebind_action, event.physical_keycode)
			_awaiting_rebind_action = ""
			_refresh_rows()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_rows.size() - 1, _selected_index + 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action1") or event.is_action_pressed("ui_accept"):
		_activate_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _activate_selected() -> void:
	var row = _rows[_selected_index]
	match row["kind"]:
		RowKind.RESOLUTION:
			var idx = SettingsManager.RESOLUTIONS.find(SettingsManager.resolution)
			var next_idx = (idx + 1) % SettingsManager.RESOLUTIONS.size() if idx >= 0 else 0
			SettingsManager.set_resolution(SettingsManager.RESOLUTIONS[next_idx])
			_refresh_rows()
		RowKind.FULLSCREEN:
			SettingsManager.set_fullscreen(not SettingsManager.fullscreen)
			_refresh_rows()
		RowKind.VOLUME:
			var idx = VOLUME_STEPS.find(SettingsManager.volume)
			var next_idx = (idx + 1) % VOLUME_STEPS.size() if idx >= 0 else 0
			SettingsManager.set_volume(VOLUME_STEPS[next_idx])
			_refresh_rows()
		RowKind.KEYBIND:
			_awaiting_rebind_action = row["action"]
			_refresh_rows()
		RowKind.RESET:
			SettingsManager.reset_to_defaults()
			_refresh_rows()
		RowKind.BACK:
			_close()
