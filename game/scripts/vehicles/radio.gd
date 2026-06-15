class_name Radio
extends Node
## In-vehicle radio: pre-bakes one looping AudioStream per station track from
## RadioModel (placeholder synth, no music binaries) and plays the tuned one,
## cycling to the next track on a station once the current one has played out.
## The car turns it on while a driver is aboard and off on exit; tune()/next()
## switch stations and seek_track() skips within one (wire to radio input actions
## when they exist). Replace the per-track stream with a CC-licensed track when
## assets land.

const SAMPLE_RATE: int = 22050

var _station: int = 0
var _track: int = 0
## Seconds the current track has been playing; cycles tracks at track_play_seconds.
var _track_elapsed: float = 0.0
var _on: bool = false
## _streams[station] is an Array[AudioStreamWAV], one baked loop per track.
var _streams: Array = []

@onready var _player: AudioStreamPlayer = _make_player()


func _ready() -> void:
	for s in RadioModel.station_count():
		var tracks: Array[AudioStreamWAV] = []
		for t in RadioModel.track_count(s):
			tracks.append(_bake(s, t))
		_streams.append(tracks)


## Start playing the current station (called when a driver enters).
func turn_on() -> void:
	if _streams.is_empty():
		return
	_on = true
	_track_elapsed = 0.0
	_play_current()


## Stop playback (driver exits).
func turn_off() -> void:
	_on = false
	_player.stop()


## Tune by a step (+1 next, -1 previous) with wrap, restarting at the station's
## first track, and keep playing if on.
func tune(step: int) -> void:
	_station = RadioModel.tune(_station, step)
	_track = 0
	_track_elapsed = 0.0
	if _on:
		_play_current()


## Skip by a step within the tuned station's playlist (wraps), and keep playing.
func seek_track(step: int) -> void:
	_track = RadioModel.cycle_track(_station, _track, step)
	_track_elapsed = 0.0
	if _on:
		_play_current()


## Name of the tuned station, for HUD/notifications.
func station_name() -> String:
	return RadioModel.station_name(_station)


## Title of the playing track, for HUD/notifications.
func track_title() -> String:
	return RadioModel.track_title(_station, _track)


func _process(delta: float) -> void:
	if not _on:
		return
	_track_elapsed += delta
	if _track_elapsed >= RadioModel.track_play_seconds(_station, _track):
		_track = RadioModel.cycle_track(_station, _track, 1)
		_track_elapsed = 0.0
		_play_current()


func _play_current() -> void:
	var tracks: Array = _streams[_station]
	if tracks.is_empty():
		return
	_player.stream = tracks[_track]
	_player.play()


func _bake(station_index: int, track_index: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var frames := RadioModel.loop_frames(SAMPLE_RATE, station_index, track_index)
	wav.data = RadioModel.frames_to_wav16(frames)
	wav.loop_end = frames.size()
	return wav


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player
