extends RefCounted
## Unit tests for CinematicEnvironment — the premium lighting preset has the
## headline features (GI, screen-space reflections, bloom, volumetrics, filmic
## tonemap, sky) switched on, and enhance() upgrades an env in place.


func test_builds_an_environment() -> bool:
	return CinematicEnvironment.build() is Environment


func test_global_illumination_and_ao_on() -> bool:
	var e := CinematicEnvironment.build()
	return e.sdfgi_enabled and e.ssao_enabled and e.ssil_enabled


func test_screen_space_reflections_on() -> bool:
	# Glass curtain-walls need SSR to mirror the street/sky.
	return CinematicEnvironment.build().ssr_enabled


func test_bloom_and_volumetric_fog_on() -> bool:
	var e := CinematicEnvironment.build()
	return e.glow_enabled and e.volumetric_fog_enabled


func test_filmic_tonemap_and_grade() -> bool:
	var e := CinematicEnvironment.build()
	return e.tonemap_mode == Environment.TONE_MAPPER_ACES and e.adjustment_enabled


func test_has_a_sky() -> bool:
	return CinematicEnvironment.build().sky != null


func test_enhance_upgrades_in_place_without_forcing_gi() -> bool:
	# enhance() defaults to no SDFGI (streamed world) but still adds SSR + AO so
	# the live scene keeps its own sky while gaining the reflections/grade.
	var base := Environment.new()
	var e := CinematicEnvironment.enhance(base)
	return e == base and e.ssr_enabled and e.ssao_enabled and not e.sdfgi_enabled


func test_quality_low_is_cheap_but_not_flat() -> bool:
	# LOW must kill the flat look (ACES + grade + bloom) yet pay for none of the
	# screen-space / GI passes — the always-affordable gameplay floor.
	var e := CinematicEnvironment.apply_quality(Environment.new(), CinematicEnvironment.Quality.LOW)
	var graded := (
		e.tonemap_mode == Environment.TONE_MAPPER_ACES and e.glow_enabled and e.adjustment_enabled
	)
	var cheap := (
		not e.ssao_enabled
		and not e.ssr_enabled
		and not e.ssil_enabled
		and not e.volumetric_fog_enabled
		and not e.sdfgi_enabled
	)
	return graded and cheap


func test_quality_medium_adds_screenspace_only() -> bool:
	# MEDIUM (the default) buys SSAO + SSR but still withholds the GI pair that
	# tanks FPS on weaker GPUs.
	var e := CinematicEnvironment.apply_quality(
		Environment.new(), CinematicEnvironment.Quality.MEDIUM
	)
	return e.ssao_enabled and e.ssr_enabled and not e.ssil_enabled and not e.sdfgi_enabled


func test_quality_high_adds_indirect_and_volumetric() -> bool:
	var e := CinematicEnvironment.apply_quality(
		Environment.new(), CinematicEnvironment.Quality.HIGH
	)
	return e.ssil_enabled and e.volumetric_fog_enabled and not e.sdfgi_enabled


func test_quality_ultra_enables_gi() -> bool:
	var e := CinematicEnvironment.apply_quality(
		Environment.new(), CinematicEnvironment.Quality.ULTRA
	)
	return e.sdfgi_enabled and e.ssil_enabled and e.ssr_enabled and e.ssao_enabled


func test_apply_quality_is_idempotent_lowering_tier() -> bool:
	# Re-applying a lower tier must switch the heavies back off (not leave them
	# latched), so a runtime quality change can't strand SDFGI on.
	var e := Environment.new()
	CinematicEnvironment.apply_quality(e, CinematicEnvironment.Quality.ULTRA)
	CinematicEnvironment.apply_quality(e, CinematicEnvironment.Quality.LOW)
	return not e.sdfgi_enabled and not e.ssil_enabled and not e.ssr_enabled and not e.ssao_enabled


func test_apply_quality_preserves_existing_sky() -> bool:
	# The gameplay scene owns its day/night sky; apply_quality must not replace it.
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	e.sky = sky
	CinematicEnvironment.apply_quality(e, CinematicEnvironment.Quality.MEDIUM)
	return e.sky == sky and e.background_mode == Environment.BG_SKY
