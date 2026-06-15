class_name VehicleAudioModel
extends RefCounted
## Pure math + synthesis for vehicle audio (M2 "engine/tire/impact audio").
## Everything here is deterministic and scene-free so it unit-tests headless;
## VehicleAudio (the node) only moves these numbers into AudioStreamPlayer3Ds.
## All loops are synthesized at runtime — the repo ships no audio binaries.
##
## Layers the node drives from these functions: an engine note + a deeper exhaust
## burble (both pitch-track rpm, dip on a gear change), a tyre layer that screeches
## from either lost grip or a handbrake drift, and a one-shot crash thud whose
## weight scales with the impact.

## Whole engine cycles per generated loop. Integer count ⇒ the loop seam is
## phase-continuous, so looping playback has no click.
const ENGINE_LOOP_CYCLES: int = 64

## Whole sub-octave cycles per generated exhaust loop. Even, so the half-order
## sub and the burble modulation both close cleanly at the seam.
const EXHAUST_LOOP_CYCLES: int = 32
## Burble (amplitude-modulation) cycles across one exhaust loop. Integer ⇒ the
## modulation seam is click-free.
const EXHAUST_BURBLE_CYCLES: int = 4

## Relative strength of engine harmonics 1..n. A falling series with a strong
## 2nd harmonic reads as "engine" rather than "organ pipe".
const HARMONIC_AMPLITUDES: PackedFloat32Array = [1.0, 0.55, 0.30, 0.18, 0.10]

## Below this slip fraction (0 = full grip) tires stay silent.
const SKID_SILENCE_SLIP: float = 0.25
## Below this drift amount (0..1) the handbrake/slide screech stays silent.
const DRIFT_SILENCE: float = 0.15
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


## Exhaust loudness: a quiet baseline that swells under throttle, plus an overrun
## term so lifting off at high rpm pops and burbles instead of going silent.
static func exhaust_volume_db(
	throttle: float, rpm: float, idle_rpm: float, redline_rpm: float
) -> float:
	var thr := clampf(throttle, 0.0, 1.0)
	var rev_range := maxf(redline_rpm - idle_rpm, 1.0)
	var rev_frac := clampf((rpm - idle_rpm) / rev_range, 0.0, 1.0)
	var overrun := 0.4 * (1.0 - thr) * rev_frac
	var loudness := clampf(0.15 + 0.5 * thr + overrun, 0.0, 1.0)
	return linear_to_db(loudness)


## Volume offset (dB, <= 0) applied to the engine/exhaust at the instant of a gear
## change, easing linearly back to 0 over recover_sec. Models the brief throttle
## lift of an upshift. At/after recover_sec it's 0 (no effect).
static func shift_dip_db(
	time_since_shift: float, dip_db: float = -9.0, recover_sec: float = 0.28
) -> float:
	if recover_sec <= 0.0 or time_since_shift >= recover_sec or time_since_shift < 0.0:
		return 0.0
	var t := time_since_shift / recover_sec
	return lerpf(dip_db, 0.0, t)


## Tire screech from slip (0 = full grip, 1 = no grip). Silent until
## SKID_SILENCE_SLIP, then ramps to 0 dB at full slip.
static func skid_volume_db(slip: float) -> float:
	var s := clampf(slip, 0.0, 1.0)
	if s <= SKID_SILENCE_SLIP:
		return SILENT_DB
	var t := (s - SKID_SILENCE_SLIP) / (1.0 - SKID_SILENCE_SLIP)
	return lerpf(-30.0, 0.0, t)


## Handbrake / power-slide screech from a drift amount (0..1, as the car exposes).
## Silent until DRIFT_SILENCE, then ramps up to a loud -2 dB at a full slide.
static func handbrake_screech_db(drift_amount: float) -> float:
	var d := clampf(drift_amount, 0.0, 1.0)
	if d <= DRIFT_SILENCE:
		return SILENT_DB
	var t := (d - DRIFT_SILENCE) / (1.0 - DRIFT_SILENCE)
	return lerpf(-28.0, -2.0, t)


## Combined tyre-layer loudness: the louder (in dB) of lost-grip screech and a
## handbrake drift, so one tyre player covers both sources.
static func tire_mix_db(slip: float, drift_amount: float) -> float:
	return maxf(skid_volume_db(slip), handbrake_screech_db(drift_amount))


## Screech pitch_scale: harder slides scrub a touch higher. intensity is the
## driving amount in 0..1 (max of slip and drift).
static func skid_pitch_scale(intensity: float) -> float:
	return lerpf(0.9, 1.4, clampf(intensity, 0.0, 1.0))


## One-shot impact loudness from a velocity jump (m/s), mapped 0 dB at
## full_dv and silent below threshold_dv.
static func impact_volume_db(dv: float, threshold_dv: float, full_dv: float) -> float:
	if dv < threshold_dv or full_dv <= threshold_dv:
		return SILENT_DB
	var t := clampf((dv - threshold_dv) / (full_dv - threshold_dv), 0.0, 1.0)
	return lerpf(-18.0, 0.0, t)


## Crash pitch_scale: a light knock cracks high, a big hit lands as a deep thud.
## Pitch falls with severity between threshold_dv and full_dv.
static func impact_pitch_scale(dv: float, threshold_dv: float, full_dv: float) -> float:
	if full_dv <= threshold_dv:
		return 1.0
	var t := clampf((dv - threshold_dv) / (full_dv - threshold_dv), 0.0, 1.0)
	return lerpf(1.2, 0.7, t)


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


## Synthesize a seamless exhaust loop: a half-order sub (base_freq/2) with odd
## harmonics for a deep burble, amplitude-modulated by a slow throb. The loop
## spans EXHAUST_LOOP_CYCLES whole sub cycles and EXHAUST_BURBLE_CYCLES whole
## throbs, so every component closes phase-continuously. Normalized to ±0.9.
static func exhaust_loop_frames(sample_rate: int, base_freq: float) -> PackedFloat32Array:
	var rate := maxi(sample_rate, 1000)
	var sub_freq := maxf(base_freq, 1.0) * 0.5
	var frame_count := maxi(int(round(float(rate) * EXHAUST_LOOP_CYCLES / sub_freq)), 1)
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	var peak := 0.0
	for i in frame_count:
		# Whole cycles of the sub across the loop; integer multiples stay in phase.
		var phase := TAU * EXHAUST_LOOP_CYCLES * float(i) / float(frame_count)
		var sample := sin(phase) + 0.5 * sin(phase * 3.0) + 0.3 * sin(phase * 5.0)
		sample += 0.2 * sin(phase * 2.0)
		var burble := 0.7 + 0.3 * sin(TAU * EXHAUST_BURBLE_CYCLES * float(i) / float(frame_count))
		sample *= burble
		frames[i] = sample
		peak = maxf(peak, absf(sample))
	if peak > 0.0:
		for i in frame_count:
			frames[i] = frames[i] / peak * 0.9
	return frames


## Deterministic looped noise (tire screech). A one-pole low-pass keeps it from
## sounding like pure static. Because the node loops this stream continuously, the
## tail is linearly cross-faded into a continuation past the end (the filter runs
## frame_count + xfade samples) so frames[0] picks up where frames[last] leaves
## off — no click at the loop seam. Stays within ±0.9 (a blend of two ±0.9 values).
static func noise_loop_frames(
	sample_rate: int, seconds: float, rng_seed: int
) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frame_count := maxi(int(float(sample_rate) * seconds), 1)
	# Short crossfade window, never more than an eighth of the loop.
	var xfade := clampi(frame_count / 8, 1, 256)
	var raw := PackedFloat32Array()
	raw.resize(frame_count + xfade)
	var prev := 0.0
	for i in raw.size():
		prev = lerpf(prev, rng.randf_range(-1.0, 1.0), 0.35)
		raw[i] = prev * 0.9
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	for i in frame_count:
		if i < xfade:
			# Fade from the post-seam continuation (raw[frame_count + i]) into the
			# head (raw[i]); at i == 0 it is purely the continuation, so the wrap
			# raw[last] → raw[frame_count] is a single, continuous filter step.
			var t := float(i) / float(xfade)
			frames[i] = raw[i] * t + raw[frame_count + i] * (1.0 - t)
		else:
			frames[i] = raw[i]
	return frames


## Deterministic one-shot crash thud: a fast-decaying low-frequency boom with a
## crunch of filtered noise riding the front. Not looped — played once per hit.
## Normalized to ±0.9.
static func crash_loop_frames(
	sample_rate: int, seconds: float, rng_seed: int
) -> PackedFloat32Array:
	var rate := maxi(sample_rate, 1000)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frame_count := maxi(int(float(rate) * seconds), 1)
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	var prev := 0.0
	var peak := 0.0
	for i in frame_count:
		var t := float(i) / float(rate)
		var env := exp(-12.0 * t)
		var body := sin(TAU * 70.0 * t)
		prev = lerpf(prev, rng.randf_range(-1.0, 1.0), 0.5)
		var sample := env * (body * 0.8 + prev * 0.6)
		frames[i] = sample
		peak = maxf(peak, absf(sample))
	if peak > 0.0:
		for i in frame_count:
			frames[i] = frames[i] / peak * 0.9
	return frames


## Pack float frames into 16-bit little-endian PCM for AudioStreamWAV.
static func frames_to_wav16(frames: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		var v := int(clampf(frames[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes
