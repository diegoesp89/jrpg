extends Node
## AudioManager — Autoload singleton. Owns the "Music"/"SFX" audio buses (created here in code —
## not in the project's audio bus layout resource, matching this project's code-first UI/asset
## conventions) and plays background music + one-shot SFX by id.
##
## MUSIC_TRACKS/SFX_SOUNDS point at plain WAV files under res://assets/audio — synthesized
## placeholders for now (see the generation script used to make them). Swapping in real audio
## later is just replacing the files at these same paths; no code changes needed.

const MUSIC_TRACKS := {
	"menu": "res://assets/audio/music/menu.wav",
	"exploration": "res://assets/audio/music/exploration.wav",
	"battle": "res://assets/audio/music/battle.wav",
}

const SFX_SOUNDS := {
	"attack_hit": "res://assets/audio/sfx/attack_hit.wav",
	"heal": "res://assets/audio/sfx/heal.wav",
	"victory": "res://assets/audio/sfx/victory.wav",
	"defeat": "res://assets/audio/sfx/defeat.wav",
	"level_up": "res://assets/audio/sfx/level_up.wav",
	"door_open": "res://assets/audio/sfx/door_open.wav",
	"door_locked": "res://assets/audio/sfx/door_locked.wav",
	"chest_open": "res://assets/audio/sfx/chest_open.wav",
	"trap_success": "res://assets/audio/sfx/trap_success.wav",
	"trap_fail": "res://assets/audio/sfx/trap_fail.wav",
	"riddle_correct": "res://assets/audio/sfx/riddle_correct.wav",
	"riddle_wrong": "res://assets/audio/sfx/riddle_wrong.wav",
}

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var _music_player: AudioStreamPlayer = null
var _current_music_id: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)

	_apply_volume(SettingsManager.volume)
	if not SettingsManager.volume_changed.is_connected(_apply_volume):
		SettingsManager.volume_changed.connect(_apply_volume)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _apply_volume(value: float) -> void:
	var db = linear_to_db(clampf(value, 0.0, 1.0))
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		var idx = AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, db)

## Switches background music to `track_id` (see MUSIC_TRACKS). No-ops if that track is already
## playing, so navigating between screens that share a track (e.g. two menu screens) doesn't
## restart the loop.
func play_music(track_id: String) -> void:
	if track_id == _current_music_id and _music_player.playing:
		return
	var path = MUSIC_TRACKS.get(track_id, "")
	if path == "":
		return
	var stream = load(path)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()
	_current_music_id = track_id

func stop_music() -> void:
	_music_player.stop()
	_current_music_id = ""

## Plays a one-shot SFX by id (see SFX_SOUNDS). Spawns its own throwaway AudioStreamPlayer so
## overlapping SFX don't cut each other off — no pool to manage, each frees itself once done.
func play_sfx(sfx_id: String) -> void:
	var path = SFX_SOUNDS.get(sfx_id, "")
	if path == "":
		return
	var player = AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.stream = load(path)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
