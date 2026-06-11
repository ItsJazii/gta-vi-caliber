shader_type spatial;
render_mode world_vertex_coords;

// Procedural greybox ground (M1 fidelity): grass/dirt macro patches with micro
// grain, height-derived normals and varied roughness so the sandbox floor reads
// as real terrain instead of a flat painted plane. Fully procedural — no
// textures (repo convention). World-space so detail stays put as you walk.

uniform vec3 u_grass_color : source_color = vec3(0.33, 0.40, 0.24);
uniform vec3 u_dirt_color : source_color = vec3(0.37, 0.31, 0.22);
uniform float u_macro_scale = 0.035; // big patches (per metre)
uniform float u_micro_scale = 0.9; // fine grain (per metre)
uniform float u_normal_strength = 0.5;

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
	for (int i = 0; i < 4; i++) {
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
	ROUGHNESS = mix(0.95, 0.78, blend); // grass a touch glossier than dry dirt
	SPECULAR = 0.4;

	// Height-derived normal from the micro field so grazing light catches grain.
	float e = 0.5;
	float h_l = fbm((w - vec2(e, 0.0)) * u_micro_scale);
	float h_r = fbm((w + vec2(e, 0.0)) * u_micro_scale);
	float h_d = fbm((w - vec2(0.0, e)) * u_micro_scale);
	float h_u = fbm((w + vec2(0.0, e)) * u_micro_scale);
	vec3 n = normalize(vec3((h_l - h_r) * u_normal_strength, 1.0, (h_d - h_u) * u_normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
