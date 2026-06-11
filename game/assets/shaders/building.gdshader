shader_type spatial;
render_mode cull_disabled;

// Procedural facade for the merged city mesh: derives a window grid from world
// position + face normal (no UVs, no textures) and lights a random subset of
// windows after dusk. Driven by the global `world_night_amount` that
// SkyController sets from SkyModel, so the skyline ignites and fades in lockstep
// with the sky's day/night cycle. One material covers every building in the
// district's batched MeshInstance3D.

global uniform float world_night_amount;

uniform vec3 wall_color : source_color = vec3(0.56, 0.58, 0.62);
uniform vec3 glass_color : source_color = vec3(0.26, 0.32, 0.40);
uniform vec3 window_emit : source_color = vec3(1.0, 0.80, 0.46);
uniform float floor_height = 3.4; // metres between window rows
uniform float window_span = 3.0; // metres between window columns
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.5; // share of windows lit at night
uniform float emit_strength : hint_range(0.0, 8.0) = 2.6;

varying vec3 w_pos;
varying vec3 w_norm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Vertical-ish walls carry windows; near-horizontal faces (roofs) stay bare.
	float wall = step(0.5, 1.0 - abs(w_norm.y));

	// Horizontal coordinate runs along the wall; the wall's fixed axis seeds the
	// grid so parallel facades don't repeat the same lit pattern.
	bool faces_x = abs(w_norm.x) > abs(w_norm.z);
	float horiz = faces_x ? w_pos.z : w_pos.x;
	float fixed_axis = faces_x ? w_pos.x : w_pos.z;

	vec2 grid = vec2(horiz / window_span, w_pos.y / floor_height);
	vec2 cell = floor(grid) + vec2(floor(fixed_axis * 0.5) * 7.0, 0.0);
	vec2 f = fract(grid);

	// Window pane within each cell (margins = mullions/spandrel).
	float pane = step(0.16, f.x) * step(f.x, 0.84) * step(0.28, f.y) * step(f.y, 0.9);
	// No windows on the ground band or on roofs.
	float is_window = pane * wall * step(floor_height * 0.6, w_pos.y);

	// Which windows are lit, and how warm.
	float r = hash21(cell + 0.5);
	float lit = step(1.0 - lit_fraction, r);
	float warm = mix(0.65, 1.0, hash21(cell + 19.7));

	ALBEDO = mix(wall_color, glass_color, is_window);
	ROUGHNESS = mix(0.9, 0.2, is_window);
	METALLIC = 0.0;

	float on = is_window * lit * clamp(world_night_amount, 0.0, 1.0);
	EMISSION = window_emit * warm * on * emit_strength;
}
