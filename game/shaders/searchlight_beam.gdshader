shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// Fake-volumetric searchlight shaft. Drawn on a thin cone (CylinderMesh, narrow
// base → wide top). Additive, so beams brighten the dark sky and overlap. A
// fresnel rim makes the cone's silhouette glow (reads as a translucent volume,
// not a solid ice-cream cone), and it fades up its length from the bright base.
// No textures, no dependency on volumetric fog.

uniform vec3 beam_color : source_color = vec3(0.8, 0.86, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float height = 170.0;

varying float v_h;  // 0 at the base, 1 at the top

void vertex() {
	v_h = clamp(VERTEX.y / height, 0.0, 1.0);
}

void fragment() {
	// Grazing (silhouette) faces glow; the cone reads as a hollow shaft.
	float fres = pow(1.0 - abs(normalize(NORMAL).z), 2.2);
	// Bright at the base lamp, fading out toward the sky.
	float along = pow(1.0 - v_h, 1.6);
	float a = fres * along * intensity;
	EMISSION = beam_color * intensity * (0.4 + 0.6 * along);
	ALBEDO = beam_color;
	ALPHA = clamp(a, 0.0, 1.0) * 0.6;
}
