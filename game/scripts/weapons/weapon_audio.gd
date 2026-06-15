class_name WeaponAudio
extends AudioStreamPlayer3D
## Positional gunshot audio: one CC0 shot sample per weapon class, played at the
## muzzle on every shot with a touch of per-shot pitch jitter so repeated fire
## doesn't sound rubber-stamped. Code-spawned by WeaponController (mirrors how
## Hitstop is spawned) and left on the default Master bus so the settings volume
## slider governs it. Samples are CC0 (see assets/audio/CREDITS.md).

## Weapon sound_key -> shot sample. Keys match WeaponStats.sound_key.
const STREAMS: Dictionary = {
	"pistol": "res://assets/audio/weapons/pistol.wav",
	"smg": "res://assets/audio/weapons/smg.wav",
	"rifle": "res://assets/audio/weapons/rifle.wav",
	"shotgun": "res://assets/audio/weapons/shotgun.wav",
}
## Used when a weapon's sound_key has no sample, so a new gun never fires silent.
const FALLBACK_KEY: String = "pistol"
## Per-shot pitch spread (±), keeping a volley lively without sounding detuned.
const PITCH_JITTER: float = 0.06

var _loaded: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# Carry well across a street without ear-splitting at point blank, and leave a
	# little headroom under the Master bus for the rest of the mix.
	unit_size = 8.0
	max_db = 3.0
	volume_db = -2.0
	for key: String in STREAMS:
		var path: String = STREAMS[key]
		if ResourceLoader.exists(path):
			_loaded[key] = load(path)


## Play the shot for `weapon_key` positioned at `muzzle_pos`. Unknown keys fall
## back to FALLBACK_KEY; a no-op (never a crash) if no sample resolved at all.
func fire(weapon_key: String, muzzle_pos: Vector3) -> void:
	var shot := _stream_for(weapon_key)
	if shot == null:
		return
	global_position = muzzle_pos
	stream = shot
	pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	play()


func _stream_for(weapon_key: String) -> AudioStream:
	if _loaded.has(weapon_key):
		return _loaded[weapon_key]
	return _loaded.get(FALLBACK_KEY, null)
