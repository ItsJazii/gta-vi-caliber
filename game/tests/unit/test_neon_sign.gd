extends RefCounted
## Functional guards for NeonSign — the glowing Vice City gateway. Pure
## construction, runs headless via populate(). Guards the panel + emissive neon
## border + headline/tagline text are built, and that populate is idempotent.


func _sign() -> NeonSign:
	var s := NeonSign.new()
	s.populate()
	return s


func test_builds_panel_and_border_and_text() -> bool:
	var sign := _sign()
	var ok := sign.has_node("Panel") and sign.has_node("NeonBorder")
	ok = ok and sign.has_node("Headline") and sign.has_node("Tagline")
	sign.free()
	return ok


func test_border_tubes_are_emissive() -> bool:
	var sign := _sign()
	var any_emissive := false
	for tube in sign.get_node("NeonBorder").get_children():
		var mat := (tube as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			any_emissive = true
	sign.free()
	return any_emissive


func test_headline_text_matches() -> bool:
	var sign := NeonSign.new()
	sign.headline = "OCEAN DRIVE"
	sign.tagline = "· EST. 1986 ·"
	sign.populate()
	var head := sign.get_node("Headline") as Label3D
	var tag := sign.get_node("Tagline") as Label3D
	var ok := head.text == "OCEAN DRIVE" and tag.text == "· EST. 1986 ·"
	sign.free()
	return ok


func test_populate_is_idempotent() -> bool:
	var sign := NeonSign.new()
	var first := sign.populate()
	var second := sign.populate()
	sign.free()
	return first == second and first > 0
