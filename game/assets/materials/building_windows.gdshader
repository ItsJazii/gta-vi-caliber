// Procedural building walls with a window grid that glows at night.
// The merged district mesh has no UVs, so windows are carved from object-space
// position (stable under FloatingOrigin shifts): a grid on the vertical faces,
// with a per-cell hash deciding which windows are lit. TimeOfDay drives the
// single `night_amount` uniform (0 = day, 1 = night) via the district loader.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 wall_color : source_color = vec4(0.62, 0.63, 0.66, 1.0);
uniform vec4 glass_color : source_color = vec4(0.16, 0.2, 0.27, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.6;
uniform float floor_height = 3.2;
uniform float window_width = 2.6;
uniform float glow_energy = 2.4;

varying vec3 obj_pos;
varying vec3 obj_normal;

float cell_random(vec2 id) {
	return fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(obj_normal);
	// Walls only — roofs (|n.y| ~ 1) get no windows.
	float wall = 1.0 - smoothstep(0.6, 0.85, abs(n.y));
	// Grid coordinate: height drives rows, the dominant horizontal axis drives
	// columns (diagonal walls pick whichever axis they mostly face).
	float u = abs(n.x) > abs(n.z) ? obj_pos.z : obj_pos.x;
	vec2 cell = vec2(u / window_width, obj_pos.y / floor_height);
	vec2 f = fract(cell);
	float win = step(0.3, f.x) * step(f.x, 0.72) * step(0.35, f.y) * step(f.y, 0.78);
	win *= wall;
	float lit = step(cell_random(floor(cell)), lit_fraction);
	ALBEDO = mix(wall_color.rgb, glass_color.rgb, win);
	ROUGHNESS = mix(0.85, 0.25, win);
	EMISSION = glow_color.rgb * (win * lit * night_amount * glow_energy);
}
