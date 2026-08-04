extends CharacterBody3D
class_name PlayerController
## PlayerController — Handles player movement

const MOVE_SPEED: float = 5.0
const INTERACTION_RANGE: float = 2.0

## How high the sprite hops while walking, and how fast. The party art is a single frame per
## character — there is no walk cycle to play — so this is what keeps a moving character from
## looking like it is being slid across the floor.
const WALK_BOB_HEIGHT: float = 0.09
const WALK_BOB_SPEED: float = 9.0
const SPRITE_BASE_Y: float = 0.8

var _current_interactable: Node = null
var _movement_disabled: bool = false
var _is_moving: bool = false
var _bob_phase: float = 0.0

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _interaction_area: Area3D = $InteractionArea

signal interactable_changed(interactable: Node)

func _ready() -> void:
	add_to_group("player")
	_apply_lead_sprite()

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
	_animate_sprite(delta)

## A hop while walking. There is no walk cycle in the party art — one frame per character — so
## the movement has to come from somewhere, and a bob costs nothing and reads at this camera angle.
func _animate_sprite(delta: float) -> void:
	if not _sprite:
		return
	if not _is_moving:
		_settle_sprite(delta)
		return
	_bob_phase += delta * WALK_BOB_SPEED
	_sprite.position.y = SPRITE_BASE_Y + absf(sin(_bob_phase)) * WALK_BOB_HEIGHT

## Eases back down to standing rather than snapping, so stopping mid-hop does not jump.
func _settle_sprite(delta: float) -> void:
	if not _sprite:
		return
	_bob_phase = 0.0
	_sprite.position.y = move_toward(_sprite.position.y, SPRITE_BASE_Y, delta * 0.6)

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
