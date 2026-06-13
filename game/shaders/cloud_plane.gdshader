shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// High-altitude broken-cumulus cloud sheet — no textures. A large horizontal
// plane sits above the city; this shader carves drifting puffy clouds out of
// fbm coverage and dissolves them into the horizon haze with distance, so the
// flat ProceduralSky gradient gains depth and motion. Purely visual, unshaded
// (sun tint is baked into the colours), transparent, writes no depth.

uniform vec3 cloud_color : source_color = vec3(0.96, 0.94, 0.92);
uniform vec3 cloud_shadow : source_color = vec3(0.58, 0.57, 0.64);
// Horizon tint the far clouds melt into (match the scene's sky horizon).
uniform vec3 sky_haze : source_color = vec3(0.72, 0.50, 0.40);
// Warm rim light from the sun side, added on the lit edges of billows.
uniform vec3 sun_tint : source_color = vec3(1.0, 0.84, 0.62);
uniform vec2 sun_dir_xz = vec2(0.6, -0.4);
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.02, 0.5) = 0.13;
uniform float noise_scale = 0.0006;
uniform vec2 wind = vec2(7.0, 2.5);
// Fade only the extreme rim of the (huge) plane so clouds persist all the way
// to the horizon — where they read densest — instead of dissolving mid-sky.
uniform float fade_start = 9000.0;
uniform float fade_end = 15000.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.95;

varying vec3 w_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.77));
	p += dot(p, p + 41.23);
	return fract(p.x * p.y);
}

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

// 4 octaves is plenty for soft cloud coverage and keeps the per-pixel cost of
// this near-fullscreen transparent sheet down (it overdraws a lot of sky).
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += vnoise(p) * amp;
		p = p * 2.04 + vec2(11.3, 7.7);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	w_pos = VERTEX;
}

void fragment() {
	vec2 p = w_pos.xz * noise_scale + wind * (TIME * noise_scale);
	float n = fbm(p);
	// Coverage threshold → puffy broken clouds; billow detail breaks the edges.
	float lo = 1.0 - coverage - softness;
	float hi = 1.0 - coverage + softness;
	float c = smoothstep(lo, hi, n);
	// Cheap single-octave billow to break the edges (full fbm here is wasted on
	// a sheet this large and overdrawn).
	float billow = vnoise(p * 3.2 + vec2(19.0, 4.0));
	c *= 0.66 + 0.34 * billow;

	// Distance fade: far clouds dissolve into the horizon haze (and the plane's
	// own rim never shows because the edge is well past fade_end).
	float dist = length(w_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	// Shade: denser cores read darker (under-lit), lit billow edges catch the
	// warm sun on the side the sun comes from.
	float dense = smoothstep(0.35, 1.0, c);
	vec3 col = mix(cloud_color, cloud_shadow, dense * 0.55);
	vec2 sd = normalize(sun_dir_xz + vec2(1e-4));
	float lit = clamp(dot(normalize(p + vec2(1e-4)), sd) * 0.5 + 0.5, 0.0, 1.0);
	col += sun_tint * (lit * (1.0 - dense) * 0.18);

	// Melt colour and alpha into haze at the far edge.
	col = mix(sky_haze, col, fade);
	float alpha = clamp(c * fade * opacity, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
