extends RefCounted
class_name Achievements
## Achievements — single entry point for unlocking an achievement. Nothing else in the codebase
## should call SaveManager.unlock_achievement() directly, so the toast can never get out of sync
## with what's actually persisted.

## Preloaded by path rather than through its class_name — see the note in DungeonBuilder.gd.
const ToastScript = preload("res://scripts/ui/AchievementToast.gd")

## Idempotent: a no-op (no write, no toast) if `id` was already unlocked, so every call site can
## just call this whenever its condition is true without tracking "have I already told the player."
## Fire-and-forget from combat (don't await — an achievement must never hold up a turn); `await` it
## at a run-completion checkpoint instead, so several unlocks queue one after another on screen.
static func unlock(parent: Node, id: String) -> void:
	if not SaveManager.unlock_achievement(id):
		return
	await ToastScript.show_at(parent, id)
