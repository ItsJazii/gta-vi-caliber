extends RefCounted
## Unit tests for PhoneContacts (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).


func test_roster_not_empty() -> bool:
	return PhoneContacts.roster().size() >= 4


func test_roster_entries_have_fields() -> bool:
	for c in PhoneContacts.roster():
		for key in ["name", "handle", "status", "hue"]:
			if not c.has(key):
				return false
	return true


func test_roster_is_a_copy() -> bool:
	# Mutating the returned roster must not affect the constant source.
	var a := PhoneContacts.roster()
	a[0]["name"] = "tampered"
	return PhoneContacts.roster()[0]["name"] != "tampered"


func test_handles_match_roster_order() -> bool:
	var handles := PhoneContacts.handles()
	var roster := PhoneContacts.roster()
	return handles.size() == roster.size() and handles[0] == roster[0]["handle"]


func test_by_name_finds_contact() -> bool:
	return PhoneContacts.by_name("Mara")["handle"] == "mara_b"


func test_by_name_missing_is_empty() -> bool:
	return PhoneContacts.by_name("Nobody").is_empty()


func test_online_friend_answers() -> bool:
	return PhoneContacts.will_answer({"status": PhoneContacts.ONLINE})


func test_offline_and_away_do_not_answer() -> bool:
	var away := PhoneContacts.will_answer({"status": PhoneContacts.AWAY})
	var offline := PhoneContacts.will_answer({"status": PhoneContacts.OFFLINE})
	return not away and not offline


func test_away_rings_longer() -> bool:
	var away := PhoneContacts.ring_seconds({"status": PhoneContacts.AWAY})
	var online := PhoneContacts.ring_seconds({"status": PhoneContacts.ONLINE})
	return away > online


func test_presence_label_per_status() -> bool:
	return (
		PhoneContacts.presence_label({"status": PhoneContacts.ONLINE}) == "Active now"
		and PhoneContacts.presence_label({"status": PhoneContacts.AWAY}) == "Away"
		and PhoneContacts.presence_label({"status": PhoneContacts.OFFLINE}) == "Offline"
	)


func test_at_least_one_friend_reachable() -> bool:
	for c in PhoneContacts.roster():
		if PhoneContacts.will_answer(c):
			return true
	return false
