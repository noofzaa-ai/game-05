extends RefCounted
## Compatibility facade for capture tools. Ownership provisioning lives in logic/.
const Kit := preload("res://logic/test_kit.gd")
static func item_ids(profile, item_rules) -> Array[String]:
	return Kit.item_ids(profile, item_rules)
static func fill(profile, item_rules, camp_data, rng: RandomNumberGenerator) -> int:
	return Kit.fill(profile, item_rules, camp_data, rng)
