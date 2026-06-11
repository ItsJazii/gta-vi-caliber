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
	root.add_child(demo)  # triggers _ready -> spawns agents + wires native

	if not demo.native_active():
		print("  native inactive after setup — skipping (OK)")
		return true

	for _f in 180:  # ~3 s at 60 Hz
		demo.step(1.0 / 60.0)

	var sum_speed := 0.0
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

	if not valid:
		return false

	var avg_speed := sum_speed / float(demo.agent_count)
	if avg_speed < 0.1:
		print("  FAIL: crowd frozen (avg speed %.3f)" % avg_speed)
		return false

	print(
		(
			"  OK: %d agents simulated, avg speed %.2f m/s, all finite + in-bounds"
			% [demo.agent_count, avg_speed]
		)
	)
	return true
