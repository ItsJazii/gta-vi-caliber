extends SceneTree
## Headless probe for the native FlowField demo: loads flow_field_demo.tscn and
## runs the field-following sim, asserting agents actually ROUTE to the goal —
## the crowd's mean distance to the goal collapses — and never end up inside a
## wall (the field steered them around). Skips when the native module is absent.
##
## Run: godot --headless --path game --script res://tests/flow_field_demo_probe.gd


func _initialize() -> void:
	var ok := _run()
	print("flow_field_demo_probe: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _run() -> bool:
	if not ClassDB.class_exists("FlowField"):
		print("  native FlowField absent — skipping (OK)")
		return true

	var packed := load("res://scenes/world/flow_field_demo.tscn")
	if packed == null:
		print("  could not load flow_field_demo.tscn")
		return false
	var demo: FlowFieldDemo = packed.instantiate()
	demo._ready()  # deterministic setup

	if not demo.native_active():
		print("  FAIL: FlowField exists but the demo did not activate it")
		return false

	var goal: Vector2 = demo.goal()
	var initial := _mean_goal_dist(demo, goal)

	# Check walls EVERY frame (the whole path, not just the final pose) so a
	# transient clip through a wall can't slip past the assertion (Codex review).
	var path_clean := true
	for _f in 700:  # ~12 s at 60 Hz — enough to route across the field
		demo.step(1.0 / 60.0)
		if path_clean:
			for i in demo.agent_count:
				if demo.is_wall_at(demo.positions[i]):
					path_clean = false
					break

	var final := _mean_goal_dist(demo, goal)

	# Routing worked if the crowd collapsed toward the goal AND the field kept
	# every agent out of the walls for the entire path.
	if final >= initial * 0.5 or not path_clean:
		print(
			(
				"  FAIL: routing weak (mean goal-dist %.1f -> %.1f, path_clean=%s)"
				% [initial, final, str(path_clean)]
			)
		)
		return false

	print(
		(
			"  OK: %d agents routed to goal (mean dist %.1f -> %.1f), never entered a wall"
			% [demo.agent_count, initial, final]
		)
	)
	return true


func _mean_goal_dist(demo: FlowFieldDemo, goal: Vector2) -> float:
	var sum := 0.0
	for i in demo.agent_count:
		sum += demo.positions[i].distance_to(goal)
	return sum / float(demo.agent_count)
