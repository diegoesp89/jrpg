extends Node3D
## CameraFollow — Smooth isometric camera that follows the player.
## Fixed rotation (no tilt). Delayed engage on movement start, smooth settle on stop.
## 2 discrete zoom levels cycled with Q/E:
##   Level 1 (default): Perspective — good FOV, fog edge matches camera frustum edge.
##   Level 2: Orthographic — far away, reveals much more of the dungeon.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(7, 9, 7)

## Perspective mode (Level 1) settings
@export var perspective_fov: float = 50.0
## Distance multiplier for perspective mode (1.0 = base offset.length())
@export var perspective_dist_mult: float = 1.0

## Orthographic mode (Level 2) settings
@export var ortho_size: float = 18.0
## Distance multiplier for ortho mode (far away)
@export var ortho_dist_mult: float = 3.0

## How fast the zoom transitions between levels (lerp speed).
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
var _zoom_index: int = 0          # 0 = perspective (default), 1 = orthographic
var _offset_dir: Vector3           # normalized offset direction, set once

# Smooth transition state
var _current_dist: float = 0.0
var _target_dist: float = 0.0
var _current_fov: float = 50.0
var _current_ortho_size: float = 18.0
var _is_ortho: bool = false        # current projection mode
var _target_is_ortho: bool = false # target projection mode

# Internal state for delayed engage / smooth settle
var _player_moving: bool = false
var _move_timer: float = 0.0
var _current_follow_factor: float = 0.0

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)
	_offset_dir = offset.normalized()
	_current_dist = offset.length() * perspective_dist_mult
	_target_dist = _current_dist
	_current_fov = perspective_fov
	_is_ortho = false
	_target_is_ortho = false
	if _camera:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = perspective_fov
		_camera.near = 0.1
		_camera.far = 500.0
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

	# --- Zoom: cycle levels with Q/E (just_pressed, not held) ---
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_index = maxi(0, _zoom_index - 1)
		_apply_zoom_level()
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_index = mini(1, _zoom_index + 1)
		_apply_zoom_level()

	# --- Smooth transition of distance ---
	_current_dist = lerpf(_current_dist, _target_dist, clampf(zoom_transition_speed * delta, 0.0, 1.0))

	# --- Update projection ---
	if _camera:
		if _target_is_ortho:
			# Transitioning to ortho: once distance is close enough, switch projection
			if not _is_ortho:
				# Smoothly increase FOV until it's time to switch
				# Actually, just switch immediately and smoothly lerp ortho_size
				_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				_camera.size = _current_ortho_size
				_is_ortho = true
			_current_ortho_size = lerpf(_current_ortho_size, ortho_size, clampf(zoom_transition_speed * delta, 0.0, 1.0))
			_camera.size = _current_ortho_size
		else:
			# Perspective mode
			if _is_ortho:
				_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				_camera.fov = _current_fov
				_is_ortho = false
			_current_fov = lerpf(_current_fov, perspective_fov, clampf(zoom_transition_speed * delta, 0.0, 1.0))
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
	var base_dist = offset.length()
	if _zoom_index == 0:
		# Perspective
		_target_dist = base_dist * perspective_dist_mult
		_target_is_ortho = false
	else:
		# Orthographic
		_target_dist = base_dist * ortho_dist_mult
		_target_is_ortho = true

func set_target(node: Node3D) -> void:
	_target = node
	if _target:
		global_position = _target.global_position + _offset_dir * _current_dist
		_apply_fixed_rotation()

## Calculates the fog_end value so fog reaches the edge of the camera's visible area on the XZ plane.
## This is used by DungeonManager to set the fog_end global shader uniform.
func get_fog_end_for_current_view() -> float:
	if not _camera:
		return 12.0
	# We need the XZ radius of the visible area on the floor (Y=0) from the player's position.
	# The camera looks at the player from offset_dir * distance.
	# The camera's vertical half-angle determines how much floor is visible.
	# For perspective: visible half-width at player distance ~ dist_to_player * tan(fov/2)
	# But we care about XZ distance on the floor from the player, not camera distance.
	# The camera is at height offset.y * (current_dist / offset.length())
	# The floor visible radius from the player (XZ) is approximately:
	#   camera_height / tan(pitch_angle - fov/2) - camera_xz_dist (for the far edge)
	# Simpler approach: the camera-to-player XZ distance + the half-width visible at that distance.
	var camera_height = global_position.y
	var camera_xz = Vector2(global_position.x, global_position.z)
	var player_xz = Vector2(_target.global_position.x, _target.global_position.z)
	var xz_dist_to_player = camera_xz.distance_to(player_xz)

	if _is_ortho:
		# Orthographic: visible area is ortho_size in the camera's vertical direction
		# The diagonal visible radius on XZ from the player center
		# ortho_size is the vertical half in world units
		# Aspect ratio ~ 16/9
		var aspect = get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
		var half_h = _current_ortho_size / 2.0
		var half_w = half_h * aspect
		# The camera looks diagonally down, so the footprint on XZ is stretched
		# Approximate: the farthest visible XZ point from player
		return maxf(half_h, half_w) * 1.5
	else:
		# Perspective: half angle of FOV
		var half_fov_rad = deg_to_rad(_current_fov * 0.5)
		# Visible half-width at the distance from camera to player
		var half_width_at_player = _current_dist * tan(half_fov_rad)
		# The XZ footprint from the player is roughly the half-width
		# (the camera looks down at ~42°, so the footprint is stretched along the look direction)
		# Use a factor to account for the diagonal view angle
		var pitch_factor = 1.2  # correction for angled view
		return half_width_at_player * pitch_factor

## Returns a dictionary with current zoom debug info.
func get_zoom_debug() -> Dictionary:
	var current_fov_val = _camera.fov if (_camera and not _is_ortho) else 0.0
	var ortho_val = _camera.size if (_camera and _is_ortho) else 0.0
	return {
		"zoom_index": _zoom_index,
		"is_ortho": _is_ortho,
		"fov": current_fov_val,
		"ortho_size": ortho_val,
		"distance": _current_dist,
		"fog_end": get_fog_end_for_current_view(),
	}
