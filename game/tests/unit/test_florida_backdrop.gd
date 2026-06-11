extends RefCounted
## Runtime-shape checks for the original Florida backdrop builder.


func test_backdrop_builds_named_premium_layers() -> bool:
	var backdrop := FloridaBackdrop.new()
	backdrop._ready()
	var ok := (
		backdrop.has_node("StateOcean")
		and backdrop.has_node("StateLandmass")
		and backdrop.has_node("SandCoastline")
		and backdrop.has_node("StateCauseways")
		and backdrop.has_node("SignatureBridges")
		and backdrop.has_node("OriginalMarinas")
		and backdrop.has_node("OriginalBeachResorts")
		and backdrop.has_node("OriginalLandmarks")
		and backdrop.has_node("OriginalCityAnchors")
		and backdrop.has_node("WetlandCypressTrunks")
		and backdrop.has_node("WetlandCypressCrowns")
		and backdrop.has_node("StateOceanSwimVolume")
	)
	backdrop.free()
	return ok


func test_backdrop_builds_all_authored_city_labels() -> bool:
	var backdrop := FloridaBackdrop.new()
	backdrop._ready()
	var anchors := backdrop.get_node("OriginalCityAnchors")
	var found := 0
	for city in FloridaMapModel.city_nodes(backdrop.map_scale):
		var label_name := "%sLabel" % String(city["name"]).replace(" ", "")
		if anchors.has_node(label_name):
			found += 1
	backdrop.free()
	return found == FloridaMapModel.CITY_NODES.size()


func test_backdrop_builds_all_authored_landmarks() -> bool:
	var backdrop := FloridaBackdrop.new()
	backdrop._ready()
	var landmarks := backdrop.get_node("OriginalLandmarks")
	var required := ["TorchKeyLight", "SunsetWheel", "AtlasPointLaunch", "GulfGateArch"]
	for node_name in required:
		if not landmarks.has_node(node_name):
			backdrop.free()
			return false
	backdrop.free()
	return true


func test_backdrop_builds_key_hotels() -> bool:
	var backdrop := FloridaBackdrop.new()
	backdrop._ready()
	var resorts := backdrop.get_node("OriginalBeachResorts")
	var hotels := 0
	for child in resorts.get_children():
		if String(child.name).begins_with("KeyHotel"):
			hotels += 1
	backdrop.free()
	return hotels >= FloridaMapModel.KEY_ISLANDS.size()
