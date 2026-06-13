class_name CinematicEnvironment
extends RefCounted
## Builds a premium, cinematic Environment any scene can adopt for trailer-grade
## lighting: real-time global illumination (SDFGI) for bounced light, screen-space
## AO + indirect light + reflections (so glass curtain-walls mirror the sky and
## the street), volumetric fog for atmosphere, ACES tonemapping, tasteful bloom,
## and a subtle contrast/saturation grade.
##
## `build()` returns a fully-configured resource for offline/hero renders.
## `enhance(env, with_gi)` upgrades a scene's *existing* Environment in place —
## keeping its own day/night sky — which is what live world scenes use so the
## SkyController/DayNight horizon tinting keeps working. Pure + unit-tested in
## tests/unit/test_cinematic_environment.gd.
##
## `apply_quality(env, tier)` is the perf-gated variant the *gameplay* scene
## uses: the near-free grade (ACES + sky ambient + bloom + aerial fog) is always
## on so the scene never looks flat, while the costly passes layer in by tier —
## SSAO/SSR at MEDIUM, SSIL + volumetric fog at HIGH, SDFGI at ULTRA. This is the
## clean hook the LOOP_HANDOFF lighting note asked for: the premium look reaches
## the player without forcing the 120→54 FPS GI hit on every GPU.

## GPU-budget tiers, cheapest → richest. Each tier is a superset of the one
## below it (see apply_quality). Ordering matters — code compares with `>=`.
enum Quality { LOW, MEDIUM, HIGH, ULTRA }


## Apply the premium grade/AO/reflections/bloom/fog to an existing Environment,
## preserving its sky and background. `with_gi` adds SDFGI (expensive — reserve
## for static hero scenes, not the streamed world where it flickers as districts
## page in). Returns the same env for chaining.
static func enhance(env: Environment, with_gi: bool = false) -> Environment:
	if env == null:
		env = Environment.new()

	# Sky-sourced ambient gives image-based lighting: metallic glass reflects the
	# sky even before SSR contributes on-screen bounces.
	if env.background_mode == Environment.BG_CLEAR_COLOR:
		env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic/ACES tonemapping keeps highlights from clipping to flat white.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0

	# Contact AO between buildings/ground + indirect colour bleed.
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 2.2
	env.ssao_power = 1.5
	env.ssil_enabled = true

	# Screen-space reflections: the headline glass-curtain-wall realism cue —
	# towers mirror the street and neighbouring buildings.
	env.ssr_enabled = true
	env.ssr_max_steps = 24
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# Bloom for emissive windows/streetlights at night and bright sky highlights.
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.1

	# Aerial-perspective depth fog down the avenues (cheap; volumetric below adds
	# god-ray-able density). Kept light so it reads as distance, not soup.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.74, 0.79, 0.86)
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.2
	env.fog_aerial_perspective = 0.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.001
	env.volumetric_fog_albedo = Color(0.82, 0.86, 0.92)

	# A gentle cinematic grade — a touch more contrast and saturation.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.14
	env.adjustment_brightness = 1.01

	# Real-time GI: bounced light, ambient occlusion and colour bleed.
	env.sdfgi_enabled = with_gi
	if with_gi:
		env.sdfgi_bounce_feedback = 0.5

	return env


static func build() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = _premium_sky()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	return enhance(env, true)


## A tuned daytime ProceduralSkyMaterial: deep blue zenith, warm hazy horizon,
## a soft sun disk. Live world scenes override the horizon tint per time-of-day.
static func _premium_sky() -> ProceduralSkyMaterial:
	var m := ProceduralSkyMaterial.new()
	m.sky_top_color = Color(0.16, 0.33, 0.62)
	m.sky_horizon_color = Color(0.78, 0.80, 0.81)
	m.sky_curve = 0.12
	m.sky_energy_multiplier = 1.1
	m.ground_horizon_color = Color(0.74, 0.74, 0.72)
	m.ground_bottom_color = Color(0.42, 0.42, 0.40)
	m.sun_angle_max = 12.0
	m.sun_curve = 0.08
	return m


## Perf-gated grade for the live gameplay scene. Always applies the near-free
## look (sky-sourced ambient/reflections, ACES tonemap, bloom, cinematic grade,
## light aerial fog) so the scene never reads flat; then layers the costly
## screen-space / GI passes by `tier`. Preserves the env's own sky/background.
## Idempotent — the tier-gated heavies are reset first, so re-applying with a
## lower tier turns them back off. Returns the same env for chaining.
static func apply_quality(env: Environment, tier: int = Quality.MEDIUM) -> Environment:
	if env == null:
		env = Environment.new()

	var had_glow := env.glow_enabled
	var had_fog := env.fog_enabled
	var had_volumetric := env.volumetric_fog_enabled
	var had_adjustment := env.adjustment_enabled
	var authored_ambient_energy := env.ambient_light_energy
	var authored_tonemap_exposure := env.tonemap_exposure
	var authored_tonemap_white := env.tonemap_white
	var authored_adjustment_contrast := env.adjustment_contrast
	var authored_adjustment_saturation := env.adjustment_saturation
	var authored_adjustment_brightness := env.adjustment_brightness
	var authored_fog_color := env.fog_light_color
	# Captured before any write: assigning fog_mode below resets fog_density
	# to 1.0 inside the engine setter (even re-assigning the current mode), so
	# reading env.fog_density after it preserves the clobber, not the author.
	var authored_fog_density := env.fog_density
	var authored_fog_aerial_perspective := env.fog_aerial_perspective
	var authored_volumetric_albedo := env.volumetric_fog_albedo
	var authored_volumetric_density := env.volumetric_fog_density
	var authored_volumetric_emission := env.volumetric_fog_emission
	# Preserve authored performance-sensitive settings so the scene file can
	# set conservative defaults (e.g. lower ssr_max_steps) without being
	# clobbered by the tier-gated apply.
	var authored_ssr_max_steps := env.ssr_max_steps
	var authored_glow_intensity := env.glow_intensity
	var authored_glow_bloom := env.glow_bloom

	# --- always-on, ~free: image-based ambient + filmic grade + bloom --------
	if env.background_mode == Environment.BG_CLEAR_COLOR:
		env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = authored_ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = maxf(authored_tonemap_white, 6.0)
	env.tonemap_exposure = authored_tonemap_exposure
	env.glow_enabled = true
	env.glow_intensity = authored_glow_intensity if had_glow else 0.7
	env.glow_bloom = authored_glow_bloom if had_glow else 0.12
	env.glow_hdr_threshold = minf(env.glow_hdr_threshold, 1.1) if had_glow else 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = authored_adjustment_contrast if had_adjustment else 1.08
	env.adjustment_saturation = authored_adjustment_saturation if had_adjustment else 1.14
	env.adjustment_brightness = authored_adjustment_brightness if had_adjustment else 1.01
	# Light exponential fog reads as aerial-perspective depth; effectively free.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = authored_fog_color if had_fog else Color(0.74, 0.79, 0.86)
	env.fog_density = authored_fog_density if had_fog else 0.0008
	env.fog_sky_affect = minf(env.fog_sky_affect, 0.2) if had_fog else 0.2
	env.fog_aerial_perspective = (
		authored_fog_aerial_perspective if had_fog else maxf(env.fog_aerial_perspective, 0.5)
	)

	# Reset the tier-gated heavies so apply_quality is idempotent across tiers.
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.sdfgi_enabled = false

	# --- MEDIUM+: screen-space contact AO + reflections ---------------------
	if tier >= Quality.MEDIUM:
		env.ssao_enabled = true
		env.ssao_radius = 3.0
		env.ssao_intensity = 2.2
		env.ssao_power = 1.5
		env.ssr_enabled = true
		env.ssr_max_steps = mini(authored_ssr_max_steps, 24)
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.2

	# --- HIGH+: indirect light bounce (SSIL) + volumetric atmosphere --------
	if tier >= Quality.HIGH:
		env.ssil_enabled = true
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = (
			authored_volumetric_density
			if had_volumetric
			else maxf(env.volumetric_fog_density, 0.001)
		)
		env.volumetric_fog_length = minf(
			env.volumetric_fog_length if had_volumetric else 450.0, 450.0
		)
		env.volumetric_fog_albedo = (
			authored_volumetric_albedo if had_volumetric else Color(0.82, 0.86, 0.92)
		)
		if had_volumetric:
			env.volumetric_fog_emission = authored_volumetric_emission

	# --- ULTRA: real-time global illumination (SDFGI) ----------------------
	if tier >= Quality.ULTRA:
		env.sdfgi_enabled = true
		env.sdfgi_bounce_feedback = 0.5

	return env


## Resolve the active quality tier. `$GTA_QUALITY` (low|medium|high|ultra) wins
## for quick per-launch overrides; otherwise the optional project setting
## `rendering/quality_tier` (int 0–3); otherwise MEDIUM — the safe default that
## ships SSAO/SSR but holds back the GI pair that tanks FPS on weaker GPUs.
static func resolved_tier() -> int:
	match OS.get_environment("GTA_QUALITY").strip_edges().to_lower():
		"low":
			return Quality.LOW
		"medium":
			return Quality.MEDIUM
		"high":
			return Quality.HIGH
		"ultra":
			return Quality.ULTRA
	if ProjectSettings.has_setting("rendering/quality_tier"):
		return clampi(
			int(ProjectSettings.get_setting("rendering/quality_tier")), Quality.LOW, Quality.ULTRA
		)
	return Quality.MEDIUM
