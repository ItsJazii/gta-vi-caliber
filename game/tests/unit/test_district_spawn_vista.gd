extends RefCounted
## Unit tests for DistrictSpawnVista — the hero corridor at the player spawn must
## carry real, night-only streetlamp light pools so the opening view lights up
## after dusk (and isn't just emissive props).


func test_spawn_vista_builds_streetlamp_light_pools() -> bool:
	var holder := Node3D.new()
	DistrictSpawnVista.build(holder, Vector3.ZERO, 0.0, -0.02)
	var omnis := _omnis(holder)
	var ok := omnis.size() >= 12
	for light in omnis:
		# Shadowless (cheap) and dark until the StreetlightSwitch fades them in.
		if light.shadow_enabled or light.visible or light.light_energy > 0.0:
			ok = false
	holder.free()
	return ok


func test_spawn_vista_has_a_streetlight_switch() -> bool:
	# A StreetlightSwitch must own the lamp fade, or the pools never light up.
	var holder := Node3D.new()
	DistrictSpawnVista.build(holder, Vector3.ZERO, 0.0, -0.02)
	var found := false
	for node in _descendants(holder):
		if node is StreetlightSwitch:
			found = true
	holder.free()
	return found


func _omnis(node: Node) -> Array:
	var out: Array = []
	if node is OmniLight3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_omnis(child))
	return out


func _descendants(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out
