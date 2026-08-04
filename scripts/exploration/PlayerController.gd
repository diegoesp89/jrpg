extends CharacterBody3D
class_name PlayerController
## PlayerController — Handles player movement

const MOVE_SPEED: float = 5.0
const INTERACTION_RANGE: float = 2.0

## The walk is a hop, not a frame animation: the party art is a single frame per character, so
## there is no walk cycle to play. abs(sin) rather than sin, because that gives the bounce its
## sharp landing and rounded apex instead of an even float.
const WALK_HOP_HEIGHT: float = 0.16
const WALK_HOP_SPEED: float = 11.0
const SPRITE_BASE_Y: float = 0.8

## Turning is a Paper Mario flip: the sprite swings around its own vertical axis, going edge-on
## and thin at the halfway point. Done with scale.x through zero rather than a real Y rotation,
## because the sprite is billboarded — billboarding overrides node rotation every frame, so a
## rotated sprite would simply snap back to facing the camera. Mirroring reads identically.
const TURN_SPEED: float = 7.0
## Ignore facing changes below this much sideways movement, so walking straight at or away from
## the camera does not make the character waver between left and right.
const TURN_DEADZONE: float = 0.25

## A soft round shadow pinned to the floor. Without it a hopping billboard reads as floating —
## the hop is what makes the contact point matter, so the two go together.
##
## Note on how much this actually shows: a shadow can only darken what is already there, and this
## dungeon's floor art sits at a median luminance of 26/255 (the wall art is 112). Under the fog
## it reaches the screen at about 11. So the shadow reads on lit ground — inside a torch's pool —
## and is close to invisible on the plain floor, because there is no brightness left to take away.
## Raising the alpha further does nothing; the floor art is what would have to change.
const SHADOW_SIZE: float = 0.62
const SHADOW_ALPHA: float = 0.55

var _current_interactable: Node = null
var _movement_disabled: bool = false
var _is_moving: bool = false
var _hop_phase: float = 0.0
var _facing: float = 1.0
var _facing_target: float = 1.0
var _shadow: Sprite3D = null

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _interaction_area: Area3D = $InteractionArea

signal interactable_changed(interactable: Node)

func _ready() -> void:
	add_to_group("player")
	_apply_lead_sprite()
	_build_shadow()

## Built in code rather than added to Player.tscn so the gradient and the sizing live next to the
## hop that depends on them.
func _build_shadow() -> void:
	_shadow = Sprite3D.new()
	_shadow.texture = _make_shadow_texture()
	# Flat on the ground, and NOT billboarded — a shadow that turns to face the camera is the one
	# thing that would give away that none of this is really 3D.
	_shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_shadow.rotation_degrees.x = -90.0
	_shadow.position.y = 0.02
	_shadow.pixel_size = SHADOW_SIZE / 64.0
	_shadow.shaded = false
	_shadow.transparent = true
	_shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	# Linear here on purpose: this is a soft gradient, not pixel art, and nearest would band it
	# into visible rings.
	_shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_shadow.render_priority = -1
	add_child(_shadow)

## A radial falloff, dark in the middle and gone at the rim.
static func _make_shadow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, SHADOW_ALPHA), Color(0, 0, 0, SHADOW_ALPHA * 0.5), Color(0, 0, 0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

## Draws whichever party member is currently being led. Falls back to a placeholder when there is
## no party at all — the map editor and the debug boot paths both reach this scene that way.
func _apply_lead_sprite() -> void:
	if not _sprite:
		return
	var member := _lead_member()
	if member.is_empty():
		_sprite.texture = _create_placeholder_texture(Color(0.2, 0.4, 0.9), Color(0.1, 0.2, 0.6))
	else:
		_sprite.texture = CharacterSprites.get_battle_texture(member)
	_sprite.region_enabled = false
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Nearest, so the pixel art stays pixel art at this magnification.
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.render_priority = 0

func _lead_member() -> Dictionary:
	if GameState.party.is_empty():
		return {}
	GameState.lead_index = posmod(GameState.lead_index, GameState.party.size())
	return GameState.party[GameState.lead_index]

## Q / E walk as the previous / next party member. Cosmetic only: nothing about the party, the
## turn order or the stats changes, just who you are looking at.
func cycle_lead(step: int) -> void:
	if GameState.party.size() < 2:
		return
	GameState.lead_index = posmod(GameState.lead_index + step, GameState.party.size())
	_apply_lead_sprite()

func _physics_process(delta: float) -> void:
	if _movement_disabled:
		velocity = Vector3.ZERO
		_is_moving = false
		_settle_sprite(delta)
		move_and_slide()
		return

	# Get input direction
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	# Convert 2D input to 3D direction relative to current camera
	var camera = get_viewport().get_camera_3d()
	var cam_right := Vector3.RIGHT
	var cam_forward := Vector3.FORWARD
	if camera:
		cam_right = camera.global_basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		cam_forward = -camera.global_basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
	var move_dir = cam_right * input_dir.x + cam_forward * -input_dir.y

	velocity = move_dir * MOVE_SPEED
	velocity.y = 0
	move_and_slide()

	_is_moving = input_dir.length() > 0.1
	# Which way to face: how much of the movement runs along the camera's right, not along world
	# X, so the flip stays correct whatever angle the camera sits at.
	if _is_moving:
		var sideways: float = move_dir.dot(cam_right)
		if absf(sideways) > TURN_DEADZONE:
			_facing_target = 1.0 if sideways > 0.0 else -1.0
	_animate_sprite(delta)

## The hop, the turn and the shadow, all driven off the same frame.
func _animate_sprite(delta: float) -> void:
	if not _sprite:
		return

	# Turn: swing towards the target facing. Passing through zero is the flip — the sprite goes
	# edge-on and thin for an instant, exactly as a sheet of paper turning would.
	_facing = move_toward(_facing, _facing_target, delta * TURN_SPEED)
	_sprite.scale.x = _facing if absf(_facing) > 0.001 else 0.001

	var height := 0.0
	if _is_moving:
		_hop_phase += delta * WALK_HOP_SPEED
		height = absf(sin(_hop_phase)) * WALK_HOP_HEIGHT
	else:
		_hop_phase = 0.0
	_sprite.position.y = move_toward(_sprite.position.y, SPRITE_BASE_Y + height, delta * 1.6)

	# The shadow shrinks and fades as the character rises, which is what sells the hop as a hop
	# rather than the sprite just sliding upward.
	if _shadow:
		var lift: float = clampf(height / maxf(WALK_HOP_HEIGHT, 0.001), 0.0, 1.0)
		var shrink: float = 1.0 - lift * 0.22
		_shadow.scale = Vector3(shrink, shrink, shrink)
		_shadow.modulate.a = 1.0 - lift * 0.3

## Eases back down to standing rather than snapping, so stopping mid-hop does not drop.
func _settle_sprite(delta: float) -> void:
	_is_moving = false
	_animate_sprite(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _movement_disabled:
		return
	if event.is_action_pressed("action1") and _current_interactable:
		if _current_interactable.has_method("interact"):
			_current_interactable.interact()
	elif event.is_action_pressed("lead_next"):
		cycle_lead(1)
	elif event.is_action_pressed("lead_prev"):
		cycle_lead(-1)

func set_movement_disabled(disabled: bool) -> void:
	_movement_disabled = disabled
	if disabled:
		velocity = Vector3.ZERO

func is_movement_disabled() -> bool:
	return _movement_disabled

func _on_interaction_area_body_entered(body: Node3D) -> void:
	if body.has_method("interact") and body.has_method("get_prompt_text"):
		if not body.has_method("is_available") or body.is_available():
			_current_interactable = body
			interactable_changed.emit(_current_interactable)

func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body == _current_interactable:
		_current_interactable = null
		interactable_changed.emit(null)

func _on_interaction_area_area_entered(area: Area3D) -> void:
	var parent = area.get_parent()
	if parent and parent.has_method("interact") and parent.has_method("get_prompt_text"):
		if not parent.has_method("is_available") or parent.is_available():
			_current_interactable = parent
			interactable_changed.emit(_current_interactable)

func _on_interaction_area_area_exited(area: Area3D) -> void:
	var parent = area.get_parent()
	if parent == _current_interactable:
		_current_interactable = null
		interactable_changed.emit(null)

static func _create_placeholder_texture(fill_color: Color, border_color: Color) -> ImageTexture:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(fill_color)
	for i in range(32):
		img.set_pixel(i, 0, border_color)
		img.set_pixel(i, 31, border_color)
		img.set_pixel(0, i, border_color)
		img.set_pixel(31, i, border_color)
	for x in range(10, 14):
		for y in range(10, 14):
			img.set_pixel(x, y, Color.WHITE)
	for x in range(18, 22):
		for y in range(10, 14):
			img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
