class_name FootstepAudio
extends Node3D
## Plays CC0 footstep samples in response to Player's `footstep(surface, is_left)`
## signal. Holds a small bank of step variations per surface and, on each step,
## plays a random non-repeating one with a little pitch jitter (plus a left/right
## bias) so a walk never sounds rubber-stamped. Unknown surfaces fall back to
## concrete; a surface with no bank is silently skipped (never crashes). Cadence
## and surface classification live in Footsteps; this node only voices the events.
## Samples are CC0 (see assets/audio/CREDITS.md).

## Surface key -> folder of `<name>_1..N.ogg` step variations. Sand doubles for
## grass (the source pack notes "Sand sounds like grass too"); any surface without
## its own bank (metal/wood/water/...) falls back to concrete.
const SURFACE_DIRS: Dictionary = {
	"concrete": "res://assets/audio/footsteps/concrete",
	"grass": "res://assets/audio/footsteps/sand",
	"sand": "res://assets/audio/footsteps/sand",
}
## Used when a surface key has no bank (matches Footsteps.DEFAULT_SURFACE).
const FALLBACK_SURFACE: String = "concrete"
## Variation files probed per folder (`<name>_1.ogg` .. `<name>_N.ogg`).
const VARIATIONS: int = 6
## Per-step pitch spread (±) layered on top of the left/right bias.
const PITCH_JITTER: float = 0.08

var _banks: Dictionary = {}
var _last_index: int = -1
var _rng := RandomNumberGenerator.new()

@onready var _player: AudioStreamPlayer3D = _make_player()


func _ready() -> void:
	_rng.randomize()
	for surface: String in SURFACE_DIRS:
		var bank := _load_bank(SURFACE_DIRS[surface])
		if not bank.is_empty():
			_banks[surface] = bank


## Connect to Player.footstep. Picks the surface's bank (falling back to concrete),
## plays a random non-repeating variation, nudges pitch by foot plus a little
## random so consecutive steps differ.
func on_footstep(surface: String, is_left: bool) -> void:
	var bank := _bank_for(surface)
	if bank.is_empty():
		return
	_player.stream = _pick(bank)
	var foot_bias := 1.03 if is_left else 0.98
	_player.pitch_scale = foot_bias + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	_player.play()


func _bank_for(surface: String) -> Array:
	if _banks.has(surface):
		return _banks[surface]
	return _banks.get(FALLBACK_SURFACE, [])


## Random variation, avoiding an immediate repeat so two steps in a row differ.
func _pick(bank: Array) -> AudioStream:
	if bank.size() <= 1:
		return bank[0]
	var idx := _rng.randi_range(0, bank.size() - 1)
	if idx == _last_index:
		idx = (idx + 1) % bank.size()
	_last_index = idx
	return bank[idx]


## Load every `<name>_i.ogg` that exists under `dir_path` (resilient to gaps), so a
## missing or renamed file just shrinks the bank instead of crashing.
func _load_bank(dir_path: String) -> Array:
	var bank: Array = []
	var prefix := dir_path.get_file()
	for i in range(1, VARIATIONS + 1):
		var path := "%s/%s_%d.ogg" % [dir_path, prefix, i]
		if ResourceLoader.exists(path):
			bank.append(load(path))
	return bank


func _make_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	# Subtle and local: footsteps should sit under the mix and fade quickly with
	# distance rather than carry across the street.
	player.unit_size = 4.0
	player.volume_db = -6.0
	add_child(player)
	return player
