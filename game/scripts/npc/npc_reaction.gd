class_name NpcReaction
extends RefCounted
## How a citizen reacts to the player: ignore, gawk, or flee. The roadmap's
## "reactions (flee/gawk)" line for M4. Pure decision math — distance + how
## threatening the player currently is + this NPC's own nerve — so it unit-tests
## headless (tests/unit/test_npc_reaction.gd) and the agent just acts on the verb.
##
## Threat is a 0..1 read of the player right now (sprinting at someone with a gun
## out is scarier than ambling by). Bravery and curiosity are per-NPC traits, so
## the Retired Stunt Double bolts while the Feral Food Critic leans in to rate it.

## Past this range the player is just scenery; the NPC carries on with its day.
const NOTICE_RADIUS: float = 14.0
## Inside this the NPC feels crowded even by a harmless passer-by.
const PERSONAL_RADIUS: float = 3.5
## A panicking citizen this close is contagious — terror spreads through a crowd.
const PANIC_RADIUS: float = 6.0
## Bravery at/above this shrugs off a neighbour's panic (the steady ones hold).
const PANIC_NERVE: float = 0.85


## Build a 0..1 threat score from the player's state. Brandishing a weapon is the
## big term; charging at speed adds to it. Saturates at 1.
static func threat_from(player_speed: float, armed: bool) -> float:
	var t := 0.0
	if armed:
		t += 0.6
	t += clampf(player_speed / 10.0, 0.0, 0.4)  # full tilt adds up to 0.4
	return clampf(t, 0.0, 1.0)


## Pick a reaction verb: "ignore", "gawk", or "flee".
##   distance  — metres from player to NPC
##   threat    — 0..1 from threat_from()
##   bravery   — 0..1 trait; higher resists fear
##   curiosity — 0..1 trait; higher leans in to gawk
static func decide(distance: float, threat: float, bravery: float, curiosity: float) -> String:
	if distance > NOTICE_RADIUS:
		return "ignore"

	# Fear wins first. A high threat lets fear reach out further than personal
	# space; a brave NPC shrugs off more of it.
	var fear := threat - bravery
	var flee_range := PERSONAL_RADIUS + threat * 8.0
	if fear > 0.0 and distance <= flee_range:
		return "flee"

	# Not scared — but is it interesting enough to stop and stare?
	if curiosity > 0.5 and distance <= NOTICE_RADIUS:
		return "gawk"

	return "ignore"


## Does this NPC catch a nearby citizen's panic? Close terror is contagious, but
## the steady-nerved (bravery >= PANIC_NERVE) hold their ground. This is what
## turns one gunshot into a whole street emptying.
static func catches_panic(distance: float, bravery: float) -> bool:
	return distance <= PANIC_RADIUS and bravery < PANIC_NERVE
