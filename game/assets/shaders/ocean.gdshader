shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// Gerstner-wave ocean: four summed waves displace a subdivided plane in the
// vertex stage, with fresnel sky tint, depth-graded colour (shallow → deep)
// and shoreline foam in the fragment stage. Purely visual — the swimmable
// surface is the flat plane at the mesh height (see WaterVolume / SwimMotion).
// Needs a plane with enough subdivisions for the crests to read.

uniform vec3 shallow_color : source_color = vec3(0.16, 0.47, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.17);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform float wave_speed = 0.55;
uniform float amplitude_scale : hint_range(0.0, 2.0) = 1.0;
uniform float beer_factor = 0.45; // how fast colour falls to deep with depth
uniform float foam_depth = 0.7; // water depth (m) the shoreline foam fades over
uniform float crest_foam = 0.6; // wave height at which whitecaps appear
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

// Four Gerstner waves. xy = travel direction, z = steepness (0..1), w = length.
uniform vec4 wave_a = vec4(1.0, 0.0, 0.20, 11.0);
uniform vec4 wave_b = vec4(0.6, 0.8, 0.18, 6.5);
uniform vec4 wave_c = vec4(-0.7, 0.5, 0.15, 4.0);
uniform vec4 wave_d = vec4(0.25, -1.0, 0.11, 2.6);

varying float v_wave_height;

// One Gerstner wave: returns the xyz displacement of `pos` and accumulates the
// surface tangent/binormal so the fragment stage gets a true rippled normal.
vec3 gerstner(vec4 w, vec3 pos, float t, inout vec3 tangent, inout vec3 binormal) {
	vec2 dir = normalize(w.xy);
	float steep = w.z;
	float k = TAU / w.w; // TAU is a built-in shader constant
	float c = sqrt(9.8 / k); // deep-water phase speed
	float f = k * (dot(dir, pos.xz) - c * t * wave_speed);
	float a = steep / k;
	float sf = sin(f);
	float cf = cos(f);

	tangent += vec3(
		-dir.x * dir.x * (steep * sf), dir.x * (steep * cf), -dir.x * dir.y * (steep * sf)
	);
	binormal += vec3(
		-dir.x * dir.y * (steep * sf), dir.y * (steep * cf), -dir.y * dir.y * (steep * sf)
	);
	return vec3(dir.x * (a * cf), a * sf, dir.y * (a * cf));
}

void vertex() {
	vec3 pos = VERTEX;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	disp += gerstner(wave_a, pos, TIME, tangent, binormal);
	disp += gerstner(wave_b, pos, TIME, tangent, binormal);
	disp += gerstner(wave_c, pos, TIME, tangent, binormal);
	disp += gerstner(wave_d, pos, TIME, tangent, binormal);
	VERTEX += disp * amplitude_scale;
	v_wave_height = disp.y;
	NORMAL = normalize(cross(binormal, tangent));
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Reconstruct how much water sits between the surface and the scene behind
	// it, in view space, to grade colour and lay foam along the shoreline.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float water_depth = max(0.0, -view.z - (-VERTEX.z));

	float fog = exp(-beer_factor * water_depth);
	vec3 col = mix(deep_color, shallow_color, clamp(fog, 0.0, 1.0));

	float foam = 1.0 - smoothstep(0.0, foam_depth, water_depth); // shore line
	foam += smoothstep(crest_foam, crest_foam + 0.4, v_wave_height); // whitecaps
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	METALLIC = metallic_amount;
	ROUGHNESS = mix(roughness_amount, 0.4, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.6;
	RIM = 0.4;
	RIM_TINT = 0.2;
	// Clear in the shallows, opaque out in the deep; foam is always solid.
	ALPHA = clamp(0.55 + fresnel * 0.35 + (1.0 - fog) * 0.45 + foam, 0.0, 1.0);
}
