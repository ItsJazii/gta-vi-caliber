class_name RadioModel
extends RefCounted
## Pure vehicle-radio logic + placeholder station synthesis (M5 "Radio").
## Station tuning (wrap-around), per-station track cycling, and a short, seamless
## arpeggio loop per track are all deterministic and scene-free, so they unit-test
## headless; Radio (the node) just bakes and plays them. Audio is synthesized at
## runtime — no music binaries — and stands in for the CC-licensed tracks the
## roadmap calls for: swap loop_frames for a streamed AudioStream per track when
## real audio lands. (The richer station/now-playing metadata model lives
## separately in systems/vehicle_radio_model.gd; this one owns the audible synth.)

## Equal-tempered semitone ratio (2^(1/12)).
const SEMITONE: float = 1.059463094359

## Fraction of each note's step spent fading back to silence. A short release so
## every note — and the loop seam — lands at ~0 amplitude and never clicks.
const RELEASE_FRACTION: float = 0.15

## Stations, each: a display name, a root frequency (Hz), and a small playlist of
## `tracks`. A track is one arpeggio: its `title`, the semitone `notes` cycled
## through, `step` seconds per note, a `timbre` ("warm"/"bright"/"sub"), and how
## many times its loop `repeats` before the radio cycles to the next track. All
## station/track names are original/fictional.
const STATIONS: Array = [
	{
		"name": "Sundown FM",
		"root": 220.0,
		"tracks":
		[
			{
				"title": "Coastline Cruise",
				"notes": [0, 4, 7, 11, 7, 4],
				"step": 0.30,
				"timbre": "warm",
				"repeats": 8,
			},
			{
				"title": "Palm Mirage",
				"notes": [0, 3, 7, 10, 12, 10],
				"step": 0.26,
				"timbre": "warm",
				"repeats": 8,
			},
		],
	},
	{
		"name": "Vice Drive",
		"root": 277.18,
		"tracks":
		[
			{
				"title": "Neon Pulse",
				"notes": [0, 3, 7, 10],
				"step": 0.22,
				"timbre": "bright",
				"repeats": 10,
			},
			{
				"title": "Chrome Rush",
				"notes": [0, 5, 7, 12, 7, 5],
				"step": 0.18,
				"timbre": "bright",
				"repeats": 10,
			},
		],
	},
	{
		"name": "Low End",
		"root": 110.0,
		"tracks":
		[
			{
				"title": "Subwoofer Sermon",
				"notes": [0, 7, 5, 7],
				"step": 0.40,
				"timbre": "sub",
				"repeats": 6,
			},
			{
				"title": "Trunk Rattle",
				"notes": [0, 0, 5, 3],
				"step": 0.33,
				"timbre": "sub",
				"repeats": 6,
			},
		],
	},
	{
		"name": "Gridlock Talk",
		"root": 165.0,
		"tracks":
		[
			{
				"title": "Drive-Time Banter",
				"notes": [0, 2, 4, 5, 4, 2],
				"step": 0.50,
				"timbre": "warm",
				"repeats": 4,
			},
		],
	},
]


## Number of tunable stations.
static func station_count() -> int:
	return STATIONS.size()


## Number of tracks on a station (clamped to a valid station).
static func track_count(station_index: int) -> int:
	if STATIONS.is_empty():
		return 0
	return _station(station_index)["tracks"].size()


## Tune by `step` stations (e.g. +1 next, -1 previous) with wrap-around, so the
## dial never lands out of range. Safe for any current/step.
static func tune(current: int, step: int) -> int:
	var n := STATIONS.size()
	if n <= 0:
		return 0
	return posmod(current + step, n)


## Cycle by `step` tracks within a station with wrap-around. Safe for any input.
static func cycle_track(station_index: int, current_track: int, step: int = 1) -> int:
	var n := track_count(station_index)
	if n <= 0:
		return 0
	return posmod(current_track + step, n)


## Display name of a station (clamped).
static func station_name(station_index: int) -> String:
	if STATIONS.is_empty():
		return ""
	return String(_station(station_index)["name"])


## Title of a track on a station (clamped). Empty if the station has no tracks.
static func track_title(station_index: int, track_index: int) -> String:
	var track := _track(station_index, track_index)
	if track.is_empty():
		return ""
	return String(track["title"])


## Frequency (Hz) of a semitone offset above a root.
static func note_hz(root: float, semitone: int) -> float:
	return root * pow(SEMITONE, float(semitone))


## Seconds of one pass through a track's arpeggio (notes x step).
static func loop_seconds(station_index: int, track_index: int) -> float:
	var track := _track(station_index, track_index)
	if track.is_empty():
		return 0.0
	return float((track["notes"] as Array).size()) * float(track["step"])


## How long the radio holds a track before cycling on — its loop length times the
## track's `repeats`. Drives Radio's track-cycling timer.
static func track_play_seconds(station_index: int, track_index: int) -> float:
	var track := _track(station_index, track_index)
	if track.is_empty():
		return 0.0
	return loop_seconds(station_index, track_index) * float(track["repeats"])


## Synthesize one track's seamless arpeggio loop: each note fills one `step` with
## a plucked tone (attack-decay-release envelope so notes and the loop seam land
## at silence and never click), coloured by the station/track `timbre`, then the
## whole loop is normalized to +/-0.9. Deterministic — same station/track always
## yields the same loop. Out-of-range indices clamp to a valid station/track.
static func loop_frames(
	sample_rate: int, station_index: int, track_index: int = 0
) -> PackedFloat32Array:
	var rate := maxi(sample_rate, 1000)
	var track := _track(station_index, track_index)
	var frames := PackedFloat32Array()
	if track.is_empty():
		return frames
	var notes: Array = track["notes"]
	var step_frames := maxi(int(float(rate) * float(track["step"])), 1)
	var release_frames := clampi(int(float(step_frames) * RELEASE_FRACTION), 1, step_frames)
	var timbre := String(track["timbre"])
	var root := float(_station(station_index)["root"])
	frames.resize(step_frames * notes.size())
	var peak := 0.0
	for n in notes.size():
		var freq := note_hz(root, int(notes[n]))
		for i in step_frames:
			var t := float(i) / float(rate)
			var env: float = exp(-4.0 * t) * (1.0 - exp(-200.0 * t))
			# Linear fade over the final release_frames so the note ends at ~0.
			var tail := i - (step_frames - release_frames)
			if tail > 0:
				env *= 1.0 - float(tail) / float(release_frames)
			var sample := _timbre_sample(timbre, freq, t)
			sample *= env
			var idx := n * step_frames + i
			frames[idx] = sample
			peak = maxf(peak, absf(sample))
	if peak > 0.0:
		for i in frames.size():
			frames[i] = frames[i] / peak * 0.9
	return frames


## Pack float frames into 16-bit little-endian PCM for AudioStreamWAV.
static func frames_to_wav16(frames: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		bytes.encode_s16(i * 2, int(clampf(frames[i], -1.0, 1.0) * 32767.0))
	return bytes


# --- internals ---------------------------------------------------------------


## One unenveloped sample for a timbre: the fundamental plus timbre-specific
## colour. "warm" mellow, "bright" extra upper harmonics, "sub" an octave below.
static func _timbre_sample(timbre: String, freq: float, t: float) -> float:
	var sample := sin(TAU * freq * t)
	match timbre:
		"bright":
			sample += 0.4 * sin(TAU * freq * 2.0 * t) + 0.2 * sin(TAU * freq * 3.0 * t)
		"sub":
			sample += 0.5 * sin(TAU * freq * 0.5 * t)
		_:  # "warm" and any unknown timbre.
			sample += 0.25 * sin(TAU * freq * 2.0 * t)
	return sample


static func _station(station_index: int) -> Dictionary:
	return STATIONS[clampi(station_index, 0, STATIONS.size() - 1)]


static func _track(station_index: int, track_index: int) -> Dictionary:
	if STATIONS.is_empty():
		return {}
	var tracks: Array = _station(station_index)["tracks"]
	if tracks.is_empty():
		return {}
	return tracks[clampi(track_index, 0, tracks.size() - 1)]
