extends Node
class_name SplashScreen
## SplashScreen — A one-time message from the developer, shown right after Boot and before
## ContinueScreen. Skippable with Z (action1); nothing else advances it, so it stays up as long
## as the player wants to read it.

const MESSAGE := "[b]Antes de empezar...[/b]

Acércate, muchacho, y escucha bien, porque este juego no fue creado por un gran estudio ni por un ejército de programadores. Lo hizo una sola persona: el DM Strife, como regalo para sus jugadores y homenaje a los personajes que tantas aventuras le han regalado.

De una lista de siete héroes deberás escoger cuatro para formar tu grupo y adentrarte en una mazmorra basada en [i]La Montaña del Penacho Blanco[/i]. Comenzarán en nivel 1 y, si sobreviven, alcanzarán el nivel 5, enfrentando peligros mediante un sistema de exploración y combate al estilo JRPG, nacido de las reglas de [i]Dungeons & Dragons[/i], pero adaptado a este pequeño videojuego.

Hay, además, algo especial. Cada combinación de personajes tiene conversaciones diferentes, escritas según sus personalidades, gustos, manías y aptitudes. Aquello fue un caos considerable y, posiblemente, una pésima decisión para la cordura de su creador.

El proyecto permaneció oculto durante más de ocho meses, construido en ratos libres, reuniones de trabajo y momentos robados al campo, a veces tecleando desde un teléfono mientras regaba.

Gracias por jugar. Te quiero mucho. Abraza los bugs, encuentra combinaciones rotas y termina la aventura. Si logras completarla con todos los grupos posibles, me quitaré el sombrero y te invitaré un café o una cerveza."

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
