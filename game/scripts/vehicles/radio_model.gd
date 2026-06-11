class_name RadioModel
extends RefCounted
## Pure vehicle-radio logic + placeholder station synthesis (M5 "Radio").
## Station tuning (wrap-around) and a short, seamless arpeggio loop per station
## are deterministic and scene-free, so they unit-test headless; Radio (the node)
## just plays them. Audio is synthesized at runtime — no music binaries — and is
## a stand-in for the CC-licensed tracks the roadmap calls for: swap
## loop_frames for a streamed AudioStream per station when tracks land.

## Equal-tempered semitone ratio (2^(1/12)).
const SEMITONE: float = 1.059463094359

## Stations: a name, root frequency (Hz), seconds per arpeggio step, the semitone
## offsets cycled through, and whether the timbre is "bright" (extra harmonic).
const STATIONS: Array = [
	{
		"name": "Sundown FM",
		"root": 220.0,
		"step": 0.30,
		"notes": [0, 4, 7, 11, 7, 4],
		"bright": false,
	},
	{
		"name": "Vice Drive",
		"root": 277.18,
		"step": 0.22,
		"notes": [0, 3, 7, 10],
		"bright": true,
	},
	{
		"name": "Low End",
		"root": 110.0,
		"step": 0.40,
		"notes": [0, 7, 5, 7],
		"bright": false,
	},
]


## Number of tunable stations.
static func station_count() -> int:
	return STATIONS.size()


## Tune by `step` stations (e.g. +1 next, -1 previous) with wrap-around, so the
## dial never lands out of range. Safe for any current/step.
static func tune(current: int, step: int) -> int:
	var n := STATIONS.size()
	if n <= 0:
		return 0
	return posmod(current + step, n)


## Frequency (Hz) of a semitone offset above a root.
static func note_hz(root: float, semitone: int) -> float:
	return root * pow(SEMITONE, float(semitone))


## Synthesize one station's seamless arpeggio loop: each note fills one `step`
## with a plucked tone (attack-decay envelope so steps don't click), normalized
## to ±0.9. Deterministic — same station always yields the same loop.
static func loop_frames(sample_rate: int, station_index: int) -> PackedFloat32Array:
	var station: Dictionary = STATIONS[clampi(station_index, 0, STATIONS.size() - 1)]
	var notes: Array = station["notes"]
	var step_frames := maxi(int(float(sample_rate) * float(station["step"])), 1)
	var bright: bool = station["bright"]
	var frames := PackedFloat32Array()
	frames.resize(step_frames * notes.size())
	var peak := 0.0
	for n in notes.size():
		var freq := note_hz(float(station["root"]), int(notes[n]))
		for i in step_frames:
			var t := float(i) / float(sample_rate)
			var env: float = exp(-5.0 * t) * (1.0 - exp(-200.0 * t))
			var sample := sin(TAU * freq * t)
			if bright:
				sample += 0.4 * sin(TAU * freq * 2.0 * t)
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
