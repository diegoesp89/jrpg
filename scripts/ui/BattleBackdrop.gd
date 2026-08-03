extends Control
## BattleBackdrop — the battlefield's floor and air, so the fight happens somewhere instead of in
## a black void.
##
## Built out of gradients, the CC0 stone tile the dungeon already uses, and a drawn rune, rather
## than a painted background: there is no painted art in the project and none I can source. That
## limit shapes the design — this leans on light and geometry (a horizon, a receding floor, a
## sigil, a vignette) instead of detail, which is also what keeps 32px sprites readable on top of
## it. Drop a real painting in later and the honest move is to replace the sky and floor layers
## with a single TextureRect; the rune and vignette still work over it.

const FLOOR_TILE_PATH := "res://assets/sprites/dungeon/floor_gray0.png"
## Where the wall stops and the ground starts, as a fraction of the battlefield's height.
const HORIZON := 0.46
## How much the stone tiles are magnified. The source art is 32px; at 1:1 the floor turns into
## visual noise at this screen size and fights the sprites for attention.
const TILE_ZOOM := 3

var _rune_layer: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	# 1. The air: a cold vault above, warming as it approaches the ground.
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.texture = _linear_gradient([
		[0.00, Color(0.030, 0.035, 0.065)],
		[0.55, Color(0.055, 0.050, 0.080)],
		[1.00, Color(0.115, 0.085, 0.080)],
	])
	add_child(sky)

	# 2. The ground, from the horizon down.
	var floor_rect := TextureRect.new()
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor_rect.anchor_top = HORIZON
	floor_rect.stretch_mode = TextureRect.STRETCH_TILE
	floor_rect.texture = _zoomed_tile()
	floor_rect.modulate = Color(0.92, 0.86, 0.82, 1.0)
	add_child(floor_rect)

	# 3. Depth on the ground: dark where it meets the wall, opening up towards the camera. Doing
	#    it with light rather than with real perspective keeps the sprite rows on a flat plane,
	#    which is what the three zone bands need to stay legible.
	var floor_shade := TextureRect.new()
	floor_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor_shade.anchor_top = HORIZON
	floor_shade.texture = _linear_gradient([
		[0.00, Color(0.0, 0.0, 0.02, 0.72)],
		[0.30, Color(0.0, 0.0, 0.0, 0.22)],
		[1.00, Color(0.10, 0.05, 0.0, 0.06)],
	])
	add_child(floor_shade)

	# 4. The sigil the fight stands on.
	_rune_layer = Control.new()
	_rune_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rune_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rune_layer.draw.connect(_draw_rune)
	add_child(_rune_layer)

	# 5. Vignette last, so it darkens everything and pushes the eye to the middle.
	var vignette := TextureRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.texture = _radial_vignette()
	add_child(vignette)

	resized.connect(func(): if _rune_layer: _rune_layer.queue_redraw())

## An 8-pointed star inside a ring, squashed vertically so it reads as lying on the ground rather
## than hanging in the air.
func _draw_rune() -> void:
	var w := size.x
	var h := size.y
	if w < 10.0 or h < 10.0:
		return
	var center := Vector2(w * 0.5, h * (HORIZON + 0.42))
	var radius := w * 0.30
	var squash := 0.30
	var ink := Color(0.85, 0.72, 0.45, 0.13)

	_ring(center, radius, squash, ink, 3.0)
	_ring(center, radius * 0.88, squash, Color(ink, 0.07), 2.0)

	var star: PackedVector2Array = []
	for i in range(16):
		var r := radius * (0.86 if i % 2 == 0 else 0.36)
		var a := TAU * float(i) / 16.0 - PI * 0.5
		star.append(center + Vector2(cos(a) * r, sin(a) * r * squash))
	star.append(star[0])
	_rune_layer.draw_polyline(star, Color(ink, 0.10), 3.0, true)

func _ring(center: Vector2, radius: float, squash: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = []
	for i in range(65):
		var a := TAU * float(i) / 64.0
		pts.append(center + Vector2(cos(a) * radius, sin(a) * radius * squash))
	_rune_layer.draw_polyline(pts, col, width, true)

# --- Texture helpers -----------------------------------------------------------------------

func _linear_gradient(stops: Array) -> GradientTexture2D:
	# Assigning the offsets/colours arrays wholesale, rather than removing the two stops a new
	# Gradient ships with: remove_point() refuses to go below one point, so clearing it that way
	# leaves a stray default stop behind (and logs an error) — which washed the whole ramp out.
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(float(s[0]))
		colors.append(s[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 256
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t

func _radial_vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.00, 0.62, 1.00])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.62),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

## The stone tile scaled up with nearest-neighbour, so magnifying it keeps the pixel art crisp
## instead of turning it into blur.
func _zoomed_tile() -> Texture2D:
	var src := load(FLOOR_TILE_PATH) as Texture2D
	if src == null:
		return null
	var img := src.get_image()
	img.resize(img.get_width() * TILE_ZOOM, img.get_height() * TILE_ZOOM, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
