extends RefCounted
## Functional guards for Searchlights — the sweeping night beams. Pure
## construction + time-driven sweep, runs headless. Guards the lamps are built,
## the beams actually sweep over time, and populate is idempotent.


func _pivots(lights: Searchlights) -> Array:
	# Pivots are the plain Node3D children (bases/lenses are MeshInstance3D).
	var out := []
	for c in lights.get_children():
		if not (c is MeshInstance3D):
			out.append(c)
	return out


func test_builds_requested_lamps() -> bool:
	var lights := Searchlights.new()
	lights.count = 3
	var n := lights.populate()
	# Each lamp adds a base + lens + pivot, and one pivot per lamp.
	var pivots := _pivots(lights).size()
	lights.free()
	return n == 3 and pivots == 3


func test_beams_sweep_over_time() -> bool:
	var lights := Searchlights.new()
	lights.populate()
	lights._apply(0.0)
	var pivot := _pivots(lights)[0] as Node3D
	var a := pivot.rotation.y
	lights._apply(1.5)
	var b := pivot.rotation.y
	lights.free()
	return absf(a - b) > 0.02


func test_beams_tilt_up() -> bool:
	var lights := Searchlights.new()
	lights.populate()
	lights._apply(0.0)
	# Beams lean off vertical (positive tilt) so they rake the sky, not straight up.
	var pivot := _pivots(lights)[0] as Node3D
	var tilts := absf(pivot.rotation.x) > 0.1
	lights.free()
	return tilts


func test_populate_is_idempotent() -> bool:
	var lights := Searchlights.new()
	var first := lights.populate()
	var second := lights.populate()
	lights.free()
	return first == second and first > 0
