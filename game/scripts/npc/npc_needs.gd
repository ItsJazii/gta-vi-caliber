class_name NpcNeeds
extends RefCounted
## Utility-AI need model for a single NPC — the "why" behind everything it does.
##
## Five drives, each a satisfaction level in [0, 1] (1 = fully sated, 0 =
## desperate). They decay over time at per-NPC rates; activities top them back
## up. The NpcBrain reads these to decide when a citizen should abandon its
## scripted routine and go eat / sleep / find a toilet / chase fun. Pure state +
## math, scene-free, so it unit-tests headless (tests/unit/test_npc_needs.gd).

## Canonical drive order. Index 0..N is stable so seeds/tests stay deterministic.
const NEEDS: PackedStringArray = ["energy", "hunger", "social", "fun", "hygiene"]

## name -> satisfaction in [0, 1].
var values: Dictionary = {}


## Start every drive at `initial` (clamped). Default: a content, well-rested NPC.
func _init(initial: float = 1.0) -> void:
	var v := clampf(initial, 0.0, 1.0)
	for n in NEEDS:
		values[n] = v


## Drain each drive by its hourly rate × elapsed game-hours. Missing rate = 0
## (that drive does not decay). Clamped at 0 so a starving NPC can't go negative.
func decay(hours: float, rates: Dictionary) -> void:
	for n in NEEDS:
		var r := float(rates.get(n, 0.0))
		values[n] = clampf(float(values[n]) - r * hours, 0.0, 1.0)


## Replenish one drive (e.g. eating restores "hunger"). Clamped at 1.
func satisfy(need: String, amount: float) -> void:
	if values.has(need):
		values[need] = clampf(float(values[need]) + amount, 0.0, 1.0)


## How badly this drive wants attention: 0 (sated) .. 1 (desperate).
func urgency(need: String) -> float:
	return 1.0 - float(values.get(need, 1.0))


## The single most-deprived drive, scanning in canonical order so ties resolve
## deterministically toward the earlier need.
func most_urgent() -> String:
	var worst := ""
	var worst_v := INF
	for n in NEEDS:
		var v := float(values[n])
		if v < worst_v:
			worst_v = v
			worst = n
	return worst


## Urgency of the most-deprived drive in [0, 1] — the brain's "interrupt" signal.
func peak_urgency() -> float:
	return urgency(most_urgent())
