extends Node3D
class_name OcclusionController
## OcclusionController — Raycasts from camera to player

var _camera: Camera3D = null
var _player: Node3D = null
var _currently_hidden: Dictionary = {}  # node_id -> Node reference

func _ready() -> void:
	# Will be set up by DungeonManager after scene is ready
	await get_tree().process_frame
	_find_references()

func _find_references() -> void:
	_camera = get_viewport().get_camera_3d()
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		# Find by type
		_player = _find_player_in_tree()

func _find_player_in_tree() -> Node3D:
	for node in get_tree().get_nodes_in_group(""):
		if node is CharacterBody3D and node.name == "Player":
			return node
	# Brute force search
	var root = get_tree().current_scene
	if root:
		var player = root.get_node_or_null("Player")
		if player:
			return player
	return null

func _physics_process(_delta: float) -> void:
	if not _camera or not _player:
		_find_references()
		return

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return

	var camera_pos = _camera.global_position
	var player_pos = _player.global_position + Vector3(0, 0.8, 0)

	# Cast ray from camera to player
	var query = PhysicsRayQueryParameters3D.create(camera_pos, player_pos)
	query.collision_mask = 16  # occluder layer (layer 5 = bit 4 = 16)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# Exclude player
	if _player is CollisionObject3D:
		query.exclude = [_player.get_rid()]

	# Collect all hits by casting multiple times
	var new_hidden: Dictionary = {}
	var max_casts = 10  # safety limit
	var excluded_rids: Array[RID] = []
	if _player is CollisionObject3D:
		excluded_rids.append(_player.get_rid())

	for i in range(max_casts):
		query.exclude = excluded_rids
		var result = space_state.intersect_ray(query)
		if result.is_empty():
			break
		var collider = result["collider"]
		if not collider:
			break
		var node_id = collider.get_instance_id()
		new_hidden[node_id] = collider
		# Exclude this collider from next cast
		if collider is CollisionObject3D:
			excluded_rids.append(collider.get_rid())

	# Fade out newly occluding objects
	for nid in new_hidden:
		var node = new_hidden[nid]
		var occludable = node.get_node_or_null("Occludable")
		if occludable and occludable.has_method("fade_out"):
			occludable.fade_out()

	# Fade in objects that are no longer occluding
	for nid in _currently_hidden:
		if nid not in new_hidden:
			var node = _currently_hidden[nid]
			if is_instance_valid(node):
				var occludable = node.get_node_or_null("Occludable")
				if occludable and occludable.has_method("fade_in"):
					occludable.fade_in()

	_currently_hidden = new_hidden
