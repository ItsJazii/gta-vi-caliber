extends RefCounted
## Functional guards for NeonPylon — the animated motel sign. Pure construction
## + time-driven animation, runs headless. Guards the structure is built, the
## border chase actually animates, the VACANCY sub-sign blinks, and populate is
## idempotent.


func _pylon() -> NeonPylon:
	var p := NeonPylon.new()
	p.populate()
	return p


func test_builds_full_structure() -> bool:
	var pylon := _pylon()
	var ok := pylon.has_node("Panel") and pylon.has_node("Border")
	ok = (
		ok
		and pylon.has_node("Headline")
		and pylon.has_node("Subtitle")
		and pylon.has_node("Vacancy")
	)
	ok = ok and pylon.get_node("Border").get_child_count() >= 8
	pylon.free()
	return ok


func test_border_chase_animates() -> bool:
	var pylon := _pylon()
	var seg := pylon.get_node("Border").get_child(0) as MeshInstance3D
	var mat := seg.material_override as StandardMaterial3D
	pylon._process(0.0)
	var e0 := mat.emission_energy_multiplier
	# Advance roughly a quarter chase cycle; the sweep must change this segment.
	pylon._process(0.25)
	var e1 := mat.emission_energy_multiplier
	pylon.free()
	return absf(e0 - e1) > 0.05


func test_vacancy_blinks() -> bool:
	var pylon := _pylon()
	var vac := pylon.get_node("Vacancy") as Node3D
	# Into the "off" window, then into the "on" window of the blink cycle.
	pylon._process(pylon.blink_period * 0.8)
	var off_state := vac.visible
	pylon._process(pylon.blink_period * 0.4)
	var on_state := vac.visible
	pylon.free()
	return off_state != on_state


func test_populate_is_idempotent() -> bool:
	var pylon := NeonPylon.new()
	var first := pylon.populate()
	var second := pylon.populate()
	pylon.free()
	return first == second and first > 0
