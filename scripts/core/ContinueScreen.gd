extends Node
class_name ContinueScreen
## ContinueScreen — First screen after Boot. Continue an existing save, start a new game,
## browse the cross-playthrough profile, or wipe the save (profile persists).

## Preloaded by path, not via its class_name — see the note in DungeonBuilder.gd.
const HelpPanelScene = preload("res://scripts/ui/HelpPanel.gd")

enum State { MAIN, RESET_CONFIRM }

var _state: State = State.MAIN
var _options: Array = []
var _selected_index: int = 0

var _root: Control
var _title: Label
var _list_container: VBoxContainer
var _option_labels: Array[Label] = []
var _options_panel: OptionsPanel
var _help_panel: HelpPanelScene

func _ready() -> void:
	_build_ui()
	_show_main()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_title = Label.new()
	_title.text = "La Montana del Penacho Blanco"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_left = 60
	_title.offset_right = -60
	_title.offset_top = 40
	_title.offset_bottom = 130
	_root.add_child(_title)

	_list_container = VBoxContainer.new()
	_list_container.set_anchors_preset(Control.PRESET_CENTER)
	_list_container.offset_left = -240
	_list_container.offset_right = 240
	_list_container.offset_top = -120
	_list_container.offset_bottom = 150
	_list_container.add_theme_constant_override("separation", 14)
	_list_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_list_container)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z: Elegir"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -60
	hint.offset_bottom = -20
	_root.add_child(hint)

	_options_panel = OptionsPanel.new()
	add_child(_options_panel)
	_options_panel.closed.connect(_show_main)

	_help_panel = HelpPanelScene.new()
	add_child(_help_panel)
	_help_panel.closed.connect(_show_main)

func _show_main() -> void:
	_state = State.MAIN
	_title.text = "La Montana del Penacho Blanco"
	_options = []
	if SaveManager.has_save():
		_options.append("Continuar partida")
	_options.append("Nueva partida")
	_options.append("Ver perfil")
	_options.append("Ayuda")
	_options.append("Opciones")
	_options.append("Resetear progreso")
	_rebuild_list()

func _show_reset_confirm() -> void:
	_state = State.RESET_CONFIRM
	_title.text = "Resetear progreso? Se borra la partida guardada Y el perfil (estrellas y estadisticas)."
	_options = ["Si", "No"]
	_rebuild_list()
	_selected_index = 1  # default a "No" para evitar un borrado accidental
	_update_highlight()

func _rebuild_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()
	_option_labels.clear()
	for opt in _options:
		var lbl = Label.new()
		lbl.text = opt
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 26)
		_list_container.add_child(lbl)
		_option_labels.append(lbl)
	_selected_index = 0
	_update_highlight()

func _update_highlight() -> void:
	for i in range(_option_labels.size()):
		if i == _selected_index:
			_option_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			_option_labels[i].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

func _unhandled_input(event: InputEvent) -> void:
	if _options_panel.is_open() or _help_panel.is_open():
		return
	if _option_labels.is_empty():
		return
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_option_labels.size() - 1, _selected_index + 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action1"):
		match _state:
			State.MAIN:
				_select_main(_options[_selected_index])
			State.RESET_CONFIRM:
				_select_reset_confirm(_options[_selected_index])
		get_viewport().set_input_as_handled()

func _select_main(option: String) -> void:
	match option:
		"Continuar partida":
			var info = SaveManager.load_game()
			if info.is_empty():
				return
			DataLoader.load_map(str(info.get("map_path", "")))
			GameState.return_position = info.get("player_position", Vector3.ZERO)
			SceneFlow.change_scene("res://scenes/exploration/Dungeon.tscn")
		"Nueva partida":
			GameState.reset()
			SceneFlow.change_scene("res://scenes/boot/MapSelection.tscn")
		"Ver perfil":
			SceneFlow.change_scene("res://scenes/boot/ProfileScreen.tscn")
		"Ayuda":
			_help_panel.open()
		"Opciones":
			_options_panel.open()
		"Resetear progreso":
			_show_reset_confirm()

func _select_reset_confirm(option: String) -> void:
	if option == "Si":
		SaveManager.delete_save()
	_show_main()
