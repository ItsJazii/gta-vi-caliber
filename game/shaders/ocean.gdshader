shader_type spatial;
render_mode world_vertex_coords, depth_draw_always, specular_schlick_ggx, cull_back;

// Gerstner-wave ocean (M4, fully procedural — no textures).
//
// CONTRACT: the wave table and the gerstner_offset()/gerstner_normal()
// formulas are mirrored verbatim in game/scripts/world/ocean_math.gd so
// CPU-side queries (buoyancy) agree with the rendered surface. Edit BOTH
// files together; test_ocean_math.gd parses this source and fails if the
// constants drift apart.
//
// Look (docs/VISION.md): sun-bleached coastal water — turquoise shallows
// blending to deep blue via depth-based absorption, soft shoreline edge,
// readable sun glitter at golden hour.

const float GRAVITY = 9.8;
const int WAVE_COUNT = 5;
const float WAVE_ANGLES[5] = {0.3, 1.1, -0.6, 2.6, -1.9};
const float WAVE_LENGTHS[5] = {42.0, 19.0, 9.0, 5.0, 3.0};
const float WAVE_AMPLITUDES[5] = {0.6, 0.26, 0.12, 0.05, 0.02};
const float WAVE_STEEPNESS[5] = {0.6, 0.8, 0.9, 1.0, 1.0};
// Sum of WAVE_AMPLITUDES — keep equal to OceanMath.max_height(1.0).
const float WAVE_HEIGHT_SUM = 1.05;

// Driven by Ocean (ocean.gd) every frame so CPU and GPU share one clock.
uniform float u_time = 0.0;
uniform float u_amplitude_scale = 1.0;

uniform vec4 u_shallow_color : source_color = vec4(0.02, 0.6, 0.56, 1.0);
uniform vec4 u_deep_color : source_color = vec4(0.0, 0.12, 0.28, 1.0);
uniform vec4 u_horizon_color : source_color = vec4(0.16, 0.38, 0.55, 1.0);
// Beer-Lambert extinction per metre of water the view ray crosses.
uniform float u_absorption = 0.3;
// Water thinner than this fades out — soft shoreline edge.
uniform float u_edge_fade = 0.6;
uniform float u_roughness = 0.08;

uniform sampler2D u_depth_texture : hint_depth_texture, filter_nearest;

// Undisplaced world-space grid position; the parameter of the wave field.
varying vec2 v_param;
// Vertical displacement, for subtle crest tinting.
varying float v_crest;
varying vec3 v_world_pos;

// Mirrors OceanMath.displacement().
vec3 gerstner_offset(vec2 p, float t, float amp_scale) {
	vec3 off = vec3(0.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		float k = TAU / WAVE_LENGTHS[i];
		float amp = WAVE_AMPLITUDES[i] * amp_scale;
		vec2 dir = vec2(cos(WAVE_ANGLES[i]), sin(WAVE_ANGLES[i]));
		float omega = sqrt(GRAVITY * k);
		float phase = k * dot(dir, p) - omega * t;
		off.x += WAVE_STEEPNESS[i] * amp * dir.x * cos(phase);
		off.z += WAVE_STEEPNESS[i] * amp * dir.y * cos(phase);
		off.y += amp * sin(phase);
	}
	return off;
}

// Mirrors OceanMath.surface_normal(). Evaluated per-pixel so short waves
// keep shading detail beyond the vertex grid resolution.
vec3 gerstner_normal(vec2 p, float t, float amp_scale) {
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		float k = TAU / WAVE_LENGTHS[i];
		float amp = WAVE_AMPLITUDES[i] * amp_scale;
		vec2 dir = vec2(cos(WAVE_ANGLES[i]), sin(WAVE_ANGLES[i]));
		float omega = sqrt(GRAVITY * k);
		float phase = k * dot(dir, p) - omega * t;
		n.x -= dir.x * k * amp * cos(phase);
		n.z -= dir.y * k * amp * cos(phase);
		n.y -= WAVE_STEEPNESS[i] * k * amp * sin(phase);
	}
	return normalize(n);
}

void vertex() {
	v_param = VERTEX.xz; // world-space thanks to world_vertex_coords
	vec3 off = gerstner_offset(v_param, u_time, u_amplitude_scale);
	v_crest = off.y;
	VERTEX += off;
	v_world_pos = VERTEX;
}

void fragment() {
	vec3 n_world = gerstner_normal(v_param, u_time, u_amplitude_scale);
	NORMAL = normalize(mat3(VIEW_MATRIX) * n_world);

	// Water column thickness along the view ray: opaque scene depth minus
	// our own depth, both linearized in view space.
	float depth_raw = texture(u_depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_dist = -scene_view.z / scene_view.w;
	vec4 frag_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	float frag_dist = -frag_view.z / frag_view.w;
	float thickness = max(scene_dist - frag_dist, 0.0);

	// Shoreline blend: shallow water lets the seabed tint through.
	float transmit = exp(-thickness * u_absorption);
	vec3 albedo = mix(u_deep_color.rgb, u_shallow_color.rgb, transmit);

	// Crests catch a touch of lighter water (cheap pre-foam readability).
	float crest = smoothstep(0.45, 1.0, v_crest / max(WAVE_HEIGHT_SUM * u_amplitude_scale, 0.001));
	albedo = mix(albedo, u_shallow_color.rgb * 1.2, crest * 0.25);

	// Fresnel: glancing angles go reflective and opaque toward the horizon.
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = pow(1.0 - clamp(dot(n_world, view_dir), 0.0, 1.0), 5.0);
	albedo = mix(albedo, u_horizon_color.rgb, fresnel * 0.35);

	float alpha = clamp(1.0 - transmit * 0.75, 0.3, 0.97);
	alpha = mix(alpha, 1.0, fresnel * 0.7);
	alpha *= smoothstep(0.0, u_edge_fade, thickness);

	// Upwelling scatter: sunlight bounced off the seabed glows turquoise.
	// Peaks at mid shallows (transmit 0.5), vanishes at the shore and at depth.
	EMISSION = u_shallow_color.rgb * (transmit * (1.0 - transmit) * 4.0) * 0.28;

	ALBEDO = albedo;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = u_roughness;
	SPECULAR = 0.5;
}
