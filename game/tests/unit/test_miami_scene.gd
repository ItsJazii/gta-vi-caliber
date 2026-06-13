extends RefCounted
## Scene composition checks for the current main Florida/Miami map.

const MIAMI_SCENE := preload("res://scenes/world/miami.tscn")


func test_miami_scene_includes_florida_backdrop_and_game_hud() -> bool:
	var packed := MIAMI_SCENE
	if packed == null:
		return false
	var scene := packed.instantiate()
	var ok := scene.has_node("FloridaBackdrop") and scene.has_node("GameHud")
	scene.free()
	return ok


func test_miami_game_hud_contains_full_map() -> bool:
	var packed := MIAMI_SCENE
	if packed == null:
		return false
	var scene := packed.instantiate()
	var hud := scene.get_node("GameHud")
	var ok := hud.has_node("FullMap") and hud.has_node("Minimap")
	scene.free()
	return ok


func test_miami_keeps_cinematic_quality_floor() -> bool:
	# The map now ships a HIGH floor so SSIL (indirect bounce) and volumetric fog
	# are on by default — the authored Environment enables both, and a MEDIUM
	# floor used to silently gate them off at runtime. A capable machine can
	# still resolve ULTRA via $GTA_QUALITY, hence the >= comparison.
	var packed := MIAMI_SCENE
	if packed == null:
		return false
	var scene := packed.instantiate()
	var world_quality := scene.get_node("WorldEnvironment") as WorldQuality
	var ok := (
		world_quality != null and world_quality.minimum_tier >= CinematicEnvironment.Quality.HIGH
	)
	scene.free()
	return ok


func test_miami_render_grade_matches_day_night_sky() -> bool:
	# The grade and the sky are a pair. The old darkened grade (exposure 0.56,
	# brightness 0.82) compensated for the bright static ProceduralSkyMaterial;
	# against the physical day/night sky it rendered noon as dusk. The scene
	# must ship the day/night ShaderMaterial sky together with the neutral
	# grade that sky was tuned for, and a live clock to drive it.
	var packed := MIAMI_SCENE
	if packed == null:
		return false
	var scene := packed.instantiate()
	var world_quality := scene.get_node("WorldEnvironment") as WorldQuality
	var env := world_quality.environment if world_quality != null else null
	var sky_is_day_night := (
		env != null and env.sky != null and env.sky.sky_material is ShaderMaterial
	)
	var clock := scene.get_node_or_null("SkyController")
	var ok := (
		sky_is_day_night
		and env.tonemap_exposure >= 1.0
		and env.adjustment_brightness >= 0.95
		and clock != null
		and clock.is_in_group("sky")
	)
	scene.free()
	return ok
