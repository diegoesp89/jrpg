extends CanvasLayer
class_name HelpPanel
## HelpPanel — Reusable in-game manual overlay: a topic list that opens scrollable pages
## explaining the mechanics the player can't otherwise discover (damage math, positions,
## status effects, the level/feat progression, and the full feat catalogue).
##
## Deliberately spoiler-free: nothing here names an enemy, a trap, an item or a puzzle answer.
## It only documents *systems* — the rules the player is expected to reason with — never the
## content those rules get applied to.
##
## The feat pages are generated from DataLoader at open() time rather than written out by hand,
## so editing data/feats.json (or a character's final_feat) updates the manual automatically
## and it can never drift out of sync with the actual game data.
##
## Same self-contained overlay contract as OptionsPanel: the host instances it as a plain
## child, checks `is_open()` at the top of its own _unhandled_input, and listens for `closed`.

signal closed

## Preloaded by path, not via its class_name — see the note in DungeonBuilder.gd.
const EasterEggsData = preload("res://scripts/data/EasterEggs.gd")

enum State { TOPICS, PAGE }

const SCROLL_STEP := 70

var _is_open: bool = false
var _state: State = State.TOPICS
var _selected_index: int = 0
## [{ "title": String, "body": Callable }] — bodies are built lazily, on open.
var _topics: Array = []

var _root: Control
var _title: Label
var _list_container: VBoxContainer
var _row_labels: Array[Label] = []
var _scroll: ScrollContainer
var _body_label: RichTextLabel
var _hint: Label

func _ready() -> void:
	layer = 90
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_title = Label.new()
	_title.text = "Ayuda"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 40
	_title.offset_bottom = 100
	_root.add_child(_title)

	_list_container = VBoxContainer.new()
	_list_container.set_anchors_preset(Control.PRESET_CENTER)
	_list_container.offset_left = -320
	_list_container.offset_right = 320
	_list_container.offset_top = -230
	_list_container.offset_bottom = 230
	_list_container.add_theme_constant_override("separation", 12)
	_list_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_list_container)

	# Page view: one scrollable rich-text block, hidden while the topic list is up.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 240
	_scroll.offset_right = -240
	_scroll.offset_top = 120
	_scroll.offset_bottom = -70
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	_root.add_child(_scroll)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 20)
	_body_label.add_theme_font_size_override("bold_font_size", 20)
	_body_label.add_theme_constant_override("line_separation", 4)
	_scroll.add_child(_body_label)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -50
	_hint.offset_bottom = -15
	_root.add_child(_hint)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	_topics = [
		{"title": "Lo básico", "body": _body_basics},
		{"title": "La ronda de combate", "body": _body_round},
		{"title": "Cómo se calcula el daño", "body": _body_damage},
		{"title": "Ventaja y desventaja", "body": _body_advantage},
		{"title": "Posiciones en combate", "body": _body_positions},
		{"title": "Estados alterados", "body": _body_status},
		{"title": "Niveles, XP y feats", "body": _body_progression},
		{"title": "Habilidades por personaje", "body": _body_skills},
		{"title": "Lista de feats", "body": _body_feat_list},
		{"title": "Feats finales (nivel 5)", "body": _body_final_feats},
	]
	_show_topics()
	_root.visible = true

func _close() -> void:
	_is_open = false
	_root.visible = false
	closed.emit()

# --- Topic list ---

func _show_topics() -> void:
	_state = State.TOPICS
	_title.text = "Ayuda"
	_scroll.visible = false
	_list_container.visible = true
	_hint.text = "WASD/Flechas: Navegar  |  Z: Abrir  |  X/Esc: Volver"

	for child in _list_container.get_children():
		child.queue_free()
	_row_labels.clear()
	for topic in _topics:
		var lbl = Label.new()
		lbl.text = topic["title"]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 24)
		_list_container.add_child(lbl)
		_row_labels.append(lbl)
	_selected_index = 0
	_update_highlight()

func _update_highlight() -> void:
	for i in range(_row_labels.size()):
		if i == _selected_index:
			_row_labels[i].add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		else:
			_row_labels[i].add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

# --- Page view ---

func _show_page(idx: int) -> void:
	if idx < 0 or idx >= _topics.size():
		return
	_state = State.PAGE
	_title.text = _topics[idx]["title"]
	_list_container.visible = false
	var builder: Callable = _topics[idx]["body"]
	var text: String = builder.call()
	var hint: String = EasterEggsData.help_hint(idx)
	if hint != "":
		text += "\n\n[color=#4a4a55]Dile a tu DM la siguiente frase y te dará una sorpresa: «%s»[/color]" % hint
	_body_label.text = text
	_scroll.visible = true
	_scroll.scroll_vertical = 0
	_hint.text = "Arriba/Abajo: Desplazar  |  X/Esc: Volver"

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	match _state:
		State.TOPICS:
			if event.is_action_pressed("move_up"):
				_selected_index = maxi(0, _selected_index - 1)
				_update_highlight()
			elif event.is_action_pressed("move_down"):
				_selected_index = mini(_topics.size() - 1, _selected_index + 1)
				_update_highlight()
			elif event.is_action_pressed("action1") or event.is_action_pressed("ui_accept"):
				_show_page(_selected_index)
			elif event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel"):
				_close()
			else:
				return
		State.PAGE:
			# allow_echo so holding the key keeps scrolling instead of needing repeated taps.
			if event.is_action_pressed("move_up", true):
				_scroll.scroll_vertical -= SCROLL_STEP
			elif event.is_action_pressed("move_down", true):
				_scroll.scroll_vertical += SCROLL_STEP
			elif event.is_action_pressed("action2") or event.is_action_pressed("ui_cancel") \
					or event.is_action_pressed("action1") or event.is_action_pressed("ui_accept"):
				_show_topics()
			else:
				return
	get_viewport().set_input_as_handled()

# --- Page bodies ---
## Kept as separate builders (rather than one big const) so the two data-driven ones can query
## DataLoader, and so each page is editable without scrolling past the others.

func _heading(text: String) -> String:
	return "[color=#e8cc66][b]%s[/b][/color]\n" % text

func _body_basics() -> String:
	return _heading("Controles") + \
		"· WASD o flechas para moverte y para navegar los menús.\n" + \
		"· Z (o Enter) confirma e interactúa con lo que tengas delante.\n" + \
		"· X (o Esc) cancela y vuelve atrás.\n" + \
		"· Esc o Enter durante la exploración abre este menú.\n" + \
		"Puedes reasignar todas las teclas desde Opciones.\n\n" + \
		_heading("Tu party") + \
		"Eliges 4 personajes de los 7 disponibles. Cada combinación distinta que termine la aventura queda marcada con una estrella en la pantalla de selección.\n\n" + \
		_heading("Guardado") + \
		"La partida se guarda sola cada vez que ganas un combate y cada vez que recoges un objeto. También puedes guardar a mano desde este menú en cualquier momento.\n\n" + \
		_heading("Si pierdes") + \
		"Si toda la party cae en combate se termina la partida: vuelves a la selección de personajes y empiezas de cero. No hay forma de revivir a mitad de la mazmorra, así que conviene retirarse a tiempo.\n\n" + \
		_heading("Descansos") + \
		"Las zonas de descanso restauran todo el HP y el MP de la party, pero solo tienes %d descansos para toda la partida, compartidos entre todas las zonas del mapa. Una vez agotados no se recuperan." % GameState.MAX_REST_CHARGES

func _body_round() -> String:
	return _heading("Orden de turnos") + \
		"Al empezar cada ronda se vuelve a tirar la iniciativa de todos, así que el orden puede cambiar de una ronda a la otra.\n" + \
		"Iniciativa = 1d20 + tu modificador de Agilidad. Actúa primero quien saque más alto.\n\n" + \
		_heading("Antes de los turnos") + \
		"Al arrancar la ronda se aplica el daño de veneno y quemadura, y bajan un punto los contadores de todos los estados que duran turnos.\n\n" + \
		_heading("En tu turno") + \
		"· [b]Atacar[/b]: ataque básico con arma contra un enemigo.\n" + \
		"· [b]Habilidad[/b]: gasta MP. Cada personaje tiene las suyas; la lista te explica qué hace la que estés marcando.\n" + \
		"· [b]Objeto[/b]: usa algo del inventario, que es compartido por toda la party.\n" + \
		"· [b]Defender[/b]: te cubres, todos los ataques contra ti tiran con desventaja hasta el inicio de la próxima ronda.\n" + \
		"· [b]Mover[/b]: cambias a una zona contigua. Te saca del melee, y eso provoca un ataque de oportunidad de cada enemigo que estaba a melee contigo.\n" + \
		"· [b]Huir[/b]: intenta escapar. La probabilidad es %d%% base + %d%% por cada personaje que siga en pie, así que huir tarde, con la party ya diezmada, es mucho más difícil. La ves calculada en pantalla, encima de la opción. Hay combates de los que no se puede huir.\n\n" % [Combatant.FLEE_BASE_CHANCE, Combatant.FLEE_CHANCE_PER_MEMBER] + \
		"Si estás aturdido o inmovilizado, tu turno se saltea por completo."

func _body_damage() -> String:
	return _heading("¿Impacta?") + \
		"Tiras 1d20 y le sumas tu bono de ataque. Si el total llega o supera la CA (Clase de Armadura) del objetivo, impactas.\n" + \
		"Bono de ataque = tu modificador de Fuerza. Monjes y Gunslingers usan Agilidad en su lugar.\n" + \
		"· Un 1 natural siempre es fallo, por altos que sean tus bonos.\n" + \
		"· Un 20 natural es golpe crítico. Ciertos feats lo bajan a 19.\n\n" + \
		_heading("Daño de un golpe") + \
		"Daño = el dado de tu clase + el mismo modificador que usaste para atacar.\n" + \
		"· Bárbaro: 1d12\n· Warlock: 1d10\n· Monje, Gunslinger y Clérigo: 1d8\n· Hechicera: 1d6\n\n" + \
		_heading("Daño crítico") + \
		"Un crítico no duplica la tirada: te da el máximo del dado, más una tirada normal de ese mismo dado, y suma tu modificador dos veces.\n" + \
		"Con 1d12 y +3, por ejemplo: (12+3) + (1d12+3) = entre 19 y 30 de daño.\n\n" + \
		_heading("Habilidades") + \
		"· Las habilidades físicas tiran ataque igual que un golpe normal y suman su poder al daño si impactan.\n" + \
		"· Las habilidades mágicas no tiran contra la CA: siempre conectan. Su daño es el poder de la habilidad + tu modificador de casteo.\n" + \
		"· Tu modificador de casteo es el mayor entre tus modificadores de Inteligencia y Sabiduría.\n\n" + \
		_heading("Curación") + \
		"Curación = poder de la habilidad u objeto + tu modificador de casteo, multiplicado por los bonos de curación que tengas.\n\n" + \
		_heading("El orden final") + \
		"Sobre el daño ya calculado se aplican primero los multiplicadores de posición y de estado, después los bonos planos de tus feats, y por último las reducciones de daño del que recibe el golpe. Un golpe que impacta nunca hace menos de 1.\n\n" + \
		_heading("Tabla de modificadores") + \
		"18 o más: +4   ·   16-17: +3   ·   14-15: +2   ·   12-13: +1\n" + \
		"10-11: 0   ·   8-9: -1   ·   7 o menos: -2"

func _body_advantage() -> String:
	return "Con [b]ventaja[/b] tiras el d20 dos veces y te quedas con el resultado más alto. Con [b]desventaja[/b], con el más bajo. Si tienes las dos a la vez se cancelan y tiras un solo dado normal.\n\n" + \
		_heading("Tienes ventaja cuando") + \
		"· Atacas a alguien que está cegado.\n" + \
		"· Atacas a alguien que acaba de atacar de forma temeraria.\n" + \
		"· Una habilidad tuya te la da explícitamente.\n\n" + \
		_heading("Tienes desventaja cuando") + \
		"· Estás cegado.\n" + \
		"· Atacas a alguien que usó la acción Defender.\n" + \
		"· Atacas a cualquiera que no sea el enemigo con el que estás a melee.\n" + \
		"· Atacas con una tirada a un enemigo protegido en la Retaguardia.\n" + \
		"· Atacas a alguien con un feat de evasión.\n\n" + \
		"La ventaja también te hace criticar más seguido: al tirar dos d20 tienes casi el doble de probabilidades de sacar un 20."

func _body_positions() -> String:
	return "El campo se divide en tres zonas, de la línea de combate hacia atrás: Adelante, Medio y Retaguardia. Los enemigos ocupan las mismas tres zonas, y dónde arranca cada uno depende de su carácter: los brutos van al frente, los cobardes se quedan en el medio y la artillería no sale de la retaguardia.\n\n" + \
		_heading("Melee") + \
		"Estar en Adelante significa estar a melee con alguien. Cada personaje se pone a melee con UN enemigo, pero un mismo enemigo puede tener varios encima: los cuatro héroes pueden rodear al mismo ogro.\n" + \
		"En la pantalla de combate ves una línea naranja entre cada par que está a melee.\n" + \
		"Si estás Adelante y no tienes a nadie a melee, el juego te pone a melee con el enemigo del frente que tenga menos gente encima.\n\n" + \
		_heading("Pegarle a otro") + \
		"Puedes atacar a quien quieras, pero golpear a alguien que no es tu melee es darle la espalda al que sí lo es: esa tirada va con desventaja. La lista de objetivos te avisa cuáles tienen ese costo.\n\n" + \
		_heading("A quién alcanzas: el peaje de guardia") + \
		"Adelante y Medio son alcanzables siempre, sin costo. Quien está en Retaguardia con algún aliado todavía en pie delante queda [b]protegido[/b]: puedes alcanzarlo igual, pero se paga.\n" + \
		"· Los ataques con tirada le pegan [b]con desventaja[/b].\n" + \
		"· La magia le pega igual, sin fallar, pero [b]a mitad de daño[/b]. Paga más porque no se arriesga a fallar.\n" + \
		"· Las habilidades de área alcanzan a todos: es la respuesta a un enemigo replegado, y lo único que mejora cuando se esconde.\n" + \
		"· Curar a un aliado no paga nada, sin importar las zonas.\n" + \
		"Es un único umbral en todo el sistema: no hay peajes intermedios.\n\n" + \
		_heading("La excepción cuerpo a cuerpo") + \
		"Bárbaros y Monjes [b]no pueden[/b] alcanzar a un protegido, ni pagando el peaje, y desde la Retaguardia no alcanzan nada en absoluto. Por eso conviene abrirse paso por el frente: limpiarlo es lo que deja expuesto al enemigo de atrás.\n" + \
		"Lo mismo vale en tu contra: los enemigos brutos tampoco alcanzan tu Retaguardia, así que poner ahí a los frágiles sigue protegiéndolos de la mitad del bestiario. De los que sí llegan, cuídate.\n\n" + \
		_heading("Moverte") + \
		"Cambiar de zona cuesta la acción del turno (salvo que tengas un feat que lo permita gratis), y solo puedes moverte a una zona contigua.\n" + \
		"Si te mueves estando a melee, sales del melee, y cada enemigo del que te separas recibe un [b]ataque de oportunidad[/b]: un golpe gratis, con tirada normal, así que puede fallar. Salir de un melee con tres enemigos encima cuesta caro.\n" + \
		"Al llegar a Adelante te pones a melee automáticamente.\n\n" + \
		_heading("Rabia del Bárbaro") + \
		"Los Bárbaros pelean siempre enrabiados: hacen el doble de daño y también lo reciben doble. Está siempre activo y no se puede apagar, así que dónde se para importa más que en nadie."

func _body_status() -> String:
	return "Todos los estados que duran turnos bajan un punto al inicio de cada ronda.\n\n" + \
		"[b]Cegado[/b]: ataca con desventaja, y los ataques contra él tienen ventaja. Dura entre 1 y 3 turnos.\n\n" + \
		"[b]Envenenado[/b]: %d de daño al inicio de cada ronda, durante %d rondas.\n\n" % [BattleController.POISON_DAMAGE, BattleController.POISON_DURATION] + \
		"[b]Quemado[/b]: %d de daño al inicio de cada ronda, durante %d rondas.\n\n" % [BattleController.BURN_DAMAGE, BattleController.BURN_DURATION] + \
		"[b]Aturdido / Inmovilizado[/b]: pierde su próximo turno completo.\n\n" + \
		"[b]Marcado[/b]: recibe un 25% más de daño de cualquier fuente. El Gunslinger marca a su objetivo cada vez que lo golpea, y solo puede haber una marca a la vez.\n\n" + \
		"[b]Expuesto[/b]: quien ataca de forma temeraria baja la guardia, los ataques contra él tienen ventaja hasta el inicio de la próxima ronda.\n\n" + \
		"El veneno y la quemadura cuentan como daño normal, así que los feats de reducción de daño también los amortiguan."

func _body_progression() -> String:
	var thresholds := ""
	for lvl in range(2, GameState.MAX_LEVEL + 1):
		thresholds += "· Nivel %d: %d XP\n" % [lvl, GameState.XP_LEVEL_THRESHOLDS[lvl - 1]]
	return _heading("Subir de nivel") + \
		"La XP es de toda la party: todos suben juntos, al mismo nivel, según la XP total acumulada. El máximo es nivel %d.\n" % GameState.MAX_LEVEL + \
		thresholds + \
		"Un botín grande de XP puede cruzar más de un nivel de golpe; en ese caso eliges un feat por cada nivel ganado.\n\n" + \
		_heading("Qué te da subir de nivel") + \
		"· Sube tu HP máximo (ver abajo).\n" + \
		"· Toda la party se cura por completo, HP y MP, en el momento de subir.\n" + \
		"· Eliges un feat nuevo.\n\n" + \
		_heading("HP máximo") + \
		"A nivel 1 tienes el máximo de tu dado de golpe, más tu modificador de Constitución, más 4 de base. Por cada nivel que subes sumas el promedio de ese dado, más tu modificador de Constitución otra vez. No se tira: la subida es siempre la misma, así que nadie queda perjudicado por mala suerte.\n" + \
		"Dado de golpe por clase, y lo que suma cada nivel:\n" + \
		"· Bárbaro: d12 (+7 por nivel)\n" + \
		"· Gunslinger: d10 (+6 por nivel)\n" + \
		"· Monje, Clérigo y Warlock: d8 (+5 por nivel)\n" + \
		"· Hechicera: d6 (+4 por nivel)\n" + \
		"Con un d8 y Constitución +2, por ejemplo: 14 de HP a nivel 1, y 42 a nivel 5.\n\n" + \
		_heading("Feats") + \
		"Cada personaje empieza con 1 feat, elegido al armar la party, y gana 1 más por cada nivel que sube: %d en total al llegar al máximo.\n" % GameState.MAX_LEVEL + \
		"Los de nivel 2, 3 y 4 salen del pool de 4 feats propio de cada personaje, y nunca te ofrece uno que ya tengas.\n" + \
		"Al llegar a nivel %d se desbloquea el feat final: uno solo por personaje, exclusivo de ese nivel, que no aparece en ningún pool.\n\n" % GameState.MAX_LEVEL + \
		_heading("Cómo se combinan") + \
		"Si dos de tus feats afectan lo mismo, se combinan solos: los bonos planos se suman, los multiplicadores se multiplican, y las cargas por combate se quedan con el valor más alto. El orden en que los elegiste no cambia nada.\n\n" + \
		"Puedes ver los feats que ya tiene cada personaje en \"Estado\"."

func _body_skills() -> String:
	var text := "Las habilidades de cada personaje, con lo que cuestan y lo que hacen. Son fijas: se tienen desde el nivel 1 y no se aprenden más con el nivel, aunque algún feat puede sumar una.\n\n"
	for c in DataLoader.get_all_characters():
		text += "[color=#e8cc66][b]%s[/b][/color]: %s %s\n" % [
			c.get("name", "???"), c.get("race", ""), c.get("class", ""),
		]
		var skill_ids: Array = c.get("skills", [])
		if skill_ids.is_empty():
			text += "Sin habilidades propias.\n\n"
			continue
		for skill_id in skill_ids:
			var skill = DataLoader.get_skill(str(skill_id))
			if skill.is_empty():
				continue
			text += "[b]%s[/b] (%d MP): %s\n" % [
				skill.get("name", "???"), int(skill.get("mp_cost", 0)), skill.get("description", ""),
			]
		text += "\n"
	return text

func _body_feat_list() -> String:
	var text := "Los feats se agrupan por personaje: cada uno tiene su propio pool de 4, y solo puede elegir de ahí. Algunos feats aparecen en el pool de varios personajes.\n\n"
	for c in DataLoader.get_all_characters():
		text += "[color=#e8cc66][b]%s[/b][/color]: %s %s\n" % [
			c.get("name", "???"), c.get("race", ""), c.get("class", ""),
		]
		for feat_id in c.get("feat_pool", []):
			var feat = DataLoader.get_feat(str(feat_id))
			if feat.is_empty():
				continue
			text += "[b]%s[/b]: %s\n" % [feat.get("name", "???"), feat.get("description", "")]
		text += "\n"
	return text

func _body_final_feats() -> String:
	var text := "Al llegar a nivel %d cada personaje desbloquea su feat final. Es único, no se puede elegir antes, y no aparece en el pool de nadie.\n\n" % GameState.MAX_LEVEL
	for c in DataLoader.get_all_characters():
		var feat = DataLoader.get_feat(str(c.get("final_feat", "")))
		if feat.is_empty():
			continue
		text += "[color=#e8cc66][b]%s[/b][/color]: %s %s\n[b]%s[/b]\n%s\n\n" % [
			c.get("name", "???"), c.get("race", ""), c.get("class", ""),
			feat.get("name", "???"), feat.get("description", ""),
		]
	return text
