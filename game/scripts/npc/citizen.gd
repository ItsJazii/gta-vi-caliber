class_name Citizen
extends Pedestrian
## A pedestrian with an inner life. Inherits all of Pedestrian's movement,
## procedural walking, flee-when-shot and damage handling, then layers on the
## deliberative life-sim: an occupation and personality (NpcArchetypes), a daily
## routine it actually walks (NpcSchedule + the CityDirector's POIs), decaying
## drives that occasionally hijack the plan (NpcNeeds + NpcMind), proximity
## reactions (NpcReaction), and an absurd running commentary (NpcDialogue) shown
## in a speech bubble.
##
## The intelligence is all in the pure, tested modules; this node is the glue
## that turns their decisions into a citizen crossing the street to a diner while
## muttering that the foam predicted this. Reuse over reinvention: it overrides
## exactly two Pedestrian seams — `_pick_new_target` (where to go next) and
## `_physics_process` (per-frame flavour) — and leaves the rest untouched.

# Drive decay per in-game hour. Tuned so a full work block leaves a citizen
# hungry/bored enough to sometimes ditch the schedule — the deviation reads as life.
const DECAY_RATES: Dictionary = {
	"energy": 0.05, "hunger": 0.10, "social": 0.06, "fun": 0.08, "hygiene": 0.05
}
# Which drive an activity replenishes once the citizen has spent time on it.
const ACTIVITY_NEED: Dictionary = {
	"sleep": "energy",
	"eat": "hunger",
	"socialize": "social",
	"goof_off": "fun",
	"freshen_up": "hygiene",
}
# How long a frightened citizen keeps running, independent of the player. This is
# Citizen-owned (Pedestrian's own flee only persists while the player is near).
const PANIC_DURATION: float = 5.0
## Caption budget: at most this many citizen speech bubbles visible at once, and
## only citizens within this range of the camera speak, so a crowd reads as
## ambient life instead of a wall of overlapping captions.
const MAX_LIVE_BUBBLES: int = 2
const BUBBLE_MAX_DISTANCE: float = 32.0
## A fresh bubble is suppressed when another citizen is already captioning within
## this many metres, so a tight crowd collapses to one readable line instead of
## stacking billboards at the same screen spot (and never doubles a bark).
const BUBBLE_MIN_SEPARATION: float = 5.0

## Seconds between proximity-reaction checks (cheap throttle on the O(n) player scan).
@export var react_interval: float = 0.7
## How long a speech bubble stays at full opacity before fading.
@export var bubble_seconds: float = 2.6
## Force a specific archetype by id; empty = derive a stable one from the node.
@export var archetype_id: String = ""

var _needs := NpcNeeds.new(0.85)
var _schedule: Array = []
var _personality: Dictionary = {}
var _voice: String = "generic"
var _activity: String = "loiter"
var _bravery: float = 0.5
var _curiosity: float = 0.6
var _voice_seed: int = 0
var _bark_n: int = 0
var _last_plan_hour: float = 8.0
var _react_left: float = 0.0
var _bubble_left: float = 0.0
var _bubble: Label3D = null
# Nav path to the current destination (world points). Empty = walk straight there.
var _path: Array = []
var _wp: int = 0
# Active fright: seconds left running, and the world point being fled.
var _panic_left: float = 0.0
var _panic_from: Vector3 = Vector3.ZERO
# Lingering memory (0..1) of a crime witnessed nearby — fades over ~13 s.
var _crime_memory: float = 0.0


func _ready() -> void:
	_assign_persona()
	_make_bubble()
	_last_plan_hour = _director_hour()
	# Parent _ready sets _home/_hp/_rng and then calls _pick_new_target() — our
	# override — so persona must already be in place above.
	super._ready()
	add_to_group("citizens")


# --- persona ----------------------------------------------------------------


func _assign_persona() -> void:
	var arch: Dictionary = NpcArchetypes.by_id(archetype_id) if archetype_id != "" else {}
	if arch.is_empty():
		arch = NpcArchetypes.pick(absi(str(name).hash()))
	_schedule = arch.get("schedule", [])
	_personality = arch.get("personality", {})
	_voice = String(arch.get("voice", "generic"))
	_voice_seed = absi(str(name).hash())
	# Stable per-citizen nerve/nosiness so the same person always reacts the same.
	_bravery = 0.25 + float(_voice_seed % 60) / 100.0
	_curiosity = 0.35 + float((_voice_seed / 60) % 60) / 100.0
	_apply_tint(arch.get("tint", Color(0.5, 0.5, 0.5)))


## Recolour the shirt (torso + arms) to the archetype tint so a Doomsday Barista
## reads differently from a Mime at a glance. Materials are duplicated first so we
## never mutate a shared resource on the shared HumanoidBody.
func _apply_tint(color: Color) -> void:
	for path in ["Rig/Hips/Torso", "Rig/Hips/ShoulderL/ArmL", "Rig/Hips/ShoulderR/ArmR"]:
		var mi := get_node_or_null(path) as MeshInstance3D
		if mi == null:
			continue
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
		else:
			mat = mat.duplicate()
		mat.albedo_color = color
		mi.material_override = mat


func _make_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.name = "Bubble"
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# World-space (not fixed_size) so distant chatter shrinks into ambient
	# background instead of stacking full-size captions over the whole crowd;
	# only NPCs near the camera read large.
	_bubble.fixed_size = false
	_bubble.pixel_size = 0.005
	_bubble.font_size = 64
	_bubble.outline_size = 14
	_bubble.position = Vector3(0.0, 2.15, 0.0)
	_bubble.modulate = Color(1, 1, 1, 0)
	add_child(_bubble)


# --- daily routine (overrides Pedestrian's random wander) -------------------


func _pick_new_target() -> void:
	var director := _city_director()
	if director == null or not director.has_pois():
		super._pick_new_target()  # no city laid out — just amble like a pedestrian
		return

	var hour := director.hour()
	# Decay drives for the time since the last plan, then bank the drive the
	# just-finished activity restored.
	var elapsed := hour - _last_plan_hour
	if elapsed < 0.0:
		elapsed += 24.0
	_needs.decay(clampf(elapsed, 0.0, 6.0), DECAY_RATES)
	var restored := String(ACTIVITY_NEED.get(_activity, ""))
	if restored != "":
		_needs.satisfy(restored, 0.6)
	_last_plan_hour = hour

	var decision := NpcMind.decide(_schedule, hour, _needs, _personality)
	_activity = String(decision.get("activity", "loiter"))
	var place := String(decision.get("place", "street"))

	_state = NpcBrain.State.WANDER
	var dest := director.position_for(place, global_position)
	dest += Vector3(_rng.randf_range(-1.6, 1.6), 0.0, _rng.randf_range(-1.6, 1.6))
	# Route around obstacles when the city has a nav grid; otherwise go straight.
	_path = []
	_wp = 0
	for p in director.path_to(global_position, dest):
		_path.append(p)
	_target = _path[0] if not _path.is_empty() else dest
	_say(NpcDialogue.bark_for_activity(_voice, _activity, _next_seed()))


# --- per-frame flavour ------------------------------------------------------


func _physics_process(delta: float) -> void:
	# Panic overrides everything: keep walking directly away from the scare until
	# it wears off. (Player-driven flee, when a player is near, is the parent's.)
	if _panic_left > 0.0:
		_panic_left -= delta
		_flee_step()
	elif not _path.is_empty() and _state != NpcBrain.State.FLEE:
		# Walk the nav path: aim at the current waypoint, advancing as each is
		# reached. The final waypoint stays the destination so Pedestrian's own
		# arrive→idle logic still fires there.
		_wp = NpcSteering.advance_waypoint(global_position, _path, _wp, 1.5)
		_target = _path[_wp]
	super._physics_process(delta)
	_fade_bubble(delta)
	_crime_memory = NpcMemory.decay(_crime_memory, delta)
	_react_left -= delta
	if _react_left <= 0.0:
		_react_left = react_interval
		_maybe_react()
		_maybe_catch_panic()
		_maybe_witness_bark()
		_maybe_weather_bark()
		_maybe_socialize()


## React to a nearby player: bolt if frightened, rubberneck if merely intrigued.
## Fleeing reuses Pedestrian's own fear machinery so the movement is consistent
## with being shot at — the citizen just got spooked by proximity instead.
func _maybe_react() -> void:
	if is_dead():
		return
	var player := _nearest_player()
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	var speed := 0.0
	if player is CharacterBody3D:
		speed = (player as CharacterBody3D).velocity.length()
	var threat := NpcReaction.threat_from(speed, false)
	match NpcReaction.decide(dist, threat, _bravery, _curiosity):
		"flee":
			_fear = maxf(_fear, 2.0)
			_threat_pos = player.global_position
			_state = NpcBrain.State.FLEE
			if _bubble.modulate.a <= 0.0:
				_say(NpcDialogue.bark(_voice, "flee", _next_seed()))
		"gawk":
			if _bubble.modulate.a <= 0.0:
				_say(NpcDialogue.bark(_voice, "gawk", _next_seed()))


## Is this citizen actively fleeing in fear right now? Neighbours read this to
## decide whether to catch the panic.
func is_panicking() -> bool:
	return _panic_left > 0.0 and not is_dead()


## Where the fear is coming from — so a caught panic sends everyone running the
## same way, not in circles.
func panic_origin() -> Vector3:
	return _panic_from


## Start fleeing a scare at `from` for PANIC_DURATION seconds, independent of the
## player (a gunshot, or a neighbour's contagious terror). _flee_step does the
## moving each frame.
func _start_panic(from: Vector3) -> void:
	_panic_left = PANIC_DURATION
	_panic_from = from
	if _bubble != null and _bubble.modulate.a <= 0.0:
		_say(NpcDialogue.bark(_voice, "flee", _next_seed()))


## One frame of fleeing: steer directly away from the scare. Reuses Pedestrian's
## WANDER locomotion (which doesn't need a player), just aimed outward.
func _flee_step() -> void:
	var away := NpcSteering.ground(global_position - _panic_from)
	if away.length() < 0.1:
		away = Vector3(cos(float(_voice_seed)), 0.0, sin(float(_voice_seed)))
	_state = NpcBrain.State.WANDER
	_target = global_position + away.normalized() * 4.0
	_path = []


## Catch a panicking neighbour's terror: one gunshot empties a street as fear
## ripples outward, citizen to citizen, the timid going first. Already-panicking
## or dead citizens skip it.
func _maybe_catch_panic() -> void:
	if is_dead() or is_panicking():
		return
	for node in get_tree().get_nodes_in_group("citizens"):
		var other := node as Citizen
		if other == null or other == self or not other.is_panicking():
			continue
		if NpcReaction.catches_panic(global_position.distance_to(other.global_position), _bravery):
			_start_panic(other.panic_origin())
			_crime_memory = 1.0  # witnessed the mayhem — remembers the culprit
			return


## Occasionally grumble about the weather when it's notable — ties the sky to the
## street. The Self-Appointed Weather Anchor delivers an actual forecast.
func _maybe_weather_bark() -> void:
	if is_dead() or is_panicking() or velocity.length() > 1.0:
		return
	if _bubble != null and _bubble.modulate.a > 0.25:
		return
	if (_voice_seed + _bark_n) % 4 != 0:
		return
	var weather := get_tree().get_nodes_in_group("weather")
	if weather.is_empty():
		return
	var condition := String(weather[0].condition())
	if condition == "clear" and _voice != "weather":
		return  # only the anchor narrates nice weather; everyone else stays quiet
	_say(NpcDialogue.weather_bark(_voice, condition, _next_seed()))


## Strike up a (one-sided) conversation with a neighbour while loitering. Only
## near-stationary, un-spooked citizens chat; a seeded gate keeps the street from
## becoming a wall of noise. The other party replies on its own tick — out of
## sync and off-topic, which is exactly the bit.
func _maybe_socialize() -> void:
	if is_dead() or _state == NpcBrain.State.FLEE:
		return
	if velocity.length() > 1.0:
		return  # walking with purpose; no time to talk
	if _bubble != null and _bubble.modulate.a > 0.25:
		return  # already mid-sentence
	if (_voice_seed + _bark_n) % 3 != 0:
		return  # most ticks, keep it to yourself
	var other := _nearest_citizen(3.2)
	if other == null:
		return
	_say(
		(
			NpcConversation.greeting(_voice, _next_seed())
			if _bark_n < 2
			else NpcDialogue.bark(_voice, "chat", _next_seed())
		)
	)


## Nearest other living Citizen within `radius`, or null.
func _nearest_citizen(radius: float) -> Citizen:
	var best: Citizen = null
	var best_d := radius
	for node in get_tree().get_nodes_in_group("citizens"):
		var c := node as Citizen
		if c == null or c == self or c.is_dead():
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


## Bark a fright line when shot, on top of Pedestrian's flee response.
func take_damage(amount: float, point: Vector3, normal: Vector3) -> void:
	super.take_damage(amount, point, normal)
	_start_panic(point)
	_crime_memory = 1.0


## Lingering memory (0..1) of a witnessed crime — for the wanted/debug systems.
func crime_memory() -> float:
	return _crime_memory


## Call the player out when recognised. A rattled witness, mid-loiter, blurts a
## (cowardly, absurd) line — the city remembering your rap sheet.
func _maybe_witness_bark() -> void:
	if is_dead() or is_panicking():
		return
	if _bubble != null and _bubble.modulate.a > 0.25:
		return
	if (_voice_seed + _bark_n) % 2 != 0:
		return
	var player := _nearest_player()
	if player == null:
		return
	if NpcMemory.recognizes(_crime_memory, global_position.distance_to(player.global_position)):
		_say(NpcDialogue.witness_bark(_next_seed()))


# --- helpers ----------------------------------------------------------------


func _say(text: String) -> void:
	if _bubble == null:
		return
	# When starting a fresh bubble (not refreshing one already up), only speak if
	# near the camera and under the citywide caption budget, so nearby NPCs do
	# not talk over each other in a garbled stack.
	if _bubble.modulate.a <= 0.0:
		var player := _nearest_player()
		if player == null:
			return
		if global_position.distance_to(player.global_position) > BUBBLE_MAX_DISTANCE:
			return
		if _live_caption_count() >= MAX_LIVE_BUBBLES:
			return
		if _caption_within(BUBBLE_MIN_SEPARATION):
			return
	_bubble.text = text
	_bubble.modulate.a = 1.0
	_bubble_left = bubble_seconds


## True while this citizen's speech bubble is on screen (including its fade).
func is_captioning() -> bool:
	return _bubble != null and _bubble.modulate.a > 0.0


## How many citizens citywide currently show a caption, for the shared budget.
func _live_caption_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("citizens"):
		var citizen := node as Citizen
		if citizen != null and citizen.is_captioning():
			count += 1
	return count


## True when another citizen within radius metres is already captioning, so a
## clustered NPC stays silent rather than drawing a bubble over a neighbour's.
func _caption_within(radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("citizens"):
		var citizen := node as Citizen
		if citizen == null or citizen == self:
			continue
		if not citizen.is_captioning():
			continue
		if global_position.distance_to(citizen.global_position) <= radius:
			return true
	return false


func _fade_bubble(delta: float) -> void:
	if _bubble == null or _bubble.modulate.a <= 0.0:
		return
	_bubble_left -= delta
	if _bubble_left <= 0.0:
		_bubble.modulate.a = maxf(_bubble.modulate.a - delta * 1.6, 0.0)


func _next_seed() -> int:
	_bark_n += 1
	return _voice_seed + _bark_n


func _director_hour() -> float:
	var director := _city_director()
	return director.hour() if director != null else 12.0


func _city_director() -> CityDirector:
	var nodes := get_tree().get_nodes_in_group("city_director")
	return nodes[0] as CityDirector if not nodes.is_empty() else null
