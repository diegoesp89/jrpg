class_name CharacterSprites
extends RefCounted
## CharacterSprites — Battle/portrait sprite loading for playable characters. Each character
## has its own standalone image (see assets/sprites/characters/CREDITS.txt for the current
## placeholder set and swap-out notes) with real alpha transparency — same cached-direct-load
## model as EnemySprites.gd, no atlas region cropping needed.

## Fallback for a character missing "sprite_path" in characters.json (shouldn't happen in
## practice — every character has one — but keeps get_texture() from erroring if it ever does).
const DEFAULT_SHEET_PATH := "res://assets/sprites/spritesheet.png"

static var _texture_cache: Dictionary = {}

static func get_texture(sprite_path: String = DEFAULT_SHEET_PATH) -> Texture2D:
	if _texture_cache.has(sprite_path):
		return _texture_cache[sprite_path]
	var tex = load(sprite_path) as Texture2D
	if not tex:
		push_warning("CharacterSprites: sprite not found at %s" % sprite_path)
		return null
	_texture_cache[sprite_path] = tex
	return tex

static func _sprite_path_for(char_data: Dictionary) -> String:
	return char_data.get("sprite_path", DEFAULT_SHEET_PATH)

## Face portrait for dialogue boxes / cards.
static func get_portrait_texture(char_data: Dictionary) -> Texture2D:
	return get_texture(_sprite_path_for(char_data))

## Battle-scene side pose for BattleUI party sprites.
static func get_battle_texture(char_data: Dictionary) -> Texture2D:
	return get_texture(_sprite_path_for(char_data))
