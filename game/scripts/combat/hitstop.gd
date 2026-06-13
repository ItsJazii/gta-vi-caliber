class_name Hitstop
extends Node
## Brief global time-dilation "hitstop" that gives an impact its crunch.
##
## On a confirmed hit a controller calls hit(): the clock jams almost to a stop
## for a few real milliseconds, then snaps back, so a blow reads as a hit instead
## of a clean pass-through. The dwell is counted in REAL seconds — a SceneTree
## timer that ignores the very time_scale it sets — and a generation counter means
## rapid back-to-back hits never let an early freeze restore time mid-crunch (the
## latest hit owns the restore). It bows out entirely if the clock is already
## dilated by something else (e.g. the weapon wheel's slow-mo) so no two systems
## fight over Engine.time_scale.
##
## Code-spawned and self-contained: a controller does `add_child(Hitstop.new())`
## and calls hit() on a damage event. No scene wiring, no autoload.

## Below this live time_scale, assume another system owns the clock and skip —
## prevents stacking onto the weapon wheel's slow-mo or onto an active freeze.
const OWNED_THRESHOLD: float = 0.9

var _gen: int = 0


## Jam time to `scale` (0 ≈ full stop) for `duration` real seconds, then restore.
## No-ops on a non-positive duration or when the clock is already slowed.
func hit(duration: float, scale: float) -> void:
	if duration <= 0.0 or Engine.time_scale < OWNED_THRESHOLD:
		return
	Engine.time_scale = clampf(scale, 0.0, 1.0)
	_gen += 1
	var mine := _gen
	# process_always = true so the timer ticks while paused; ignore_time_scale =
	# true so it measures real seconds despite the freeze it just applied.
	await get_tree().create_timer(duration, true, false, true).timeout
	# Only the most recent freeze restores, so an earlier one can't cut a later
	# (longer/kill) freeze short.
	if mine == _gen:
		Engine.time_scale = 1.0
