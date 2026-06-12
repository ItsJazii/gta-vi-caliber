class_name CombatCover
extends RefCounted
## Pure cover evaluation for shootouts — the spatial reasoning that lets the
## player and the AI duck behind walls, lean out to shoot, and choose the safest
## spot relative to a threat. Static math only, no nodes, no RNG, so behaviour is
## deterministic and unit-tested headless (tests/unit/test_combat_cover.gd).
##
## A cover point is a Dictionary {pos: Vector3, normal: Vector3}. `normal` is the
## direction the cover FACES — its open side, the side an agent stands on to be
## protected. Convention: a threat is blocked when it sits on the faced side, i.e.
## dot(threat - pos, normal) > 0 (the wall is between the agent and the threat).
##
## Planar throughout: the XZ plane with y ignored (y is up), matching CombatAi and
## NpcSteering. The owning node holds mutable state (chosen cover, peek side); these
## helpers just score and locate.

## Below this planar distance a cover and a threat are treated as coincident, so we
## never normalise a zero vector into a NaN.
const EPSILON := 0.0001


## Planar (XZ) vector with the vertical component dropped.
static func _planar(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Planar unit direction from a to b, or ZERO if effectively coincident.
static func _planar_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := _planar(b - a)
	return d.normalized() if d.length() > EPSILON else Vector3.ZERO


## Normalized horizontal direction from the agent toward the threat — what to face
## when aiming. ZERO if they're on top of each other.
static func threat_direction(agent_pos: Vector3, threat_pos: Vector3) -> Vector3:
	return _planar_dir(agent_pos, threat_pos)


## True if this cover protects against a threat at `threat_pos`: the threat must be
## on the side the cover faces, so the cover body sits between agent and threat.
## dot(threat - pos, normal) > 0 ⇒ the normal points at the threat ⇒ protected.
## A zero/degenerate normal can't block anything, so returns false.
static func provides_cover(cover: Dictionary, threat_pos: Vector3) -> bool:
	var normal := _planar(cover.get("normal", Vector3.ZERO))
	if normal.length() < EPSILON:
		return false
	var to_threat := _planar(threat_pos - cover.get("pos", Vector3.ZERO))
	if to_threat.length() < EPSILON:
		return false
	return normal.normalized().dot(to_threat.normalized()) > 0.0


## How good this cover is against the threat, in [0, 1]. Best when the cover squarely
## faces the threat (normal aligned with the cover→threat line) AND the threat is far
## enough that the wall actually shields a meaningful arc. Zero when it doesn't
## protect (threat on the open side) or the normal is degenerate.
## `agent_to_protect_radius` widens the "too close to matter" band: a bigger body
## needs the threat further off before the cover counts as squarely facing.
static func cover_quality(
	cover: Dictionary, threat_pos: Vector3, agent_to_protect_radius: float
) -> float:
	var normal := _planar(cover.get("normal", Vector3.ZERO))
	if normal.length() < EPSILON:
		return 0.0
	var to_threat := _planar(threat_pos - cover.get("pos", Vector3.ZERO))
	var dist := to_threat.length()
	if dist < EPSILON:
		return 0.0
	var facing := normal.normalized().dot(to_threat / dist)
	if facing <= 0.0:
		return 0.0
	# Range factor: the threat must clear the agent's own radius before the wall
	# shields a useful arc; saturates to 1 once comfortably beyond it.
	var min_useful := maxf(agent_to_protect_radius, EPSILON)
	var range_factor := clampf((dist - min_useful) / (min_useful + 1.0), 0.0, 1.0)
	return clampf(facing * range_factor, 0.0, 1.0)


## Pick the cover that protects the agent from the threat and is nearest the agent.
## Returns the chosen cover Dictionary, or {} if the list is empty or none protect.
static func best_cover(cover_points: Array, agent_pos: Vector3, threat_pos: Vector3) -> Dictionary:
	var best := {}
	var best_dist := INF
	for entry in cover_points:
		var cover := entry as Dictionary
		if cover == null or not provides_cover(cover, threat_pos):
			continue
		var d := _planar(cover.get("pos", Vector3.ZERO) - agent_pos).length()
		if d < best_dist:
			best_dist = d
			best = cover
	return best


## A spot stepped sideways along the cover face from which the agent can see and
## shoot the threat. Perpendicular to the cover→threat line, so leaning out clears
## the wall edge rather than walking into the line of fire. `peek_offset` is how far
## to lean (negative flips to the other edge). Falls back to the cover position when
## the threat is coincident (no defined sideways).
static func peek_position(cover: Dictionary, threat_pos: Vector3, peek_offset: float) -> Vector3:
	var pos := cover.get("pos", Vector3.ZERO) as Vector3
	var to_threat := _planar_dir(pos, threat_pos)
	if to_threat.length() < EPSILON:
		return pos
	# Right-hand perpendicular in XZ to the cover→threat line.
	var side := Vector3(to_threat.z, 0.0, -to_threat.x)
	return pos + side * peek_offset


## True if the agent has stepped out of cover into the threat's sightline — i.e. the
## agent is now on the threat's side of the wall (the open side) rather than tucked
## behind it. When the cover can't protect at all (degenerate normal / threat on the
## open side), any position counts as exposed.
static func is_exposed(agent_pos: Vector3, cover: Dictionary, threat_pos: Vector3) -> bool:
	if not provides_cover(cover, threat_pos):
		return true
	var normal := _planar(cover.get("normal", Vector3.ZERO)).normalized()
	var pos := cover.get("pos", Vector3.ZERO) as Vector3
	var agent_offset := _planar(agent_pos - pos)
	# Agent is exposed once it crosses the wall plane onto the threat-facing side.
	return agent_offset.dot(normal) > 0.0
