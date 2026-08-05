extends Control
class_name CreditsBackdrop
## CreditsBackdrop — a looping daytime road: sky, grass, a dirt path, and two parallax layers of
## trees scrolling right-to-left so the party (drawn on top by CreditsScreen) reads as walking
## right forever. Same "drawn, not painted" approach as BattleBackdrop.gd — no road/grass/tree art
## exists in the project, so this is fully procedural, no PNG to fall back from.

const SKY_HORIZON := 0.42   # fraction of height where sky meets grass
const PATH_TOP := 0.70      # fraction of height where the path band starts
const PATH_BOTTOM := 0.86   # ...and ends — the party walks inside this band

const SKY_TOP := Color(0.55, 0.75, 0.92)
const SKY_BOTTOM := Color(0.80, 0.90, 0.96)
const GRASS_FAR := Color(0.36, 0.60, 0.28)
const GRASS_NEAR := Color(0.28, 0.52, 0.20)
const PATH_COLOR := Color(0.62, 0.52, 0.34)
const PATH_EDGE := Color(0.46, 0.38, 0.24)

const BACK_TREE_COUNT := 7
const FRONT_TREE_COUNT := 5
const BACK_TREE_SPEED := 26.0
const FRONT_TREE_SPEED := 70.0
const BACK_TRUNK := Color(0.32, 0.23, 0.15)
const BACK_LEAVES := Color(0.22, 0.44, 0.22)
const FRONT_TRUNK := Color(0.36, 0.24, 0.14)
const FRONT_LEAVES := Color(0.17, 0.48, 0.19)

var _content: Control = null
## Each entry: {x: float, scale: float}. Re-rolled on wraparound so the loop never reads as an
## obviously repeating single tree.
var _back_trees: Array = []
var _front_trees: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_seed_trees()
	set_process(true)

func _build() -> void:
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.texture = _linear_gradient([[0.0, SKY_TOP], [1.0, SKY_BOTTOM]])
	add_child(sky)

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_scene)
	add_child(_content)

	resized.connect(_seed_trees)

func _seed_trees() -> void:
	var w := maxf(size.x, 100.0)
	_back_trees = _make_row(BACK_TREE_COUNT, w)
	_front_trees = _make_row(FRONT_TREE_COUNT, w)

func _make_row(count: int, w: float) -> Array:
	var row: Array = []
	var spacing := w / float(count)
	for i in range(count):
		row.append({
			"x": i * spacing + randf_range(-spacing * 0.2, spacing * 0.2),
			"scale": randf_range(0.8, 1.25),
		})
	return row

## Trees scroll every frame regardless of whether anything else in the scene is animating —
## the "infinite walk" illusion depends entirely on this never pausing.
func _process(delta: float) -> void:
	var w := size.x
	if w < 10.0:
		return
	_scroll_row(_back_trees, BACK_TREE_SPEED, delta, w)
	_scroll_row(_front_trees, FRONT_TREE_SPEED, delta, w)
	_content.queue_redraw()

func _scroll_row(row: Array, speed: float, delta: float, w: float) -> void:
	for t in row:
		t["x"] -= speed * delta
		if t["x"] < -80.0:
			t["x"] += w + 160.0
			t["scale"] = randf_range(0.8, 1.25)

func _draw_scene() -> void:
	var w := size.x
	var h := size.y
	if w < 10.0 or h < 10.0:
		return

	var horizon_y := h * SKY_HORIZON
	var path_top_y := h * PATH_TOP
	var path_bottom_y := h * PATH_BOTTOM

	_content.draw_rect(Rect2(0, horizon_y, w, path_top_y - horizon_y), GRASS_FAR, true)
	_content.draw_rect(Rect2(0, path_top_y - 4, w, 4), PATH_EDGE, true)
	_content.draw_rect(Rect2(0, path_top_y, w, path_bottom_y - path_top_y), PATH_COLOR, true)
	_content.draw_rect(Rect2(0, path_bottom_y, w, 4), PATH_EDGE, true)
	_content.draw_rect(Rect2(0, path_bottom_y + 4, w, h - (path_bottom_y + 4)), GRASS_NEAR, true)

	for t in _back_trees:
		_draw_tree(t, horizon_y + 6.0, 0.75, BACK_TRUNK, BACK_LEAVES)
	for t in _front_trees:
		_draw_tree(t, path_bottom_y + 10.0, 1.35, FRONT_TRUNK, FRONT_LEAVES)

## Trunk = a rect, canopy = three overlapping circles — cheap, but reads fine at credits-scroll
## viewing distance and stays perfectly crisp (no texture, so filtering never enters into it).
func _draw_tree(t: Dictionary, base_y: float, base_scale: float, trunk_color: Color, leaves_color: Color) -> void:
	var s: float = base_scale * float(t.get("scale", 1.0))
	var x: float = float(t.get("x", 0.0))
	var trunk_w := 8.0 * s
	var trunk_h := 34.0 * s
	_content.draw_rect(Rect2(x - trunk_w * 0.5, base_y - trunk_h, trunk_w, trunk_h), trunk_color, true)
	var canopy_r := 26.0 * s
	var canopy_y := base_y - trunk_h - canopy_r * 0.5
	_content.draw_circle(Vector2(x, canopy_y), canopy_r, leaves_color)
	_content.draw_circle(Vector2(x - canopy_r * 0.5, canopy_y + canopy_r * 0.35), canopy_r * 0.7, leaves_color)
	_content.draw_circle(Vector2(x + canopy_r * 0.5, canopy_y + canopy_r * 0.35), canopy_r * 0.7, leaves_color)

func _linear_gradient(stops: Array) -> GradientTexture2D:
	# Assigning offsets/colors wholesale rather than removing the default 2 stops — see the
	# identical note in BattleBackdrop.gd (remove_point() refuses to go below 1, washing the ramp).
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(float(s[0]))
		colors.append(s[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex
