extends RefCounted
## Functional guards for NeonStrip — the Ocean Drive Art-Deco hotels. Pure
## construction, runs headless via populate(). Guards the row is built, each
## building has its neon roofline + lit windows + named marquee, and populate
## is idempotent.


func test_builds_requested_count() -> bool:
	var strip := NeonStrip.new()
	strip.count = 6
	var n := strip.populate()
	var made := strip.get_child_count()
	strip.free()
	return n == 6 and made == 6


func test_each_building_has_neon_windows_and_marquee() -> bool:
	var strip := NeonStrip.new()
	strip.populate()
	var ok := true
	for b in strip.get_children():
		var node := b as Node3D
		if not (
			node.has_node("NeonRoofline") and node.has_node("Windows") and node.has_node("Marquee")
		):
			ok = false
	strip.free()
	return ok


func test_marquee_names_from_pool() -> bool:
	var strip := NeonStrip.new()
	strip.populate()
	var ok := true
	for b in strip.get_children():
		var label := (b as Node3D).get_node("Marquee") as Label3D
		if not NeonStrip.NAMES.has(label.text):
			ok = false
	strip.free()
	return ok


func test_populate_is_idempotent() -> bool:
	var strip := NeonStrip.new()
	var first := strip.populate()
	var second := strip.populate()
	var made := strip.get_child_count()
	strip.free()
	return first == second and made == first
