class_name VehicleAudioModel
extends RefCounted
## Pure math + synthesis for vehicle audio (M2 "engine/tire/impact audio").
## Everything here is deterministic and scene-free so it unit-tests headless;
## VehicleAudio (the node) only moves these numbers into AudioStreamPlayer3Ds.
## All loops are synthesized at runtime — the repo ships no audio binaries.

## Whole engine cycles per generated loop. Integer count ⇒ the loop seam is
## phase-continuous, so looping playback has no click.
const ENGINE_LOOP_CYCLES: int = 64

## Relative strength of engine harmonics 1..n. A falling series with a strong
## 2nd harmonic reads as "engine" rather than "organ pipe".
const HARMONIC_AMPLITUDES: PackedFloat32Array = [1.0, 0.55, 0.30, 0.18, 0.10]

## Below this slip fraction (0 = full grip) tires stay silent.
const SKID_SILENCE_SLIP: float = 0.25
const SILENT_DB: float = -60.0


## Playback pitch_scale for an engine loop recorded at base_rpm.
static func pitch_for_rpm(rpm: float, base_rpm: float, max_pitch: float = 3.0) -> float:
	if base_rpm <= 0.0:
		return 1.0
	return clampf(rpm / base_rpm, 0.5, max_pitch)


## Engine loudness: quiet at closed-throttle idle, full at open throttle, with
## a small rpm term so coasting at high revs still sounds alive.
static func engine_volume_db(
	throttle: float, rpm: float, idle_rpm: float, redline_rpm: float
) -> float:
	var rev_range := maxf(redline_rpm - idle_rpm, 1.0)
	var rev_frac := clampf((rpm - idle_rpm) / rev_range, 0.0, 1.0)
	var loudness := clampf(0.25 + 0.6 * clampf(throttle, 0.0, 1.0) + 0.15 * rev_frac, 0.0, 1.0)
	return linear_to_db(loudness)


## Tire screech from slip (0 = full grip, 1 = no grip). Silent until
## SKID_SILENCE_SLIP, then ramps to 0 dB at full slip.
static func skid_volume_db(slip: float) -> float:
	var s := clampf(slip, 0.0, 1.0)
	if s <= SKID_SILENCE_SLIP:
		return SILENT_DB
	var t := (s - SKID_SILENCE_SLIP) / (1.0 - SKID_SILENCE_SLIP)
	return lerpf(-30.0, 0.0, t)


## One-shot impact loudness from a velocity jump (m/s), mapped 0 dB at
## full_dv and silent below threshold_dv.
static func impact_volume_db(dv: float, threshold_dv: float, full_dv: float) -> float:
	if dv < threshold_dv or full_dv <= threshold_dv:
		return SILENT_DB
	var t := clampf((dv - threshold_dv) / (full_dv - threshold_dv), 0.0, 1.0)
	return lerpf(-18.0, 0.0, t)


## Synthesize a seamless engine loop: HARMONIC_AMPLITUDES summed over
## ENGINE_LOOP_CYCLES whole cycles of base_freq, normalized to ±0.9.
static func engine_loop_frames(sample_rate: int, base_freq: float) -> PackedFloat32Array:
	var frame_count := int(round(float(sample_rate) * ENGINE_LOOP_CYCLES / base_freq))
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	var peak := 0.0
	for i in frame_count:
		var phase := TAU * ENGINE_LOOP_CYCLES * float(i) / float(frame_count)
		var sample := 0.0
		for h in HARMONIC_AMPLITUDES.size():
			sample += HARMONIC_AMPLITUDES[h] * sin(phase * float(h + 1))
		frames[i] = sample
		peak = maxf(peak, absf(sample))
	if peak > 0.0:
		for i in frame_count:
			frames[i] = frames[i] / peak * 0.9
	return frames


## Deterministic looped noise (tire screech / impact body). A one-pole
## low-pass keeps it from sounding like pure static.
static func noise_loop_frames(
	sample_rate: int, seconds: float, rng_seed: int
) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frame_count := maxi(int(float(sample_rate) * seconds), 1)
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	var prev := 0.0
	for i in frame_count:
		prev = lerpf(prev, rng.randf_range(-1.0, 1.0), 0.35)
		frames[i] = prev * 0.9
	return frames


## Pack float frames into 16-bit little-endian PCM for AudioStreamWAV.
static func frames_to_wav16(frames: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		var v := int(clampf(frames[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes
