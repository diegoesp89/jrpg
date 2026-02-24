# agents2.MD — Estado del Proyecto JRPG (Post-Sesion 7)

## Goal

Build a complete **Vertical Slice MVP of a JRPG** in **Godot 4.6.1** using **GDScript**. The project is located at `/Users/despinozav/Downloads/jrpg` and pushed to **https://github.com/diegoesp89/jrpg**. The game features isometric 3D exploration with 2D billboard sprites, turn-based combat (Final Fantasy style lateral view), dialogue with branching, minimap with fog-of-war, a lantern system, occlusion fade, and a dungeon inspired loosely by White Plume Mountain.

## Instructions

- **Engine**: Godot 4.6.1, GDScript only, no external plugins
- **Resolution**: 1920x1080, stretch mode canvas_items, **fullscreen** (`window/size/mode=3`)
- **Font sizes**: All text has been **tripled (x3)** from original values for readability at fullscreen — this includes BattleUI, DialogueBox, DungeonManager, DungeonBuilder
- **Controls**: WASD/arrows for movement, Z (`action1`) for confirm/interact, X (`action2`) for cancel/back, Q (`zoom_in`) / E (`zoom_out`) for camera zoom
- **Data format**: JSON files for all game data (characters, enemies, skills, items, encounters, dialogues). Loaded by `DataLoader.gd` autoload.
- **Visual approach**: No external art assets except player spritesheet. All other visuals are procedural (ImageTexture, QuadMesh, PlaneMesh, ColorRect placeholders). NPC=green billboard, walls=gray flat quads perpendicular to floor, doors=brown, chests=yellow, enemies=red.
- **Player sprite**: Uses `assets/sprites/spritesheet.png` — a classic RPG character spritesheet with BG color `RGB(255, 5, 238)` replaced with transparency at runtime. 4-direction walk cycle (3 frames each) from band 2 (y=84, 26x30px cells).
- **Walls**: Must be perpendicular to the floor (like real walls), NOT billboards. One quad per exposed face, visible from both sides (`CULL_DISABLED`). Walls start opaque for correct depth testing.
- **Sprites (player, NPC, chest, door)**: Billboard mode with `alpha_cut = ALPHA_CUT_OPAQUE_PREPASS` for correct depth buffer writing.
- **Movement**: Must be camera-relative (derived from camera basis projected onto XZ plane at runtime).
- **Camera**: Perspective projection with 2 discrete zoom levels cycled via Q/E. Fixed rotation (no tilt/wobble — `look_at` called once, never per-frame). Delayed engage on movement start (0.15s), smooth settle on stop. **Always stays in PROJECTION_PERSPECTIVE** — level 2 uses very low FOV (5°) to approximate ortho, allowing smooth interpolation. FOV and distance lerp **independently** to avoid nonlinear spikes from `1/tan(fov/2)`.
- **Camera FOV limits**: Minimum FOV for zoom-out is **5°**. Lower values cause the camera distance to exceed the `far` plane (1000 units) — at FOV 1° the distance is ~1002 units, causing geometry to clip. At FOV 5° the distance is ~200, safely within range. See Discovery #33.
- **Fog**: Player-centered XZ distance fog via spatial shaders on all dungeon materials (floor, walls, caps, trap, exit). NOT camera-based Environment fog. Uses global shader uniforms (`player_world_pos`, `fog_start=6.0`, `fog_end=10.0`). **Fog values are FIXED at fog_start=6.0, fog_end=10.0, independent of zoom level.**
- **Dungeon generation**: Built programmatically from a 2D array in `DungeonBuilder.gd` (not TileMap).
- **Scene transitions**: Fade-to-black via `SceneFlow.gd` (CanvasLayer + ColorRect, 0.3s tween).
- **Combat**: Copies party data for battle, syncs back to GameState on completion. Final Fantasy lateral view.
- **Occlusion**: Walls have a child node `Occludable`; `OcclusionController` raycasts camera→player and calls fade_out/fade_in. Walls use ShaderMaterial — Occludable swaps between opaque shader (`_fog_shader_textured`) and transparent shader (`_fog_shader_textured_alpha` with `depth_draw_always`) during fade.
- **Autoload order**: DataLoader → GameState → SceneFlow (DataLoader must load first).
- **Git**: Project pushed to `https://github.com/diegoesp89/jrpg`, branch `main`. Use `gh` CLI (authenticated as `diegoesp89`) for pushes.
- Full spec is in `agents.MD` (sections 0-16).

## Discoveries

1. **Godot version is 4.6.1**, not 4.7. The enum `Environment.TONE_MAP_ACES` doesn't exist — correct name is `Environment.TONE_MAPPER_ACES`.
2. **`class_name` was missing** on `TurnSystem.gd`, `Combatant.gd`, `EnemyAI.gd` — all three are referenced by type name in `BattleController.gd`. Fixed in prior session.
3. **Camera `look_at` crash**: When camera and target are at the same position, `look_at()` fails. Fixed with `_safe_look_at()` guard.
4. **Movement must be camera-relative**: Hardcoded isometric vectors were wrong. Fixed to derive from `camera.global_basis.x` and `-camera.global_basis.z` projected onto XZ plane.
5. **`_clear_container` using `queue_free()` caused ghost children**: Fixed by calling `remove_child()` before `queue_free()`.
6. **Transparent materials don't write to depth buffer**: Walls with `TRANSPARENCY_ALPHA` caused sprites to render on top of walls. Fix: walls start opaque, `Occludable` toggles transparency only during fade.
7. **Fabricated UIDs in .tscn files** (`uid://boot_scene`, etc.) would cause parse errors in Godot. Fixed by removing all fake UIDs from all 5 scene files.
8. **DialogueBox.setup() was called twice** — once by `_ready()` on `add_child()` and once explicitly in `DialogueController._find_or_create_dialogue_box()`. This created duplicate UI children. Fixed by removing the explicit call.
9. **BattleController soft-lock**: When `player_action` got an empty target for "attack", `_waiting_for_player` was set to false but never restored. Fixed by re-setting `_waiting_for_player = true` on early return.
10. **CombatTrigger set flag before battle started**: Losing/fleeing battle made the encounter disappear permanently. Fixed by moving flag-setting to `BattleScene._on_battle_ended("victory")`.
11. **NPC/Chest had no world collision** (only interactable layer 4). Player walked through them. Fixed by adding layer 1 to their collision_layer.
12. **Double floor tiles** for NPC, Chest, and Door cells (one from `_build_floor()`, one from explicit `_create_floor_tile()` calls). Caused Z-fighting. Fixed by removing the duplicate explicit calls.
13. **Occludable._find_visuals() timing**: Called in `_ready()` before sibling WallFace meshes might exist. Fixed by deferring with `await get_tree().process_frame`.
14. **JSON data matches code**: Despite differing from the AGENTS.md spec (which said arrays, different enum names), the actual JSON uses dict-by-id and `effect_type: "physical"/"magical"/"heal"`, `target_type: "single_enemy"/"all_enemies"/"single_ally"` — and the code was written to match the actual JSON. No mismatch.
15. **Combatant damage formula operator precedence**: `atk + skill_power - def_val / 2` computes `atk + skill_power - (def_val/2)` which may or may not be intended. Not fixed — noted as a potential balance issue.
16. **BattleUI._update_battle_sprites is a no-op** (`pass`). Dead combatants never visually change. Not fixed — acceptable for MVP.
17. **DungeonBuilder.gd match indentation**: Looked visually misaligned in the read tool but confirmed correct with `cat -vet` (all tabs properly aligned).
18. **Void ternary expression** (`body.set_movement_disabled(true) if cond else null`) is invalid GDScript 4.6 — produces parser error. Fixed with normal `if` block.
19. **GameState autoload persists across scene changes**: After defeat restart, party stays dead, flags stay set, inventory persists. Fixed by adding `GameState.reset()` called on defeat.
20. **BattleUI empty menu crash**: Navigating skill/item/target menus with 0 entries caused `_selected_index = -1` → array out-of-bounds. Fixed with empty-list guards.
21. **Enemy MP not checked**: `BattleController` ignored `use_mp()` return value for enemies — skill executed without deducting MP. Fixed to check and fall back to basic attack.
22. **Camera tilt/wobble**: Caused by calling `look_at()` every frame. Fixed by calling it once in `_apply_fixed_rotation()` and never again.
23. **Camera off-center after combat**: Player position was restored AFTER camera setup in `DungeonManager._ready()`. Camera snapped to start position, player teleported, follow factor was 0 so camera never caught up. Fixed by moving return_position restore BEFORE `_setup_camera()`.
24. **Zoom only worked during movement**: Camera only moved when `_current_follow_factor > 0.001`. When standing still, factor was 0, so zoom changes were ignored. Fixed by always following at full speed when standing still or fully engaged, only applying ramp during the engage delay.
25. **Spritesheet BG color**: The spritesheet uses `RGB(255, 5, 238)` (palette index 0, 78.7% of pixels), NOT pure magenta `(255, 0, 255)`. Detected via pixel analysis with PNG defiltering. Replaced at runtime with tolerance-based comparison.
26. **Spritesheet layout**: 334x184px, palette-indexed (ColorType 3, 68 colors). 4 content bands separated by fully-BG rows: Band 1 (y=7 h=65) = portrait + large frames, Band 2 (y=86 h=26) = 12 walk frames, Band 3 (y=119 h=25) = 12 walk frames (alt set), Band 4 (y=151 h=25) = 10 frames. Band 2 used for walk cycle: 4 dirs × 3 frames at 26x30px cells.
27. **Zoom out narrowed view instead of expanding it**: Lowering FOV without compensating distance made the view *smaller*. Fixed with `_get_distance_for_zoom()` using `tan(ref_fov/2) / tan(current_fov/2)` to scale distance inversely with FOV.
28. **Canvas_item post-process fog failed (all white)**: Reconstructing world position from depth buffer in a `canvas_item` shader is unreliable in Godot 4 / Vulkan — NDC conventions, Y flip, and projection matrix quirks made reconstruction output garbage. Replaced with **spatial shader approach**: fog logic built directly into each dungeon material's fragment shader using `MODEL_MATRIX * VERTEX` for world position. 100% reliable since no depth reconstruction needed.
29. **ShaderMaterial breaks Occludable**: Old `Occludable.gd` accessed `StandardMaterial3D` properties (`albedo_color.a`, `transparency`). With ShaderMaterial, these don't exist. Fixed by having Occludable detect material type — for ShaderMaterial, it swaps between opaque shader (no ALPHA output) and transparent shader (writes ALPHA + `depth_draw_always`), and sets the `alpha` uniform parameter.
30. **Global shader uniforms must exist before shaders render**: `DungeonBuilder._ready()` runs before `DungeonManager._ready()` (children before parent). Globals are now registered in `DungeonBuilder._register_fog_globals()` with existence checks, and `DungeonManager._setup_player_fog_global()` also checks before adding to avoid duplicates.
31. **Zoom transition caused distance spike**: When FOV and distance were coupled via `1/tan(fov/2)` and FOV was lerped linearly, the highly nonlinear function caused distance to spike at small angles during transition (e.g., going from FOV 5° to 50°, distance would jump up before coming down). **Fixed by lerping FOV and distance independently** — both use the same `lerpf` speed, distance goes directly from ~200 to ~13.4 without deriving from the intermediate FOV values.
32. **Fog_end was dynamically tied to camera frustum**: Made fog change with zoom which user didn't want. **Fixed to always be fog_start=6.0, fog_end=10.0 regardless of zoom level.**
33. **FOV near 0° breaks rendering**: With very low FOV, `_calc_distance()` pushes camera extremely far away. The relationship is: FOV 5° → distance ~200 (OK), FOV 3° → ~334 (borderline), FOV 2° → ~501 (risky depth precision), FOV 1° → ~1002 (exceeds `far=1000`, geometry clips). **Minimum safe FOV is 5°.** This was investigated when user requested FOV 0 and the fog appeared bugged — the actual problem was geometry clipping past the far plane, not the fog shader itself.

## Accomplished

### All implementation phases code-complete + bug fixes from 7 sessions:

- All 11 implementation phases code-complete (session 1)
- Fixed fabricated UIDs in all 5 `.tscn` files
- Fixed DialogueBox.setup() double-call creating duplicate UI children
- Fixed BattleController soft-lock on empty attack target
- Fixed CombatTrigger flag timing (now set on victory, not on trigger entry)
- Fixed PlayerController _sprite access outside null guard (crash)
- Fixed DungeonBuilder double floor tiles (Z-fighting)
- Fixed NPC/Chest walk-through (added world collision layer)
- Fixed SceneFlow re-entrancy guard for change_scene
- Fixed DataLoader null check on FileAccess.open()
- Fixed Occludable._find_visuals() timing (deferred with await)
- Fixed CameraFollow lerp clamp + removed dead `_desired_position` code
- Fixed Pickup._ready() sprite search order
- Fixed NPCIntro player stuck if dialogue data missing
- Verified JSON data matches what code expects
- Implemented victory screen
- Fixed void ternary expression in DungeonBuilder.gd:411 (CRITICAL)
- Added GameState.reset() and called on defeat (HIGH)
- Fixed BattleUI empty menu negative index crash (HIGH)
- Fixed BattleController enemy MP check (MEDIUM)
- Set fullscreen mode (`window/size/mode=3` in project.godot)
- **Tripled all font sizes (x3)** across BattleUI, DialogueBox, DungeonManager, DungeonBuilder
- **Fixed camera tilt**: Rotation set once via `_apply_fixed_rotation()`, never `look_at()` per frame
- **Added delayed camera engage** (0.15s delay before following) and **smooth settle** on stop
- **Switched to perspective camera** with offset `(7, 9, 7)`, FOV-driven
- **Fixed camera off-center after combat**: Moved return_position restore before `_setup_camera()`
- **Fixed zoom only working during movement**: Camera follows at full speed when standing still
- **Integrated spritesheet** for player character: 4-direction walk animation (3 frames each, ping-pong)
- **Moved spritesheet** from `data/characters/` to `assets/sprites/`
- **Player-centered XZ fog via spatial shaders**: Replaced broken Environment fog AND broken canvas_item post-process with fog logic in every dungeon material's fragment shader. Uses global uniforms `player_world_pos`, `fog_start=6.0`, `fog_end=10.0`.
- **3 fog shaders created**: `_fog_shader_color` (floors/caps), `_fog_shader_textured` (walls opaque), `_fog_shader_textured_alpha` (walls during occlusion fade, with `depth_draw_always`)
- **All StandardMaterial3D replaced with ShaderMaterial** in DungeonBuilder: floor tiles, wall faces, wall caps, trap floor, exit floor
- **Occludable updated for ShaderMaterial**: Detects material type, swaps shader between opaque/alpha variants, sets `alpha` uniform
- **Camera redesigned for smooth zoom**: Always `PROJECTION_PERSPECTIVE`. Level 1 = FOV 50° (perspective), Level 2 = FOV 5° + far distance (quasi-ortho). FOV and distance lerp independently to avoid nonlinear spikes.
- **Fixed zoom transition distance spike**: Distance now lerps directly (13.4 ↔ ~200) instead of being derived from the nonlinear `1/tan(fov/2)` during FOV interpolation.
- **Fog fixed at fog_start=6.0, fog_end=10.0**: No longer dynamically tied to camera frustum.
- **Debug zoom HUD overlay** (green text, top-right): shows zoom level, FOV, distance, fog_end
- **Widened BattleUI layout** for 3x fonts (party stats container 650px, menu panel 450px)
- **DialogueBox height increased** from 160px to 300px, offset_top=-320, offset_bottom=-20 to fix box appearing below screen edge
- **Investigated FOV 0° bug**: Confirmed minimum safe FOV is 5° (lower causes geometry to exceed camera far plane). Reverted fov_level_2 back to 5.0.
- **Pushed all changes to GitHub** (`https://github.com/diegoesp89/jrpg`, branch `main`)

### Known issues NOT fixed (acceptable for MVP):
- Combatant damage formula operator precedence (may be intentional)
- BattleUI._update_battle_sprites is a no-op (dead combatants don't visually change)
- MiniMapUI positioning with anchors may need runtime testing
- Minor sprite corner clipping at wall edges (very minor visual)
- OcclusionController `get_nodes_in_group("")` dead code path (fallback works)
- WallCap not recognized by Occludable (enclosed walls can't fade — rarely hit by raycast anyway)
- Spritesheet walk frame rects were estimated from pixel analysis — may need fine-tuning if frames appear offset at runtime

### What's left (next session):
1. **Run the project in Godot 4.6.1** and fix any remaining runtime errors
2. **Test full game flow**: Boot → Dungeon → move → interact with NPC → dialogue → combat triggers → battle → return → boss → exit → victory screen
3. **Fix any additional runtime bugs** that surface during testing
4. **Visual/layout polish** if needed (UI positioning, sprite sizes, dialogue box sizing for 3x fonts)
5. **Fine-tune fog start/end** if 6.0/10.0 doesn't feel right at runtime
6. **Spritesheet frame alignment** may need adjustment if walk frames are visually offset
7. **Remove debug zoom overlay** once zoom values are finalized
8. **Push final changes to GitHub**

## Relevant files / directories

```
/Users/despinozav/Downloads/jrpg/
├── agents.MD                          # Original spec (read-only reference)
├── agents2.MD                         # Implementation log (THIS FILE)
├── project.godot                      # EDITED: window/size/mode=3 (fullscreen)
├── .gitignore                         # Excludes .godot/, .DS_Store
├── assets/
│   └── sprites/
│       ├── spritesheet.png            # Player character spritesheet
│       └── spritesheet.png.import     # Godot import metadata
├── scenes/
│   ├── boot/Boot.tscn                 # Clean
│   ├── exploration/
│   │   ├── Dungeon.tscn              # Clean
│   │   ├── Player.tscn               # Clean
│   │   └── CameraRig.tscn           # Clean
│   └── combat/Battle.tscn            # Clean
├── scripts/
│   ├── core/
│   │   ├── Boot.gd                   # Clean
│   │   ├── GameState.gd              # EDITED: added reset() method for defeat restart
│   │   └── SceneFlow.gd             # Clean
│   ├── data/
│   │   └── DataLoader.gd            # Clean
│   ├── exploration/
│   │   ├── PlayerController.gd       # EDITED: spritesheet loading, BG transparency, 4-dir walk animation
│   │   ├── CameraFollow.gd          # EDITED: always PROJECTION_PERSPECTIVE, 2 zoom levels (FOV 50° / FOV 5°), FOV and distance lerp independently, _calc_distance() for final distance, _current_dist/_target_dist lerped directly, level_2_view_scale=1.4
│   │   ├── DungeonBuilder.gd        # EDITED: fog globals default fog_end=10.0, all materials use ShaderMaterial with spatial fog shaders
│   │   ├── DungeonManager.gd        # EDITED: fog fixed at fog_start=6.0/fog_end=10.0, debug label for zoom info
│   │   ├── Interactable.gd          # Clean
│   │   ├── Door.gd                  # Clean
│   │   ├── Pickup.gd               # Clean
│   │   ├── CombatTrigger.gd        # Clean
│   │   ├── NPCIntro.gd             # Clean
│   │   ├── Trap.gd                  # Clean
│   │   ├── MiniMapReveal.gd        # Clean
│   │   ├── Occludable.gd           # EDITED: supports ShaderMaterial, swaps opaque/alpha shaders
│   │   └── OcclusionController.gd  # Clean
│   ├── combat/
│   │   ├── BattleScene.gd          # EDITED: GameState.reset() on defeat
│   │   ├── BattleController.gd     # EDITED: enemy MP check with basic attack fallback
│   │   ├── TurnSystem.gd           # Clean
│   │   ├── Combatant.gd            # Clean
│   │   └── EnemyAI.gd             # Clean
│   └── ui/
│       ├── DialogueController.gd   # Clean
│       ├── DialogueBox.gd          # EDITED: height 300px, offset_top=-320, offset_bottom=-20
│       ├── MiniMapUI.gd            # Clean
│       └── BattleUI.gd            # EDITED: tripled ALL combat font sizes, widened panels, empty menu guards
├── data/
│   ├── characters/characters.json   # Clean
│   ├── enemies/enemies.json         # Clean
│   ├── skills/skills.json           # Clean
│   ├── items/items.json             # Clean
│   ├── encounters/encounters.json   # Clean
│   └── dialogues/dialogues.json     # Clean
```

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

1. **Sin assets externos** (salvo spritesheet del player): Todo visual es procedural (ImageTexture, PlaneMesh, ColorRect placeholders).
2. **Data en JSON**: Todos los datos editables estan en `data/`.
3. **Dungeon generado por codigo**: DungeonBuilder usa array 2D, no TileMap. Mas robusto para generacion sin editor.
4. **Occlusion via nodo hijo**: Cada muro tiene un nodo "Occludable" hijo. OcclusionController busca ese hijo en los colliders detectados por raycast.
5. **Transiciones con fade**: SceneFlow usa CanvasLayer layer 100 con ColorRect, tween alpha 0.3s.
6. **Combate con copia de party**: BattleController trabaja con copias, sync de vuelta a GameState al terminar.
7. **Dialogo con nodos JSON**: Estructura de nodos con next/choices, flags procesados inline.
8. **Fog via spatial shaders**: No Environment fog ni canvas_item post-process. El fog se computa en el fragment shader de cada material del dungeon usando `MODEL_MATRIX * VERTEX` para obtener la posicion mundo y distancia XZ al jugador.
9. **Camera siempre perspectiva**: Zoom out usa FOV bajo (5°) para aproximar ortho, evitando la necesidad de cambiar entre PROJECTION_PERSPECTIVE y PROJECTION_ORTHOGONAL.
10. **FOV y distancia se interpolan independientemente**: Evita el spike no-lineal de `1/tan(fov/2)` durante transiciones de zoom.

---

## Camera zoom level reference

| Level | FOV | Distance | Look |
|-------|-----|----------|------|
| 1 (default) | 50° | ~18.8 | Perspective, close |
| 2 (zoom out) | 5° | ~200 | Quasi-ortho, wide |

**Minimum safe FOV: 5°** (lower values push camera beyond `far=1000` plane)

| FOV | Distance | Status |
|-----|----------|--------|
| 50° | 18.8 | OK (level 1) |
| 10° | 100 | OK |
| 5° | 200 | OK — minimum safe |
| 3° | 334 | Borderline |
| 2° | 501 | Risky — depth precision loss |
| 1° | 1002 | Exceeds far plane — geometry clips |

---

## Stack tecnico final

- Godot 4.6.1, GDScript
- 3 autoloads: DataLoader → GameState → SceneFlow
- 5 escenas .tscn: Boot, Dungeon, Player, CameraRig, Battle (el resto es por codigo)
- 6 archivos JSON de data
- 22+ scripts GDScript
- 1 asset externo (spritesheet.png), resto procedural
- Resolucion: 1920x1080, stretch canvas_items, fullscreen
- Physics layers: world(1), player(2), interactable(3), trigger(4), occluder(5)
- Input: WASD/flechas + Z(action1) + X(action2) + Q(zoom_in) + E(zoom_out)
