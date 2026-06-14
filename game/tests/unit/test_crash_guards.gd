class_name TestCrashGuards
extends GdUnitTestSuite
## Regression tests for two crash-guards:
##   - CrimeWitness count/collect crashed on a malformed observer whose "pos" is
##     present but not a Vector3, aborting the loop and dropping ALL witnesses.
##   - CausewayNetwork.sample indexed points[-1] on an empty polyline.


func test_count_witnesses_survives_a_malformed_observer() -> void:
	var crime := Vector3.ZERO
	var good := {"pos": Vector3(1, 0, 0), "facing": Vector3(-1, 0, 0)}
	var bad := {"pos": "not a vector", "facing": null}  # would crash the typed read
	var n := CrimeWitness.count_witnesses(crime, [bad, good], 50.0, deg_to_rad(120.0))
	assert_int(n).is_equal(1)  # the good witness still counts; no crash


func test_collect_witnesses_survives_a_malformed_observer() -> void:
	var crime := Vector3.ZERO
	var good := {"pos": Vector3(1, 0, 0), "facing": Vector3(-1, 0, 0), "is_police": false}
	var bad := {"pos": 42}
	var res := CrimeWitness.collect_witnesses(
		crime, [bad, good], 50.0, deg_to_rad(120.0), 60.0, deg_to_rad(160.0)
	)
	assert_int((res["witnesses"] as Array).size()).is_equal(1)


func test_causeway_sample_handles_empty_polyline() -> void:
	assert_vector(CausewayNetwork.sample(PackedVector2Array(), 5.0)).is_equal(Vector2.ZERO)
