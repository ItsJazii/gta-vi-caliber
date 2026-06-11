class_name NpcSchedule
extends RefCounted
## A citizen's daily routine: the scripted "where should I be and what should I
## be doing right now" baseline, before needs and the world interrupt it.
##
## A routine is an Array of blocks, each a Dictionary:
##   {"start": float, "end": float, "activity": String, "place": String}
## `start`/`end` are clock hours in [0, 24). A block may wrap past midnight
## (start > end, e.g. sleep 22.0 -> 6.0). Blocks are scanned in order and the
## first one covering the hour wins, so author them most-specific-first.
##
## All static + pure (clock hour in, block out), so it unit-tests headless
## (tests/unit/test_npc_schedule.gd).

## The fallback when no block matches — an NPC with a gap in its day just loiters.
const IDLE := {"start": 0.0, "end": 24.0, "activity": "loiter", "place": "street"}


## Wrap a clock value into [0, 24).
static func wrap_hour(hour: float) -> float:
	return fposmod(hour, 24.0)


## Does `block` cover `hour`? Handles midnight-wrapping blocks (start > end).
static func block_covers(block: Dictionary, hour: float) -> bool:
	var h := wrap_hour(hour)
	var s := float(block.get("start", 0.0))
	var e := float(block.get("end", 24.0))
	if s <= e:
		return h >= s and h < e
	# Wrapping block, e.g. 22 -> 6 covers [22,24) ∪ [0,6).
	return h >= s or h < e


## The active block at `hour`, or IDLE if the routine leaves a gap.
static func activity_at(blocks: Array, hour: float) -> Dictionary:
	for block in blocks:
		if block_covers(block, hour):
			return block
	return IDLE


## Hours from `hour` until the given block ends (always positive, handles wrap).
## Lets the brain know "you only have 20 minutes of lunch left" for pacing.
static func hours_until_end(block: Dictionary, hour: float) -> float:
	var h := wrap_hour(hour)
	var e := float(block.get("end", 24.0))
	var delta := e - h
	if delta <= 0.0:
		delta += 24.0
	return delta
