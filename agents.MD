# agents.MD — JRPG Godot 4.7 (Vertical Slice: White Plume Mountain libre)

## 0) Objetivo
Construir un **Vertical Slice jugable** (MVP) de un JRPG por turnos en **Godot 4.7** usando **GDScript**.

Debe incluir:
- Exploración isométrica en 3D (cámara fija isométrica con seguimiento suave)
- Mundo 3D con **billboards 2D** (player, NPCs, muros, puertas, props)
- Suelo en plano con **tileset**
- **Minimapa** con fog-of-war (revela lo explorado)
- **Linterna** del jugador (luz simple)
- **Occlusion Fade**: paredes/props que tapan al jugador se desvanecen con fade suave y vuelven con fade-in
- **Diálogo** con NPC de intro y una decisión binaria (sí/no) que cambia la respuesta del NPC
- Combate por turnos en escena aparte con **vista lateral** estilo FF
- Transición exploración ⇄ combate con conservación de estado mínimo

---

## 1) Stack y restricciones
- Engine: **Godot 4.7**
- Lenguaje: **GDScript**
- Target: Desktop (Windows/macOS/Linux)
- Resolución base sugerida: **1280x720** (escalable)
- Persistencia: guardado simple local (JSON o ConfigFile) **opcional** (recomendado si es rápido)
- Evitar plugins externos salvo necesidad real

### Principios
- Priorizar **jugabilidad y legibilidad** sobre perfección.
- Separar **Data (Resources/JSON)** de **Lógica (Nodes/Scripts)**.
- Nada de sobre-ingeniería: entregar slice completo y extensible.

---

## 2) Controles (InputMap obligatorio)
Configurar en Godot (Project Settings → Input Map):

- `move_up`, `move_down`, `move_left`, `move_right` (WASD o flechas)
- `action1` → tecla **Z**
  - Activar / usar / interactuar / siguiente / confirmar
- `action2` → tecla **X**
  - Volver / cancelar / no / atrás

### Reglas de UX
- Exploración:
  - `action1`: interactuar con objeto/NPC si hay prompt
  - `action2`: cerrar UI (si aplica) o cancelar (si aplica)
- Diálogo:
  - `action1`: avanzar texto / confirmar opción
  - `action2`: **en pantalla de elección** equivale a elegir inmediatamente la **opción 2 (No/Cancelar)**
  - `action2` no debe “cerrar” la intro por accidente (solo se usa como “No” en elección)
- Combate:
  - `action1`: confirmar acción/target
  - `action2`: volver un nivel en menús / cancelar selección

---

## 3) Pitch / Fantasía
Exploración de dungeon con visibilidad limitada por linterna y navegación con minimapa progresivo. Combate por turnos clásico con vista lateral. Inspiración libre en White Plume Mountain (sin copiar mapa/texto literal).

---

## 4) Core Loop
1. Explorar dungeon (moverse, ver minimapa, linterna, paredes se desvanecen si tapan al PJ).
2. Interactuar (puertas, cofres, NPC intro).
3. Activar eventos (triggers y combates).
4. Combate por turnos → recompensas.
5. Volver a exploración y avanzar hasta el final del slice.

---

## 5) Alcance del MVP (lo que SÍ)

### Exploración
- Player controller con colisiones.
- **Cámara isométrica con seguimiento suave al jugador (obligatorio):**
  - La cámara sigue al PJ con una transición suave usando **Tween**.
  - Debe existir “ease in/out” al comenzar a moverse y al detenerse (no snap).
  - La cámara puede mantener un offset fijo isométrico respecto al PJ.
  - Prioridad: sensación “fluida” sin mareo.
- Elevaciones: 1–2 niveles **opcional** (si complica, recortar; lo importante es cámara/3D/billboards).
- Interacciones mínimas:
  - **Door**: abrir/cerrar y habilitar/deshabilitar colisión.
  - **Pickup/Cofre**: agrega ítem (poción).
  - **NPC Intro**: diálogo con branching (2 opciones).
  - **CombatTrigger**: inicia un encuentro al entrar en área.
- UI exploración:
  - Prompt de interacción (“Z: usar”)
  - **Minimapa** (lo descubierto)
  - HP/MP del líder (opcional)

### Linterna del jugador (obligatorio)
- Luz simple que sigue al jugador.
- Entorno oscuro fuera del radio.
- Sin sombras complejas.

### Minimapa con fog-of-war (obligatorio)
- Muestra la posición del jugador.
- Revela el mapa a medida que se explora.
- Persiste lo revelado durante la sesión del dungeon.

### Occlusion Fade (obligatorio)
- Paredes/props que crucen la línea entre la cámara y el jugador:
  - **fade-out suave** (semi transparente o invisible)
- Al dejar de obstruir:
  - **fade-in suave** y vuelve a estado normal
- Sin flickering/popping.

### Diálogo (obligatorio)
- Diálogo lineal + un nodo de decisión con 2 opciones (sí/no).
- La decisión cambia la respuesta del NPC.

### Combate (obligatorio)
- Escena aparte: vista lateral.
- Party 2–3 personajes.
- Enemigos 1–3.
- Iniciativa por turno.
- Acciones mínimas:
  - Attack (daño físico)
  - Skill (daño mágico o cura)
  - Defend (reduce daño)
  - Item (poción)
  - Flee (probabilidad simple)
- Victoria/Derrota + retorno a exploración + recompensas (XP + oro o drop simple).

### Contenido (slice)
- 3–5 secciones/salas.
- 2–3 encuentros.
- 1 setpiece (trampa/puzzle mínimo).
- 1 miniboss final.

---

## 6) Fuera de alcance (NO)
- Crafting, equipamiento complejo, quests robustas.
- IA avanzada.
- Animaciones complejas.
- Varios dungeons / world map.
- Cinemáticas largas.
- Localización multi-idioma.

---

## 7) Dirección visual / técnica

### Exploración: 3D isométrico + billboards 2D
- Cámara isométrica fija (pitch/rot estables) con **seguimiento suave** al PJ.
- Player/NPC/muros/props como billboards 2D mirando a cámara.
- Suelo como plano con tileset.

#### Seguimiento de cámara (detalle técnico)
- La cámara debe:
  - Mantener un offset constante (isométrico) respecto al PJ.
  - Interpolar el “target position” con Tween o smoothing controlado.
- Recomendación MVP:
  - Actualizar un `desired_position` basado en `player.global_position + offset`
  - Si cambia significativamente (moviéndose), tween hacia `desired_position`.
  - Al detenerse, aplicar tween corto para “asentar” la cámara.
- Evitar micro-tweens por ruido:
  - usar umbral mínimo (deadzone) antes de re-tween.

#### Billboard
- Preferencia: **Sprite3D** (si aplica) o QuadMesh + textura + billboard.
- El objetivo es legibilidad desde cámara fija, no realismo.

### Linterna (implementación)
Elegir una opción simple:

**Opción A (preferida si es rápida):**
- `SpotLight3D` u `OmniLight3D` pegada al jugador.
- `WorldEnvironment` con ambient bajo para que “se sienta” el radio.

**Opción B (válida si A complica):**
- Overlay 2D “darkness mask”:
  - `CanvasLayer` con rect oscuro
  - agujero circular en el jugador (shader o textura)
- Esta opción es totalmente aceptada en MVP.

### Occlusion Fade (paredes transparentes)
- Debe ser interpolado, nunca instantáneo.
- Implementación:
  - `modulate.a` si son Sprite3D/CanvasItem-like
  - o material/shader con parámetro `alpha`
- El fade no debe tocar colisiones (solo visual).

### Combate: vista lateral
- Escena aparte.
- Sprites 2D para party/enemigos.
- UI clásica menú.

---

## 8) Arquitectura del proyecto (carpetas)
```
res://
  scenes/
    boot/
      Boot.tscn
    exploration/
      Dungeon.tscn
      Player.tscn
      CameraRig.tscn
      NPCIntro.tscn
      Door.tscn
      Pickup.tscn
      CombatTrigger.tscn
    combat/
      Battle.tscn
    ui/
      HUDExploration.tscn
      DialogueBox.tscn
      MiniMap.tscn
      HUDBattle.tscn
  scripts/
    core/
      GameState.gd
      SceneFlow.gd
    exploration/
      PlayerController.gd
      CameraFollow.gd
      Interactable.gd
      Door.gd
      Pickup.gd
      CombatTrigger.gd
      MiniMapReveal.gd
      OcclusionController.gd
      Occludable.gd
    combat/
      BattleController.gd
      TurnSystem.gd
      Combatant.gd
      EnemyAI.gd
    ui/
      DialogueController.gd
      DialogueBox.gd
      MiniMapUI.gd
      BattleUI.gd
    data/
      DataLoader.gd (si se usa JSON)
  data/
    dialogues/
    characters/
    enemies/
    skills/
    items/
    encounters/
    maps/
  assets/
    sprites/
    tiles/
    ui/
    audio/
```

---

## 9) Sistemas — definiciones mínimas

### 9.1 GameState (obligatorio)
Responsable de:
- party actual + HP/MP
- inventario
- flags del dungeon (cofres abiertos, `intro_done`, etc.)
- posición de retorno al salir de combate
- estado del minimapa (celdas reveladas)
- estado temporal si aplica (oro, XP)

### 9.2 Data (Resources o JSON)
Para MVP se aceptan ambos. Recomendación:
- **Resources** si se generan rápido con el agente
- si no: JSON + `DataLoader.gd`

Definir:
- `CharacterData`: id, name, stats, skills
- `EnemyData`: id, name, stats, skills
- `SkillData`: id, name, mp_cost, target_type, power, effect_type
- `ItemData`: id, name, effect
- `EncounterData`: id, enemies[], rewards

### 9.3 Exploración — Interacción
Base:
- `Interactable.gd`:
  - `interact()` (virtual)
  - `get_prompt_text()`
  - `is_available()`

El player detecta interactable (raycast/area frontal):
- si hay interactable: mostrar prompt
- `action1` llama `interact()`

#### Door
- Estado `open/closed`
- Open: colisión off, Closed: colisión on
- Fade/occlusion no afecta la colisión.

#### Pickup/Cofre
- Al interactuar: añade item + set flag `opened`
- Desaparece o cambia sprite

#### CombatTrigger
- Area → SceneFlow cambia a Battle con `EncounterData.id`

### 9.4 Cámara con seguimiento suave (obligatorio)
Debe existir un componente dedicado, por ejemplo `CameraFollow.gd` en un `CameraRig.tscn`.

Requisitos:
- Cámara mantiene un offset isométrico respecto al PJ.
- Al comenzar el movimiento del PJ:
  - la cámara “engancha” con **tween suave** hasta seguirlo (ease out).
- Al detenerse el PJ:
  - la cámara “asienta” con **tween suave** (ease in/out).
- Debe evitar jitter:
  - usar deadzone o tolerancia mínima antes de re-tween.
  - no disparar tweens cada frame por variaciones mínimas.
- La cámara no debe atravesar paredes (opcional para MVP; priorizar suavidad).

### 9.5 Minimapa con fog-of-war (obligatorio)
Debe:
- Mostrar player marker
- Revelar celdas exploradas
- Persistir lo revelado en GameState mientras dure el dungeon

**Implementación mínima recomendada**
- Basada en grid del TileMap del suelo:
  - `MiniMapReveal.gd`: convierte posición player→celda, revela radio (2–4)
  - guarda en `revealed_cells` (Dictionary/Set)
- `MiniMapUI.gd`:
  - dibuja celdas reveladas (Control._draw o textura)
  - dibuja player marker

### 9.6 Linterna (obligatorio)
- Debe seguir al jugador.
- Radio configurable.
- No requiere sombras caras.

### 9.7 Sistema de Diálogo con branching mínimo (obligatorio)

#### Datos de diálogo
Formato recomendado (JSON simple):
- `nodes` por id, con:
  - `text`
  - `speaker` (opcional)
  - `next` (opcional)
  - `choices` (opcional: array de 2)

#### UI/Comportamiento
- `DialogueController.gd`:
  - `start(dialogue_id)`
  - bloquea input de movimiento
  - emite `dialogue_finished(dialogue_id)`
- `DialogueBox.gd`:
  - muestra speaker + texto
  - si hay choices:
    - renderiza 2 opciones
    - selección por defecto opción 1
    - `action1`: confirma opción seleccionada
    - `action2`: confirma opción 2 inmediatamente (equivale a “no/cancelar”)

Regla importante:
- Durante diálogo lineal:
  - `action1` avanza
  - `action2` no cancela
- Durante elección:
  - `action2` = elegir opción 2

### 9.8 Sistema de Occlusion Fade (obligatorio)

Objetivo:
Si una pared/prop se interpone entre cámara y jugador:
- **fade-out suave**
Si deja de obstruir:
- **fade-in suave**

Implementación mínima:
- `OcclusionController.gd` (manager global):
  - raycast desde cámara a jugador (1–3 rays si hace falta)
  - detecta colliders en layer `occluder`
  - mantiene cache de objetos ocultos actualmente
  - llama `fade_out()` / `fade_in()` según corresponda
- `Occludable.gd` en cada pared/prop relevante:
  - estados VISIBLE/HIDDEN y target alpha
  - interpolación con `lerp` o Tween
  - no modifica colisión

Requisitos:
- Sin flickering/popping.
- Fade solo visual.
- No ocultar suelo ni props irrelevantes.

### 9.9 Combate por turnos (obligatorio)
- `TurnSystem.gd`:
  - iniciativa: `spd + randi_range(0,5)` o `spd` puro
  - cola de turnos
- `Combatant.gd`:
  - stats base + HP/MP actuales
  - `defending` reduce daño por 1 turno
- `EnemyAI.gd`:
  - elige Attack o Skill simple
- `BattleController.gd`:
  - procesa turnos y emite eventos para UI
- UI:
  - menú Attack/Skill/Item/Defend/Flee
  - selección de target si aplica
  - log textual de acciones

---

## 10) Flujo de escenas
- `Boot.tscn` inicializa `GameState` y carga dungeon.
- `Dungeon.tscn` contiene:
  - Player + CameraRig (CameraFollow)
  - HUDExploration (minimapa, prompt)
  - NPC intro
  - 2–3 combat triggers
  - 1 door
  - 1 pickup/cofre
  - paredes/props en layer `occluder` con `Occludable.gd`
- Al iniciar combate:
  - guardar `return_position` en GameState
  - cargar `Battle.tscn` con `EncounterData.id`
- Al terminar combate:
  - aplicar recompensas
  - volver al dungeon y restaurar posición

---

## 11) Contenido mínimo del Slice
Propuesta:
1. Entrada con NPC intro (diálogo + decisión).
2. Pasillo con primer trigger de combate.
3. Sala con puerta cerrada y cofre/poción.
4. Trampa simple (tile daño o switch abre atajo).
5. Sala final con miniboss + salida.

Nota legal:
- Adaptación libre: no replicar mapa ni texto literal del módulo.

---

## 12) NPC Intro (guion mínimo obligatorio)
Debe incluir una elección y dos respuestas distintas.

Ejemplo (editable):
- NPC: “Al fin llegas. Este lugar castiga la arrogancia.”
- NPC: “¿Quieres que te marque el camino en el minimapa?”
- Opciones:
  1) “Sí, muéstrame.” (action1)
  2) “No, prefiero descubrirlo.” (action2)
- Respuesta si Sí:
  - “Bien. Lo que explores quedará registrado.”
  - Efecto opcional: revelar un radio inicial extra.
- Respuesta si No:
  - “Valiente… entonces confía en tu memoria.”
- Flag final:
  - `intro_done = true`

---

## 13) Checklist de entregables
- Proyecto Godot 4.7 corre.
- Flujo completo: exploración → combate → retorno → final del slice.
- InputMap Z/X (action1/action2) correcto.
- Diálogo con branching 2 opciones.
- Minimapa fog-of-war funcional.
- Linterna funcional.
- Occlusion Fade funcional sin flickering.
- Cámara sigue al PJ con tween suave al iniciar y detener movimiento.
- Puertas, pickup, triggers.
- Combate por turnos con UI funcional.
- Data editables: 2–3 party, 3 enemigos, 2 skills, 1–2 items, 2–3 encounters.

---

## 14) Criterios de aceptación
El MVP está listo cuando:
- Movimiento y colisiones funcionan.
- **Cámara**: sigue al PJ con **tween suave** al moverse y al detenerse (sin snap, sin jitter).
- Linterna oscurece correctamente.
- Minimapa revela progresivamente.
- NPC Intro tiene decisión funcional (Z confirma, X toma “No”).
- Al menos 2 combates completos.
- Miniboss derrotable.
- Occlusion Fade funciona sin parpadeos.
- Flujo completo sin depender del editor.

---

## 15) Plan de implementación (orden recomendado)
1. Skeleton del proyecto (Boot + GameState + SceneFlow).
2. Exploración base (Player + colisiones + cámara isométrica estática).
3. **CameraFollow con tween** (suavidad de seguimiento).
4. Interactables (Door/Pickup/Triggers).
5. Diálogo con branching (NPC intro).
6. Minimapa (reveal + UI).
7. Linterna (Light3D u overlay).
8. Occlusion Fade (OcclusionController + Occludable).
9. Combate (Battle + TurnSystem + UI).
10. Integración y contenido final.
11. Pulido mínimo.

---

## 16) Notas para el agente IA
- Mantener scripts pequeños y legibles.
- Usar señales para separar UI y lógica.
- Si algo se complica, recortar sin romper el slice.
- “Suficientemente bueno” en minimapa/linterna/occlusion > “perfecto”.
