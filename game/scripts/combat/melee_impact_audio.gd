class_name MeleeImpactAudio
extends Node
## Plays runtime-synthesized melee impact sounds on a connecting strike. Pre-bakes
## one AudioStreamWAV per strike variant (plus a kill voicing) in _ready from
## MeleeImpactAudioModel (no audio binaries) and plays the matching one-shot,
## nudging pitch slightly so a flurry doesn't sound mechanical. Pure synthesis
## lives in MeleeImpactAudioModel; this node only bakes and plays. Code-spawned and
## self-contained: a controller does add_child(MeleeImpactAudio.new()) and calls
## play() on a confirmed hit. Non-positional (it's the player's own punch).

const SAMPLE_RATE: int = 22050

var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()

@onready var _player: AudioStreamPlayer = _make_player()


func _ready() -> void:
	_rng.randomize()
	for strike in [
		MeleeCombat.Strike.JAB,
		MeleeCombat.Strike.CROSS,
		MeleeCombat.Strike.KICK,
		MeleeCombat.Strike.HEAVY,
	]:
		_streams[_key(strike, false)] = _bake(strike, false)
	# One kill voicing, meatier than any strike's wound sound.
	_streams[_key(MeleeCombat.Strike.HEAVY, true)] = _bake(MeleeCombat.Strike.HEAVY, true)


## Play the impact for a landed strike: a kill uses the single kill voicing
## regardless of which blow landed it; an unbaked strike falls back to the jab.
## Slight per-hit pitch variance keeps a flurry from sounding mechanical.
func play(strike: int, killed: bool) -> void:
	var key := _key(MeleeCombat.Strike.HEAVY, true) if killed else _key(strike, false)
	if not _streams.has(key):
		key = _key(MeleeCombat.Strike.JAB, false)
	if not _streams.has(key):
		return
	_player.stream = _streams[key]
	_player.pitch_scale = _rng.randf_range(0.94, 1.06)
	_player.play()


func _bake(strike: int, killed: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	# Stable per-variant seed so the timbre is consistent run to run.
	var variant_seed := hash(_key(strike, killed)) & 0x7fffffff
	var frames := MeleeImpactAudioModel.impact_frames(SAMPLE_RATE, strike, killed, variant_seed)
	wav.data = MeleeImpactAudioModel.frames_to_wav16(frames)
	return wav


func _key(strike: int, killed: bool) -> String:
	return "kill" if killed else "strike_%d" % strike


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player
