class_name EnemySprites
extends RefCounted
## EnemySprites — Battle sprite loading for enemies. Unlike CharacterSprites (which crops
## regions out of one shared spritesheet with a magenta background to key out), each enemy
## already has its own standalone PNG with real alpha transparency (see
## assets/sprites/enemies/CREDITS.txt for the current placeholder set and swap-out notes) —
## so this is just a cached direct load.

static var _texture_cache: Dictionary = {}

## `enemy` is a battle_enemy dict (see BattleController._setup_enemies) or a raw enemies.json
## entry — both carry "sprite_path".
static func get_texture(enemy: Dictionary) -> Texture2D:
	var path = str(enemy.get("sprite_path", ""))
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex = load(path) as Texture2D
	if not tex:
		push_warning("EnemySprites: sprite not found at %s" % path)
		return null
	_texture_cache[path] = tex
	return tex
