extends Node3D
## CameraFollow — Smooth isometric camera that follows the player.
## Fixed rotation (no tilt). Delayed engage on movement start, smooth settle on stop.

@export var target_path: NodePath
## Offset: lowered Y and brought closer for a less steep angle with perspective.
@export var offset: Vector3 = Vector3(7, 9, 7)
@export var fov: float = 45.0
@export var zoom_speed: float = 2.0
@export var zoom_min: float = 0.4
@export var zoom_max: float = 2.0

## How many seconds to wait after the player starts moving before camera follows.
@export var engage_delay: float = 0.15
## Max follow lerp factor per second (higher = faster catch-up).
@export var follow_speed_max: float = 5.0
## How fast the follow factor ramps up once engaged (ease-in).
@export var follow_ramp_up: float = 3.0
## How fast the follow factor decays when player stops (ease-out / settle).
@export var follow_ramp_down: float = 2.5
## Minimum distance to bother moving the camera.
@export var deadzone: float = 0.05

var _target: Node3D = null
var _zoom_factor: float = 1.0  # multiplier on offset distance (1.0 = default)
var _offset_dir: Vector3      # normalized offset direction, set once

# Internal state for delayed engage / smooth settle
var _player_moving: bool = false
var _move_timer: float = 0.0        # time since player started moving
var _current_follow_factor: float = 0.0  # 0 = not following, 1 = full speed

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)
	_offset_dir = offset.normalized()
	if _camera:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov
		_camera.near = 0.1
		_camera.far = 100.0
	if _target:
		global_position = _target.global_position + offset
		_apply_fixed_rotation()

func _apply_fixed_rotation() -> void:
	if not _camera or not _target:
		return
	# Calculate the look direction from offset toward origin (the player)
	var look_from = _target.global_position + offset
	var look_to = _target.global_position
	if look_from.is_equal_approx(look_to):
		return
	# Temporarily set position, look_at to get the correct basis, then freeze rotation
	_camera.global_position = look_from
	_camera.look_at(look_to, Vector3.UP)
	# Store this rotation — it will never change again

func _process(delta: float) -> void:
	if not _target:
		return

	# --- Zoom (scale offset distance) ---
	if Input.is_action_pressed("zoom_in"):
		_zoom_factor = maxf(zoom_min, _zoom_factor - zoom_speed * delta)
	if Input.is_action_pressed("zoom_out"):
		_zoom_factor = minf(zoom_max, _zoom_factor + zoom_speed * delta)

	# --- Detect if player is moving ---
	var current_offset = _offset_dir * (offset.length() * _zoom_factor)
	var target_pos = _target.global_position + current_offset
	var distance = global_position.distance_to(target_pos)

	# Check if the player CharacterBody3D has velocity
	var player_vel_len := 0.0
	if _target is CharacterBody3D:
		player_vel_len = _target.velocity.length()
	_player_moving = player_vel_len > 0.1

	# --- Ramp follow factor ---
	if _player_moving:
		_move_timer += delta
		if _move_timer >= engage_delay:
			# Ramp up smoothly toward 1.0
			_current_follow_factor = minf(1.0, _current_follow_factor + follow_ramp_up * delta)
	else:
		_move_timer = 0.0
		# Ramp down smoothly toward 0.0 (settle)
		_current_follow_factor = maxf(0.0, _current_follow_factor - follow_ramp_down * delta)

	# --- Move camera ---
	if distance > deadzone:
		var lerp_factor: float
		if _player_moving and _current_follow_factor < 0.99:
			# Player moving but ramp hasn't fully engaged yet — use ramped speed
			lerp_factor = clampf(follow_speed_max * _current_follow_factor * delta, 0.0, 1.0)
		else:
			# Either standing still (settle / zoom / re-center) or fully engaged
			lerp_factor = clampf(follow_speed_max * delta, 0.0, 1.0)
		global_position = global_position.lerp(target_pos, lerp_factor)

func set_target(node: Node3D) -> void:
	_target = node
	if _target:
		var current_offset = _offset_dir * (offset.length() * _zoom_factor)
		global_position = _target.global_position + current_offset
		_apply_fixed_rotation()
