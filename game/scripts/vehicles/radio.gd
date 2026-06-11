class_name Radio
extends Node
## In-vehicle radio: pre-bakes one looping AudioStream per station from
## RadioModel (placeholder synth, no music binaries) and plays the tuned one.
## The car turns it on while a driver is aboard and off on exit; tune()/next()
## switch stations (wire to a radio input action when one exists). Replace the
## per-station stream with a CC-licensed track when assets land.

const SAMPLE_RATE: int = 22050

var _station: int = 0
var _streams: Array[AudioStreamWAV] = []

@onready var _player: AudioStreamPlayer = _make_player()


func _ready() -> void:
	for i in RadioModel.station_count():
		_streams.append(_bake(i))


## Start playing the current station (called when a driver enters).
func turn_on() -> void:
	if _streams.is_empty():
		return
	_player.stream = _streams[_station]
	_player.play()


## Stop playback (driver exits).
func turn_off() -> void:
	_player.stop()


## Tune by a step (+1 next, -1 previous) with wrap, and keep playing if on.
func tune(step: int) -> void:
	_station = RadioModel.tune(_station, step)
	if _player.playing:
		_player.stream = _streams[_station]
		_player.play()


## Name of the tuned station, for HUD/notifications.
func station_name() -> String:
	return RadioModel.STATIONS[_station]["name"]


func _bake(index: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var frames := RadioModel.loop_frames(SAMPLE_RATE, index)
	wav.data = RadioModel.frames_to_wav16(frames)
	wav.loop_end = frames.size()
	return wav


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player
