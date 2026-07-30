extends Node
class_name MapEditorScreen
## MapEditorScreen — Standalone entry point for the map editor, reached directly from
## MapSelection's "Editar" button (no character selection / dungeon needed).

func _ready() -> void:
	var editor_script = load("res://scripts/ui/MapEditor.gd")
	var editor = CanvasLayer.new()
	editor.name = "MapEditor"
	editor.set_script(editor_script)
	editor.standalone = true
	add_child(editor)
