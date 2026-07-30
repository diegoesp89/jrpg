extends PanelContainer
class_name DialogueBox
## DialogueBox — UI for showing dialogue

var _speaker_label: Label = null
var _text_label: RichTextLabel = null
var _portrait_rect: TextureRect = null
var _emoji_label: Label = null
var _choices_container: VBoxContainer = null
var _choice_labels: Array[Label] = []
var _selected_choice: int = 0
var _showing_choices: bool = false

func _ready() -> void:
	add_to_group("dialogue_box")
	if _speaker_label == null:
		setup()

func setup() -> void:
	# Configure panel
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 300)
	offset_top = -320
	offset_bottom = -20
	offset_left = 40
	offset_right = -40

	# Add stylebox
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.15, 0.92)
	style.border_color = Color(0.6, 0.55, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	# HBox layout: emoji portrait (left) + speaker/text/choices (right)
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

	var portrait_col = VBoxContainer.new()
	portrait_col.custom_minimum_size = Vector2(110, 0)
	portrait_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(portrait_col)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(100, 105)
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.visible = false
	portrait_col.add_child(_portrait_rect)

	_emoji_label = Label.new()
	_emoji_label.add_theme_font_size_override("font_size", 48)
	_emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emoji_label.visible = false
	portrait_col.add_child(_emoji_label)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	# Speaker
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 48)
	_speaker_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	vbox.add_child(_speaker_label)

	# Text
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(0, 60)
	_text_label.add_theme_font_size_override("normal_font_size", 42)
	vbox.add_child(_text_label)

	# Choices container
	_choices_container = VBoxContainer.new()
	_choices_container.visible = false
	vbox.add_child(_choices_container)

	hide()

func show_text(speaker: String, text: String, emoji: String = "", portrait: Texture2D = null) -> void:
	_showing_choices = false
	_speaker_label.text = speaker
	_text_label.text = text
	_choices_container.visible = false
	_emoji_label.text = emoji
	_emoji_label.visible = emoji != ""
	_portrait_rect.texture = portrait
	_portrait_rect.visible = portrait != null
	visible = true

func show_choices(speaker: String, text: String, choices: Array) -> void:
	_showing_choices = true
	_speaker_label.text = speaker
	_text_label.text = text
	_emoji_label.visible = false
	_portrait_rect.visible = false

	# Clear old choices
	for child in _choices_container.get_children():
		child.queue_free()
	_choice_labels.clear()

	# Create choice labels
	for i in range(choices.size()):
		var label = Label.new()
		label.text = "  %s" % choices[i].get("text", "???")
		label.add_theme_font_size_override("font_size", 42)
		_choices_container.add_child(label)
		_choice_labels.append(label)

	_selected_choice = 0
	_update_choice_highlight()
	_choices_container.visible = true
	visible = true

func _input(event: InputEvent) -> void:
	if not visible or not _showing_choices:
		return

	if event.is_action_pressed("move_up"):
		_selected_choice = maxi(0, _selected_choice - 1)
		_update_choice_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_choice = mini(_choice_labels.size() - 1, _selected_choice + 1)
		_update_choice_highlight()
		get_viewport().set_input_as_handled()

func _update_choice_highlight() -> void:
	for i in range(_choice_labels.size()):
		if i == _selected_choice:
			_choice_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
			_choice_labels[i].text = "> " + _choice_labels[i].text.strip_edges().trim_prefix("> ")
		else:
			_choice_labels[i].add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			var clean = _choice_labels[i].text.strip_edges().trim_prefix("> ")
			_choice_labels[i].text = "  " + clean

func is_showing_choices() -> bool:
	return _showing_choices

func get_selected_choice() -> int:
	return _selected_choice
