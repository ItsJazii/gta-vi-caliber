shader_type spatial;
render_mode cull_disabled;
// Procedural building facades — no textures. Mesh-LOCAL position drives the
// window grid (stable under FloatingOrigin shifts, unlike world space). Per
// building, vertex COLOR.rgb carries the wall tone and COLOR.a a "glassiness"
// seed (tall buildings high, short low) set by DistrictLoader from
// CityBuilder.building_glass_seed. Two facade modes are mixed per building so a
// block reads as a real mixed-era streetscape, not one extruded material:
//   * GLASS CURTAIN WALL  — reflective coated glass + opaque spandrel + mullions
//   * MASONRY / PUNCHED   — warm walls with recessed punched windows
// Both get a ground-floor storefront band and a hashed set of night-lit windows.

// Day->night driver for window emission (0 = full daylight, 1 = full night).
// SkyController feeds the world_night_amount global; night_mix is a per-material
// manual override for demos/tests. The larger wins.
global uniform float world_night_amount;
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;
// Storey height, metres (downtown mid/high-rise rhythm).
uniform float floor_height = 3.2;
// Horizontal distance between punched-window bay centres, metres.
uniform float window_step = 2.7;
// Tileable CC0 stucco albedo — real troweled-plaster breakup blended over the
// procedural masonry fill at close range. White default = neutral (greybox
// fallback and tests behave identically without the texture).
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_pos; // mesh-local position
varying vec3 v_nrm; // mesh-local normal (flat per wall face)
varying vec3 v_tint; // per-building wall colour from vertex COLOR.rgb
varying float v_glass; // per-building glassiness seed from vertex COLOR.a

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.77));
	p += dot(p, p + 41.23);
	return fract(p.x * p.y);
}

// Smooth value noise (bilinear-interpolated hash with a smoothstep fade) — C1
// enough that screen-space derivatives stay clean for bump mapping.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
	v_tint = COLOR.rgb;
	v_glass = COLOR.a;
}

void fragment() {
	// Roof faces point up; walls are vertical.
	float wall = 1.0 - smoothstep(0.55, 0.8, abs(v_nrm.y));

	// Facade-plane coordinates: u runs along the wall, v is height above base.
	vec3 tang = normalize(vec3(-v_nrm.z, 0.0, v_nrm.x) + vec3(1e-4, 0.0, 0.0));
	float u = dot(v_pos, tang);
	float v = v_pos.y;
	// Per-face seed so parallel/opposite facades don't mirror each other.
	float fseed = dot(round(v_nrm.xz * 4.0), vec2(17.0, 59.0)) + v_tint.r * 91.0;

	// Glass curtain-wall towers when the packed seed is high (tall buildings);
	// masonry otherwise. Soft edge so the transition band isn't a hard cutoff.
	float is_glass = smoothstep(0.46, 0.60, v_glass);

	// ======================================================================
	//  MASONRY / PUNCHED-WINDOW WALL
	// ======================================================================
	vec2 mcell = vec2(floor(u / window_step), floor(v / floor_height));
	vec2 mf = vec2(fract(u / window_step), fract(v / floor_height));
	float mr = hash21(mcell + fseed);
	float mwx = smoothstep(0.30, 0.35, mf.x) * (1.0 - smoothstep(0.73, 0.78, mf.x));
	float mwy = smoothstep(0.28, 0.33, mf.y) * (1.0 - smoothstep(0.76, 0.81, mf.y));
	float mwin = mwx * mwy * wall * step(0.12, mr);

	// Weathering: low-frequency tone patches, storey ledges, ground grime, and
	// faint vertical rain streaks under the window line.
	// Light weathering only — Art-Deco stucco reads as clean pastel, so keep
	// tone patches/grime subtle or the vivid palette muddies to grey.
	float patch = (hash21(floor(vec2(u, v) * 0.45) + fseed * 0.7) - 0.5) * 0.07;
	float streak = (hash21(vec2(floor(u * 0.7), 0.0) + fseed) - 0.5) * 0.035;
	float ledge = 1.0 - 0.16 * (1.0 - smoothstep(0.0, 0.07, mf.y)) * wall;
	float grime = 1.0 - 0.13 * (1.0 - smoothstep(0.0, 2.6, v));
	vec3 mwall_col = (v_tint + vec3(patch + streak)) * ledge * grime;
	float mgl = 0.6 + 0.7 * hash21(mcell + vec2(fseed + 11.0));
	float mrecess = 1.0 - 0.45 * smoothstep(0.45, 0.78, mf.y);
	vec3 mglass_col = vec3(0.10, 0.12, 0.15) * mgl * mrecess;
	vec3 m_albedo = mix(mwall_col, mglass_col, mwin);
	float m_rough = mix(0.78 + 0.18 * hash21(mcell - vec2(fseed)), 0.14, mwin);
	float m_metal = 0.0;
	float m_spec = mix(0.4, 0.6, mwin);

	// ======================================================================
	//  GLASS CURTAIN WALL
	//  Tight mullion grid; each storey = vision glass (upper) over an opaque
	//  spandrel band (lower). Vision glass is metallic + smooth so it reflects
	//  the sky radiance and on-screen geometry (SSR) like real coated glass.
	// ======================================================================
	float gstep = 1.7; // mullion bay width (m)
	vec2 gcell = vec2(floor(u / gstep), floor(v / floor_height));
	vec2 gf = vec2(fract(u / gstep), fract(v / floor_height));
	float mull = (1.0 - smoothstep(0.06, 0.13, gf.x)) + (1.0 - smoothstep(0.06, 0.13, 1.0 - gf.x))
		+ (1.0 - smoothstep(0.05, 0.11, gf.y)) + (1.0 - smoothstep(0.05, 0.11, 1.0 - gf.y));
	mull = clamp(mull, 0.0, 1.0);
	float spandrel = 1.0 - smoothstep(0.30, 0.36, gf.y); // lower 32% opaque panel
	// Per-building glass hue: blue / sea-green / bronze coated glass.
	float hue = hash21(vec2(round(v_tint.g * 97.0), round(v_tint.b * 61.0)));
	vec3 g_blue = vec3(0.52, 0.62, 0.72);
	vec3 g_green = vec3(0.46, 0.62, 0.56);
	vec3 g_bronze = vec3(0.60, 0.50, 0.36);
	vec3 gtint = hue < 0.4 ? g_blue : (hue < 0.75 ? g_green : g_bronze);
	float gpv = 0.85 + 0.30 * hash21(gcell + vec2(fseed + 11.0)); // panel variance
	vec3 vision_col = gtint * gpv;
	vec3 spandrel_col = gtint * 0.32;
	vec3 mullion_col = vec3(0.05, 0.055, 0.06);
	vec3 g_albedo = mix(vision_col, spandrel_col, spandrel);
	float g_metal = mix(0.92, 0.15, spandrel);
	float g_rough = mix(0.08, 0.45, spandrel);
	float g_spec = 0.85;
	g_albedo = mix(g_albedo, mullion_col, mull);
	g_metal = mix(g_metal, 0.5, mull);
	g_rough = mix(g_rough, 0.5, mull);

	// ======================================================================
	//  Blend the two wall classes, then lay a ground-floor storefront over them.
	// ======================================================================
	vec3 wall_albedo = mix(m_albedo, g_albedo, is_glass);
	float wall_rough = mix(m_rough, g_rough, is_glass);
	float wall_metal = mix(m_metal, g_metal, is_glass);
	float wall_spec = mix(m_spec, g_spec, is_glass);

	// Strong readable facade relief at gameplay distance: the old pastel wall
	// fill collapsed into one tan slab in the default camera. Keep the Art-Deco
	// colour, but cut it with visible mullion/storey grid and cooler shadow glass.
	float bay_grid = (
		1.0 - smoothstep(0.035, 0.075, min(fract(u / window_step), 1.0 - fract(u / window_step)))
	);
	float floor_grid = (
		1.0 - smoothstep(0.025, 0.065, min(fract(v / floor_height), 1.0 - fract(v / floor_height)))
	);
	float readable_grid = clamp((bay_grid + floor_grid) * wall, 0.0, 1.0);
	wall_albedo = mix(wall_albedo, wall_albedo * vec3(0.62, 0.68, 0.76), wall * 0.22);
	wall_albedo = mix(wall_albedo, vec3(0.035, 0.045, 0.055), readable_grid * 0.72);
	wall_rough = mix(wall_rough, 0.42, readable_grid);

	// Storefront band: bottom ~5 m gets tall dark glass with wide mullion bays.
	float ground = (1.0 - smoothstep(4.0, 5.2, v)) * wall;
	float sf_frame = 1.0 - smoothstep(0.0, 0.16, fract(u / 3.4));
	wall_albedo = mix(wall_albedo, vec3(0.07, 0.08, 0.10), ground * 0.85);
	wall_albedo = mix(wall_albedo, vec3(0.03, 0.03, 0.035), ground * sf_frame);
	wall_rough = mix(wall_rough, 0.12, ground * 0.7);
	wall_metal = mix(wall_metal, 0.5, ground * 0.5);

	// Art-Deco belt course: a crisp pale trim band capping the storefront level,
	// a near-universal South Beach Deco cue. Masonry only (glass towers skip it).
	float belt = smoothstep(5.0, 5.18, v) * (1.0 - smoothstep(5.5, 5.7, v)) * wall * (1.0 - is_glass);
	wall_albedo = mix(wall_albedo, vec3(0.97, 0.95, 0.90), belt * 0.85);
	wall_rough = mix(wall_rough, 0.55, belt);
	wall_metal = mix(wall_metal, 0.0, belt);

	// Roof: darker gravel-toned version of the wall colour.
	float roof_n = (hash21(floor(v_pos.xz * 0.8)) - 0.5) * 0.06;
	vec3 roof_col = v_tint * 0.45 + vec3(roof_n);

	ALBEDO = mix(roof_col, wall_albedo, wall);
	ROUGHNESS = mix(0.95, wall_rough, wall);
	METALLIC = wall_metal * wall;
	SPECULAR = mix(0.3, wall_spec, wall);

	// ----------------------------------------------------------------------
	//  Stucco micro-surface: fine troweled-plaster grain on masonry walls. A
	//  smooth value-noise height drives a TANGENT-FREE normal perturbation
	//  (Mikkelsen screen-space surface gradient — the city meshes carry no
	//  tangents) plus roughness/albedo break-up, so the flat pastel fills read
	//  as painted stucco instead of plastic. Glass curtain-wall skips it.
	// Grain is only legible up close; fade it out with view distance so far
	// walls don't shimmer/alias (the screen-space derivative gets noisy there).
	float grain_fade = 1.0 - smoothstep(6.0, 18.0, length(VERTEX));
	float stucco = wall * (1.0 - is_glass) * grain_fade;
	if (stucco > 0.001) {
		// CC0 stucco detail map: luminance-modulates the wall fill (keeps the
		// per-building pastel hue) and roughens with the plaster height. Same
		// distance fade as the procedural grain so far walls stay stable.
		vec3 detail = texture(detail_tex, vec2(u, v) * 0.55).rgb;
		float dlum = dot(detail, vec3(0.3333));
		float wall_area = stucco * (1.0 - mwin) * (1.0 - ground);
		ALBEDO *= mix(1.0, clamp(0.82 + dlum * 0.36, 0.82, 1.18), wall_area);
		ROUGHNESS = clamp(ROUGHNESS + (dlum - 0.5) * 0.12 * wall_area, 0.1, 1.0);

		vec2 st = vec2(u, v) * 13.0;
		float h = vnoise(st) * 0.6 + vnoise(st * 2.6) * 0.3;
		vec3 sx = dFdx(VERTEX);
		vec3 sy = dFdy(VERTEX);
		vec3 r1 = cross(sy, NORMAL);
		vec3 r2 = cross(NORMAL, sx);
		float det = dot(sx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - (0.03 * stucco) * grad);
		ROUGHNESS = clamp(ROUGHNESS + (h - 0.45) * 0.10 * stucco, 0.18, 1.0);
		ALBEDO *= 1.0 + (h - 0.45) * 0.05 * stucco;
	}

	// ======================================================================
	//  Night life: a hashed subset of windows lights up. Punched windows on
	//  masonry, vision panes on glass, plus warm storefront glow at street level.
	// ======================================================================
	float night = max(night_mix, world_night_amount);
	float mlit = step(0.62, hash21(mcell + vec2(fseed + 47.0))) * mwin;
	float gpane = (1.0 - spandrel) * (1.0 - mull) * wall;
	float glit = step(0.55, hash21(gcell + vec2(fseed + 47.0))) * gpane;
	float lit = mix(mlit, glit, is_glass);
	vec3 lamp = mix(vec3(1.0, 0.82, 0.55), vec3(0.95, 0.93, 0.85), hash21(mcell + vec2(3.0)));
	float sflit = ground * (1.0 - sf_frame) * wall;
	vec3 emis = lamp * lit * (1.2 + 1.6 * hash21(mcell + vec2(fseed + 5.0)))
		+ vec3(1.0, 0.86, 0.6) * sflit * 1.6;

	// Neon signage: a vivid emissive sign band over the storefront on a hashed
	// subset of (commercial) buildings, broken into per-bay signs. The Vice City
	// night colour identity; blooms through the environment glow at dusk/night.
	float commercial = step(0.42, hash21(vec2(round(v_tint.b * 53.0), round(v_tint.r * 37.0))));
	float nband = smoothstep(4.25, 4.4, v) * (1.0 - smoothstep(4.9, 5.05, v)) * wall;
	float nbay = fract(u / 4.2);
	float nseg = smoothstep(0.12, 0.17, nbay) * (1.0 - smoothstep(0.83, 0.88, nbay));
	float nhue = hash21(vec2(round(v_tint.r * 61.0), round(v_tint.g * 43.0)));
	vec3 neon = nhue < 0.25
		? vec3(1.0, 0.13, 0.6)  // hot pink
		: (
			nhue < 0.45
			? vec3(0.1, 0.95, 1.0)  // cyan
			: (
				nhue < 0.62
				? vec3(0.72, 0.2, 1.0)  // electric violet
				: (nhue < 0.8 ? vec3(1.0, 0.5, 0.1) : vec3(0.3, 1.0, 0.45))  // amber / lime
			)
		);
	emis += neon * (nband * nseg * commercial) * 3.2;
	EMISSION = emis * night;
}
