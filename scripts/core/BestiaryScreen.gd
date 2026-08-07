extends Node
class_name BestiaryScreen
## BestiaryScreen — Read-only compendium of every enemy the party has actually fought at least
## once (SaveManager.mark_enemy_seen(), called from BattleController._setup_enemies() the moment
## an enemy appears in a fight). Reached from ContinueScreen's "Bestiario". Unlike Logros, an
## unseen enemy is real spoiler content (its name, stats and sprite), so those rows stay fully
## hidden behind "???" instead of dimmed-but-readable.

const SCROLL_STEP := 70

var _root: Control
var _scroll: ScrollContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var seen: Array = SaveManager.get_profile().get("seen_enemies", [])
	var enemies: Array = DataLoader.get_all_enemies()
	enemies.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))

	var title = Label.new()
	title.text = "Bestiario (%d/%d)" % [seen.size(), enemies.size()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 90
	_root.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 200
	_scroll.offset_right = -200
	_scroll.offset_top = 110
	_scroll.offset_bottom = -70
	_root.add_child(_scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	_scroll.add_child(list)

	for e in enemies:
		var id = str(e.get("id", ""))
		_add_row(list, e, seen.has(id))

	var hint = Label.new()
	hint.text = "Arriba/Abajo: Desplazar  |  Z / Esc: Volver"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	_root.add_child(hint)

func _add_row(parent: VBoxContainer, enemy: Dictionary, is_seen: bool) -> void:
	var panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.9) if is_seen else Color(0.07, 0.07, 0.08, 0.7)
	style.border_color = Color(0.75, 0.35, 0.3) if is_seen else Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	if is_seen:
		var tex = EnemySprites.get_texture(enemy)
		if tex:
			var portrait = TextureRect.new()
			portrait.texture = tex
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			portrait.custom_minimum_size = Vector2(48, 48)
			row.add_child(portrait)
	else:
		var lock = Label.new()
		lock.text = "🔒"
		lock.add_theme_font_size_override("font_size", 28)
		lock.custom_minimum_size = Vector2(48, 0)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(lock)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	row.add_child(vbox)

	var name_label = Label.new()
	name_label.text = str(enemy.get("name", "???")) if is_seen else "???"
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.75) if is_seen else Color(0.55, 0.55, 0.6))
	vbox.add_child(name_label)

	if not is_seen:
		return

	var stats_label = Label.new()
	stats_label.text = "HP %d   CA %d   Daño %s   XP %d   Oro %d" % [
		int(enemy.get("hp", 0)), int(enemy.get("ca", 10)), str(enemy.get("damage", "")),
		int(enemy.get("xp_reward", 0)), int(enemy.get("gold_reward", 0)),
	]
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	vbox.add_child(stats_label)

	var skill_names: Array = []
	for skill_id in enemy.get("skills", []):
		var skill = DataLoader.get_skill(str(skill_id))
		skill_names.append(str(skill.get("name", skill_id)))
	if not skill_names.is_empty():
		var skills_label = Label.new()
		skills_label.text = "Habilidades: %s" % ", ".join(skill_names)
		skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skills_label.add_theme_font_size_override("font_size", 15)
		skills_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		vbox.add_child(skills_label)

func _unhandled_input(event: InputEvent) -> void:
	# allow_echo so holding the key keeps scrolling instead of needing repeated taps.
	if event.is_action_pressed("move_up", true):
		_scroll.scroll_vertical -= SCROLL_STEP
	elif event.is_action_pressed("move_down", true):
		_scroll.scroll_vertical += SCROLL_STEP
	elif event.is_action_pressed("action1") or event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
	else:
		return
	get_viewport().set_input_as_handled()
