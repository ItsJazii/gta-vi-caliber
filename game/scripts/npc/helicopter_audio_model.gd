class_name HelicopterAudioModel
extends RefCounted
## Pure synthesis for the police helicopter's rotor thump and pursuit siren —
## the same no-audio-binaries approach as VehicleAudioModel: deterministic,
## scene-free loops that unit-test headless; the HelicopterAudio node only
## moves these frames into AudioStreamPlayer3Ds.

## Whole blade-pass pulses per generated rotor loop. Integer count ⇒ the loop
## seam lands where the pulse envelope has decayed to ~0, so looping is
## click-free.
const ROTOR_LOOP_PULSES: int = 24

## Default blade-pass rate: 520 rotor rpm × 2 blades / 60 ≈ 17.3 thumps/s.
const DEFAULT_PULSE_HZ: float = 17.3

## Two-tone wail sweep defaults (Hz).
const SIREN_LOW_HZ: float = 620.0
const SIREN_HIGH_HZ: float = 1250.0
const SIREN_SWEEP_HZ: float = 0.55


## Synthesize a seamless rotor loop: a decaying thump per blade pass (body
## tones locked to pulse harmonics so the seam stays phase-continuous), a
## faint turbine whine, and a noise transient riding each pulse front.
## Normalized to ±0.9.
static func rotor_loop_frames(
	sample_rate: int, pulse_hz: float = DEFAULT_PULSE_HZ
) -> PackedFloat32Array:
	var rate := maxi(sample_rate, 1000)
	var hz := maxf(pulse_hz, 1.0)
	var count := maxi(int(round(float(rate) * float(ROTOR_LOOP_PULSES) / hz)), 1)
	var frames := PackedFloat32Array()
	frames.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	var peak := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var pulse_pos := fposmod(t * hz, 1.0)
		var env := exp(-5.5 * pulse_pos)
		# Body partials at pulse harmonics (3rd/6th ≈ 52/104 Hz at default
		# rate) — integer multiples of the loop length, so the seam is clean.
		var body := sin(TAU * hz * 3.0 * t) * 0.78 + sin(TAU * hz * 6.0 * t) * 0.22
		var whine := 0.10 * sin(TAU * hz * 12.0 * t)
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.4)
		var sample := env * (body + noise * 0.25) + whine
		frames[i] = sample
		peak = maxf(peak, absf(sample))
	if peak > 0.0:
		for i in count:
			frames[i] = frames[i] / peak * 0.9
	return frames


## Synthesize one seamless wail period: a symmetric triangle frequency sweep
## low → high → low. Phase comes from the closed-form integral of the sweep,
## and the loop duration is chosen so the total carrier phase is an exact
## whole number of cycles — the seam joins mid-wave with no click.
## Normalized to ±0.9 by construction.
static func siren_loop_frames(
	sample_rate: int,
	low_hz: float = SIREN_LOW_HZ,
	high_hz: float = SIREN_HIGH_HZ,
	sweep_hz: float = SIREN_SWEEP_HZ
) -> PackedFloat32Array:
	var rate := maxi(sample_rate, 1000)
	var lo := minf(maxf(low_hz, 1.0), maxf(high_hz, 1.0))
	var hi := maxf(maxf(low_hz, 1.0), maxf(high_hz, 1.0))
	var avg := (lo + hi) * 0.5
	var cycles := maxi(int(round(avg / maxf(sweep_hz, 0.01))), 1)
	var duration := float(cycles) / avg
	var count := maxi(int(round(duration * float(rate))), 1)
	var frames := PackedFloat32Array()
	frames.resize(count)
	for i in count:
		var u := float(i) / float(count)
		# ∫₀ᵘ tri(v) dv for tri(v) = 1 - |2v - 1| (the symmetric sweep shape);
		# I(1) = 0.5, so phase(1) = TAU·duration·avg = TAU·cycles exactly.
		var integral := u * u if u <= 0.5 else 2.0 * u - u * u - 0.5
		var phase := TAU * duration * (lo * u + (hi - lo) * integral)
		# A touch of 2nd harmonic keeps it brassy instead of a pure test tone.
		frames[i] = (sin(phase) * 0.82 + sin(phase * 2.0) * 0.18) * 0.9
	return frames
