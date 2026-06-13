extends RefCounted
## Functional guards for Pier — the bay fishing pier. Pure construction, runs
## headless via populate(). Guards the deck, the pilings (grouped under a Pilings
## node, dropping below the waterline), and the lit lamps are built, and that
## populate is idempotent.


func _pier() -> Pier:
	var p := Pier.new()
	p.populate()
	return p


func test_builds_pilings_into_the_water() -> bool:
	var pier := _pier()
	var pilings := pier.get_node("Pilings")
	var ok := pilings.get_child_count() >= 12
	for piling in pilings.get_children():
		# Pilings must reach below the waterline (y < 0).
		if (piling as Node3D).position.y >= 0.0:
			ok = false
	pier.free()
	return ok


func test_has_a_deck() -> bool:
	var pier := _pier()
	var has_deck := pier.has_node("Deck")
	pier.free()
	return has_deck


func test_has_lit_lamps() -> bool:
	var pier := _pier()
	var lit := false
	for lamp in pier.get_node("Lamps").get_children():
		var mat := (lamp as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			lit = true
	pier.free()
	return lit


func test_populate_is_idempotent() -> bool:
	var pier := Pier.new()
	var first := pier.populate()
	var children_after_first := pier.get_child_count()
	var second := pier.populate()
	var children_after_second := pier.get_child_count()
	pier.free()
	return first == second and children_after_first == children_after_second
