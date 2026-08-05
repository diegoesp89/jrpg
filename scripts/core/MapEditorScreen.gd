extends Node
class_name MapEditorScreen
## MapEditorScreen — Standalone entry point for the map editor, reached directly from
## MapSelection's "Editar" button (no character selection / dungeon needed).

func _ready() -> void:
	# Defense in depth: MapSelection's "Editar" button already only appears in admin mode, but
	# this scene could in principle be reached directly (e.g. change_scene called some other way).
	if not GameState.admin_mode:
		SceneFlow.change_scene("res://scenes/boot/MapSelection.tscn")
		return
	var editor_script = load("res://scripts/ui/MapEditor.gd")
	var editor = CanvasLayer.new()
	editor.name = "MapEditor"
	editor.set_script(editor_script)
	editor.standalone = true
	add_child(editor)
