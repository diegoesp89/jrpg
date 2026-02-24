extends Node
## Occludable — Attached to walls/props that should fade when blocking camera-to-player line.
## Works in conjunction with OcclusionController.
## Supports walls with multiple face meshes (WallFace_0, WallFace_1, etc.) and single Sprite3D.
##
## Walls start OPAQUE (no transparency) for correct depth testing.
## For ShaderMaterial walls: swaps shader to transparent variant and sets alpha uniform.
## For StandardMaterial3D walls: toggles transparency mode (legacy).

var _current_alpha: float = 1.0
var _fade_speed: float = 4.0  # alpha per second
var _visuals: Array[Node3D] = []  # MeshInstance3D or Sprite3D nodes
var _visual_types: Array[bool] = []  # true = MeshInstance3D, false = Sprite3D
var _transparent: bool = false  # whether transparency mode is currently on

# Cached shader references for opaque/transparent swap
var _opaque_shader: Shader = null
var _alpha_shader: Shader = null

enum State { VISIBLE, FADING_OUT, FADING_IN, HIDDEN }
var _state: State = State.VISIBLE

func _ready() -> void:
	# Defer to next frame to ensure all sibling nodes are added
	await get_tree().process_frame
	_find_visuals()
	# Try to get shader references from DungeonBuilder
	var builder = _find_dungeon_builder()
	if builder:
		_opaque_shader = builder._fog_shader_textured
		_alpha_shader = builder._fog_shader_textured_alpha

func _find_dungeon_builder():
	# Occludable → Wall → DungeonBuilder
	var wall = get_parent()
	if not wall:
		return null
	var builder = wall.get_parent()
	if builder and builder.has_method("get_player_start_position"):
		return builder
	# Fallback: search up the tree
	var node = builder
	while node:
		for child in node.get_children():
			if child.has_method("get_player_start_position"):
				return child
		node = node.get_parent()
	return null

func _process(delta: float) -> void:
	if _visuals.is_empty():
		return

	match _state:
		State.FADING_OUT:
			_current_alpha = move_toward(_current_alpha, 0.15, _fade_speed * delta)
			_apply_alpha(_current_alpha)
			if _current_alpha <= 0.16:
				_state = State.HIDDEN
		State.FADING_IN:
			_current_alpha = move_toward(_current_alpha, 1.0, _fade_speed * delta)
			_apply_alpha(_current_alpha)
			if _current_alpha >= 0.99:
				_state = State.VISIBLE
				_current_alpha = 1.0
				_apply_alpha(1.0)
				_set_transparent(false)

func _apply_alpha(alpha: float) -> void:
	for i in range(_visuals.size()):
		if _visual_types[i]:
			var mi := _visuals[i] as MeshInstance3D
			if mi and mi.material_override:
				if mi.material_override is ShaderMaterial:
					mi.material_override.set_shader_parameter("alpha", alpha)
				elif mi.material_override is StandardMaterial3D:
					mi.material_override.albedo_color.a = alpha
		else:
			_visuals[i].modulate.a = alpha

func _set_transparent(enabled: bool) -> void:
	if _transparent == enabled:
		return
	_transparent = enabled
	for i in range(_visuals.size()):
		if _visual_types[i]:
			var mi := _visuals[i] as MeshInstance3D
			if mi and mi.material_override:
				if mi.material_override is ShaderMaterial:
					# Swap shader between opaque and transparent variant
					if _opaque_shader and _alpha_shader:
						if enabled:
							mi.material_override.shader = _alpha_shader
							mi.material_override.set_shader_parameter("alpha", _current_alpha)
						else:
							mi.material_override.set_shader_parameter("alpha", 1.0)
							mi.material_override.shader = _opaque_shader
				elif mi.material_override is StandardMaterial3D:
					if enabled:
						mi.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					else:
						mi.material_override.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
						mi.material_override.albedo_color.a = 1.0

func fade_out() -> void:
	if _state != State.FADING_OUT and _state != State.HIDDEN:
		_set_transparent(true)
		_state = State.FADING_OUT

func fade_in() -> void:
	if _state != State.FADING_IN and _state != State.VISIBLE:
		_state = State.FADING_IN

func _find_visuals() -> void:
	var parent = get_parent()
	if not parent:
		return
	for child in parent.get_children():
		if child is MeshInstance3D and child.name.begins_with("WallFace"):
			_visuals.append(child)
			_visual_types.append(true)
		elif child is MeshInstance3D and child.name == "WallMesh":
			_visuals.append(child)
			_visual_types.append(true)
		elif child is Sprite3D:
			_visuals.append(child)
			_visual_types.append(false)
