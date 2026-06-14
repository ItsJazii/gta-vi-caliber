class_name MeleeImpactAudioModel
extends RefCounted
## Pure runtime synthesis for melee impact sounds — one short percussive "thwack"
## per strike, no audio binaries in the repo (mirrors FootstepAudioModel's
## approach). A low body thud that pitches down, blended with a low-passed noise
## transient (the smack), enveloped and normalized so a heavier strike is lower,
## longer and louder than a jab, with a kill the meatiest of all. Deterministic
## and scene-free so it unit-tests headless; MeleeImpactAudio (the node) only packs
## these frames into streams and plays them. Honestly placeholder-quality audio.
## Covered by tests/unit/test_melee_impact_audio_model.gd.


## Voicing for a strike, same (strike, killed) signature as
## MeleeCombat.hitstop_for_strike so the two feedback cues read consistently.
## thud_hz: body pitch (lower = heavier). duration: burst length (s). amp: target
## peak after normalisation (louder = heavier). noise_mix: 0 pure body .. 1 pure
## smack. noise_lp: noise brightness (0 dull .. 1 bright). decay: envelope rate
## (lower = longer ring). A kill overrides to the lowest/longest/loudest voicing;
## an unknown strike falls back to the lightest (jab).
static func params_for_strike(strike: int, killed: bool) -> Dictionary:
	if killed:
		return {
			"thud_hz": 72.0,
			"duration": 0.20,
			"amp": 0.98,
			"noise_mix": 0.35,
			"noise_lp": 0.35,
			"decay": 18.0,
		}
	match strike:
		MeleeCombat.Strike.CROSS:
			return {
				"thud_hz": 150.0,
				"duration": 0.11,
				"amp": 0.68,
				"noise_mix": 0.50,
				"noise_lp": 0.50,
				"decay": 36.0,
			}
		MeleeCombat.Strike.KICK:
			return {
				"thud_hz": 120.0,
				"duration": 0.13,
				"amp": 0.80,
				"noise_mix": 0.45,
				"noise_lp": 0.45,
				"decay": 30.0,
			}
		MeleeCombat.Strike.HEAVY:
			return {
				"thud_hz": 95.0,
				"duration": 0.16,
				"amp": 0.90,
				"noise_mix": 0.40,
				"noise_lp": 0.40,
				"decay": 24.0,
			}
		_:
			return {
				"thud_hz": 175.0,
				"duration": 0.09,
				"amp": 0.55,
				"noise_mix": 0.55,
				"noise_lp": 0.55,
				"decay": 42.0,
			}


## Synthesize one impact: a downward-pitching body thud blended with a low-passed
## noise transient, exponentially enveloped, normalized so the peak equals the
## voicing's `amp`. Deterministic for a given seed so tests and playback repeat.
static func impact_frames(
	sample_rate: int, strike: int, killed: bool, rng_seed: int
) -> PackedFloat32Array:
	var p := params_for_strike(strike, killed)
	var duration: float = p["duration"]
	var frame_count := maxi(int(float(sample_rate) * duration), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frames := PackedFloat32Array()
	frames.resize(frame_count)
	var prev := 0.0
	var raw_peak := 0.0
	var thud_hz: float = p["thud_hz"]
	var noise_mix: float = p["noise_mix"]
	var noise_lp: float = p["noise_lp"]
	var decay: float = p["decay"]
	for i in frame_count:
		var t := float(i) / float(sample_rate)
		var env: float = exp(-decay * t)
		# Body thud drops ~40% in pitch across the hit, for a punchy "whump".
		var body_hz := thud_hz * (1.0 - 0.4 * t / duration)
		var body := sin(TAU * body_hz * t)
		prev = lerpf(prev, rng.randf_range(-1.0, 1.0), noise_lp)
		var sample := lerpf(body, prev, noise_mix) * env
		frames[i] = sample
		raw_peak = maxf(raw_peak, absf(sample))
	if raw_peak > 0.0:
		var target: float = p["amp"]
		for i in frame_count:
			frames[i] = frames[i] / raw_peak * target
	return frames


## Pack float frames into 16-bit little-endian PCM for AudioStreamWAV. Local copy
## (deliberate ~5-line duplication) so this stays entirely inside combat/ with no
## dependency on player/FootstepAudioModel.
static func frames_to_wav16(frames: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		bytes.encode_s16(i * 2, int(clampf(frames[i], -1.0, 1.0) * 32767.0))
	return bytes
