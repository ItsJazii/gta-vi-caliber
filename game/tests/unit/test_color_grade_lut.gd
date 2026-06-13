extends RefCounted
## Unit tests for ColorGradeLut — the Vice City split-tone grade cools shadows
## toward teal, warms highlights toward orange, leaves identity at strength 0,
## stays in gamut, and bakes into a correctly-sized 3D LUT.


func test_zero_strength_is_identity() -> bool:
	var src := Color(0.3, 0.55, 0.7)
	var out := ColorGradeLut.grade(src, 0.0)
	return (
		is_equal_approx(out.r, src.r)
		and is_equal_approx(out.g, src.g)
		and is_equal_approx(out.b, src.b)
	)


func test_shadows_drift_cool() -> bool:
	# A dark grey should pick up blue/green (teal) and lose a touch of red.
	var out := ColorGradeLut.grade(Color(0.15, 0.15, 0.15))
	return out.b > 0.15 and out.b > out.r


func test_highlights_drift_warm() -> bool:
	# A bright grey should warm: red rises above the input, blue falls below it.
	var out := ColorGradeLut.grade(Color(0.8, 0.8, 0.8))
	return out.r > 0.8 and out.b < 0.8 and out.r > out.b


func test_output_stays_in_gamut() -> bool:
	for sample in [Color(0, 0, 0), Color(1, 1, 1), Color(1, 0, 0), Color(0, 0, 1)]:
		var out := ColorGradeLut.grade(sample, 1.5)
		if out.r < 0.0 or out.r > 1.0 or out.g < 0.0 or out.g > 1.0 or out.b < 0.0 or out.b > 1.0:
			return false
	return true


func test_grade_is_deterministic() -> bool:
	var a := ColorGradeLut.grade(Color(0.42, 0.18, 0.63))
	var b := ColorGradeLut.grade(Color(0.42, 0.18, 0.63))
	return a.is_equal_approx(b)


func test_build_returns_cubic_lut() -> bool:
	var lut := ColorGradeLut.build(9, 1.0)
	return (
		lut is ImageTexture3D
		and lut.get_width() == 9
		and lut.get_height() == 9
		and lut.get_depth() == 9
	)
