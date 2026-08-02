extends CanvasLayer
class_name LevelUpPanel
## LevelUpPanel — Overlay shown right after a battle victory whenever GameState.pending_level_ups
## has entries. Walks the player through each queued level-up one at a time, letting them pick
## which feat to gain when there's more than one option left in the pool (mirrors
## CharacterSelection's feat picker, but triggered mid-run instead of at chargen — see
## BattleScene._on_battle_ended). Emits `finished` once the whole queue is resolved.

signal finished

var _root: Control
var _title: Label
var _options_container: VBoxContainer
var _current_options: Array = []
var _current_member_id: String = ""
var _selected_index: int = 0

func _ready() -> void:
	layer = 95
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 80
	_title.offset_bottom = 140
	_root.add_child(_title)

	_options_container = VBoxContainer.new()
	_options_container.set_anchors_preset(Control.PRESET_CENTER)
	_options_container.offset_left = -450
	_options_container.offset_right = 450
	_options_container.offset_top = -160
	_options_container.offset_bottom = 200
	_options_container.add_theme_constant_override("separation", 18)
	_root.add_child(_options_container)

	var hint = Label.new()
	hint.text = "WASD/Flechas: Navegar  |  Z: Elegir"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -60
	hint.offset_bottom = -20
	_root.add_child(hint)

func open() -> void:
	_show_next_step()

func _show_next_step() -> void:
	if GameState.pending_level_ups.is_empty():
		finished.emit()
		return

	var step: Dictionary = GameState.pending_level_ups[0]
	_current_member_id = step.get("member_id", "")
	# Computed now (not stored on the step) — by the time we get here, any earlier step for the
	# same member in this batch has already been resolved via apply_level_up_choice, so this
	# always reflects the member's up-to-the-moment feats. See GameState.get_level_up_options.
	_current_options = GameState.get_level_up_options(_current_member_id, int(step.get("level", 0)))
	if _current_options.is_empty():
		# Member already owns everything available at this level (edge case) — nothing to
		# choose, so this step is a no-op: drop it and move straight to the next one.
		GameState.pending_level_ups.remove_at(0)
		_show_next_step()
		return
	AudioManager.play_sfx("level_up")
	_title.text = "%s alcanza el nivel %d!" % [step.get("member_name", ""), step.get("level", 0)]

	# free() (not queue_free()) — see CharacterSelection._show_feat_step for why: queue_free
	# defers removal to end-of-frame, so the immediate _update_highlight() call below would
	# still see the previous step's stale labels mixed in with the new ones.
	for child in _options_container.get_children():
		child.free()

	for feat_id in _current_options:
		var feat = DataLoader.get_feat(feat_id)
		var label = Label.new()
		label.text = "%s — %s" % [feat.get("name", feat_id), feat.get("description", "")]
		label.add_theme_font_size_override("font_size", 20)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(900, 0)
		_options_container.add_child(label)

	_selected_index = 0
	_update_highlight()

func _update_highlight() -> void:
	var children = _options_container.get_children()
	for i in range(children.size()):
		if i == _selected_index:
			children[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			children[i].add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

func _unhandled_input(event: InputEvent) -> void:
	if _current_options.is_empty():
		return
	if event.is_action_pressed("move_up"):
		_selected_index = maxi(0, _selected_index - 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_selected_index = mini(_current_options.size() - 1, _selected_index + 1)
		_update_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("action1"):
		var chosen_feat_id = str(_current_options[_selected_index])
		GameState.apply_level_up_choice(_current_member_id, chosen_feat_id)
		GameState.pending_level_ups.remove_at(0)
		_current_options = []
		_show_next_step()
		get_viewport().set_input_as_handled()
