extends Node3D
class_name DungeonManager
## DungeonManager — Top-level manager

## Preloaded by path rather than through its class_name — see the note in DungeonBuilder.gd.
const NarrativeToastScript = preload("res://scripts/ui/NarrativeToast.gd")

@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig = $CameraRig
@onready var _dungeon_builder = $DungeonBuilder
@onready var _world_env: WorldEnvironment = $WorldEnvironment

var _hud: CanvasLayer = null
var _minimap_ui = null
var _prompt_label: Label = null
var _map_editor = null
var _debug_panel = null

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
	_setup_status_menu()
	_setup_minimap()
	_setup_occlusion_controller()
	_setup_player_fog_global()
	_setup_map_editor()
	_setup_debug_panel()
	_show_pending_tier_message()

## Catches a legendary-weapon toast that fired while the party was still in the Battle scene (a
## boss drop): GameState.add_item() has no way to show UI itself, so it just queues the message,
## and whichever scene next loads picks it up. A floor pickup shows it immediately instead — see
## Pickup.gd — since grabbing one doesn't leave this scene for anything to catch it here.
func _show_pending_tier_message() -> void:
	if GameState.pending_tier_message == "":
		return
	var msg := GameState.pending_tier_message
	GameState.pending_tier_message = ""
	await NarrativeToastScript.show_at(self, msg)

func _setup_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
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
	_update_player_fog_pos()

func _update_hp_display() -> void:
	var hp_label = _hud.get_node_or_null("HPLabel")
	if hp_label and GameState.party.size() > 0:
		# The one you are actually walking as (Q/E), so the HUD and the sprite never disagree.
		var leader = GameState.party[posmod(GameState.lead_index, GameState.party.size())]
		var mp = leader.get("mp", 0)
		var max_mp = leader.get("max_mp", 0)
		hp_label.text = "%s  HP: %d/%d  MP: %d/%d" % [
			leader["name"], leader["hp"], leader["max_hp"],
			mp, max_mp
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

func _setup_status_menu() -> void:
	var status_script = load("res://scripts/ui/StatusMenu.gd")
	var status_menu = CanvasLayer.new()
	status_menu.name = "StatusMenu"
	status_menu.set_script(status_script)
	add_child(status_menu)

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

func _setup_map_editor() -> void:
	if not GameState.admin_mode:
		return
	var editor_script = load("res://scripts/ui/MapEditor.gd")
	var editor = CanvasLayer.new()
	editor.name = "MapEditor"
	editor.set_script(editor_script)
	add_child(editor)
	_map_editor = editor

	var btn = Button.new()
	btn.name = "MapEditorButton"
	btn.text = "Editor de Mapa"
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -180
	btn.offset_right = -10
	btn.offset_top = -50
	btn.offset_bottom = -10
	btn.pressed.connect(func(): _map_editor.open_editor())
	_hud.add_child(btn)

func _setup_debug_panel() -> void:
	if not GameState.admin_mode:
		return
	var panel_script = load("res://scripts/ui/DebugPanel.gd")
	var panel = CanvasLayer.new()
	panel.name = "DebugPanel"
	panel.set_script(panel_script)
	add_child(panel)
	_debug_panel = panel
	_debug_panel._dungeon_builder = _dungeon_builder

	var btn = Button.new()
	btn.name = "DebugPanelButton"
	btn.text = "Debug"
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -180
	btn.offset_right = -10
	btn.offset_top = -100
	btn.offset_bottom = -60
	btn.pressed.connect(func(): _debug_panel.open())
	_hud.add_child(btn)

func _setup_occlusion_controller() -> void:
	var oc_script = load("res://scripts/exploration/OcclusionController.gd")
	var oc = Node3D.new()
	oc.name = "OcclusionController"
	oc.set_script(oc_script)
	add_child(oc)

func _setup_player_fog_global() -> void:
	# DungeonBuilder already registered the globals in its _ready() (children run before parent).
	# We just set the values here.
	RenderingServer.global_shader_parameter_set("fog_start", 6.0)
	RenderingServer.global_shader_parameter_set("fog_end", 10.0)
	# Set initial player pos
	RenderingServer.global_shader_parameter_set("player_world_pos", _player.global_position)

func _update_player_fog_pos() -> void:
	if _player:
		RenderingServer.global_shader_parameter_set("player_world_pos", _player.global_position)
