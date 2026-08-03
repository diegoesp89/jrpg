extends RefCounted
## BattleTheme — the battle screen's palette and panel frames in one place.
##
## Every panel on the battle screen used to build its own StyleBoxFlat inline, which is how they
## drifted into four different borders and three different backgrounds. The look is defined here
## once and asked for by name, so "make the frames match" is a change in this file rather than a
## hunt through _build_ui.
##
## Loaded with preload() rather than class_name on purpose: a freshly added class_name is not in
## the editor's cache until it reindexes, and a stale cache turns into "Identifier not declared"
## at startup. A path never goes stale.

# --- Palette -------------------------------------------------------------------------------

## The metal the frames are made of. Bright edge, dark seat, so a border reads as bevelled.
const GOLD := Color(0.83, 0.68, 0.36)
const GOLD_DIM := Color(0.42, 0.34, 0.18)
const GOLD_TEXT := Color(1.0, 0.87, 0.45)

## Panel interiors: near-black with a blue cast, so the warm frames read as lit from outside.
const PANEL_BG := Color(0.045, 0.05, 0.09, 0.96)
const PANEL_BG_SOFT := Color(0.07, 0.075, 0.13, 0.92)

## The battle log is a scribe's page, not another dark slab — it is the one thing on screen that
## is read as prose rather than glanced at, and dark-on-light is easier for that.
const PARCHMENT := Color(0.88, 0.82, 0.68)
const PARCHMENT_EDGE := Color(0.62, 0.52, 0.34)
const INK := Color(0.16, 0.12, 0.08)

## Bars. Green while healthy, amber under half, red under a quarter — the colour is the warning.
const HP_FULL := Color(0.36, 0.76, 0.35)
const HP_HURT := Color(0.90, 0.70, 0.20)
const HP_CRIT := Color(0.85, 0.22, 0.18)
const MP_COLOR := Color(0.33, 0.55, 0.92)
const BAR_TRACK := Color(0.10, 0.10, 0.14, 0.9)

## Zone bands. The two facing front ranks run warm so that pair reads as one shared melee space.
const ZONE_FRONT_FILL := Color(0.38, 0.22, 0.13, 0.34)
const ZONE_FRONT_EDGE := Color(0.78, 0.50, 0.28, 0.55)
const ZONE_BACK_FILL := Color(0.12, 0.14, 0.22, 0.34)
const ZONE_BACK_EDGE := Color(0.38, 0.42, 0.55, 0.40)

const TEXT := Color(0.95, 0.95, 0.97)
const TEXT_DIM := Color(0.60, 0.60, 0.68)
const TEXT_DEAD := Color(0.42, 0.42, 0.46)

# --- Frames --------------------------------------------------------------------------------

## The standard framed panel: dark seat, bronze edge, rounded corners, room to breathe inside.
static func panel(margin: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = GOLD_DIM
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	return s

## Same frame, brighter edge — for the panel the player is currently acting in.
static func panel_active(margin: int = 14) -> StyleBoxFlat:
	var s := panel(margin)
	s.border_color = GOLD
	return s

static func parchment(margin: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PARCHMENT
	s.border_color = PARCHMENT_EDGE
	s.set_border_width_all(3)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	return s

## The highlight behind the selected menu row.
static func menu_selection() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.24, 0.20, 0.10, 0.9)
	s.border_color = GOLD
	s.border_width_left = 4
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s

## An invisible box with the SAME metrics as menu_selection(), used on unselected rows so that
## selecting one doesn't shift every row sideways as the margins appear and disappear.
static func menu_idle() -> StyleBoxFlat:
	var s := menu_selection()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_width_left = 4
	s.border_color = Color(0, 0, 0, 0)
	return s

## Colour for an HP bar at the given fill fraction.
static func hp_color(fraction: float) -> Color:
	if fraction <= 0.25:
		return HP_CRIT
	if fraction <= 0.5:
		return HP_HURT
	return HP_FULL
