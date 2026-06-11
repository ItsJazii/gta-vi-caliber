extends SceneTree
## Headless end-to-end probe for the native crowd stack: loads
## crowd_native_demo.tscn, runs the SpatialHash + CrowdSteering simulation for a
## few seconds of frames, and asserts the crowd actually simulates — agents stay
## finite, in-bounds, and keep moving (flocking) rather than freezing or
## exploding. Skips cleanly when the native module isn't built.
##
## Run: godot --headless --path game --script res://tests/crowd_native_probe.gd


func _initialize() -> void:
	var ok := _run()
	print("crowd_native_probe: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _run() -> bool:
	if not (ClassDB.class_exists("SpatialHash") and ClassDB.class_exists("CrowdSteering")):
		print("  native worldcore modules absent — skipping (OK)")
		return true

	var packed := load("res://scenes/world/crowd_native_demo.tscn")
	if packed == null:
		print("  could not load crowd_native_demo.tscn")
		return false
	var demo: CrowdNativeDemo = packed.instantiate()
	demo.agent_count = 150
	demo.half_extent = 50.0
	demo._ready()  # explicit + deterministic (don't depend on tree _ready timing)

	# The top guard proved the classes exist, so the demo MUST activate them now.
	# A skip here would mask a real native-wiring failure (Codex review).
	if not demo.native_active():
		print("  FAIL: native classes exist but the demo did not activate them")
		return false

	# Spread = mean distance from the crowd centroid. Starts large (uniform
	# scatter); if flock + arrive actually gather the crowd it must shrink. This
	# is the meaningful nav check (a loose "within the field" bound can pass
	# trivially — Codex review).
	var initial_spread := _crowd_spread(demo.positions)

	for _f in 180:  # ~3 s at 60 Hz
		demo.step(1.0 / 60.0)

	var sum_speed := 0.0
	var sum_goal_dist := 0.0
	var goal: Vector2 = demo.current_goal()
	var valid := true
	for i in demo.agent_count:
		var p: Vector2 = demo.positions[i]
		if not (is_finite(p.x) and is_finite(p.y)):
			print("  FAIL: non-finite agent position at %d" % i)
			valid = false
			break
		if absf(p.x) > demo.half_extent + 1.0 or absf(p.y) > demo.half_extent + 1.0:
			print("  FAIL: agent %d left the field (%.1f, %.1f)" % [i, p.x, p.y])
			valid = false
			break
		sum_speed += demo.velocities[i].length()
		sum_goal_dist += p.distance_to(goal)

	if not valid:
		return false

	var avg_speed := sum_speed / float(demo.agent_count)
	var avg_goal_dist := sum_goal_dist / float(demo.agent_count)
	var final_spread := _crowd_spread(demo.positions)
	# Meaningful nav check: the crowd must COHERE — spread (mean distance from the
	# centroid) shrinks vs the uniform start — AND keep moving. A merely scattered
	# field can't pass the spread test, unlike a loose "within the field" bound.
	if avg_speed < 0.1 or final_spread >= initial_spread * 0.85:
		print(
			(
				"  FAIL: crowd not gathering (speed %.2f, spread %.1f -> %.1f)"
				% [avg_speed, initial_spread, final_spread]
			)
		)
		return false

	print(
		(
			"  OK: %d agents, speed %.2f m/s, spread %.1f->%.1f, goal-dist %.1f"
			% [demo.agent_count, avg_speed, initial_spread, final_spread, avg_goal_dist]
		)
	)
	return true


## Mean distance of the agents from their centroid — a scatter metric. Large for
## a uniform field, small for a clustered (gathered/flocked) crowd.
func _crowd_spread(points: PackedVector2Array) -> float:
	var n := points.size()
	if n == 0:
		return 0.0
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(n)
	var spread := 0.0
	for p in points:
		spread += p.distance_to(centroid)
	return spread / float(n)
