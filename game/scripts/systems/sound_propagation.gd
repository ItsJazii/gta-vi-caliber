class_name SoundPropagation
extends RefCounted
## Pure auditory-perception model — the "ear" of the world. Decides which NPCs
## actually HEAR a positional sound event (gunshot, alarm, engine, explosion,
## footstep, shout, glass break) given each source's loudness, XZ-plane distance
## falloff, and the ambient noise floor that masks quiet sounds. Returns a perceived
## intensity (0..1) per listener and a discrete reaction tier
## (UNHEARD / NOTICED / ALARMED), so a world/AI controller can route alertness
## without any scene access.
##
## This is the missing auditory complement to the VISUAL detection stack
## (StealthDetection's FOV meter, CrimeWitness's line-of-sight): a cop around a
## corner can't SEE the player but should still turn toward a gunshot. A silenced
## pistol vs. a bare one, a revving engine vs. a coasting car, a smashed window vs.
## a footstep — all change WHO reacts. Quiet 3am streets carry sound far
## (low ambient); a roaring daytime highway or heavy rain masks it (high ambient).
##
## No nodes, no scene access: a controller owns the NPC listener list, emits events
## on noisy actions, and feeds the result into StealthDetection / CrimeWitness /
## WantedSystem / CrowdPanic / EmergencyServices. All the math stays unit-tested
## headless (tests/unit/test_sound_propagation.gd).

## Categorical event kinds a spawner maps real actions onto.
enum Sound {
	GUNSHOT,
	SILENCED_SHOT,
	EXPLOSION,
	ALARM,
	CAR_HORN,
	ENGINE,
	FOOTSTEP,
	SHOUT,
	GLASS_BREAK,
}

## Discrete listener response tier.
enum Reaction { UNHEARD, NOTICED, ALARMED }

## Distance falloff reference (metres-squared): perceived loudness halves once the
## squared XZ distance reaches this. Larger = sound carries further.
const FALLOFF_REFERENCE_SQ: float = 400.0
## Perceived intensity at/above which a listener registers the sound at all.
const NOTICED_AT: float = 0.08
## An alarming sound (gunshot, explosion...) reaches ALARMED at this intensity.
const ALARMED_AT_ALARMING: float = 0.25
## An ambient sound (engine, horn...) needs to be much louder to alarm.
const ALARMED_AT_AMBIENT: float = 0.6
## Default audibility threshold (mirrors NOTICED_AT so "audible" == "not unheard").
const DEFAULT_AUDIBLE: float = NOTICED_AT
## Night drops the ambient floor by this factor (quiet streets carry sound).
const NIGHT_QUIET_FACTOR: float = 0.5
## Heavy rain adds up to this much to the ambient floor (weather masks sound).
const RAIN_MASK_GAIN: float = 0.3


## Built-in loudness (0..1) for a sound kind; unknown kind -> 0.0.
static func base_loudness(kind: int) -> float:
	match kind:
		Sound.EXPLOSION:
			return 1.0
		Sound.GUNSHOT:
			return 0.85
		Sound.ALARM:
			return 0.7
		Sound.CAR_HORN:
			return 0.55
		Sound.GLASS_BREAK:
			return 0.5
		Sound.SHOUT:
			return 0.45
		Sound.ENGINE:
			return 0.35
		Sound.SILENCED_SHOT:
			return 0.2
		Sound.FOOTSTEP:
			return 0.12
	return 0.0


## True for kinds that spike fear/alertness; false for ambient kinds (a suppressed
## shot is deliberately not alarming — that is the whole point of a suppressor).
static func is_alarming(kind: int) -> bool:
	match kind:
		Sound.GUNSHOT, Sound.EXPLOSION, Sound.ALARM, Sound.GLASS_BREAK, Sound.SHOUT:
			return true
	return false


## Perceived intensity (0..1) of a sound at a listener: loudness attenuated by
## inverse-square-ish XZ distance falloff, then masked by the ambient floor
## (subtractive), clamped. Height (y) is ignored.
static func perceived_intensity(
	source_pos: Vector3, listener_pos: Vector3, loudness: float, ambient: float
) -> float:
	if loudness <= 0.0:
		return 0.0
	var dx: float = source_pos.x - listener_pos.x
	var dz: float = source_pos.z - listener_pos.z
	var dist_sq: float = dx * dx + dz * dz
	var attenuated: float = loudness * FALLOFF_REFERENCE_SQ / (FALLOFF_REFERENCE_SQ + dist_sq)
	return clampf(attenuated - maxf(ambient, 0.0), 0.0, 1.0)


## Whether the sound is at/above the audibility threshold at the listener.
static func is_audible(
	source_pos: Vector3,
	listener_pos: Vector3,
	loudness: float,
	ambient: float,
	threshold: float = DEFAULT_AUDIBLE
) -> bool:
	return perceived_intensity(source_pos, listener_pos, loudness, ambient) >= threshold


## Max XZ distance at which a sound of this loudness stays above `hearing_floor`
## (for spawn culling / "who could possibly hear this" broad-phase). Loudness or
## floor <= 0, or a sound already below the floor at the source, returns 0.0.
static func audible_radius(loudness: float, hearing_floor: float) -> float:
	if loudness <= 0.0 or hearing_floor <= 0.0 or loudness <= hearing_floor:
		return 0.0
	return sqrt(FALLOFF_REFERENCE_SQ * (loudness / hearing_floor - 1.0))


## Map a perceived intensity to UNHEARD / NOTICED / ALARMED. An alarming sound
## reaches ALARMED at a lower intensity than an ambient one.
static func reaction_for(intensity: float, alarming: bool) -> int:
	if intensity < NOTICED_AT:
		return Reaction.UNHEARD
	var alarmed_at: float = ALARMED_AT_ALARMING if alarming else ALARMED_AT_AMBIENT
	if intensity >= alarmed_at:
		return Reaction.ALARMED
	return Reaction.NOTICED


## Fan one event out to many listeners. Each listener is a Dictionary {pos, ...};
## it is carried through intact (id, etc. preserved) with {intensity, reaction,
## heard} added. Returns a NEW array of NEW dicts — the input is never mutated.
static func emit(source_pos: Vector3, kind: int, listeners: Array, ambient: float) -> Array:
	var loudness: float = base_loudness(kind)
	var alarming: bool = is_alarming(kind)
	var out: Array = []
	for entry: Variant in listeners:
		if not (entry is Dictionary):
			continue
		var listener: Dictionary = (entry as Dictionary).duplicate()
		var pos: Vector3 = listener.get("pos", Vector3.ZERO)
		var intensity: float = perceived_intensity(source_pos, pos, loudness, ambient)
		var reaction: int = reaction_for(intensity, alarming)
		listener["intensity"] = intensity
		listener["reaction"] = reaction
		listener["heard"] = reaction != Reaction.UNHEARD
		out.append(listener)
	return out


## Given many concurrent events [{pos, kind}], return the one that reaches this
## listener at the highest perceived intensity (a copy, with {intensity, reaction}
## added) — for picking what an idle NPC turns its head toward. {} if none audible.
static func loudest_heard(listener_pos: Vector3, events: Array, ambient: float) -> Dictionary:
	var best: Dictionary = {}
	var best_intensity: float = 0.0
	for entry: Variant in events:
		if not (entry is Dictionary):
			continue
		var event: Dictionary = entry
		var kind: int = int(event.get("kind", -1))
		var pos: Vector3 = event.get("pos", Vector3.ZERO)
		var intensity: float = perceived_intensity(pos, listener_pos, base_loudness(kind), ambient)
		if intensity >= DEFAULT_AUDIBLE and intensity > best_intensity:
			best_intensity = intensity
			var hit: Dictionary = event.duplicate()
			hit["intensity"] = intensity
			hit["reaction"] = reaction_for(intensity, is_alarming(kind))
			best = hit
	return best


## Derive the ambient masking floor from time-of-day and weather, so callers can
## wire WeatherEffects / a day-night clock without this model touching them: night
## is quieter (sound carries further), rain raises the floor (sound is masked).
static func ambient_for(base_ambient: float, is_night: bool, rain01: float) -> float:
	var floor_level: float = maxf(base_ambient, 0.0)
	if is_night:
		floor_level *= NIGHT_QUIET_FACTOR
	floor_level += clampf(rain01, 0.0, 1.0) * RAIN_MASK_GAIN
	return clampf(floor_level, 0.0, 1.0)
