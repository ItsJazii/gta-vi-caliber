shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// Procedural greybox ground (M1 fidelity): grass/dirt macro patches with micro
// grain. Fully procedural — no textures (repo convention). World-space so
// detail stays put as you walk.
//
// NOTE: lit mode with distance-based specular anti-aliasing (matches
// florida_land.gdshader pattern). ROUGHNESS and SPECULAR fade at distance.

uniform vec3 u_grass_color : source_color = vec3(0.055, 0.075, 0.065);
uniform vec3 u_dirt_color : source_color = vec3(0.035, 0.04, 0.04);
uniform float u_macro_scale = 0.035; // big patches (per metre)
uniform float u_micro_scale = 0.9; // fine grain (per metre)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		s += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return s;
}

varying vec3 v_wpos;

void vertex() {
	v_wpos = VERTEX; // world-space (world_vertex_coords)
}

void fragment() {
	vec2 w = v_wpos.xz;
	float macro = fbm(w * u_macro_scale);
	float micro = fbm(w * u_micro_scale);
	float blend = clamp(macro * 1.3 - 0.15 + micro * 0.2, 0.0, 1.0);

	vec3 col = mix(u_dirt_color, u_grass_color, blend);
	col *= 0.85 + 0.3 * micro; // micro brightness break-up
	ALBEDO = col;

	// Distance-based specular anti-aliasing
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float aa = clamp((dist - 40.0) / 140.0, 0.0, 1.0);
	ROUGHNESS = mix(0.92, 1.0, aa * 0.6);
	SPECULAR = 0.15 * (1.0 - aa * 0.7);
}
