extends Node3D
## CameraFollow — Smooth isometric camera that follows the player.
## Fixed rotation (no tilt). Delayed engage on movement start, smooth settle on stop.
## 2 discrete zoom levels cycled with Q/E:
##   Level 1 (default): Perspective — wide FOV, fog edge matches camera frustum edge.
##   Level 2: Quasi-orthographic — very low FOV + far distance, reveals much more dungeon.
## Both levels stay in PROJECTION_PERSPECTIVE (low FOV approximates ortho perfectly).
## FOV and distance are interpolated independently to avoid nonlinear spikes.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(7, 9, 7)

## Level 1 (perspective) settings
@export var fov_level_1: float = 50.0
## Level 2 (quasi-ortho) settings — low FOV + far distance
@export var fov_level_2: float = 5.0
## How much more world area level 2 reveals compared to level 1.
## 1.0 = same visible area (just ortho look), 1.4 = 1.4x wider view.
@export var level_2_view_scale: float = 1.4

## How fast the zoom transitions between levels (lerp speed per second).
@export var zoom_transition_speed: float = 3.0

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
var _zoom_index: int = 0          # 0 = level 1 (perspective), 1 = level 2 (quasi-ortho)
var _offset_dir: Vector3           # normalized offset direction, set once
var _base_dist: float = 0.0       # offset.length()

# Smooth transition state — FOV and distance lerp independently
var _current_fov: float = 50.0
var _target_fov: float = 50.0
var _current_dist: float = 0.0
var _target_dist: float = 0.0

# Internal state for delayed engage / smooth settle
var _player_moving: bool = false
var _move_timer: float = 0.0
var _current_follow_factor: float = 0.0

@onready var _camera: Camera3D = $Camera3D

## Compute the final distance for a given FOV and view_scale.
func _calc_distance(fov: float, view_scale: float) -> float:
	var ref_tan = tan(deg_to_rad(fov_level_1 * 0.5))
	var cur_tan = tan(deg_to_rad(fov * 0.5))
	if cur_tan < 0.001:
		cur_tan = 0.001
	return _base_dist * ref_tan / cur_tan * view_scale

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)
	_offset_dir = offset.normalized()
	_base_dist = offset.length()
	_current_fov = fov_level_1
	_target_fov = fov_level_1
	_current_dist = _calc_distance(fov_level_1, 1.0)
	_target_dist = _current_dist
	if _camera:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov_level_1
		_camera.near = 0.05
		_camera.far = 1000.0
	if _target:
		global_position = _target.global_position + _offset_dir * _current_dist
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

	# --- Zoom: cycle levels with Q/E ---
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_index = maxi(0, _zoom_index - 1)
		_apply_zoom_level()
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_index = mini(1, _zoom_index + 1)
		_apply_zoom_level()

	# --- Smooth FOV and distance interpolation (independent) ---
	var t = clampf(zoom_transition_speed * delta, 0.0, 1.0)
	_current_fov = lerpf(_current_fov, _target_fov, t)
	_current_dist = lerpf(_current_dist, _target_dist, t)
	if _camera:
		_camera.fov = _current_fov

	# --- Detect if player is moving ---
	var current_offset = _offset_dir * _current_dist
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

func _apply_zoom_level() -> void:
	if _zoom_index == 0:
		_target_fov = fov_level_1
		_target_dist = _calc_distance(fov_level_1, 1.0)
	else:
		_target_fov = fov_level_2
		_target_dist = _calc_distance(fov_level_2, level_2_view_scale)

func set_target(node: Node3D) -> void:
	_target = node
	if _target:
		global_position = _target.global_position + _offset_dir * _current_dist
		_apply_fixed_rotation()

## Calculates the fog_end value so fog reaches the edge of the camera's visible area on the XZ plane.
func get_fog_end_for_current_view() -> float:
	if not _camera or not _target:
		return 12.0
	# Camera position relative to player
	var cam_offset = _offset_dir * _current_dist
	var cam_height = cam_offset.y
	var cam_xz_dist = Vector2(cam_offset.x, cam_offset.z).length()
	# Pitch angle: angle below horizontal that the camera looks at
	var pitch_rad = atan2(cam_height, cam_xz_dist)
	var half_fov_v = deg_to_rad(_current_fov * 0.5)
	# Far floor edge: ray at (pitch - half_fov_v) from horizontal
	var far_angle = pitch_rad - half_fov_v
	var far_xz: float
	if far_angle > 0.02:
		far_xz = cam_height / tan(far_angle) - cam_xz_dist
	else:
		far_xz = 50.0
	# Horizontal FOV (aspect ratio widens the view sideways)
	var aspect = get_viewport().get_visible_rect().size.x / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var half_fov_h = atan(tan(half_fov_v) * aspect)
	var side_xz = _current_dist * tan(half_fov_h) * 0.7
	return maxf(far_xz, side_xz) * 1.05

## Returns a dictionary with current zoom debug info.
func get_zoom_debug() -> Dictionary:
	return {
		"zoom_index": _zoom_index,
		"fov": _current_fov,
		"fov_target": _target_fov,
		"distance": _current_dist,
		"fog_end": get_fog_end_for_current_view(),
	}
