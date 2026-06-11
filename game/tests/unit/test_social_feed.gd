extends RefCounted
## Unit tests for SocialFeed (see tests/run_tests.gd for the runner contract:
## test_* methods return true to pass).

const HANDLES: PackedStringArray = ["mara_b", "dev.ortiz", "cooper"]


func test_photo_posts_count() -> bool:
	return SocialFeed.photo_posts(HANDLES, 1, 12).size() == 12


func test_photo_posts_have_fields() -> bool:
	var post := SocialFeed.photo_posts(HANDLES, 7, 1)[0]
	for key in ["handle", "caption", "likes", "hue", "hue2", "liked"]:
		if not post.has(key):
			return false
	return true


func test_photo_posts_deterministic_for_seed() -> bool:
	var first := SocialFeed.photo_posts(HANDLES, 42, 6)
	var second := SocialFeed.photo_posts(HANDLES, 42, 6)
	return first == second


func test_photo_posts_differ_by_seed() -> bool:
	return SocialFeed.photo_posts(HANDLES, 1, 6) != SocialFeed.photo_posts(HANDLES, 2, 6)


func test_photo_hue_in_unit_range() -> bool:
	for post in SocialFeed.photo_posts(HANDLES, 3, 20):
		var hue: float = post["hue"]
		if hue < 0.0 or hue > 1.0:
			return false
	return true


func test_photo_likes_within_bounds() -> bool:
	for post in SocialFeed.photo_posts(HANDLES, 9, 30):
		var likes: int = post["likes"]
		if likes < 3 or likes > 4200:
			return false
	return true


func test_photo_authors_cycle_handles() -> bool:
	var posts := SocialFeed.photo_posts(HANDLES, 5, 3)
	return posts[0]["handle"] == "mara_b" and posts[2]["handle"] == "cooper"


func test_photo_posts_empty_handles_yields_nothing() -> bool:
	return SocialFeed.photo_posts(PackedStringArray(), 1, 5).is_empty()


func test_chirp_posts_have_fields() -> bool:
	var post := SocialFeed.chirp_posts(HANDLES, 2, 1)[0]
	for key in ["handle", "text", "likes", "reposts"]:
		if not post.has(key):
			return false
	return not String(post["text"]).is_empty()


func test_chirp_posts_deterministic_for_seed() -> bool:
	var first := SocialFeed.chirp_posts(HANDLES, 11, 8)
	var second := SocialFeed.chirp_posts(HANDLES, 11, 8)
	return first == second


func test_stories_one_per_handle() -> bool:
	return SocialFeed.stories(HANDLES, 1).size() == HANDLES.size()


func test_stories_hue_in_unit_range() -> bool:
	for s in SocialFeed.stories(HANDLES, 4):
		var hue: float = s["hue"]
		if hue < 0.0 or hue > 1.0:
			return false
	return true


func test_format_count_below_thousand_is_plain() -> bool:
	return SocialFeed.format_count(980) == "980" and SocialFeed.format_count(0) == "0"


func test_format_count_thousands_abbreviated() -> bool:
	return SocialFeed.format_count(1200) == "1.2k"
