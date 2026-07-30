extends CanvasLayer
class_name RiddleInputBox
## RiddleInputBox — Shows a riddle question with a free-text answer field.
## Enter submits (answered), Escape gives up on the riddle (cancelled).

signal answered(text: String)
signal cancelled()

var _root: Control = null
var _question_label: Label = null
var _line_edit: LineEdit = null
var _feedback_label: Label = null

func _ready() -> void:
	layer = 55
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -420
	vbox.offset_right = 420
	vbox.offset_top = -120
	vbox.offset_bottom = 160
	vbox.add_theme_constant_override("separation", 20)
	_root.add_child(vbox)

	_question_label = Label.new()
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_label.add_theme_font_size_override("font_size", 28)
	_question_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	vbox.add_child(_question_label)

	_line_edit = LineEdit.new()
	_line_edit.custom_minimum_size = Vector2(0, 50)
	_line_edit.add_theme_font_size_override("font_size", 26)
	_line_edit.placeholder_text = "Escribe tu respuesta..."
	_line_edit.text_submitted.connect(_on_submitted)
	_line_edit.gui_input.connect(_on_line_edit_gui_input)
	vbox.add_child(_line_edit)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_font_size_override("font_size", 20)
	_feedback_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	vbox.add_child(_feedback_label)

	var hint = Label.new()
	hint.text = "Enter: Responder  |  Esc: Atacar en su lugar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func show_riddle(question: String) -> void:
	_question_label.text = question
	_line_edit.text = ""
	_feedback_label.text = ""
	_root.visible = true
	_line_edit.grab_focus()

## Shows a short message (e.g. "no es correcto, intenta de nuevo") and re-focuses the field.
func show_feedback(text: String) -> void:
	_feedback_label.text = text
	_line_edit.text = ""
	_root.visible = true
	_line_edit.grab_focus()

func hide_box() -> void:
	_root.visible = false
	_line_edit.release_focus()

func _on_submitted(text: String) -> void:
	answered.emit(text)

func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
