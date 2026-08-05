extends Node
class_name SplashScreen
## SplashScreen — A one-time message from the developer, shown right after Boot and before
## ContinueScreen. Skippable with Z (action1); nothing else advances it, so it stays up as long
## as the player wants to read it.

const MESSAGE := "[b]Antes de empezar...[/b]

Este juego fue diseñado y programado por una sola persona —el DM Strife— como un regalo y un homenaje para sus jugadores y para los personajes que crearon.

De una lista de siete personajes deberás elegir cuatro para formar tu party. Con ellos recorrerás una mazmorra inspirada y libremente adaptada de La Montaña del Penacho Blanco. Los personajes avanzan del nivel 1 al 5, bajo un sistema de combate al estilo JRPG, muy inspirado en D&D pero con cambios propios pensados para este videojuego.

Hay un detalle que vale la pena contar: en ciertos momentos de la aventura los personajes conversan entre sí, y existe una conversación distinta para cada combinación posible de party. Adaptar la personalidad, las aptitudes y los gustos de cada personaje a todas esas combinaciones fue un trabajo caótico y un esfuerzo casi sobrehumano.

Este proyecto avanzó tras bambalinas durante poco más de ocho meses, a fuerza de ratos libres: algunas veces en medio de reuniones de mi propio trabajo, otras mientras regaba o hacía tareas en el campo, escribiendo desde el celular.

Gracias por leer hasta acá. Quiero que sepas que te quiero mucho, que aceptes y abraces los bugs, que encuentres mecánicas y combinaciones rotas, y que consigas terminarlo al menos una vez. Y si alguna vez llegas a completarlo con todas las combinaciones posibles de party, me saco el sombrero: te invito un café o una cerveza, lo que prefieras."

var _finished: bool = false

func _ready() -> void:
	_build_ui()
	set_process_unhandled_input(true)

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 160
	scroll.offset_right = -160
	scroll.offset_top = 70
	scroll.offset_bottom = -70
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("bold_font_size", 28)
	body.add_theme_constant_override("line_separation", 8)
	body.add_theme_color_override("default_color", Color(0.92, 0.92, 0.92))
	body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	body.text = MESSAGE
	scroll.add_child(body)

	var hint = Label.new()
	hint.text = "Z: Continuar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_bottom = -15
	root.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event.is_action_pressed("action1"):
		get_viewport().set_input_as_handled()
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	SceneFlow.change_scene("res://scenes/boot/ContinueScreen.tscn")
