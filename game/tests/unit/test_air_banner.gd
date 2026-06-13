extends RefCounted
## Functional guards for AirBanner — the satirical beach banner-tow plane. Pure
## time-driven flight, so populate()/_apply run headless. Guards the plane is
## built, circles over time, tows a banner, and carries a real ad string (the
## joke must actually be on the banner).


func test_builds_requested_count() -> bool:
	var banner := AirBanner.new()
	banner.count = 2
	banner.populate()
	var made := banner.get_child_count()
	banner.free()
	return made == 2


func test_plane_circles_over_time() -> bool:
	var banner := AirBanner.new()
	banner.count = 1
	banner.radius = 400.0
	banner.populate()
	banner._apply(0.0)
	var before: Vector3 = (banner.get_child(0) as Node3D).position
	banner._apply(12.0)
	var after: Vector3 = (banner.get_child(0) as Node3D).position
	banner.free()
	return before.distance_to(after) > 5.0


func test_plane_tows_a_banner() -> bool:
	var banner := AirBanner.new()
	banner.populate()
	var has_banner := (banner.get_child(0) as Node3D).has_node("Banner")
	banner.free()
	return has_banner


func test_banner_carries_an_ad() -> bool:
	var banner := AirBanner.new()
	banner.populate()
	var found := ""
	var towed := (banner.get_child(0) as Node3D).get_node("Banner")
	for child in towed.get_children():
		if child is Label3D:
			found = (child as Label3D).text
	banner.free()
	return found != "" and AirBanner.ADS.has(found)
