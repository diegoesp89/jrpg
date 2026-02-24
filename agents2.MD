# agents2.MD — Estado del Proyecto JRPG (Post-Sesion 1)

## Resumen

Este documento describe todo lo implementado en la primera sesion de desarrollo del Vertical Slice JRPG en Godot 4.7. El objetivo es que cualquier agente IA o desarrollador pueda continuar el trabajo sin perder contexto.

El documento original de especificacion esta en `agents.MD`. Este archivo (`agents2.MD`) documenta **lo que ya existe** y **lo que falta ajustar/probar**.

---

## Estado general: IMPLEMENTACION COMPLETA (no probada)

Todos los sistemas obligatorios del MVP fueron implementados en codigo. Sin embargo, **nada fue probado en Godot** porque el agente no tiene acceso al editor. El primer paso de la siguiente sesion debe ser abrir el proyecto en Godot 4.7 y resolver errores de carga/ejecucion.

---

## Archivos creados (39 archivos)

### Configuracion
- `project.godot` — Config completa: display 1280x720, stretch canvas_items, input map (WASD/flechas + Z/X), 5 physics layers, 3 autoloads, render forward_plus, clear color oscuro.

### Escenas (.tscn)
- `scenes/boot/Boot.tscn` — Escena de entrada, carga dungeon via SceneFlow.
- `scenes/exploration/Dungeon.tscn` — Escena principal de exploracion. Contiene Player, CameraRig, DungeonBuilder, WorldEnvironment. El DungeonManager (script raiz) instancia DialogueController, MiniMapReveal, MiniMapUI, OcclusionController y la linterna en `_ready()`.
- `scenes/exploration/Player.tscn` — CharacterBody3D con CollisionShape3D, Sprite3D (billboard), InteractionArea (SphereShape3D radio 2.0). Collision layer 2 (player), mask 1 (world).
- `scenes/exploration/CameraRig.tscn` — Node3D con Camera3D ortogonal (size 14).
- `scenes/combat/Battle.tscn` — Escena de combate, crea BattleController y BattleUI por codigo.

### Scripts Core (autoloads)
- `scripts/core/GameState.gd` — Singleton. Maneja party (array de dicts), inventario, flags, revealed_cells (minimapa), combat return state. Inicializa party desde DataLoader en `_ready()`.
- `scripts/core/SceneFlow.gd` — Singleton. Maneja transiciones con fade-to-black (CanvasLayer + ColorRect). Metodos: `change_scene()`, `start_battle()`, `end_battle()`. Fade de 0.3s.
- `scripts/core/Boot.gd` — Entry point. Espera un frame y llama SceneFlow.change_scene al dungeon.

### Scripts Data
- `scripts/data/DataLoader.gd` — Singleton. Carga 6 JSONs al inicio. Getters: `get_character()`, `get_enemy()`, `get_skill()`, `get_item()`, `get_encounter()`, `get_dialogue()`, `get_all_characters()`.

### Scripts Exploracion
- `scripts/exploration/PlayerController.gd` — Movimiento isometrico (WASD mapeado a ejes iso), deteccion de interactables via InteractionArea, signal `interactable_changed`, `set_movement_disabled()`. Se agrega al grupo "player". Genera textura placeholder azul con "ojos" en _ready().
- `scripts/exploration/CameraFollow.gd` — Camara isometrica. Offset Vector3(10, 14, 10). Sigue al jugador con `lerp()` en `_process()`. Camera3D ortogonal, look_at al target. Deadzone de 0.1 para evitar micro-movimientos.
- `scripts/exploration/DungeonBuilder.gd` — Genera el dungeon completo por codigo desde un array 2D (25x20). Tiles: EMPTY(0), FLOOR(1), WALL(2), DOOR(3), NPC(4), CHEST(5), COMBAT_TRIGGER(6), TRAP(7), BOSS_TRIGGER(8), EXIT(9). Crea StaticBody3D para muros, Area3D para triggers/traps, suelo con PlaneMesh checkerboard. Cada muro tiene un nodo hijo Occludable. Texturas generadas proceduralmente (ImageTexture).
- `scripts/exploration/DungeonManager.gd` — Script raiz del Dungeon.tscn. En `_ready()` configura: Environment (oscuro, ambient bajo), posicion inicial del player, camara, HUD (CanvasLayer con prompt label y HP label), linterna (OmniLight3D hijo del player), DialogueController, MiniMapReveal, MiniMapUI, OcclusionController. Restaura posicion post-combate.
- `scripts/exploration/Interactable.gd` — Base class (class_name Interactable). Metodos virtuales: `interact()`, `get_prompt_text()`, `is_available()`.
- `scripts/exploration/Door.gd` — Extiende StaticBody3D. Toggle open/closed. Open: deshabilita collision, sprite alpha 0.3. Closed: habilita collision, sprite alpha 1.0.
- `scripts/exploration/Pickup.gd` — Extiende StaticBody3D. Al interactuar: agrega item a inventario, set flag opened, grisea sprite, deshabilita collision. Verifica flag en _ready() para persistencia.
- `scripts/exploration/CombatTrigger.gd` — Extiende Area3D. Auto-detecta encounter_id por nombre del nodo ("hallway", "golem", "boss"). Set flag al activarse para no repetir. Llama SceneFlow.start_battle().
- `scripts/exploration/NPCIntro.gd` — Extiende StaticBody3D. Busca DialogueController en grupo "dialogue_controller". Deshabilita movimiento del player. Si ya se completo (flag "intro_done"), muestra mensaje corto.
- `scripts/exploration/Trap.gd` — Extiende Area3D. Al entrar el player, hace 10 de dano al lider. Se activa una sola vez.
- `scripts/exploration/MiniMapReveal.gd` — Cada frame, convierte posicion del player a celda grid y revela celdas en radio 3 (circular).
- `scripts/exploration/Occludable.gd` — Nodo hijo de muros/props. Maquina de estados (VISIBLE, FADING_OUT, FADING_IN, HIDDEN). Interpola modulate.a con move_toward(). Busca Sprite3D como sibling.
- `scripts/exploration/OcclusionController.gd` — Raycast desde camara a player cada physics frame. Collision mask 16 (layer 5 = occluder). Multi-cast (hasta 10 hits). Llama fade_out/fade_in en el nodo hijo "Occludable" de cada wall colisionado.

### Scripts Combate
- `scripts/combat/BattleScene.gd` — Script raiz de Battle.tscn. Crea BattleController y BattleUI por codigo, los conecta, inicia batalla con GameState.current_encounter_id. En victoria/huida: SceneFlow.end_battle(). En derrota: vuelve a Boot.
- `scripts/combat/BattleController.gd` — Orquesta el combate. Setup: copia party de GameState, crea enemies desde DataLoader. TurnSystem para orden. Procesa turnos player y enemy. Formulas en Combatant.gd. Signals: battle_ended, action_performed, turn_changed, hp_updated. Sync party de vuelta a GameState al terminar.
- `scripts/combat/TurnSystem.gd` — Calcula orden: spd + randi_range(0,5), ordena descendente. Metodos: start_new_round(), get_current_combatant(), advance_turn().
- `scripts/combat/Combatant.gd` — Funciones estaticas de calculo: calculate_physical_damage, calculate_magical_damage, calculate_heal, calculate_flee_chance, apply_damage, apply_heal, use_mp, is_dead. Varianza +/-10% en dano.
- `scripts/combat/EnemyAI.gd` — 70% attack, 30% skill (si tiene MP). Elige target aleatorio vivo. Para heal, elige aliado mas debil.

### Scripts UI
- `scripts/ui/DialogueController.gd` — Se agrega a grupo "dialogue_controller". Carga dialogo de DataLoader, navega nodos con next/choices. action1 avanza/confirma, action2 elige opcion 2 inmediatamente. Set flags desde nodos de dialogo. Crea DialogueBox dinamicamente si no existe.
- `scripts/ui/DialogueBox.gd` — PanelContainer con speaker label, RichTextLabel, VBoxContainer de choices. Navegacion con move_up/move_down. Highlight amarillo en seleccion actual. Fondo semi-transparente azul oscuro con borde dorado.
- `scripts/ui/MiniMapUI.gd` — Control que dibuja en _draw(). Fondo negro semi-transparente, borde dorado. Dibuja celdas reveladas con colores por tipo (wall gris, door marron, floor oscuro). Player marker como circulo cyan. Obtiene dungeon_map del DungeonBuilder. Esquina superior derecha.
- `scripts/ui/BattleUI.gd` — CanvasLayer completo. Campo de batalla arriba (60%) con party sprites azules a la izquierda y enemy sprites rojos a la derecha. Panel inferior con: stats de party, menu de acciones, log de combate. Menus: MAIN (Atacar/Habilidad/Objeto/Defender/Huir), SKILL, ITEM, TARGET. Navegacion con move_up/move_down, action1 confirma, action2 vuelve atras.

### Data JSON
- `data/characters/characters.json` — 3 personajes: Kael (warrior), Lyra (mage), Voss (rogue).
- `data/enemies/enemies.json` — 3 enemigos: Esqueleto, Golem de Piedra, Guardian de Llamas (boss).
- `data/skills/skills.json` — 6 skills: power_strike, fireball, heal, poison_blade, smash, fire_breath.
- `data/items/items.json` — 1 item: Pocion (heal 30 HP).
- `data/encounters/encounters.json` — 3 encuentros: encounter_hallway (2 esqueletos), encounter_golem (1 golem), encounter_boss (1 guardian).
- `data/dialogues/dialogues.json` — Dialogo del NPC intro con branching. 5 nodos: start -> ask -> yes_response/no_response -> end. Flags: minimap_hint, intro_done.

---

## Layout del dungeon (mapa 25x20)

```
  [Sala 1: Entrada] (rows 0-4, cols 0-7)
       |
  NPC Intro en (col 2, row 2)
       |
  [Pasillo] (rows 5-7, cols 2-5)
       |
  CombatTrigger #1 en (col 3, row 6) — 2 esqueletos
       |
  [Sala 2: Bifurcacion] (rows 8-11, cols 0-11)
      / \
     /   \
[Sala 3: izq]       [Sala 4: der]
Door en (col 1, row 14)   Trap en (col 9, row 13)
Chest en (col 2, row 13)  CombatTrigger #2 (col 9, row 14) — 1 golem
     \   /
      \ /
  [Reconnect] (row 16)
       |
  [Sala 5: Boss] (rows 17-19)
  Boss trigger en (col 5, row 18) — Guardian de Llamas
  Exit en (col 5, row 19)
```

Player start: col 4, row 2 (centro de Sala 1).
TILE_SIZE = 2.0 unidades Godot.

---

## Formulas de combate implementadas

```
# Dano fisico
damage = atk - def/2  (+ skill_power si aplica)
damage *= random(0.9, 1.1)
damage = max(1, damage)
if defending: damage /= 2

# Dano magico
damage = skill_power + mag - mdef/2
# misma varianza y defend

# Curacion
heal = skill_power + mag/2
# varianza 0.9-1.1

# Huida
chance = 0.5 + (avg_party_spd - avg_enemy_spd) * 0.05
chance = clamp(0.1, 0.9)

# Iniciativa
initiative = spd + randi_range(0, 5)
```

---

## Decisiones de diseno tomadas

1. **Sin assets externos**: Todo visual es procedural (ImageTexture, PlaneMesh, ColorRect).
2. **Data en JSON**: Todos los datos editables estan en `data/`.
3. **Dungeon generado por codigo**: DungeonBuilder usa array 2D, no TileMap. Mas robusto para generacion sin editor.
4. **Occlusion via nodo hijo**: Cada muro tiene un nodo "Occludable" hijo. OcclusionController busca ese hijo en los colliders detectados por raycast.
5. **Transiciones con fade**: SceneFlow usa CanvasLayer layer 100 con ColorRect, tween alpha 0.3s.
6. **Combate con copia de party**: BattleController trabaja con copias, sync de vuelta a GameState al terminar.
7. **Dialogo con nodos JSON**: Estructura de nodos con next/choices, flags procesados inline.

---

## Problemas conocidos y cosas a verificar en Godot

### Prioridad ALTA (probablemente necesitan fix)

1. **UIDs en .tscn**: Use UIDs inventados (`uid://boot_scene`, `uid://player_scene`, etc.). Godot 4.7 podria rechazarlos. **Fix**: Abrir cada .tscn en Godot, dejar que regenere UIDs, o eliminar las lineas `uid=` de los .tscn.

2. **Orden de carga de autoloads**: GameState llama `DataLoader.get_all_characters()` en su `_ready()`. Si DataLoader no ha ejecutado su `_ready()` aun, los datos estaran vacios. **Fix potencial**: Verificar el orden de autoloads en project.godot (DataLoader debe estar antes que GameState) o usar `call_deferred` / `await`.

3. **Player.tscn InteractionArea signals**: Las conexiones de signals en el .tscn podrian no funcionar si el formato no es exacto. **Fix**: Reconectar manualmente en el editor si falla, o conectar por codigo en `_ready()`.

4. **Dungeon.tscn referencia DungeonManager.gd como script raiz**: Verifica que el ExtResource path es correcto y que DungeonManager.gd extiende Node3D como espera el nodo raiz.

5. **MiniMapUI posicionamiento**: Usa `position` negativa para esquina superior derecha. Puede necesitar ajuste dependiendo del anchor real.

### Prioridad MEDIA

6. **Occludable _find_sprite()**: Busca Sprite3D entre siblings (hijos del parent). Deberia funcionar pero verificar que el Sprite3D se crea antes que el Occludable en DungeonBuilder.

7. **CombatTrigger auto-detect**: Depende de que el nombre del nodo contenga "hallway", "golem", o "boss". Verificar que DungeonBuilder nombra los triggers correctamente.

8. **BattleUI layout**: Las posiciones absolutas (px) pueden no verse bien en todas las resoluciones. Es aceptable para MVP.

9. **DialogueBox dinámico**: DialogueController crea el DialogueBox por codigo. Verificar que funciona con el CanvasLayer que crea.

### Prioridad BAJA

10. **TurnSystem `advance_turn()`**: Salta combatants muertos. Verificar edge case donde todos mueren en medio de una ronda.

11. **Exit handler**: Solo hace print("Victory!"). Falta una pantalla de victoria real. Aceptable para MVP inicial.

---

## Orden recomendado para la siguiente sesion

1. **Abrir en Godot 4.7** — Resolver errores de carga (UIDs, paths, etc.)
2. **Fix del orden de autoloads** — Asegurar DataLoader carga antes que GameState.
3. **Probar flujo basico** — Boot -> Dungeon: verificar que el mapa se genera, el player se mueve, la camara sigue.
4. **Probar interacciones** — NPC dialogo, puerta, cofre.
5. **Probar combate** — Trigger -> Battle -> acciones -> victoria -> retorno.
6. **Ajustar visual** — Posiciones de UI, tamano de sprites, iluminacion.
7. **Pulir** — Balance de stats, experiencia de usuario, edge cases.
8. **Pantalla de victoria** — Agregar una escena o UI simple al llegar al Exit.

---

## Archivos NO creados (que el spec original menciona pero no son estrictos)

- `scenes/ui/HUDExploration.tscn` — Se crea por codigo en DungeonManager.
- `scenes/ui/DialogueBox.tscn` — Se crea por codigo en DialogueController.
- `scenes/ui/MiniMap.tscn` — Se crea por codigo en DungeonManager.
- `scenes/ui/HUDBattle.tscn` — Se crea por codigo en BattleScene.
- `scenes/exploration/NPCIntro.tscn` — Se crea por codigo en DungeonBuilder.
- `scenes/exploration/Door.tscn` — Se crea por codigo en DungeonBuilder.
- `scenes/exploration/Pickup.tscn` — Se crea por codigo en DungeonBuilder.
- `scenes/exploration/CombatTrigger.tscn` — Se crea por codigo en DungeonBuilder.
- `data/maps/` — El mapa esta hardcoded en DungeonBuilder.gd como array.

Estos no fueron creados como .tscn separados porque la generacion por codigo es mas confiable sin acceso al editor. Si en el futuro se quiere extraerlos a escenas, es refactoring directo.

---

## Stack tecnico final

- Godot 4.7, GDScript
- 3 autoloads: GameState, SceneFlow, DataLoader
- 3 escenas .tscn: Boot, Dungeon, Battle (el resto es por codigo)
- 6 archivos JSON de data
- 22 scripts GDScript
- 0 assets externos (todo procedural)
- Resolucion: 1280x720, stretch canvas_items
- Physics layers: world(1), player(2), interactable(3), trigger(4), occluder(5)
- Input: WASD/flechas + Z(action1) + X(action2)
