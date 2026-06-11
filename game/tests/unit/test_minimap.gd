extends RefCounted
## Unit tests for Minimap.clip_segment_circle pure helper.


func test_segment_fully_inside_unchanged() -> bool:
	var r := Minimap.clip_segment_circle(Vector2(-5, 0), Vector2(5, 0), 10.0)
	return (
		r.size() == 2
		and r[0].is_equal_approx(Vector2(-5, 0))
		and r[1].is_equal_approx(Vector2(5, 0))
	)


func test_segment_crossing_clips_to_radius() -> bool:
	# Horizontal line from outside-left to centre, radius 10 → enters at x=-10.
	var r := Minimap.clip_segment_circle(Vector2(-20, 0), Vector2(0, 0), 10.0)
	return r.size() == 2 and absf(r[0].x - (-10.0)) < 0.0001 and r[1].is_equal_approx(Vector2(0, 0))


func test_segment_through_circle_clips_both_ends() -> bool:
	var r := Minimap.clip_segment_circle(Vector2(-20, 0), Vector2(20, 0), 10.0)
	return r.size() == 2 and absf(r[0].x + 10.0) < 0.0001 and absf(r[1].x - 10.0) < 0.0001


func test_segment_missing_circle_returns_empty() -> bool:
	var r := Minimap.clip_segment_circle(Vector2(-20, 50), Vector2(20, 50), 10.0)
	return r.is_empty()


func test_degenerate_point_outside_empty() -> bool:
	var r := Minimap.clip_segment_circle(Vector2(50, 50), Vector2(50, 50), 10.0)
	return r.is_empty()


func test_star_points_has_ten_vertices() -> bool:
	return WantedStars.star_points(Vector2.ZERO, 9.0).size() == 10
