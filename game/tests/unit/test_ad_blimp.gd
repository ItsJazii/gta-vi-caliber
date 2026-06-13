extends RefCounted
## Functional guards for AdBlimp — the advertising blimp. Pure time-driven drift,
## runs headless. Guards the hull + flank ad are built, it drifts and stays at
## altitude, carries a parody ad, and populate is idempotent.


func test_builds_hull_and_ad() -> bool:
	var blimp := AdBlimp.new()
	blimp.populate()
	var ok := blimp.has_node("Hull") and blimp.has_node("Ad")
	blimp.free()
	return ok


func test_drifts_at_altitude() -> bool:
	var blimp := AdBlimp.new()
	blimp.populate()
	blimp._apply(0.0)
	var a := blimp.position
	blimp._apply(20.0)
	var b := blimp.position
	# Moved horizontally, and stayed well up in the sky.
	var moved := Vector2(a.x - b.x, a.z - b.z).length() > 5.0
	var high := a.y > 100.0 and b.y > 100.0
	blimp.free()
	return moved and high


func test_carries_a_parody_ad() -> bool:
	var blimp := AdBlimp.new()
	blimp.populate()
	var ad := blimp.get_node("Ad") as Label3D
	var ok := AdBlimp.ADS.has(ad.text)
	blimp.free()
	return ok


func test_populate_is_idempotent() -> bool:
	var blimp := AdBlimp.new()
	var first := blimp.populate()
	var second := blimp.populate()
	blimp.free()
	return first == second and first > 0
