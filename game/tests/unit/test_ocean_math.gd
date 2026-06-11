extends RefCounted
## Unit tests for OceanMath — the CPU twin of game/shaders/ocean.gdshader.
## Includes a contract test that parses the shader source so the two wave
## tables cannot silently drift apart.

const SHADER_PATH := "res://shaders/ocean.gdshader"
const EPSILON := 0.00001


func test_flat_sea_at_zero_amplitude() -> bool:
	var d := OceanMath.displacement(Vector2(12.3, -45.6), 7.8, 0.0)
	return d.is_equal_approx(Vector3.ZERO)


func test_height_bounded_by_amplitude_sum() -> bool:
	var bound := OceanMath.max_height() + EPSILON
	for i in 50:
		var p := Vector2(i * 7.31, i * -3.17)
		if absf(OceanMath.displacement(p, i * 0.61).y) > bound:
			return false
	return true


func test_surface_moves_over_time() -> bool:
	var p := Vector2(10.0, 20.0)
	return not is_equal_approx(OceanMath.wave_height_at(p, 0.0), OceanMath.wave_height_at(p, 1.3))


func test_surface_varies_in_space() -> bool:
	var heights: Array[float] = []
	for i in 8:
		heights.append(OceanMath.wave_height_at(Vector2(i * 11.7, i * 5.3), 2.0))
	var lowest: float = heights.min()
	var highest: float = heights.max()
	return highest - lowest > 0.01


func test_horizontal_displacement_bounded() -> bool:
	var bound := 0.0
	for i in OceanMath.WAVE_COUNT:
		bound += OceanMath.WAVE_STEEPNESS[i] * OceanMath.WAVE_AMPLITUDES[i]
	for i in 30:
		var d := OceanMath.displacement(Vector2(i * 4.9, i * -8.2), i * 0.37)
		if Vector2(d.x, d.z).length() > bound + EPSILON:
			return false
	return true


func test_inversion_lands_on_query_point() -> bool:
	# wave_height_at solves for the grid parameter whose displaced position
	# is the query point; the residual must be far below the wave scale.
	var query := Vector2(33.3, -21.0)
	var time := 4.2
	var param := query
	for _i in OceanMath.INVERT_ITERATIONS:
		var d := OceanMath.displacement(param, time)
		param = query - Vector2(d.x, d.z)
	var final := OceanMath.displacement(param, time)
	var landed := param + Vector2(final.x, final.z)
	return landed.distance_to(query) < 0.05


func test_normal_is_unit_and_upward() -> bool:
	for i in 30:
		var n := OceanMath.surface_normal(Vector2(i * 6.1, i * 2.9), i * 0.53)
		if absf(n.length() - 1.0) > EPSILON or n.y < 0.5:
			return false
	return true


func test_calm_sea_normal_is_up() -> bool:
	return OceanMath.surface_normal(Vector2(5.0, 5.0), 1.0, 0.0).is_equal_approx(Vector3.UP)


func test_no_wave_self_intersects() -> bool:
	# Gerstner crests loop over themselves when steepness * k * amplitude
	# exceeds 1 for any single wave.
	for i in OceanMath.WAVE_COUNT:
		var k := TAU / OceanMath.WAVE_LENGTHS[i]
		if OceanMath.WAVE_STEEPNESS[i] * k * OceanMath.WAVE_AMPLITUDES[i] > 1.0:
			return false
	return true


func test_shader_constants_match() -> bool:
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		return false
	var source := shader.code
	return (
		_array_matches(source, "WAVE_ANGLES", OceanMath.WAVE_ANGLES)
		and _array_matches(source, "WAVE_LENGTHS", OceanMath.WAVE_LENGTHS)
		and _array_matches(source, "WAVE_AMPLITUDES", OceanMath.WAVE_AMPLITUDES)
		and _array_matches(source, "WAVE_STEEPNESS", OceanMath.WAVE_STEEPNESS)
		and source.contains("const float GRAVITY = %s" % String.num(OceanMath.GRAVITY, 1))
		and source.contains("const int WAVE_COUNT = %d" % OceanMath.WAVE_COUNT)
	)


func test_shader_height_sum_matches() -> bool:
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		return false
	var declared := _shader_floats(shader.code, "WAVE_HEIGHT_SUM = ", ";")
	return declared.size() == 1 and absf(declared[0] - OceanMath.max_height()) < EPSILON


func _array_matches(source: String, name: String, expected: Array[float]) -> bool:
	var values := _shader_floats(source, name, "}")
	if values.size() != expected.size():
		return false
	for i in expected.size():
		if absf(values[i] - expected[i]) > EPSILON:
			return false
	return true


## Floats between `marker` and the next `terminator` in shader source.
func _shader_floats(source: String, marker: String, terminator: String) -> Array[float]:
	var start := source.find(marker)
	if start < 0:
		return []
	start += marker.length()
	var open := source.find("{", start)
	if open >= 0 and open < source.find(terminator, start):
		start = open + 1
	var end := source.find(terminator, start)
	if end < 0:
		return []
	var out: Array[float] = []
	for token in source.substr(start, end - start).split(","):
		out.append(token.strip_edges().to_float())
	return out
