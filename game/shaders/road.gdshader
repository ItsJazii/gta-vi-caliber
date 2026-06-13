shader_type spatial;
render_mode cull_disabled;
// Procedural road ribbon — no textures. CityBuilder.road_ribbon writes UVs
// where UV.x spans the ribbon width 0..1 and UV.y accumulates metres along
// the centreline, so paint and wear stay in road space regardless of where
// the ribbon sits in the world.

uniform vec3 asphalt_color : source_color = vec3(0.24, 0.235, 0.23);
uniform vec3 sidewalk_color : source_color = vec3(0.60, 0.57, 0.51);
uniform vec3 paint_color : source_color = vec3(0.80, 0.75, 0.60);
// Fraction of each ribbon edge that reads as sidewalk-toned concrete.
uniform float sidewalk_frac : hint_range(0.0, 0.4) = 0.14;
// Photoreal tileable asphalt albedo (Codex-generated) — modulates the procedural
// base so long straights gain real aggregate/oil grain. White default = neutral.
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
// Rain wetness published by the WeatherController (0 dry .. 1 soaked): wet
// asphalt darkens and turns glossy so streets gleam after a front passes.
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

void vertex() {
	v_uv = UV;
}

void fragment() {
	float x = v_uv.x;
	float along = v_uv.y;
	float d_edge = min(x, 1.0 - x);

	// Sidewalk band on both edges, with a darker curb seam against the asphalt.
	float side = 1.0 - smoothstep(sidewalk_frac - 0.012, sidewalk_frac + 0.012, d_edge);
	float curb = 1.0 - smoothstep(0.004, 0.022, abs(d_edge - sidewalk_frac));

	// Faint dashed centre line, repainted long ago: wear varies per dash.
	float line_mask = 1.0 - smoothstep(0.012, 0.022, abs(x - 0.5));
	float dash = step(fract(along / 8.0), 0.55);
	float wear = 0.58 + 0.34 * hash21(vec2(floor(along / 8.0), 7.0));
	float centre_paint = line_mask * dash * wear * (1.0 - side);

	// Thin shoulder/turn-lane ghosts near each side of the asphalt. They are
	// intentionally uneven so the street reads like maintained real asphalt, not
	// a clean procedural ribbon.
	float left_lane = 1.0 - smoothstep(0.006, 0.013, abs(x - 0.32));
	float right_lane = 1.0 - smoothstep(0.006, 0.013, abs(x - 0.68));
	float lane_dash = step(fract((along + 3.5) / 14.0), 0.72);
	float lane_wear = 0.24 + 0.22 * hash21(vec2(floor(along / 14.0), floor(x * 8.0)));
	float lane_paint = (left_lane + right_lane) * lane_dash * lane_wear * (1.0 - side);
	float paint = clamp(centre_paint + lane_paint, 0.0, 1.0);

	// Patchy asphalt tone so long straights don't read as one flat slab.
	float n = (hash21(floor(vec2(along * 1.5, x * 12.0))) - 0.5) * 0.03;
	float patch_cell = hash21(floor(vec2(along * 0.08, x * 5.0)));
	float patch = step(0.78, patch_cell) * (1.0 - smoothstep(0.12, 0.36, abs(x - 0.5)));
	float tar = (1.0 - smoothstep(0.004, 0.018, abs(fract(along * 0.18 + x * 1.7) - 0.5))) * 0.12;
	float tire = (
		1.0 - smoothstep(0.025, 0.085, min(abs(x - 0.39), abs(x - 0.61)))
	) * (0.06 + 0.08 * hash21(floor(vec2(along * 0.65, x * 9.0))));

	vec3 col = asphalt_color + vec3(n);
	col = mix(col, col * 0.72, patch * 0.34);
	col *= 1.0 - tar - tire;
	col = mix(col, sidewalk_color + vec3(n), side);

	// Asphalt grain from the Codex tileable albedo (luminance modulation), kept
	// off the lane paint + sidewalk bands so markings/kerbs stay crisp.
	float grain = dot(texture(detail_tex, vec2(x * 2.5, along * 0.30)).rgb, vec3(0.3333));
	float asphalt_area = (1.0 - side) * (1.0 - paint);
	col *= mix(1.0, clamp(0.74 + grain * 1.2, 0.74, 1.28), asphalt_area);

	// Asphalt micro-surface normal from the grain texture, giving wet roads
	// readable specular highlights (nearly free — reuses the grain lookup).
	vec3 sx = dFdx(VERTEX);
	vec3 sy = dFdy(VERTEX);
	vec3 r1 = cross(sy, NORMAL);
	vec3 r2 = cross(NORMAL, sx);
	float det = dot(sx, r1);
	vec3 grain_grad = sign(det) * (dFdx(grain) * r1 + dFdy(grain) * r2);

	col = mix(col, paint_color, paint * 0.7);
	col *= 1.0 - 0.30 * curb;

	float wet = clamp(world_wetness, 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.92 - 0.25 * paint, 0.16, wet);
	float dist = length(VERTEX);
	float aa = clamp((dist - 30.0) / 100.0, 0.0, 1.0);
	// Grain-gradient normal, distance-faded, gives wet roads readable specular.
	NORMAL = normalize(abs(det) * NORMAL - (0.04 * asphalt_area * (1.0 - aa)) * grain_grad);
	METALLIC = 0.0;
	// Dry asphalt dims with distance; wet asphalt reads glossy.
	SPECULAR = mix(mix(0.35, 0.15, aa), 0.72, wet);

	// Aggregate micro-relief: a smooth value-noise height perturbs the normal
	// (tangent-free Mikkelsen surface gradient — road meshes carry no tangents)
	// and roughness, so close asphalt reads as coarse, light-catching aggregate
	// instead of a flat slab. Faded with distance (derivatives go noisy far off),
	// kept off the paint/kerb, and relaxed when wet (a soaked road is glassy).
	float micro_fade = 1.0 - smoothstep(12.0, 50.0, length(VERTEX));
	float micro = asphalt_area * micro_fade;
	if (micro > 0.001) {
		vec2 st = vec2(x * 6.0, along * 1.2);
		float h = vnoise(st) * 0.6 + vnoise(st * 2.6) * 0.3;
		vec3 sx = dFdx(VERTEX);
		vec3 sy = dFdy(VERTEX);
		vec3 r1 = cross(sy, NORMAL);
		vec3 r2 = cross(NORMAL, sx);
		float det = dot(sx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - (0.06 * micro * (1.0 - 0.7 * wet)) * grad);
		ROUGHNESS = clamp(ROUGHNESS + (h - 0.45) * 0.13 * micro * (1.0 - wet), 0.08, 1.0);
	}
}
