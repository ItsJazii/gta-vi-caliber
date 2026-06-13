extends SceneTree
## Mission-campaign probe for the main playable map.
##
## Proves the in-world CAMPAIGN actually plays end to end: every frame it pins
## the player rig onto the MissionController's CURRENT waypoint — whatever
## mission and objective that is — so reach objectives complete on arrival and
## hold objectives complete by dwelling (the player stays pinned until the
## waypoint moves on). The MissionCampaign coordinator advances through all
## five missions, including the timed ones. Asserts the campaign reports
## complete and that the reward loop accrued across missions — money, respect,
## and the missions-passed stat. Guards the mission framework + its wiring in
## CI. Run headless:
##   godot --headless --path game --script res://tests/miami_mission_probe.gd

const SCENE_PATH: String = "res://scenes/world/miami.tscn"
const WARMUP_FRAMES: int = 36
## Generous cap: 16 objectives, ~10.5 s of hold beats (~630 frames) plus
## per-zone detection and mission handoffs, with slack.
const DRIVE_FRAMES: int = 2400

var _scene: Node = null
var _player: Node3D = null
var _campaign: Node = null
var _controller: Node = null
var _stats: Node = null
var _money_at_start: int = 0
var _frames: int = 0
var _failed: bool = false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("miami mission probe: scene failed to load")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	if _frames == WARMUP_FRAMES:
		return _resolve_nodes()
	if _failed:
		return true

	if _campaign.is_campaign_complete():
		return _pass()
	if _frames >= WARMUP_FRAMES + DRIVE_FRAMES:
		return _timeout()

	# Chase the live waypoint: pinning the player on it satisfies reach
	# objectives instantly and accrues hold objectives' dwell clocks; when an
	# objective (or mission) flips, the waypoint moves and the pin follows.
	# Velocity is zeroed so the teleport doesn't bank fall speed into a lethal
	# phantom impact during long holds.
	var target: Vector3 = _controller.current_waypoint(_player.global_position)
	_player.global_position = target
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	return false


func _resolve_nodes() -> bool:
	var players := get_nodes_in_group("player")
	_player = players[0] as Node3D if not players.is_empty() else null
	_campaign = get_first_node_in_group("campaign")
	if _player == null:
		return _fail("no player rig in group 'player'")
	if _campaign == null or not _campaign.has_method("is_campaign_complete"):
		return _fail("no MissionCampaign in group 'campaign'")
	_controller = get_first_node_in_group("mission")
	if _controller == null or not _controller.has_method("current_waypoint"):
		return _fail("no MissionController in group 'mission'")
	_stats = get_first_node_in_group("player_stats")
	if _stats == null or not ("money" in _stats):
		return _fail("no PlayerStats with money in group 'player_stats'")
	_money_at_start = int(_stats.money)
	return false


func _pass() -> bool:
	var earned := int(_stats.money) - _money_at_start
	var progression := get_first_node_in_group("progression")
	var xp := int(progression.total_xp()) if progression != null else 0
	var stats_node := get_first_node_in_group("stats")
	var passed := int(stats_node.stat("missions_passed")) if stats_node != null else 0
	var total: int = _campaign.mission_total() if _campaign.has_method("mission_total") else 0
	if earned <= 0:
		return _fail("campaign complete but economy paid nothing")
	if xp <= 0:
		return _fail("campaign complete but no respect awarded")
	if passed < total or passed <= 0:
		return _fail("campaign complete but missions_passed=%d (of %d)" % [passed, total])
	print(
		(
			"miami mission probe: OK (%d-mission campaign cleared, earned $%d + %d respect)"
			% [passed, earned, xp]
		)
	)
	quit(0)
	return true


func _timeout() -> bool:
	var passed: int = _campaign.missions_done() if _campaign.has_method("missions_done") else -1
	var hud: String = _controller.hud_text() if _controller.has_method("hud_text") else "?"
	var health := get_first_node_in_group("player_health")
	var hp: float = float(health.health) if health != null and "health" in health else -1.0
	return _fail(
		"campaign never completed (missions_done=%d, hp=%.0f, stuck on: %s)" % [passed, hp, hud]
	)


func _fail(message: String) -> bool:
	_failed = true
	push_error("miami mission probe FAIL :: %s" % message)
	print("miami mission probe: FAIL — %s" % message)
	quit(1)
	return true
