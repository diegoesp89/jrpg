extends CharacterBody3D
## PlayerController — Handles player movement, interaction detection, and prompt display.

const MOVE_SPEED: float = 5.0
const INTERACTION_RANGE: float = 2.0

var _current_interactable: Node = null
var _movement_disabled: bool = false

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _interaction_area: Area3D = $InteractionArea

signal interactable_changed(interactable: Node)

func _ready() -> void:
	add_to_group("player")
	# Create placeholder texture if none assigned
	if _sprite:
		if not _sprite.texture:
			_sprite.texture = _create_placeholder_texture(Color(0.2, 0.4, 0.9), Color(0.1, 0.2, 0.6))
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.pixel_size = 0.03
		# Alpha scissor so the sprite writes to the depth buffer correctly
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		_sprite.render_priority = 0

func _physics_process(delta: float) -> void:
	if _movement_disabled:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Get input direction (isometric mapping)
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
		# Project camera axes onto the ground (XZ) plane
		cam_right = camera.global_basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		cam_forward = -camera.global_basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
	var move_dir = cam_right * input_dir.x + cam_forward * -input_dir.y

	velocity = move_dir * MOVE_SPEED
	velocity.y = 0  # Stay on ground plane
	move_and_slide()

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
	# Draw border
	for i in range(32):
		img.set_pixel(i, 0, border_color)
		img.set_pixel(i, 31, border_color)
		img.set_pixel(0, i, border_color)
		img.set_pixel(31, i, border_color)
	# Draw simple face/indicator (eyes)
	for x in range(10, 14):
		for y in range(10, 14):
			img.set_pixel(x, y, Color.WHITE)
	for x in range(18, 22):
		for y in range(10, 14):
			img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
