extends RefCounted
## Unit tests for BarkDirector's label pooling (see tests/run_tests.gd for the
## runner contract: test_* methods return true to pass). The director and stub
## speakers live outside the SceneTree, exercising _bark/_tick_active/_acquire
## directly — no engine loop needed.


func _director(pool: int = 8) -> BarkDirector:
	var d := BarkDirector.new()
	d.pool_size = pool
	return d


func test_bark_attaches_label_to_speaker() -> bool:
	var d := _director()
	var ped := Node3D.new()
	d._bark(ped, "hey", Color.WHITE)
	var label := ped.get_child(0) as Label3D
	var ok := label != null and label.text == "hey" and label.visible
	ped.free()
	d.free()
	return ok


func test_expired_label_returns_to_pool_and_is_reused() -> bool:
	var d := _director()
	var ped := Node3D.new()
	d._bark(ped, "first", Color.WHITE)
	var first := ped.get_child(0)
	d._tick_active(d.bark_duration + 0.1)
	# Expired: hidden, parked under the director, pool of one.
	var parked := first.get_parent() == d and not (first as Label3D).visible
	d._bark(ped, "second", Color.WHITE)
	var reused := ped.get_child_count() == 1 and ped.get_child(0) == first
	var ok := parked and reused and (first as Label3D).text == "second"
	ped.free()
	d.free()
	return ok


func test_pool_caps_total_labels_by_stealing_oldest() -> bool:
	var d := _director(2)
	var peds: Array[Node3D] = []
	for i in 3:
		var ped := Node3D.new()
		peds.append(ped)
		d._bark(ped, "line %d" % i, Color.WHITE)
	# Third bark steals the first speaker's label: cap holds at 2 live labels.
	var ok := (
		d._active.size() == 2
		and peds[0].get_child_count() == 0
		and peds[1].get_child_count() == 1
		and peds[2].get_child_count() == 1
	)
	for ped in peds:
		ped.free()
	d.free()
	return ok


func test_speaker_despawn_mid_bark_rebuilds_pool() -> bool:
	var d := _director()
	var ped := Node3D.new()
	d._bark(ped, "doomed", Color.WHITE)
	ped.free()
	# Expiry finds the label gone (freed with its speaker) and drops it.
	d._tick_active(d.bark_duration + 0.1)
	var survivor := Node3D.new()
	d._bark(survivor, "fresh", Color.WHITE)
	var ok := survivor.get_child_count() == 1 and d._active.size() == 1
	survivor.free()
	d.free()
	return ok


func test_empty_text_or_null_speaker_is_ignored() -> bool:
	var d := _director()
	var ped := Node3D.new()
	d._bark(ped, "", Color.WHITE)
	d._bark(null, "ghost", Color.WHITE)
	var ok := ped.get_child_count() == 0 and d._active.is_empty()
	ped.free()
	d.free()
	return ok
