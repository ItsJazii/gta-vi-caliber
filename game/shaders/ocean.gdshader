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

// Far-field displacement fade for tiered meshes (OceanMeshBuilder): vertex
// displacement is full inside u_fade_start (Chebyshev distance from
// u_fade_center), zero at/beyond u_fade_end, so the coarse far quads stay
// coplanar with the fine grid's edge. Mirrors
// OceanMeshBuilder.displacement_falloff — edit both together. Defaults keep
// uniform planes (no fade) fully displaced.
uniform vec2 u_fade_center = vec2(0.0);
uniform float u_fade_start = 1.0e8;
uniform float u_fade_end = 1.0e9;

uniform vec4 u_shallow_color : source_color = vec4(0.02, 0.6, 0.56, 1.0);
uniform vec4 u_deep_color : source_color = vec4(0.0, 0.12, 0.28, 1.0);
uniform vec4 u_horizon_color : source_color = vec4(0.16, 0.38, 0.55, 1.0);
// Beer-Lambert extinction per metre of water the view ray crosses.
uniform float u_absorption = 0.3;
// Water thinner than this fades out — soft shoreline edge.
uniform float u_edge_fade = 0.6;
uniform float u_roughness = 0.08;
// Surf foam: water-column depth (m) where the shore band fully saturates,
// and the foam tint (warm white reads better at golden hour than pure).
uniform float u_foam_depth = 1.1;
uniform vec4 u_foam_color : source_color = vec4(0.96, 0.97, 0.94, 1.0);
uniform float u_foam_strength : hint_range(0.0, 2.0) = 1.0;
// Open-water whitecaps (Ocean v2) — decoupled from the shore band so a calm,
// flat-seabed bay can keep a thin shoreline yet still froth on the swell.
// Foam appears where the Gerstner field *pinches* (Jacobian < coverage), i.e.
// the steep leeward face of a cresting wave — physically where caps break, not
// merely where the surface is tall.
uniform float u_whitecap_strength : hint_range(0.0, 2.0) = 1.0;
// Jacobian below this folds → foam. 1.0 = foam only at true overlap; higher
// pre-empts the break so caps feather in on steep (not yet folded) crests.
uniform float u_whitecap_coverage : hint_range(0.4, 1.6) = 1.0;

uniform sampler2D u_depth_texture : hint_depth_texture, filter_nearest;

// Undisplaced world-space grid position; the parameter of the wave field.
varying vec2 v_param;
// Vertical displacement, for subtle crest tinting.
varying float v_crest;
varying vec3 v_world_pos;
// Precomputed world-space normal from the vertex stage (mirrors the wave
// displacement so shading stays consistent without recomputing all 5 waves
// per fragment — a major GPU saving on a large water surface).
varying vec3 v_normal_world;

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

// Horizontal Jacobian determinant of the Gerstner map (x,z) -> displaced (x,z).
// Mirrors the derivatives of gerstner_offset's xz terms. J ~ 1 on calm water;
// J -> 0 where short steep waves compress the surface; J < 0 is an overlapping
// (breaking) crest. Whitecap foam keys off where J drops below coverage.
float gerstner_jacobian(vec2 p, float t, float amp_scale) {
	// d(off.x)/dx, d(off.x)/dz, d(off.z)/dz  (Jzx == Jxz by symmetry below).
	float jxx = 0.0;
	float jxz = 0.0;
	float jzz = 0.0;
	for (int i = 0; i < WAVE_COUNT; i++) {
		float k = TAU / WAVE_LENGTHS[i];
		float amp = WAVE_AMPLITUDES[i] * amp_scale;
		vec2 dir = vec2(cos(WAVE_ANGLES[i]), sin(WAVE_ANGLES[i]));
		float omega = sqrt(GRAVITY * k);
		float phase = k * dot(dir, p) - omega * t;
		// off.{x,z} = S*amp*dir.{x,y}*cos(phase); d/dp = -S*amp*k*dir*dir*sin.
		float w = WAVE_STEEPNESS[i] * amp * k * sin(phase);
		jxx -= w * dir.x * dir.x;
		jxz -= w * dir.x * dir.y;
		jzz -= w * dir.y * dir.y;
	}
	// det of [[1+jxx, jxz],[jxz, 1+jzz]].
	return (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;
}

// Cheap animated value noise for foam break-up (no textures in the repo).
float foam_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_param = VERTEX.xz; // world-space thanks to world_vertex_coords
	vec2 rel = v_param - u_fade_center;
	float cheb = max(abs(rel.x), abs(rel.y));
	float fade = 1.0 - smoothstep(u_fade_start, u_fade_end, cheb);
	vec3 off = gerstner_offset(v_param, u_time, u_amplitude_scale) * fade;
	v_crest = off.y;
	VERTEX += off;
	v_world_pos = VERTEX;
	v_normal_world = gerstner_normal(v_param, u_time, u_amplitude_scale);
}

void fragment() {
	vec3 n_world = v_normal_world;
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

	// Surf foam (Ocean v2). Two independent contributions sharing one noise
	// field but their own strength knobs, so a calm flat-seabed bay can keep a
	// thin shoreline (u_foam_strength low) while still frothing on the open
	// swell (u_whitecap_strength up). Noise breaks both into streaks so they
	// read as moving wash, not painted stripes.
	//
	// Perf (PR #38): the streak noise taps plus the Jacobian whitecap test are
	// the costly part and their detail is imperceptible far away, so beyond
	// 120 m we fall back to a cheap pulsing band + crest proxy and skip both.
	float foam_band = 1.0 - smoothstep(0.0, u_foam_depth, thickness);
	float surf_pulse = 0.7 + 0.3 * sin(u_time * 0.9 + v_param.x * 0.05);
	float frag_cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float foam;
	if (frag_cam_dist < 120.0) {
		float streaks = foam_noise(v_param * 0.35 + vec2(u_time * 0.25, 0.0));
		streaks = streaks * 0.6 + 0.4 * foam_noise(v_param * 1.4 - vec2(0.0, u_time * 0.4));

		// (a) Shoreline band: white where the water column thins at the sand,
		// pulsing with the longest wave so the surf line breathes.
		float shore_foam = clamp(foam_band * surf_pulse * smoothstep(0.35, 0.85, streaks) * 1.6, 0.0, 1.0);
		shore_foam *= u_foam_strength;

		// (b) Whitecaps: foam where the Gerstner field folds (Jacobian dips
		// below coverage) — the breaking leeward face of a cresting wave.
		// Modulated by the same streak noise so caps scatter, not band.
		float jac = gerstner_jacobian(v_param, u_time, u_amplitude_scale);
		float caps = smoothstep(u_whitecap_coverage, u_whitecap_coverage - 0.35, jac);
		float whitecaps = clamp(caps * smoothstep(0.3, 0.8, streaks) * u_whitecap_strength, 0.0, 1.0);

		foam = clamp(shore_foam + whitecaps, 0.0, 1.0);
	} else {
		// Far field: cheap breathing shore band + crest-keyed whitecap proxy,
		// no noise or Jacobian taps. Honour both strength knobs so distant
		// water still answers to the same controls.
		float shore_foam = clamp(foam_band * surf_pulse * 0.5, 0.0, 1.0) * u_foam_strength;
		float whitecaps = clamp(crest * 0.35, 0.0, 1.0) * u_whitecap_strength;
		foam = clamp(shore_foam + whitecaps, 0.0, 1.0);
	}
	albedo = mix(albedo, u_foam_color.rgb, foam);
	alpha = mix(alpha, 1.0, foam * 0.85);
	ROUGHNESS = mix(u_roughness, 0.7, foam);

	ALBEDO = albedo;
	ALPHA = alpha;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
