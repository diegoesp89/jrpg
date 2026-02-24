extends Node3D
## CameraFollow — Smooth isometric camera that follows the player.
## Fixed rotation (no tilt). Delayed engage on movement start, smooth settle on stop.
## Zoom controls both distance and projection: zoom out = quasi-orthogonal, zoom in = perspective.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(7, 9, 7)
@export var zoom_speed: float = 2.0
@export var zoom_min: float = 0.4   # closest (most perspective)
@export var zoom_max: float = 2.0   # farthest (most orthogonal)

## FOV range: low FOV at max zoom (ortho-like), high FOV at min zoom (perspective).
@export var fov_at_zoom_min: float = 60.0   # close up: strong perspective
@export var fov_at_zoom_max: float = 8.0    # far out: nearly orthogonal

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
var _offset_dir: Vector3       # normalized offset direction, set once

# Internal state for delayed engage / smooth settle
var _player_moving: bool = false
var _move_timer: float = 0.0
var _current_follow_factor: float = 0.0

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)
	_offset_dir = offset.normalized()
	if _camera:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = _get_fov_for_zoom(_zoom_factor)
		_camera.near = 0.1
		_camera.far = 500.0
	if _target:
		global_position = _target.global_position + offset
		_apply_fixed_rotation()

func _apply_fixed_rotation() -> void:
	if not _camera or not _target:
		return
	var look_from = _target.global_position + offset
	var look_to = _target.global_position
	if look_from.is_equal_approx(look_to):
		return
	_camera.global_position = look_from
	_camera.look_at(look_to, Vector3.UP)

func _get_fov_for_zoom(zoom: float) -> float:
	# Normalize zoom to 0..1 range where 0 = zoom_min (close), 1 = zoom_max (far)
	var t = clampf((zoom - zoom_min) / (zoom_max - zoom_min), 0.0, 1.0)
	# t=0 → close (perspective), t=1 → far (ortho-like)
	return lerpf(fov_at_zoom_min, fov_at_zoom_max, t)

func _get_distance_for_zoom(zoom: float) -> float:
	# The base distance at zoom_factor=1.0 corresponds to fov_at_zoom_min (reference).
	# When FOV shrinks (zoom out), the camera must pull back proportionally
	# to keep (and expand) the visible area.
	# Visible half-width at distance d with fov f: d * tan(f/2)
	# To expand view when FOV shrinks: d = base_dist * tan(ref_fov/2) / tan(current_fov/2)
	var current_fov = _get_fov_for_zoom(zoom)
	var ref_fov = fov_at_zoom_min
	var ref_tan = tan(deg_to_rad(ref_fov * 0.5))
	var cur_tan = tan(deg_to_rad(current_fov * 0.5))
	# Also apply the linear zoom factor for the user-controlled distance
	var base_dist = offset.length() * zoom
	return base_dist * ref_tan / cur_tan

func _process(delta: float) -> void:
	if not _target:
		return

	# --- Zoom (scale offset distance + FOV) ---
	if Input.is_action_pressed("zoom_in"):
		_zoom_factor = maxf(zoom_min, _zoom_factor - zoom_speed * delta)
	if Input.is_action_pressed("zoom_out"):
		_zoom_factor = minf(zoom_max, _zoom_factor + zoom_speed * delta)

	# Smoothly interpolate FOV toward target
	if _camera:
		var target_fov = _get_fov_for_zoom(_zoom_factor)
		_camera.fov = lerpf(_camera.fov, target_fov, clampf(8.0 * delta, 0.0, 1.0))

	# --- Detect if player is moving ---
	var current_dist = _get_distance_for_zoom(_zoom_factor)
	var current_offset = _offset_dir * current_dist
	var target_pos = _target.global_position + current_offset
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
		var current_dist = _get_distance_for_zoom(_zoom_factor)
		global_position = _target.global_position + _offset_dir * current_dist
		_apply_fixed_rotation()
