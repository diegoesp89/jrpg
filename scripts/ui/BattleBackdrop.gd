extends Control
## BattleBackdrop — a torchlit stone corridor for the fight to happen in.
##
## Drawn, not painted: there is no background art in the project and none I can source. So the
## corridor is built from the one thing a 2D canvas fakes convincingly — a real perspective grid.
## Floor blocks and wall courses share one vanishing point, and every block is then shaded by an
## actual little lighting model: a list of torches in screen space, each block asking how much
## light reaches it. That is what makes the pools fall across floor AND wall together instead of
## looking like circles pasted on top.
##
## Sprites stand on this, so the middle of the corridor is deliberately the darkest, flattest part
## of the frame — the light is pushed out to the walls, where nothing has to stay readable.
##
## If real painted art turns up later, the swap is to drop a TextureRect in place of the corridor
## layer and keep the vignette over it.

## Where the corridor's far end sits, as a fraction of the battlefield's height.
const HORIZON := 0.30
## The grid. Rows recede geometrically so they bunch towards the vanishing point the way real ones
## do. The floor is exactly COLS wide, so its outer edge is where the walls stand.
const ROWS := 20
const COLS := 8
const Z_NEAR := 1.0
const Z_FAR := 22.0
const TILE_WIDTH := 250.0
const WALL_HEIGHT := 620.0
const WALL_COURSES := 5

## Stone under two very different lights: cold damp ambient, warm fire.
const STONE_COOL := Color(0.105, 0.130, 0.205)
const STONE_WALL := Color(0.085, 0.100, 0.160)
const STONE_LIT := Color(0.92, 0.52, 0.22)
const HAZE := Color(0.30, 0.36, 0.56)
const GROUT := Color(0.03, 0.035, 0.06, 0.55)

## Torch positions as (depth 0..1 along the corridor, height up the wall).
const TORCH_PLACEMENTS := [[0.06, 0.62], [0.30, 0.60], [0.55, 0.58], [0.76, 0.56]]

var _corridor: Control = null
## Screen-space lights rebuilt each redraw: {pos, radius, strength}.
var _lights: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.texture = _linear_gradient([
		[0.00, Color(0.014, 0.020, 0.042)],
		[0.35, Color(0.032, 0.040, 0.075)],
		[1.00, Color(0.020, 0.024, 0.045)],
	])
	add_child(sky)

	_corridor = Control.new()
	_corridor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_corridor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corridor.draw.connect(_draw_corridor)
	add_child(_corridor)

	var vignette := TextureRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.texture = _radial_vignette()
	add_child(vignette)

	resized.connect(func(): if _corridor: _corridor.queue_redraw())

# --- Perspective ----------------------------------------------------------------------------

## Screen y of the floor line and the lateral scale, per grid row. Both fall out of the row's
## depth, which is what makes the rows converge instead of merely getting shorter.
func _row_geometry(h: float, horizon: float) -> Array:
	var ys: Array[float] = []
	var ks: Array[float] = []
	for i in range(ROWS + 1):
		var t := float(i) / float(ROWS)
		var z: float = Z_NEAR * pow(Z_FAR / Z_NEAR, t)
		var k: float = Z_NEAR / z
		ys.append(horizon + (h - horizon) * k)
		ks.append(k)
	return [ys, ks]

func _draw_corridor() -> void:
	var w := size.x
	var h := size.y
	if w < 10.0 or h < 10.0:
		return
	var horizon := h * HORIZON
	var cx := w * 0.5
	var geom := _row_geometry(h, horizon)
	var ys: Array[float] = geom[0]
	var ks: Array[float] = geom[1]

	_place_lights(cx, ys, ks)
	_draw_far_end(w, h, horizon, cx, ks)
	_draw_walls(cx, ys, ks)
	_draw_floor(w, cx, ys, ks)
	_draw_flames()

## Torches sit on the wall line at a given depth, so they shrink and converge with everything else.
func _place_lights(cx: float, ys: Array[float], ks: Array[float]) -> void:
	_lights.clear()
	var half := float(COLS) * 0.5 * TILE_WIDTH
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		for placement in TORCH_PLACEMENTS:
			var t: float = float(placement[0])
			var height: float = float(placement[1])
			var row: int = clampi(int(round(t * float(ROWS))), 0, ROWS)
			var k: float = ks[row]
			_lights.append({
				"pos": Vector2(cx + side * half * k, ys[row] - WALL_HEIGHT * height * k),
				"radius": maxf(90.0, 620.0 * k),
				"strength": 1.0,
			})

## How much torchlight reaches a point, 0..1. Quadratic falloff, summed over every torch — that
## sum is what makes two neighbouring torches read as one continuous wash down the wall.
func _light_at(p: Vector2) -> float:
	var total := 0.0
	for light in _lights:
		var d: float = p.distance_to(light["pos"])
		var r: float = light["radius"]
		if d < r:
			var f := 1.0 - d / r
			total += f * f * float(light["strength"])
	return clampf(total, 0.0, 1.0)

# --- Surfaces -------------------------------------------------------------------------------

func _draw_walls(cx: float, ys: Array[float], ks: Array[float]) -> void:
	var half := float(COLS) * 0.5 * TILE_WIDTH
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		for i in range(ROWS):
			var depth := float(i) / float(ROWS)
			var x0: float = cx + side * half * ks[i]
			var x1: float = cx + side * half * ks[i + 1]
			var top0: float = ys[i] - WALL_HEIGHT * ks[i]
			var top1: float = ys[i + 1] - WALL_HEIGHT * ks[i + 1]
			for c in range(WALL_COURSES):
				var v0 := float(c) / float(WALL_COURSES)
				var v1 := float(c + 1) / float(WALL_COURSES)
				var quad := PackedVector2Array([
					Vector2(x0, lerpf(ys[i], top0, v0)),
					Vector2(x1, lerpf(ys[i + 1], top1, v0)),
					Vector2(x1, lerpf(ys[i + 1], top1, v1)),
					Vector2(x0, lerpf(ys[i], top0, v1)),
				])
				var centre := (quad[0] + quad[2]) * 0.5
				# Courses higher up the wall catch less of the fire below them.
				var shade := 1.0 - v0 * 0.35
				_corridor.draw_colored_polygon(quad,
					_stone_color(STONE_WALL, centre, depth, i, c * 7 + int(side) * 3, shade))
				_corridor.draw_polyline(
					PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
					GROUT, maxf(1.0, 2.5 * ks[i]), true)

func _draw_floor(w: float, cx: float, ys: Array[float], ks: Array[float]) -> void:
	for i in range(ROWS):
		var depth := float(i) / float(ROWS)
		for j in range(COLS):
			var off := float(j) - float(COLS) * 0.5
			var quad := PackedVector2Array([
				Vector2(cx + off * TILE_WIDTH * ks[i], ys[i]),
				Vector2(cx + (off + 1.0) * TILE_WIDTH * ks[i], ys[i]),
				Vector2(cx + (off + 1.0) * TILE_WIDTH * ks[i + 1], ys[i + 1]),
				Vector2(cx + off * TILE_WIDTH * ks[i + 1], ys[i + 1]),
			])
			if maxf(quad[0].x, quad[3].x) < -40.0 or minf(quad[1].x, quad[2].x) > w + 40.0:
				continue
			var centre := (quad[0] + quad[2]) * 0.5
			_corridor.draw_colored_polygon(quad, _stone_color(STONE_COOL, centre, depth, i, j, 1.0))
			_corridor.draw_polyline(
				PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
				GROUT, maxf(1.0, 2.5 * ks[i]), true)

## One block's colour: cold stone, warmed by whatever fire reaches it, flattened into the haze
## with distance, and nudged per-block so the grid never reads as a checkerboard. The nudge is a
## hash of the block's coordinates, so it is identical on every redraw and never shimmers.
func _stone_color(base: Color, centre: Vector2, depth: float, i: int, j: int, shade: float) -> Color:
	var lit := _light_at(centre)
	var col := base.lerp(STONE_LIT, lit * 0.88)
	col = col.lerp(HAZE, pow(depth, 1.8) * 0.62)
	var v := (0.87 + 0.26 * _block_noise(i, j)) * shade
	return Color(col.r * v, col.g * v, col.b * v, 1.0)

func _block_noise(i: int, j: int) -> float:
	var n := (i * 73856093) ^ (j * 19349663)
	return float(absi(n) % 997) / 997.0

## The lit far end of the corridor. Light spilling out of it rather than a filled shape: a solid
## quad at this size reads as a grey card floating at the vanishing point, because there is no
## detail left at that scale for it to be anything else.
func _draw_far_end(w: float, h: float, horizon: float, cx: float, ks: Array[float]) -> void:
	var k: float = ks[ROWS]
	var mouth := maxf(70.0, WALL_HEIGHT * k * 1.6)
	var centre := Vector2(cx, horizon - WALL_HEIGHT * k * 0.35)
	_glow(centre, mouth * 2.4, Color(0.38, 0.46, 0.72), 0.34, 9)
	_glow(centre, mouth * 0.9, Color(0.72, 0.76, 0.95), 0.42, 6)
	_glow(centre, mouth * 0.32, Color(0.92, 0.94, 1.0), 0.55, 4)

## The flames themselves, on top of the masonry they are lighting.
func _draw_flames() -> void:
	for light in _lights:
		var p: Vector2 = light["pos"]
		var r: float = light["radius"]
		_glow(p, r * 0.55, Color(1.0, 0.52, 0.14), 0.55, 7)
		_glow(p, r * 0.13, Color(1.0, 0.90, 0.62), 0.85, 4)

## Layered circles, largest and faintest first, building up into a soft falloff.
func _glow(center: Vector2, radius: float, tint: Color, peak: float, layers: int) -> void:
	for i in range(layers):
		var t := float(i) / float(maxi(layers - 1, 1))
		var r := radius * (1.0 - 0.86 * t)
		var a := peak * (0.10 + 0.90 * t * t) / float(layers) * 2.6
		_corridor.draw_circle(center, r, Color(tint, a))

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
	g.offsets = PackedFloat32Array([0.00, 0.52, 1.00])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.08), Color(0, 0, 0, 0.80),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
