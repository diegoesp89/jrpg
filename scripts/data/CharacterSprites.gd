class_name CharacterSprites
extends RefCounted
## CharacterSprites — Shared spritesheet loading/regions for playable characters.
## Temporary: all 7 characters currently share one placeholder sheet (Locke, FF6-style
## walk-cycle sheet) until each gets its own art. Any character can already point to a
## different sheet via characters.json's "sprite_path" field.

const DEFAULT_SHEET_PATH := "res://assets/sprites/spritesheet.png"
const BG_COLOR := Color(255.0 / 255.0, 5.0 / 255.0, 238.0 / 255.0)
const BG_TOLERANCE := 0.08

## Face portrait (band 1 of the sheet). Pixel-analyzed bounding box of the icon.
const PORTRAIT_REGION := Rect2(32, 24, 38, 40)
## Side-view battle pose (band 2, facing-right idle frame — matches PlayerController's
## Dir.RIGHT center frame, and the classic FF party-faces-right convention).
const BATTLE_REGION := Rect2(186, 84, 26, 30)

static var _texture_cache: Dictionary = {}

## Loads sheet_path, replaces its magenta background with transparency, and caches the
## result (several characters currently share the same file — no need to reprocess it).
static func get_texture(sheet_path: String = DEFAULT_SHEET_PATH) -> Texture2D:
	if _texture_cache.has(sheet_path):
		return _texture_cache[sheet_path]

	var tex = load(sheet_path) as Texture2D
	if not tex:
		push_warning("CharacterSprites: sheet not found at %s" % sheet_path)
		return null
	var img = tex.get_image()
	if not img:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p = img.get_pixel(x, y)
			if absf(p.r - BG_COLOR.r) < BG_TOLERANCE and absf(p.g - BG_COLOR.g) < BG_TOLERANCE and absf(p.b - BG_COLOR.b) < BG_TOLERANCE:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	var result: Texture2D = ImageTexture.create_from_image(img)
	_texture_cache[sheet_path] = result
	return result

static func _sheet_path_for(char_data: Dictionary) -> String:
	return char_data.get("sprite_path", DEFAULT_SHEET_PATH)

## Face portrait for dialogue boxes / cards.
static func get_portrait_texture(char_data: Dictionary) -> AtlasTexture:
	var base = get_texture(_sheet_path_for(char_data))
	if not base:
		return null
	var atlas = AtlasTexture.new()
	atlas.atlas = base
	atlas.region = PORTRAIT_REGION
	return atlas

## Side-view battle pose for BattleUI party sprites.
static func get_battle_texture(char_data: Dictionary) -> AtlasTexture:
	var base = get_texture(_sheet_path_for(char_data))
	if not base:
		return null
	var atlas = AtlasTexture.new()
	atlas.atlas = base
	atlas.region = BATTLE_REGION
	return atlas
