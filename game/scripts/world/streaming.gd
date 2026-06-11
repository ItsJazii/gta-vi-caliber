class_name Streaming
extends RefCounted
## Pure residency logic for district streaming: given the camera position and the
## district manifest, decide which districts to load and unload. Hysteresis
## (load_radius < unload_radius) stops a district thrashing on/off at the boundary.
##
## Scene-free so it unit-tests headless (tests/unit/test_streaming.gd). The
## DistrictStreamer node applies the decision by instancing/freeing subtrees.


## districts: Array of {name:String, offset:Vector2 (world x,z)}.
## resident: Dictionary of name -> anything (presence = currently loaded).
## Returns {to_load:Array[String], to_unload:Array[String]}.
static func resolve(
	camera_xz: Vector2,
	districts: Array,
	load_radius: float,
	unload_radius: float,
	resident: Dictionary
) -> Dictionary:
	var to_load: Array[String] = []
	var to_unload: Array[String] = []
	for d in districts:
		var dist := camera_xz.distance_to(d["offset"])
		var is_resident := resident.has(d["name"])
		if not is_resident and dist <= load_radius:
			to_load.append(d["name"])
		elif is_resident and dist > unload_radius:
			to_unload.append(d["name"])
	return {"to_load": to_load, "to_unload": to_unload}
