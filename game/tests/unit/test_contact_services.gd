extends RefCounted
## Unit tests for ContactServices (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).
##
## Includes a PhoneContacts composition test (a service only fires if its contact
## actually picks up).


func test_default_services_loaded() -> bool:
	var s := ContactServices.new()
	return s.service_count() == 5 and s.has_service("lower_wanted") and s.has_service("mechanic")


func test_malformed_services_dropped() -> bool:
	var s := (
		ContactServices
		. new(
			[
				{"id": "ok", "cost": 100},
				{"id": "", "cost": 100},
				{"cost": 100},  # no id
				{"id": "free", "cost": 0},  # non-positive cost
				{"id": "ok", "cost": 200},  # duplicate id
			]
		)
	)
	return s.service_count() == 1 and s.has_service("ok")


func test_lookups() -> bool:
	var s := ContactServices.new()
	return (
		s.contact_of("mechanic") == "Devin"
		and s.cost_of("mechanic") == 1000
		and s.kind_of("mechanic") == "vehicle"
		and s.cost_of("nope") == -1
	)


func test_request_success_deducts() -> bool:
	var s := ContactServices.new()
	var r := s.request("mechanic", 0.0, 5000)
	return (
		r["success"] and r["cost"] == 1000 and r["new_balance"] == 4000 and r["kind"] == "vehicle"
	)


func test_request_unknown_fails() -> bool:
	var s := ContactServices.new()
	return not s.request("nope", 0.0, 5000)["success"]


func test_request_insufficient_funds() -> bool:
	var s := ContactServices.new()
	var r := s.request("lower_wanted", 0.0, 100)
	return not r["success"] and r["new_balance"] == 100


func test_request_unreachable_fails() -> bool:
	var s := ContactServices.new()
	var r := s.request("backup", 0.0, 9999, false)
	return not r["success"] and r["reason"].contains("pick up")


func test_cooldown_blocks_refire() -> bool:
	var s := ContactServices.new()
	s.request("mechanic", 0.0, 5000)  # cooldown 120
	var soon := s.request("mechanic", 60.0, 5000)
	var later := s.request("mechanic", 120.0, 5000)
	return not soon["success"] and later["success"]


func test_cooldown_remaining_and_ready() -> bool:
	var s := ContactServices.new()
	s.request("mechanic", 0.0, 5000)
	return (
		is_equal_approx(s.cooldown_remaining("mechanic", 30.0), 90.0)
		and not s.is_ready("mechanic", 30.0)
	)


func test_can_use_gates() -> bool:
	var s := ContactServices.new()
	var afford_online := s.can_use("mechanic", 0.0, 5000, true)
	var afford_offline := s.can_use("mechanic", 0.0, 5000, false)
	var broke := s.can_use("mechanic", 0.0, 100, true)
	return afford_online and not afford_offline and not broke


func test_reset_clears_cooldowns() -> bool:
	var s := ContactServices.new()
	s.request("mechanic", 100.0, 5000)
	s.reset_cooldowns()
	return s.is_ready("mechanic", 0.0)


func test_phone_contacts_gate_service() -> bool:
	# Composition: PhoneContacts.will_answer decides if the service connects.
	var s := ContactServices.new()
	var devin_online := PhoneContacts.will_answer(PhoneContacts.by_name("Devin"))  # ONLINE
	var tomas_offline := PhoneContacts.will_answer(PhoneContacts.by_name("Tomas"))  # OFFLINE
	var mechanic := s.request("mechanic", 0.0, 5000, devin_online)
	var backup := s.request("backup", 0.0, 9999, tomas_offline)
	return mechanic["success"] and not backup["success"]
