extends Node
class_name CreditsScreen
## CreditsScreen — Reached after dismissing the victory screen. The party (whoever is in
## GameState.party at that moment) appears to walk right forever along a looping road while the
## credits crawl up from the map's own data (DataLoader.get_current_map()["credits"]), so they're
## editable placeholder text rather than something baked into code.
##
## GameState.reset() happens HERE, not before — DungeonBuilder used to reset on dismissing the
## victory screen, but this scene needs GameState.party intact to know who to draw walking.

## Preloaded by path rather than through its class_name — see the note in DungeonBuilder.gd on why
## a class_name added this same session can't be trusted by its bare identifier yet.
const BackdropScript = preload("res://scripts/ui/CreditsBackdrop.gd")

## Same hop formula as PlayerController.gd's WALK_HOP_HEIGHT/WALK_HOP_SPEED — abs(sin(phase)) gives
## the sharp-landing "bouncy ball" feel instead of a smooth float. Reimplemented rather than shared
## because PlayerController's version is tightly coupled to a billboarded Sprite3D and turn-facing;
## here it's a handful of Sprite2D nodes with no turning at all.
const HOP_HEIGHT := 10.0
const HOP_SPEED := 11.0
const SPRITE_SCALE := 3.5

# Mirrors CreditsBackdrop's own PATH_TOP/PATH_BOTTOM so the party stands on the drawn path without
# reaching into that script's internals — duplicated on purpose, not imported.
const PATH_TOP := 0.70
const PATH_BOTTOM := 0.86

const CRAWL_SPEED := 60.0   # px/sec, upward

var _root: Control
var _crawl: Control
var _crawl_content_height: float = 0.0
var _walkers: Array = []   # [{sprite: Sprite2D, phase: float, base_y: float}]
var _finished: bool = false

func _ready() -> void:
	_build_ui()
	set_process(true)
	set_process_unhandled_input(true)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop = BackdropScript.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_build_walkers()
	_build_credits_crawl()

	var hint = Label.new()
	hint.text = "Z / X / Esc: Saltar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hint.add_theme_constant_override("outline_size", 3)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -40
	hint.offset_bottom = -12
	_root.add_child(hint)

func _build_walkers() -> void:
	var w := get_viewport().get_visible_rect().size.x
	var h := get_viewport().get_visible_rect().size.y
	var base_y := h * lerpf(PATH_TOP, PATH_BOTTOM, 0.65)
	var party: Array = GameState.party
	if party.is_empty():
		return
	var spacing := 150.0
	var start_x := w * 0.5 - spacing * (float(party.size()) - 1.0) * 0.5
	for i in range(party.size()):
		var member: Dictionary = party[i]
		var sprite := Sprite2D.new()
		sprite.texture = CharacterSprites.get_battle_texture(member)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		sprite.position = Vector2(start_x + spacing * float(i), base_y)
		_root.add_child(sprite)
		_walkers.append({"sprite": sprite, "phase": float(i) * 0.8, "base_y": base_y})

## Parses the map's "credits" array: a line starting with "# " is a big centered title, an empty
## string is a blank spacer, anything else is a normal centered line. Kept dead simple (no bold/
## color markup beyond that) so the Map Editor's plain multiline text box can produce it directly.
func _build_credits_crawl() -> void:
	var lines: Array = DataLoader.get_current_map().get("credits", [])
	if lines.is_empty():
		lines = ["# ¡Gracias por jugar!"]

	_crawl = Control.new()
	_crawl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_crawl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crawl.position.y = get_viewport().get_visible_rect().size.y
	_root.add_child(_crawl)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	vbox.add_theme_constant_override("separation", 10)
	_crawl.add_child(vbox)

	for raw_line in lines:
		var line := str(raw_line)
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 5)
		if line.begins_with("# "):
			lbl.text = line.substr(2)
			lbl.add_theme_font_size_override("font_size", 42)
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		elif line == "":
			lbl.text = " "
			lbl.add_theme_font_size_override("font_size", 20)
		else:
			lbl.text = line
			lbl.add_theme_font_size_override("font_size", 24)
			lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		vbox.add_child(lbl)

	# vbox's own anchors only stretch its WIDTH (top==bottom anchor leaves height at 0 by
	# default) — force it to its real minimum height explicitly rather than trust the anchor
	# system for a dimension it isn't actually driving. get_combined_minimum_size() is a live
	# calculation, not dependent on waiting for a deferred layout pass.
	var min_size := vbox.get_combined_minimum_size()
	vbox.size.y = min_size.y
	_crawl_content_height = min_size.y

func _process(delta: float) -> void:
	for w in _walkers:
		w["phase"] += delta * HOP_SPEED
		var lift: float = absf(sin(w["phase"])) * HOP_HEIGHT
		var sprite: Sprite2D = w["sprite"]
		sprite.position.y = w["base_y"] - lift

	if _crawl == null or _finished:
		return
	_crawl.position.y -= CRAWL_SPEED * delta
	if _crawl.position.y + _crawl_content_height < 0.0:
		_finish()

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event.is_action_pressed("action1") or event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	GameState.reset()
	SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
