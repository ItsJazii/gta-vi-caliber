class_name HelicopterAudio
extends Node3D
## Runtime-synthesized rotor + siren audio for the police helicopter. Attach as
## a child of PoliceHelicopter; it owns two looping AudioStreamPlayer3Ds built
## in _ready from HelicopterAudioModel (no audio files in the repo, matching
## VehicleAudio). Volumes ease toward their targets so engage/disengage reads
## as the chopper spooling, not a hard mute.

const SAMPLE_RATE: int = 22050
## dB per second the volumes ease at.
const FADE_DB_PER_SEC: float = 30.0

## Blade-pass rate the loop is synthesized for (520 rpm × 2 blades).
@export var pulse_hz: float = HelicopterAudioModel.DEFAULT_PULSE_HZ
## Audible-range scale: the chopper should carry over city noise.
@export var unit_size: float = 26.0

var _rotor: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _rotor_target_db: float = VehicleAudioModel.SILENT_DB
var _siren_target_db: float = VehicleAudioModel.SILENT_DB


func _ready() -> void:
	_rotor = _make_player(HelicopterAudioModel.rotor_loop_frames(SAMPLE_RATE, pulse_hz))
	_siren = _make_player(HelicopterAudioModel.siren_loop_frames(SAMPLE_RATE))
	_rotor.play()
	_siren.play()


func _process(delta: float) -> void:
	_rotor.volume_db = move_toward(_rotor.volume_db, _rotor_target_db, FADE_DB_PER_SEC * delta)
	_siren.volume_db = move_toward(_siren.volume_db, _siren_target_db, FADE_DB_PER_SEC * delta)


## Rotor thump while the chopper is deployed.
func set_running(on: bool) -> void:
	_rotor_target_db = 0.0 if on else VehicleAudioModel.SILENT_DB


## Pursuit wail layered on top at high heat.
func set_siren(on: bool) -> void:
	_siren_target_db = -6.0 if on else VehicleAudioModel.SILENT_DB


func _make_player(frames: PackedFloat32Array) -> AudioStreamPlayer3D:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = VehicleAudioModel.frames_to_wav16(frames)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = frames.size()
	var player := AudioStreamPlayer3D.new()
	player.stream = wav
	player.unit_size = unit_size
	player.volume_db = VehicleAudioModel.SILENT_DB
	add_child(player)
	return player
