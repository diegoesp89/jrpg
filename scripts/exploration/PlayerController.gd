extends CharacterBody3D
class_name PlayerController
## PlayerController — Handles player movement

const MOVE_SPEED: float = 5.0
const INTERACTION_RANGE: float = 2.0
const ANIM_FPS: float = 6.0  # frames per second for walk animation

# Spritesheet path
const SPRITESHEET_PATH = "res://assets/sprites/spritesheet.png"
# Background color to replace with transparency
const BG_COLOR = Color(255.0/255.0, 5.0/255.0, 238.0/255.0)
const BG_TOLERANCE = 0.05

## Walk cycle frame regions (Rect2: x, y, w, h) from spritesheet analysis.
## Band 2 (y=84..114): 12 frames = 4 directions x 3 frames each.
## Order in spritesheet: down(3), left(3), right(3), up(3)
## Using uniform 26x30 cells centered on each sprite.
const FRAME_W: int = 26
const FRAME_H: int = 30

# Direction enum
enum Dir { DOWN, LEFT, RIGHT, UP }

# Frame rects per direction: 3 frames each (left-step, center, right-step)
# Band 2 frames - x positions based on content centers
var _dir_frames: Dictionary = {}

var _current_interactable: Node = null
var _movement_disabled: bool = false
var _current_dir: int = Dir.DOWN
var _anim_timer: float = 0.0
var _anim_frame: int = 1  # start on center frame (idle)
var _is_moving: bool = false
var _sprite_texture: Texture2D = null

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _interaction_area: Area3D = $InteractionArea

signal interactable_changed(interactable: Node)

func _ready() -> void:
	add_to_group("player")
	_init_frame_rects()
	_load_spritesheet()
	_setup_sprite()

func _init_frame_rects() -> void:
	# Frame x-centers derived from spritesheet analysis (band 2, y=84)
	# Down: frames 0-2, Left: frames 3-5, Right: frames 6-8, Up: frames 9-11
	var band_y: int = 84
	var frame_x_starts = [3, 27, 51, 84, 107, 129, 163, 186, 219, 243, 275, 300]

	_dir_frames[Dir.DOWN] = [
		Rect2(frame_x_starts[0], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[1], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[2], band_y, FRAME_W, FRAME_H),
	]
	_dir_frames[Dir.LEFT] = [
		Rect2(frame_x_starts[3], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[4], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[5], band_y, FRAME_W, FRAME_H),
	]
	_dir_frames[Dir.RIGHT] = [
		Rect2(frame_x_starts[6], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[7], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[8], band_y, FRAME_W, FRAME_H),
	]
	_dir_frames[Dir.UP] = [
		Rect2(frame_x_starts[9], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[10], band_y, FRAME_W, FRAME_H),
		Rect2(frame_x_starts[11], band_y, FRAME_W, FRAME_H),
	]

func _load_spritesheet() -> void:
	var tex = load(SPRITESHEET_PATH) as Texture2D
	if not tex:
		push_warning("PlayerController: spritesheet not found at %s" % SPRITESHEET_PATH)
		return

	# Get the image and replace background with transparency
	var img = tex.get_image()
	if not img:
		push_warning("PlayerController: could not get image from spritesheet")
		return

	# Convert to RGBA if needed
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	# Replace BG color with transparent
	var bg_r = BG_COLOR.r
	var bg_g = BG_COLOR.g
	var bg_b = BG_COLOR.b
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var px = img.get_pixel(x, y)
			if absf(px.r - bg_r) < BG_TOLERANCE and absf(px.g - bg_g) < BG_TOLERANCE and absf(px.b - bg_b) < BG_TOLERANCE:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	_sprite_texture = ImageTexture.create_from_image(img)

func _setup_sprite() -> void:
	if not _sprite:
		return
	if _sprite_texture:
		_sprite.texture = _sprite_texture
		_sprite.region_enabled = true
		_sprite.region_rect = _dir_frames[Dir.DOWN][1]  # center/idle frame facing down
	else:
		# Fallback to placeholder
		_sprite.texture = _create_placeholder_texture(Color(0.2, 0.4, 0.9), Color(0.1, 0.2, 0.6))
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 0.05
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.render_priority = 0

func _physics_process(delta: float) -> void:
	if _movement_disabled:
		velocity = Vector3.ZERO
		_is_moving = false
		_set_idle_frame()
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

	# Update animation direction and frame
	if input_dir.length() > 0.1:
		_is_moving = true
		_update_direction(input_dir)
		_update_animation(delta)
	else:
		if _is_moving:
			_is_moving = false
			_set_idle_frame()

func _update_direction(input_dir: Vector2) -> void:
	# Choose direction based on dominant input axis
	# input_dir: x>0 = right, x<0 = left, y>0 = down, y<0 = up
	if absf(input_dir.x) > absf(input_dir.y):
		_current_dir = Dir.RIGHT if input_dir.x > 0 else Dir.LEFT
	else:
		_current_dir = Dir.DOWN if input_dir.y > 0 else Dir.UP

func _update_animation(delta: float) -> void:
	_anim_timer += delta
	var frame_duration = 1.0 / ANIM_FPS
	if _anim_timer >= frame_duration:
		_anim_timer -= frame_duration
		# Cycle through 0, 1, 2, 1, 0, 1, 2, ... (ping-pong for smooth walk)
		_anim_frame = (_anim_frame + 1) % 4
	_apply_frame()

func _set_idle_frame() -> void:
	_anim_frame = 1  # center frame
	_anim_timer = 0.0
	_apply_frame()

func _apply_frame() -> void:
	if not _sprite or not _sprite.region_enabled:
		return
	if _current_dir not in _dir_frames:
		return
	var frames = _dir_frames[_current_dir]
	# Ping-pong pattern: 0→1→2→1→0→1→2→...
	var actual_frame: int
	match _anim_frame:
		0: actual_frame = 0
		1: actual_frame = 1
		2: actual_frame = 2
		3: actual_frame = 1
		_: actual_frame = 1
	_sprite.region_rect = frames[actual_frame]

func _unhandled_input(event: InputEvent) -> void:
	if _movement_disabled:
		return
	if event.is_action_pressed("action1") and _current_interactable:
		if _current_interactable.has_method("interact"):
			_current_interactable.interact()

func set_movement_disabled(disabled: bool) -> void:
	_movement_disabled = disabled
	if disabled:
		velocity = Vector3.ZERO

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
