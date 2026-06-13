shader_type spatial;
render_mode cull_disabled;
// Procedural concrete sidewalk — no textures. Expansion-joint grooves (one
// transverse every panel_len metres, one longitudinal down the walking top), a
// distinct curb-face tint band, and faint patch noise so long runs don't read
// flat. UV: U across the strip (0 at the curb face .. 1 at the outer edge),
// V metres along the centreline — mesh-local, so the pattern is stable under
// FloatingOrigin shifts and streaming.

uniform vec3 concrete_color : source_color = vec3(0.62, 0.60, 0.56);
uniform vec3 joint_color : source_color = vec3(0.40, 0.39, 0.37);
uniform vec3 curb_color : source_color = vec3(0.70, 0.68, 0.64);
// Expansion-joint spacing along the walk, metres.
uniform float panel_len = 1.5;
// Joint groove width, metres.
uniform float joint_w = 0.06;
// U fraction occupied by the vertical curb face (curb_h / (curb_h + walk_width)).
uniform float curb_frac = 0.06;
// Rain wetness published by the WeatherController (0 dry .. 1 soaked): wet
// concrete darkens and gleams, a touch less mirror-like than asphalt.
global uniform float world_wetness;

varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.77));
	p += dot(p, p + 41.23);
	return fract(p.x * p.y);
}

// Smooth value noise (bilinear hash + smoothstep fade) — C1 enough that the
// screen-space derivatives used for the tangent-free bump stay clean.
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

// Without this, v_uv stayed (0,0) and the whole joint/curb/patch pattern below
// collapsed to a flat slab — the mesh carries UVs (CityBuilder.sidewalk_ribbon).
void vertex() {
	v_uv = UV;
}

void fragment() {
	float u = v_uv.x;
	float along = v_uv.y;

	// Low-frequency tonal patches across the slabs.
	float patch = (hash21(floor(vec2(along * 0.8, u * 4.0))) - 0.5) * 0.05;
	vec3 col = concrete_color + vec3(patch);

	// On the walking top only (u above the curb band):
	float on_top = step(curb_frac, u);
	// Transverse expansion joints: distance (metres) to the nearest panel line.
	float tm = min(fract(along / panel_len), 1.0 - fract(along / panel_len)) * panel_len;
	float tj = (1.0 - smoothstep(joint_w * 0.5, joint_w, tm)) * on_top;
	// One longitudinal joint near the middle of the walking top.
	float lj = (1.0 - smoothstep(0.02, 0.035, abs(u - 0.55))) * on_top;
	float joint = max(tj, lj);
	col = mix(col, joint_color, joint * 0.7);

	// Curb face: brighter painted/worn lip, distinct from the top plane.
	float curb = 1.0 - smoothstep(curb_frac, curb_frac + 0.01, u);
	col = mix(col, curb_color + vec3(patch), curb);

	// Concrete micro-surface bump from the hash-based patch noise, giving the
	// flat slabs a tactile quality under raking light.
	vec3 sx = dFdx(VERTEX);
	vec3 sy = dFdy(VERTEX);
	vec3 r1 = cross(sy, NORMAL);
	vec3 r2 = cross(NORMAL, sx);
	float det = dot(sx, r1);
	vec3 bump_grad = sign(det) * (dFdx(patch) * r1 + dFdy(patch) * r2);
	float dist = length(VERTEX);
	float aa = clamp((dist - 20.0) / 80.0, 0.0, 1.0);

	float wet = clamp(world_wetness, 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.7, wet);
	NORMAL = normalize(abs(det) * NORMAL - (0.03 * (1.0 - aa)) * bump_grad);
	ROUGHNESS = mix(mix(0.93, 1.0, aa * 0.4), 0.24, wet);
	METALLIC = 0.0;
	SPECULAR = mix(mix(0.3, 0.12, aa), 0.6, wet);

	// Troweled-concrete micro-relief: a smooth value-noise height perturbs the
	// normal (tangent-free Mikkelsen gradient) and roughness so the walking top
	// reads as real concrete grain up close. Kept off the joints so the grooves
	// stay crisp, faded with distance, and relaxed when wet.
	float micro_fade = 1.0 - smoothstep(10.0, 42.0, dist);
	float micro = on_top * (1.0 - joint) * micro_fade;
	if (micro > 0.001) {
		vec2 st = vec2(u * 5.0, along) * 4.0;
		float h = vnoise(st) * 0.6 + vnoise(st * 2.7) * 0.3;
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - (0.04 * micro * (1.0 - 0.7 * wet)) * grad);
		ROUGHNESS = clamp(ROUGHNESS + (h - 0.45) * 0.10 * micro * (1.0 - wet), 0.1, 1.0);
	}
}
