extends Node3D
class_name CameraFollow
## CameraFollow — Smooth isometric camera, quasi-orthographic look (low FOV + far distance).

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(7, 9, 7)
@export var fov: float = 50.0

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
var _offset_dir: Vector3  # normalized offset direction, set once
var _dist: float = 0.0    # offset.length()

# Internal state for delayed engage / smooth settle
var _player_moving: bool = false
var _move_timer: float = 0.0
var _current_follow_factor: float = 0.0

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)
	_offset_dir = offset.normalized()
	_dist = offset.length()
	if _camera:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov
		_camera.near = 0.05
		_camera.far = 1000.0
	if _target:
		global_position = _target.global_position + _offset_dir * _dist
		_apply_fixed_rotation()

func _apply_fixed_rotation() -> void:
	if not _camera or not _target:
		return
	var look_from = global_position
	var look_to = _target.global_position
	if look_from.is_equal_approx(look_to):
		return
	_camera.global_position = look_from
	_camera.look_at(look_to, Vector3.UP)

func _process(delta: float) -> void:
	if not _target:
		return

	var target_pos = _target.global_position + _offset_dir * _dist
	var distance = global_position.distance_to(target_pos)

	var player_vel_len := 0.0
	if _target is CharacterBody3D:
		player_vel_len = _target.velocity.length()
	_player_moving = player_vel_len > 0.1

	# --- Ramp follow factor ---
	if _player_moving:
		_move_timer += delta
		if _move_timer >= engage_delay:
			_current_follow_factor = minf(1.0, _current_follow_factor + follow_ramp_up * delta)
	else:
		_move_timer = 0.0
		_current_follow_factor = maxf(0.0, _current_follow_factor - follow_ramp_down * delta)

	# --- Move camera ---
	if distance > deadzone:
		var lerp_factor: float
		if _player_moving and _current_follow_factor < 0.99:
			lerp_factor = clampf(follow_speed_max * _current_follow_factor * delta, 0.0, 1.0)
		else:
			lerp_factor = clampf(follow_speed_max * delta, 0.0, 1.0)
		global_position = global_position.lerp(target_pos, lerp_factor)

func set_target(node: Node3D) -> void:
	_target = node
	if _target:
		global_position = _target.global_position + _offset_dir * _dist
		_apply_fixed_rotation()
