shader_type spatial;
render_mode world_vertex_coords;

// Shell sand with wind streaks, darker wet bands, and optional bound albedo
// texture so beaches do not read as flat painted strips.

uniform vec3 dry_color : source_color = vec3(0.86, 0.77, 0.55);
uniform vec3 wet_color : source_color = vec3(0.56, 0.47, 0.33);
uniform vec3 shell_color : source_color = vec3(0.96, 0.88, 0.72);
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_uv_scale = 0.045;
uniform float streak_scale = 0.018;
uniform float grain_scale = 0.22;

varying vec3 w_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
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

void vertex() {
	w_pos = VERTEX;
}

void fragment() {
	vec2 p = w_pos.xz;
	float streak = vnoise(vec2(p.x * streak_scale, p.y * streak_scale * 0.22));
	float grain = vnoise(p * grain_scale);
	float shells = smoothstep(0.82, 0.98, vnoise(p * 0.7));
	float wet = smoothstep(0.0, 0.22, streak) * 0.55;

	vec3 col = mix(dry_color, wet_color, wet);
	col = mix(col, shell_color, shells * 0.38);
	col *= 0.86 + grain * 0.28;
	vec3 detail_col = texture(detail_tex, p * detail_uv_scale).rgb;
	col *= mix(vec3(1.0), detail_col, 0.46);

	// Specular anti-aliasing: wet bands used to drop roughness to 0.58 and raise
	// specular, so the procedural wet streaks caught a hard sheen that shimmered
	// as the camera moved. Keep a damp tone difference but a far gentler sheen,
	// and trend fully matte in the distance where the streaks alias.
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float aa = clamp((dist - 40.0) / 140.0, 0.0, 1.0);

	ALBEDO = col;
	float rough = mix(0.94, 0.80, wet);
	ROUGHNESS = mix(rough, 1.0, aa * 0.6);
	SPECULAR = (0.18 + wet * 0.08) * (1.0 - aa * 0.7);
}
