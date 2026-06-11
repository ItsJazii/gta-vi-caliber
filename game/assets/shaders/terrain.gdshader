shader_type spatial;

// Heightfield terrain material: blends sand → grass → rock → snow by world
// height and slope, with a little large-scale noise so the bands don't read as
// hard contour lines. Pairs with TerrainModel/Terrain; world-space varyings mean
// the look is continuous across chunk borders.

uniform vec3 sand_color : source_color = vec3(0.60, 0.55, 0.39);
uniform vec3 grass_color : source_color = vec3(0.24, 0.35, 0.15);
uniform vec3 grass_color2 : source_color = vec3(0.30, 0.40, 0.18);
uniform vec3 rock_color : source_color = vec3(0.30, 0.28, 0.26);
uniform vec3 snow_color : source_color = vec3(0.90, 0.92, 0.96);
uniform float shore_height = 2.0;
uniform float snow_height = 34.0;
uniform float rock_slope : hint_range(0.0, 1.0) = 0.6;

varying vec3 w_pos;
varying vec3 w_norm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
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

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = clamp(1.0 - w_norm.y, 0.0, 1.0);
	float h = w_pos.y;
	float n = vnoise(w_pos.xz * 0.05);

	// Two-tone grass to break up the flats.
	vec3 grass = mix(grass_color, grass_color2, n);

	// Sand near the waterline → grass above it.
	vec3 base = mix(sand_color, grass, smoothstep(shore_height, shore_height + 4.0, h));
	// Snow caps on the high ground (noisy snowline).
	base = mix(base, snow_color, smoothstep(snow_height, snow_height + 8.0, h + n * 6.0));
	// Bare rock on anything steep, whatever the height.
	base = mix(base, rock_color, smoothstep(rock_slope, rock_slope + 0.18, slope));

	ALBEDO = base;
	ROUGHNESS = mix(0.9, 1.0, slope);
	METALLIC = 0.0;
}
