class_name MissionCampaign
extends Node
## Turns the lone opening objective into a CAMPAIGN: drives a sequence of
## missions through the scene's single MissionController, advancing to the next
## when one is passed and replaying the same one when it fails (timeout/death).
## Every mission carries its own objective list — each objective declares an id,
## HUD text, world position, and a kind ("reach" or "hold" — see
## MissionObjectiveDriver) — so missions play at distinct locations with
## distinct beats instead of re-theming three fixed trigger zones. Timed
## missions set MissionController.time_limit. The opening mission keeps the
## hand-placed trigger ids (reach_car/drive_strip/return_home) so the scene's
## static zones stay live; the driver completes everything else by predicate.
##
## Joins group "campaign"; exposes is_campaign_complete() + mission progress for
## the HUD. All sequencing rides on the pure, tested MissionChain.

var _chain: MissionChain
var _controller: Node = null
var _driver: MissionObjectiveDriver = null
var _started: bool = false
var _retry_pending: bool = false


func _process(_delta: float) -> void:
	# Resolve + kick off on the first tick (not _ready) so the MissionController
	# has registered with group "mission" regardless of node ready order.
	if _started:
		# A failed mission re-arms only once the player is back on their feet;
		# resetting while dead would just fail again next tick and thrash.
		if _retry_pending and not _player_dead():
			_retry_pending = false
			_load_current()
		return
	_controller = get_tree().get_first_node_in_group("mission")
	if _controller == null:
		return
	_started = true
	add_to_group("campaign")
	_driver = MissionObjectiveDriver.new()
	_driver.name = "ObjectiveDriver"
	add_child(_driver)
	_chain = MissionChain.new(_missions())
	if _controller.has_signal("mission_completed"):
		_controller.connect("mission_completed", _on_mission_passed)
	if _controller.has_signal("mission_failed"):
		_controller.connect("mission_failed", _on_mission_failed)
	_load_current()


func _missions() -> Array:
	# Five-mission opening arc. Positions are absolute world coordinates near
	# the downtown spawn; MissionController converts to engine-local at read
	# time, so they survive FloatingOrigin shifts.
	return [
		{
			"id": "intro",
			"title": "WELCOME TO VICE CITY",
			"objectives":
			[
				_reach("reach_car", "Get in your car", Vector3(7, 1, 5)),
				_reach("drive_strip", "Drive down to the strip", Vector3(72, 1, -48), 7.0),
				_reach("return_home", "Head back to the start", Vector3(0, 1, 0)),
			],
		},
		{
			"id": "pickup",
			"title": "THE PICKUP",
			"objectives":
			[
				_reach("m2_stash", "Collect the stash from the alley", Vector3(-58, 1, 34)),
				_hold("m2_contact", "Wait for the contact at the docks", Vector3(-24, 1, -86), 2.5),
				_reach("m2_dropoff", "Run the package to the drop", Vector3(46, 1, 62)),
			],
		},
		{
			"id": "heat",
			"title": "HEAT",
			"time_limit": 150.0,
			"objectives":
			[
				_reach("m3_wheels", "Grab fresh wheels — move!", Vector3(16, 1, -28)),
				_reach(
					"m3_strip", "Tear down the strip, they're tailing you", Vector3(96, 1, -14), 8.0
				),
				_reach(
					"m3_safehouse", "Make the safehouse before the clock dies", Vector3(-44, 1, -60)
				),
			],
		},
		{
			"id": "deal",
			"title": "THE DEAL",
			"objectives":
			[
				_hold("m4_meet", "Hold the meet — show them you're alone", Vector3(62, 1, 38), 3.0),
				_reach("m4_exchange", "Make the exchange under the overpass", Vector3(-70, 1, -18)),
				_hold("m4_bank", "Sit on the cash till it cools", Vector3(10, 1, 70), 3.0),
			],
		},
		{
			"id": "kingpin",
			"title": "KINGPIN",
			"time_limit": 180.0,
			"objectives":
			[
				_reach("m5_collect", "Collect tribute across town", Vector3(-88, 1, 52), 7.0),
				_hold("m5_rivals", "Stare down the rivals' corner", Vector3(82, 1, -66), 2.0),
				_reach("m5_strip", "Own the strip one last time", Vector3(72, 1, -48), 8.0),
				_reach("m5_throne", "Take the throne — return home the king", Vector3(0, 1, 0)),
			],
		},
	]


func _load_current() -> void:
	var mission := _chain.current()
	if mission.is_empty():
		return
	var objective_defs: Array = []
	var waypoints: Dictionary = {}
	var driver_defs: Dictionary = {}
	for o in mission["objectives"]:
		objective_defs.append({"id": o["id"], "text": o["text"]})
		waypoints[o["id"]] = o["pos"]
		driver_defs[o["id"]] = {
			"kind": o.get("kind", "reach"),
			"radius": o.get("radius", 6.0),
			"duration": o.get("duration", 3.0),
		}
	_controller.title = String(mission["title"])
	_controller.objective_defs = objective_defs
	_controller.waypoints = waypoints
	_controller.time_limit = float(mission.get("time_limit", 0.0))
	if _controller.has_method("reset"):
		_controller.reset()
	_driver.defs = driver_defs
	_driver.bind(_controller)


func _on_mission_passed() -> void:
	_chain.complete_current()
	if _chain.is_campaign_complete():
		return
	# Defer so the controller finishes emitting before we rebuild it.
	_load_current.call_deferred()


func _on_mission_failed() -> void:
	# Failure (timeout, player death) replays the same mission — GTA's retry.
	# Deferred to _process so a death-fail waits out the respawn first.
	_retry_pending = true


func _player_dead() -> bool:
	for health in get_tree().get_nodes_in_group("player_health"):
		if health.has_method("is_dead") and health.is_dead():
			return true
	return false


func is_campaign_complete() -> bool:
	return _chain != null and _chain.is_campaign_complete()


## Missions passed so far / total, for a HUD "Mission 2 of 5" readout.
func missions_done() -> int:
	return _chain.completed() if _chain != null else 0


func mission_total() -> int:
	return _chain.count() if _chain != null else 0


## Compact objective-entry builders so the mission table stays readable.
static func _reach(id: String, text: String, pos: Vector3, radius: float = 6.0) -> Dictionary:
	return {"id": id, "text": text, "pos": pos, "kind": "reach", "radius": radius}


static func _hold(
	id: String, text: String, pos: Vector3, duration: float, radius: float = 8.0
) -> Dictionary:
	return {
		"id": id,
		"text": text,
		"pos": pos,
		"kind": "hold",
		"duration": duration,
		"radius": radius,
	}
