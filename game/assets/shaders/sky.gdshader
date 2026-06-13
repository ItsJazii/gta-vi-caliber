shader_type sky;

// Physically-based sky for the open world. A single shader carries the whole
// celestial vault — there are no skybox textures in the repo, every pixel is
// computed:
//
//   * Atmosphere   — Rayleigh + Mie single-scattering integrated along the
//                    view ray through a spherical atmosphere (the wwwtyro /
//                    Nishita formulation). Gives true blue-noon → orange-dusk
//                    gradients and a reddened sun near the horizon for free.
//   * Sun disk     — finite angular size with limb darkening, occluded as it
//                    drops below the horizon.
//   * Clouds       — domed FBM layer raymarched toward the sun for self
//                    shadowing, with wind drift and coverage control.
//   * Night        — hashed star field that fades in as the sun sets, plus a
//                    softly lit moon opposite the sun.
//
// SkyController feeds `sun_direction` / `sun_energy` every frame from SkyModel
// so the look stays locked to the day/night cycle and the DirectionalLight.

// --- celestial drivers (set by SkyController from SkyModel) -------------------
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // unit, world-space, points TO the sun
uniform float sun_energy = 1.0; // overall daylight scale (0 at night)
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0); // unit, opposite-ish the sun
uniform float night_amount : hint_range(0.0, 1.0) = 0.0; // 0 day .. 1 deep night

// --- atmosphere ---------------------------------------------------------------
uniform float rayleigh_strength : hint_range(0.0, 4.0) = 1.0;
uniform float mie_strength : hint_range(0.0, 4.0) = 1.0;
uniform float mie_eccentricity : hint_range(-0.99, 0.99) = 0.76; // forward-scatter halo
uniform float sun_intensity : hint_range(1.0, 64.0) = 22.0;
uniform float exposure : hint_range(0.1, 4.0) = 1.1;

// --- sun disk -----------------------------------------------------------------
uniform float sun_angular_size : hint_range(0.2, 6.0) = 1.2; // degrees
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.95, 0.86);

// --- clouds -------------------------------------------------------------------
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.46;
// Storm weight from the WeatherController (WeatherState.sky_storm_darkness):
// darkens the cloud deck toward charcoal, mutes the sun disk and dims the
// whole vault as a front builds. 0 = fair weather.
uniform float storm_darkness : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_density : hint_range(0.0, 4.0) = 1.3;
uniform float cloud_height = 1200.0;
uniform float cloud_scale = 0.00055;
uniform vec2 cloud_wind = vec2(0.012, 0.006);
uniform vec3 cloud_base_color : source_color = vec3(0.62, 0.66, 0.72);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.98, 0.94);

// --- night --------------------------------------------------------------------
uniform float star_density : hint_range(0.0, 1.0) = 0.16;
uniform vec3 night_zenith : source_color = vec3(0.012, 0.016, 0.035);
uniform vec3 moon_color : source_color = vec3(0.85, 0.88, 0.95);

// PI is a built-in constant in Godot's shading language — no redefinition here.

// Earth-scale atmosphere constants (metres). Camera sits just above sea level.
const float R_PLANET = 6371000.0;
const float R_ATMOS = 6471000.0;
const vec3 RAYLEIGH_COEFF = vec3(5.5e-6, 13.0e-6, 22.4e-6); // per-channel scatter
const float MIE_COEFF = 21e-6;
const float RAYLEIGH_SCALE_H = 8000.0;
const float MIE_SCALE_H = 1200.0;
const int PRIMARY_STEPS = 8;
const int LIGHT_STEPS = 4;

// ---------------------------------------------------------------- noise helpers
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 3; i++) {
		total += value_noise(p * freq) * amp;
		freq *= 2.02;
		amp *= 0.5;
	}
	return total;
}

// Distance the ray (origin r0, dir r) travels before exiting a sphere of radius
// sr centred on the origin. Returns vec2(near, far); x<0 means we start inside.
vec2 ray_sphere(vec3 r0, vec3 r, float sr) {
	float a = dot(r, r);
	float b = 2.0 * dot(r, r0);
	float c = dot(r0, r0) - sr * sr;
	float d = b * b - 4.0 * a * c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	d = sqrt(d);
	return vec2((-b - d) / (2.0 * a), (-b + d) / (2.0 * a));
}

// Nishita-style single-scattering atmosphere. `view` and `sun` are world-space
// unit vectors; returns linear HDR radiance toward the eye.
vec3 atmosphere(vec3 view, vec3 sun) {
	// Skip expensive integration for rays aimed well below the horizon.
	if (view.y < -0.05) {
		return vec3(0.0);
	}
	vec3 origin = vec3(0.0, R_PLANET + 1.0, 0.0);
	vec2 p = ray_sphere(origin, view, R_ATMOS);
	if (p.x > p.y) {
		return vec3(0.0);
	}
	// The camera sits just above the surface, so the near atmosphere root is
	// behind us (negative): start integrating at the camera, not in deep space.
	p.x = max(p.x, 0.0);
	// Only stop early on the ground when the planet is actually hit in FRONT of
	// the camera; a downward ray clips it, an upward ray's roots are behind us.
	vec2 pg = ray_sphere(origin, view, R_PLANET);
	if (pg.x > 0.0) {
		p.y = min(p.y, pg.x);
	}
	float seg = (p.y - p.x) / float(PRIMARY_STEPS);
	float t = p.x;

	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0; // accumulated Rayleigh optical depth
	float od_m = 0.0; // accumulated Mie optical depth

	float mu = dot(view, sun);
	float g = mie_eccentricity;
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu))
		/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));

	for (int i = 0; i < PRIMARY_STEPS; i++) {
		vec3 pos = origin + view * (t + seg * 0.5);
		float h = length(pos) - R_PLANET;
		float hr = exp(-h / RAYLEIGH_SCALE_H) * seg;
		float hm = exp(-h / MIE_SCALE_H) * seg;
		od_r += hr;
		od_m += hm;

		// optical depth along the ray toward the sun (light ray)
		vec2 lp = ray_sphere(pos, sun, R_ATMOS);
		float lseg = lp.y / float(LIGHT_STEPS);
		float lt = 0.0;
		float lod_r = 0.0;
		float lod_m = 0.0;
		bool grounded = false;
		for (int j = 0; j < LIGHT_STEPS; j++) {
			vec3 lpos = pos + sun * (lt + lseg * 0.5);
			float lh = length(lpos) - R_PLANET;
			if (lh < 0.0) {
				grounded = true;
				break;
			}
			lod_r += exp(-lh / RAYLEIGH_SCALE_H) * lseg;
			lod_m += exp(-lh / MIE_SCALE_H) * lseg;
			lt += lseg;
		}
		if (!grounded) {
			vec3 tau = RAYLEIGH_COEFF * rayleigh_strength * (od_r + lod_r)
				+ MIE_COEFF * mie_strength * 1.1 * (od_m + lod_m);
			vec3 atten = exp(-tau);
			sum_r += atten * hr;
			sum_m += atten * hm;
		}
		t += seg;
	}

	vec3 col = sun_intensity * (sum_r * RAYLEIGH_COEFF * rayleigh_strength * phase_r
		+ sum_m * MIE_COEFF * mie_strength * phase_m);
	return col;
}

// Domed cloud layer. The view ray is projected onto a flat sheet at
// `cloud_height`; the projection distance is clamped so the noise doesn't
// smear to infinity (and alias into bands) as the ray nears the horizon.
// Density comes from domain-warped FBM for billowy edges; lighting compares a
// tap toward the sun so sun-facing flanks brighten and shadow sides stay grey.
// Returns cloud colour in .rgb and coverage in .a. All outputs pass through
// min/max so any stray non-finite intermediate is flushed to a sane value.
vec4 clouds(vec3 view, vec3 sun, float day) {
	// Fade in from the horizon; nothing below it.
	float horizon = smoothstep(0.04, 0.30, view.y);
	if (horizon <= 0.0) {
		return vec4(0.0);
	}
	// Project onto the cloud sheet, clamping the horizon stretch.
	float dist = cloud_height / max(view.y, 0.05);
	dist = min(dist, cloud_height * 14.0);
	vec2 uv = view.xz * dist * cloud_scale + cloud_wind * TIME;

	// Two-octave domain warp → rounded, evolving billows instead of streaks.
	vec2 warp = vec2(fbm(uv + vec2(0.0, 0.0)), fbm(uv + vec2(5.2, 1.3)));
	float n = fbm(uv + 1.6 * warp);

	float top = min(cloud_coverage + 0.5, 0.99);
	float density = smoothstep(cloud_coverage, top, n);
	density = clamp(density * cloud_density, 0.0, 1.0) * horizon;
	density = min(max(density, 0.0), 1.0); // flush NaN/Inf to [0,1]
	if (density <= 0.002) {
		return vec4(0.0);
	}

	// Lighting: where the cloud thins toward the sun it reads as lit.
	float ln = fbm(uv + sun.xz * 0.6 + 1.6 * warp);
	float lit = clamp(0.5 + (n - ln) * 2.0, 0.0, 1.0);
	vec3 col = mix(cloud_base_color, cloud_lit_color, lit);

	// Warm the lit flanks when the sun is low; sink to a cool blue at night.
	float warm = 1.0 - clamp(sun.y * 3.0, 0.0, 1.0);
	col = mix(col, col * vec3(1.15, 0.86, 0.62), warm * lit * day);
	col = mix(col * vec3(0.22, 0.27, 0.42), col, day);

	// Storm deck: drag the whole layer toward flat charcoal — lit flanks lose
	// their shine first, so a building front reads heavy before rain falls.
	col = mix(col, col * vec3(0.34, 0.36, 0.40), storm_darkness);

	col = min(max(col, vec3(0.0)), vec3(4.0));
	return vec4(col, density);
}

// Hashed star field for the night sky — sparse bright points on a direction
// grid, twinkling slowly with TIME.
vec3 stars(vec3 view) {
	if (view.y <= 0.0) {
		return vec3(0.0);
	}
	vec2 grid = view.xz / max(view.y, 0.05);
	vec2 cell = floor(grid * 140.0);
	float h = hash12(cell);
	float s = step(1.0 - star_density * 0.06, h);
	float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 100.0);
	float bright = s * tw * smoothstep(0.04, 0.35, view.y);
	float warm = hash12(cell + 7.3);
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.9, 0.75), warm);
	return tint * bright;
}

void sky() {
	vec3 view = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float day = clamp(1.0 - night_amount, 0.0, 1.0);

	// --- atmospheric inscattering --------------------------------------------
	vec3 sky_col = atmosphere(view, sun) * sun_energy;

	// Keep a faint lit atmosphere even after the sun is gone, then sink to a
	// deep night zenith colour as night_amount climbs.
	vec3 night_col = mix(night_zenith * 2.2, night_zenith, smoothstep(0.0, 0.6, view.y));
	sky_col = mix(night_col, sky_col, day);

	// --- stars + moon (night only) -------------------------------------------
	sky_col += stars(view) * night_amount;

	vec3 moon = normalize(moon_direction);
	float md = dot(view, moon);
	float moon_disk = smoothstep(0.9994, 0.99975, md);
	float moon_glow = pow(max(md, 0.0), 1200.0) * 0.4 + pow(max(md, 0.0), 60.0) * 0.04;
	sky_col += (moon_color * moon_disk + moon_color * moon_glow) * night_amount;

	// Overcast dims the whole vault, not just the cloud pixels.
	sky_col *= mix(1.0, 0.55, storm_darkness);

	// --- sun disk -------------------------------------------------------------
	float cos_size = cos(radians(sun_angular_size));
	float sd = dot(view, sun);
	float disk = smoothstep(cos_size, cos_size + 0.0002, sd);
	// limb darkening: dimmer toward the disk edge
	float edge = clamp((sd - cos_size) / max(1.0 - cos_size, 1e-4), 0.0, 1.0);
	float limb = mix(0.55, 1.0, sqrt(edge));
	float above = smoothstep(-0.04, 0.06, sun.y); // fade the disk out below horizon
	// A storm deck swallows the disk — only a pale smear survives full overcast.
	float deck = 1.0 - 0.9 * storm_darkness;
	sky_col += sun_disk_color * disk * limb * sun_intensity * 1.3 * above * day * deck;

	// --- clouds ---------------------------------------------------------------
	vec4 cl = clouds(view, sun, day);
	sky_col = mix(sky_col, cl.rgb, cl.a);

	// --- exposure -> linear HDR ----------------------------------------------
	// Output linear radiance and let the WorldEnvironment's ACES tonemapper do
	// the single, authoritative filmic compression. Previously a second ACES
	// curve was applied here, double-tonemapping the sky into a flat, washed
	// vault and crushing the highlight rolloff on the sun disk and lit cloud
	// flanks.
	sky_col *= exposure;
	// A generous ceiling tames fireflies in the radiance cubemap (the sun disk
	// is intentionally very bright) without clipping the visible HDR range.
	sky_col = clamp(sky_col, vec3(0.0), vec3(60.0));

	COLOR = sky_col;
}
