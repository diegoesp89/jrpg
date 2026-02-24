extends Node3D
## DungeonManager — Top-level manager for the dungeon exploration scene.
## Wires up player, camera, HUD, and dungeon builder.

@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig = $CameraRig
@onready var _dungeon_builder = $DungeonBuilder
@onready var _world_env: WorldEnvironment = $WorldEnvironment

var _hud: CanvasLayer = null
var _minimap_ui = null
var _prompt_label: Label = null

func _ready() -> void:
	_setup_environment()
	_setup_player_position()
	# Restore position if returning from combat (BEFORE camera setup so it snaps correctly)
	if GameState.return_position != Vector3.ZERO:
		_player.global_position = GameState.return_position
		GameState.return_position = Vector3.ZERO
	_setup_camera()
	_setup_hud()
	_setup_lantern()
	_setup_dialogue_controller()
	_setup_minimap()
	_setup_occlusion_controller()

func _setup_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Fog: fades to black at distance so far-away areas aren't visible
	env.fog_enabled = true
	env.fog_light_color = Color(0.0, 0.0, 0.0)
	env.fog_light_energy = 0.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 0.06
	_world_env.environment = env

func _setup_player_position() -> void:
	var start_pos = _dungeon_builder.get_player_start_position()
	_player.global_position = start_pos

func _setup_camera() -> void:
	_camera_rig.set_target(_player)

func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 10
	add_child(_hud)

	# Interaction prompt
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.text = ""
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-100, -60)
	_prompt_label.custom_minimum_size = Vector2(200, 30)
	_prompt_label.add_theme_font_size_override("font_size", 54)
	_hud.add_child(_prompt_label)

	# Connect player signal for interactable changes
	_player.interactable_changed.connect(_on_interactable_changed)

	# HP display
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_label.position = Vector2(10, 10)
	hp_label.add_theme_font_size_override("font_size", 48)
	_hud.add_child(hp_label)

func _process(_delta: float) -> void:
	_update_hp_display()

func _update_hp_display() -> void:
	var hp_label = _hud.get_node_or_null("HPLabel")
	if hp_label and GameState.party.size() > 0:
		var leader = GameState.party[0]
		hp_label.text = "%s  HP: %d/%d  MP: %d/%d" % [
			leader["name"], leader["hp"], leader["max_hp"],
			leader["mp"], leader["max_mp"]
		]

func _on_interactable_changed(interactable: Node) -> void:
	if interactable and interactable.has_method("get_prompt_text"):
		_prompt_label.text = interactable.get_prompt_text()
	else:
		_prompt_label.text = ""

func _setup_lantern() -> void:
	# Add OmniLight3D as child of player for lantern effect
	var light = OmniLight3D.new()
	light.name = "Lantern"
	light.light_color = Color(1.0, 0.9, 0.7)
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0, 2.0, 0)
	_player.add_child(light)

func _setup_dialogue_controller() -> void:
	var dc_script = load("res://scripts/ui/DialogueController.gd")
	var dc = Node.new()
	dc.name = "DialogueController"
	dc.set_script(dc_script)
	add_child(dc)

func _setup_minimap() -> void:
	# MiniMapReveal (logic)
	var reveal_script = load("res://scripts/exploration/MiniMapReveal.gd")
	var reveal = Node.new()
	reveal.name = "MiniMapReveal"
	reveal.set_script(reveal_script)
	add_child(reveal)

	# MiniMapUI (visual) - add to HUD canvas layer
	var minimap_script = load("res://scripts/ui/MiniMapUI.gd")
	_minimap_ui = Control.new()
	_minimap_ui.name = "MiniMapUI"
	_minimap_ui.set_script(minimap_script)
	_hud.add_child(_minimap_ui)

func _setup_occlusion_controller() -> void:
	var oc_script = load("res://scripts/exploration/OcclusionController.gd")
	var oc = Node3D.new()
	oc.name = "OcclusionController"
	oc.set_script(oc_script)
	add_child(oc)
