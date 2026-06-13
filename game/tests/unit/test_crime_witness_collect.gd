extends RefCounted
## Unit tests for CrimeWitness.collect_witnesses — the role-aware partition the
## WantedTracker uses to find who actually saw a crime (peds and cops carry
## different perception cones) before any heat lands.

# Ped-ish defaults: a 60-degree half-cone (120 total), 10m sight.
const PED_FOV: float = PI / 3.0
const PED_RANGE: float = 10.0

# Cop-ish defaults: a wider 120-degree half-cone, 25m sight.
const COP_FOV: float = 2.0 * PI / 3.0
const COP_RANGE: float = 25.0


func test_applies_role_perception() -> bool:
	# Both stand 20m from the crime facing it: out of ped sight (10m), well
	# inside a cop's (25m) — only the cop makes the witness list.
	var crime := Vector3.ZERO
	var observers := [
		{"pos": Vector3(20, 0, 0), "facing": Vector3(-1, 0, 0), "is_police": false},
		{"pos": Vector3(20, 0, 0), "facing": Vector3(-1, 0, 0), "is_police": true},
	]
	var seen := CrimeWitness.collect_witnesses(
		crime, observers, PED_RANGE, PED_FOV, COP_RANGE, COP_FOV
	)
	var witnesses: Array = seen["witnesses"]
	return witnesses.size() == 1 and bool(seen["police_saw"])


func test_civilians_only_means_no_police_flag() -> bool:
	var observers := [
		{"pos": Vector3(-5, 0, 0), "facing": Vector3(1, 0, 0), "is_police": false},
		{"pos": Vector3(0, 0, -5), "facing": Vector3(0, 0, 1), "is_police": false},
	]
	var seen := CrimeWitness.collect_witnesses(
		Vector3.ZERO, observers, PED_RANGE, PED_FOV, COP_RANGE, COP_FOV
	)
	var witnesses: Array = seen["witnesses"]
	return witnesses.size() == 2 and not bool(seen["police_saw"])


func test_carries_caller_payload_through() -> bool:
	var observers := [
		{"pos": Vector3(-5, 0, 0), "facing": Vector3(1, 0, 0), "tag": "alice"},
	]
	var seen := CrimeWitness.collect_witnesses(
		Vector3.ZERO, observers, PED_RANGE, PED_FOV, COP_RANGE, COP_FOV
	)
	var witnesses: Array = seen["witnesses"]
	if witnesses.size() != 1:
		return false
	return String((witnesses[0] as Dictionary).get("tag", "")) == "alice"


func test_empty_alley_sees_nothing() -> bool:
	var seen := CrimeWitness.collect_witnesses(
		Vector3.ZERO, [], PED_RANGE, PED_FOV, COP_RANGE, COP_FOV
	)
	var witnesses: Array = seen["witnesses"]
	return witnesses.is_empty() and not bool(seen["police_saw"])


func test_skips_malformed_entries() -> bool:
	var observers := [
		"not a dict",
		{"pos": Vector3(-5, 0, 0), "facing": Vector3(1, 0, 0)},
	]
	var seen := CrimeWitness.collect_witnesses(
		Vector3.ZERO, observers, PED_RANGE, PED_FOV, COP_RANGE, COP_FOV
	)
	var witnesses: Array = seen["witnesses"]
	return witnesses.size() == 1
