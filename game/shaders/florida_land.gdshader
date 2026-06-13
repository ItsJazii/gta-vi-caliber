shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// State-map ground material: a sunlit subtropical wetland (Leonida) — luminous
// tropical grass, dry palmetto-scrub clearings, dark marsh basins, and fine
// procedural grain. No texture assets required. Albedos sit in a real sunlit
// range (the old set maxed at 0.18 and read near-black at ground level); a
// large-scale "field" band breaks the canopy into open clearings so the land
// reads as varied terrain from altitude instead of a single flat green sheet.

uniform vec3 grass_low : source_color = vec3(0.10, 0.17, 0.08);
uniform vec3 grass_high : source_color = vec3(0.22, 0.31, 0.13);
uniform vec3 marsh_color : source_color = vec3(0.05, 0.10, 0.06);
uniform vec3 dry_sand_color : source_color = vec3(0.44, 0.38, 0.23);
// Sun-bleached open-field grass between the wet canopy and the dry scrub.
uniform vec3 field_color : source_color = vec3(0.34, 0.36, 0.16);
uniform float macro_scale = 0.0022;
uniform float detail_scale = 0.042;
uniform float normal_strength = 0.38;

varying vec3 w_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 845.21));
	p += dot(p, p + 37.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	w_pos = VERTEX;
}

void fragment() {
	vec2 p = w_pos.xz;
	float macro = fbm(p * macro_scale);
	float detail = fbm(p * detail_scale);
	float marsh = smoothstep(0.08, 0.36, fbm((p + vec2(180.0, -90.0)) * 0.004));
	float dry = smoothstep(0.60, 0.85, macro);
	// Large-scale open fields/clearings: an independent low-frequency band so the
	// wet canopy breaks into lighter sun-bleached savanna, readable from altitude.
	float field = smoothstep(0.42, 0.72, fbm((p + vec2(-260.0, 410.0)) * 0.0015));

	// Layered tonal zones: lush canopy -> open field -> dry scrub, with marsh
	// basins darkened last so water-logged ground stays dark even inside a field.
	vec3 grass = mix(grass_low, grass_high, detail);
	vec3 col = mix(grass, field_color, field * 0.6);
	col = mix(col, dry_sand_color, dry * 0.5);
	col = mix(col, marsh_color, marsh * 0.6);
	col *= 0.85 + detail * 0.3;

	// Specular anti-aliasing: the procedural normal grain below is high-frequency,
	// so in the distance it aliases under the pixel grid and the sharp specular
	// lobe makes the ground sparkle/"flash" as the camera and sun move. Fade the
	// normal perturbation flat and push roughness to fully matte with distance so
	// far ground is calm; keep the grain only within ~40 m of the camera.
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float aa = clamp((dist - 40.0) / 140.0, 0.0, 1.0);

	float ns = normal_strength * (1.0 - aa);
	vec3 sx = dFdx(VERTEX);
	vec3 sy = dFdy(VERTEX);
	vec3 r1 = cross(sy, NORMAL);
	vec3 r2 = cross(NORMAL, sx);
	float det = dot(sx, r1);
	vec3 grad = sign(det) * (dFdx(detail) * r1 + dFdy(detail) * r2);
	vec3 n = normalize(abs(det) * NORMAL - ns * grad);

	ALBEDO = col;
	NORMAL = n;
	// Matte grass/marsh: high roughness floor + low specular so wet sheen never
	// blows out, trending to 1.0 roughness in the distance.
	float rough = mix(0.96, 0.86, marsh * 0.45);
	ROUGHNESS = mix(rough, 1.0, aa * 0.6);
	SPECULAR = 0.2 * (1.0 - aa * 0.7);
}
