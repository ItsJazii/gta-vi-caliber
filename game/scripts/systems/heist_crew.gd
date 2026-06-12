class_name HeistCrew
extends RefCounted
## Pure model for assembling a heist crew (driver, hacker, gunman, ...).
##
## No scene access — a mission node owns one and feeds it members, then queries
## odds and payouts (unit-tested in tests/unit/test_heist_crew.gd). Each member
## takes a cut of the take; the player keeps whatever the crew does not. A more
## skilled crew raises the heist's success chance against a base difficulty.
##
## All randomness goes through a caller-supplied RandomNumberGenerator so a given
## seed always produces the same outcome — never the global randf/randi.

## How much a fully unskilled crew (skill 0) shifts the base difficulty, and how
## much a maxed crew (skill 1) helps. success = base_difficulty - DIFF + skill*SWING.
const SKILL_SWING: float = 0.6
const SKILL_FLOOR_PENALTY: float = 0.25

var max_members: int
## Each entry: {"role": String, "skill": float (0..1), "cut": float (0..1)}.
var members: Array[Dictionary] = []


func _init(max_member_count: int = 3) -> void:
	max_members = maxi(max_member_count, 0)


## Add a member. Fails if the crew is full, the role is already taken, or the
## new cut would push the crew's total cut over 1.0 (100%). Skill/cut clamped.
func add_member(role: String, skill: float, cut: float) -> bool:
	if role.is_empty():
		return false
	if members.size() >= max_members:
		return false
	if _has_role(role):
		return false
	var safe_cut := clampf(cut, 0.0, 1.0)
	if total_cut() + safe_cut > 1.0 + 0.000001:
		return false
	members.append({"role": role, "skill": clampf(skill, 0.0, 1.0), "cut": safe_cut})
	return true


## Drop a member by role. Returns true if one was removed.
func remove_member(role: String) -> bool:
	for i in members.size():
		if members[i]["role"] == role:
			members.remove_at(i)
			return true
	return false


func member_count() -> int:
	return members.size()


func roles() -> Array:
	var out: Array = []
	for member in members:
		out.append(member["role"])
	return out


## Sum of every member's cut (their combined share of the take).
func total_cut() -> float:
	var sum := 0.0
	for member in members:
		sum += float(member["cut"])
	return sum


## The player's share of the take: whatever the crew does not claim, floored 0.
func player_share() -> float:
	return maxf(1.0 - total_cut(), 0.0)


## Average member skill, 0..1; 0 when the crew is empty.
func crew_skill() -> float:
	if members.is_empty():
		return 0.0
	var sum := 0.0
	for member in members:
		sum += float(member["skill"])
	return sum / float(members.size())


## Odds of pulling the heist off, 0..1. A harder base_difficulty lowers it; a
## more skilled crew raises it. Clamped so it never leaves [0, 1].
func success_chance(base_difficulty: float) -> float:
	var base := clampf(base_difficulty, 0.0, 1.0)
	var raw := base - SKILL_FLOOR_PENALTY + crew_skill() * SKILL_SWING
	return clampf(raw, 0.0, 1.0)


## Roll the heist against success_chance using the supplied rng. Deterministic
## for a given seed — same seed, same result.
func attempt(base_difficulty: float, rng: RandomNumberGenerator) -> bool:
	if rng == null:
		return false
	return rng.randf() < success_chance(base_difficulty)


## The player's actual take on a heist outcome: their share of `take` on success,
## 0 on failure. Always non-negative, returned as whole currency.
func payout(take: int, success: bool) -> int:
	if not success or take <= 0:
		return 0
	return int(maxf(float(take) * player_share(), 0.0))


## Planning value: expected player take = chance * take * share.
func expected_payout(take: int, base_difficulty: float) -> float:
	if take <= 0:
		return 0.0
	return success_chance(base_difficulty) * float(take) * player_share()


## Deterministic-test helper: a fresh rng seeded with `seed_value`.
static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _has_role(role: String) -> bool:
	for member in members:
		if member["role"] == role:
			return true
	return false
