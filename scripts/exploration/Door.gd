extends StaticBody3D
class_name Door
## Door — Opens/closes on interaction. Optionally locked behind a key item; using the key
## consumes it from the inventory and unlocks the door permanently (persisted via a flag,
## same pattern as Pickup.gd's chest_id + "_opened").

var is_open: bool = false
@export var door_id: String = ""
@export var locked: bool = false
@export var required_item_id: String = ""

## Set by DungeonBuilder right after construction (plain vars, not @export — these are
## generated ShaderMaterials, not map-editor config data). Looks like a wall segment (same quad
## faces DungeonBuilder gives a WALL tile), just tinted brown/red instead of the stone texture.
var unlocked_material: Material = null
var locked_material: Material = null

@onready var _collision: CollisionShape3D = null
var _faces: Array[MeshInstance3D] = []

func _ready() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			_collision = child
		elif child is MeshInstance3D:
			_faces.append(child)

	if locked and door_id != "" and GameState.get_flag(door_id + "_unlocked"):
		locked = false
	_update_lock_visual()

func interact() -> void:
	if locked:
		if not GameState.has_item(required_item_id):
			AudioManager.play_sfx("door_locked")
			return
		GameState.remove_item(required_item_id, 1)
		locked = false
		if door_id != "":
			GameState.set_flag(door_id + "_unlocked")
		_update_lock_visual()
		print("Puerta desbloqueada con %s!" % required_item_id)

	if is_open:
		_close()
	else:
		_open()

func _open() -> void:
	is_open = true
	if _collision:
		_collision.disabled = true
	for face in _faces:
		face.visible = false
	AudioManager.play_sfx("door_open")
	print("Door opened!")

func _close() -> void:
	is_open = false
	if _collision:
		_collision.disabled = false
	for face in _faces:
		face.visible = true
	print("Door closed!")

## Swaps the wall-face material to the locked (red) or unlocked (brown) variant to match current
## state. Called on _ready and again the instant a key unlocks the door, so the color change is
## immediate instead of only visible after a scene reload.
func _update_lock_visual() -> void:
	var mat = locked_material if (locked and locked_material) else unlocked_material
	if mat == null:
		return
	for face in _faces:
		face.material_override = mat

func get_prompt_text() -> String:
	if locked:
		return "Necesitas una llave"
	if is_open:
		return "Z: Cerrar puerta"
	return "Z: Abrir puerta"

func is_available() -> bool:
	return true
