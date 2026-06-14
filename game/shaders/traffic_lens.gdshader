shader_type spatial;
render_mode unshaded, cull_disabled;
// Per-instance lens for the batched traffic signals (issue #61). One MultiMesh
// holds every lens in the city; each instance's COLOR is set per phase by
// TrafficSignalField. The active lens carries a bright colour with alpha 1 and
// glows; an unlit lens carries a darkened colour with alpha 0 and just reads as
// dark glass. Unshaded so a lit lens stays a clear beacon at night regardless of
// scene lighting.

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * COLOR.a * 6.0;
}
