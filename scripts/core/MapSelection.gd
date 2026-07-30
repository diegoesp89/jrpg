extends Node
class_name MapSelection

var _maps: Array = []
var _selected_index: int = 0

var _root: Control
var _list_container: VBoxContainer
var _option_labels: Array[Label] = []

func _ready() -> void:
	_maps = DataLoader.list_maps()
	_build_ui()
	_update_highlight()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title = Label.new()
	title.text = "Selecciona un mapa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 100
	_root.add_child(title)

	_list_container = VBoxContainer.new()
	_list_container.set_anchors_preset(Control.PRESET_CENTER)
	_list_container.offset_left = -300
	_list_container.offset_right = 300
	_list_container.offset_top = -150
	_list_container.offset_bottom = 150
	_list_container.add_theme_constant_override("separation", 14)
	_list_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_list_container)

	if _maps.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No hay mapas en res://maps/"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 22)
		empty_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))
		_list_container.add_child(empty_label)
	else:
		for map_entry in _maps:
			var row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 20)
			_list_container.add_child(row)

			var label = Label.new()
			label.text = str(map_entry.get("name", "???"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 24)
			label.custom_minimum_size = Vector2(280, 0)
			row.add_child(label)
			_option_labels.append(label)

			var edit_btn = Button.new()
			edit_btn.text = "Editar"
			edit_btn.pressed.connect(_on_edit_pressed.bind(str(map_entry.get("path", ""))))
			row.add_child(edit_btn)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z: Elegir"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -60
	hint.offset_bottom = -20
	_root.add_child(hint)

func _update_highlight() -> void:
	for i in range(_option_labels.size()):
		if i == _selected_index:
			_option_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			_option_labels[i].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

func _unhandled_input(event: InputEvent) -> void:
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
		var chosen = _maps[_selected_index]
		DataLoader.load_map(str(chosen.get("path", "")))
		SceneFlow.change_scene("res://scenes/boot/CharacterSelection.tscn")
		get_viewport().set_input_as_handled()

func _on_edit_pressed(path: String) -> void:
	DataLoader.load_map(path)
	SceneFlow.change_scene("res://scenes/boot/MapEditorScreen.tscn")
