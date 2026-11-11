extends RefCounted
## Authority-owned refinement with server RNG and protected failure brackets for the existing main stat.
const SLOTS := ["weapon", "hat", "shirt", "armband", "pants", "shoes"]
static func quote(item, rules, camp) -> Dictionary:
	if item == null or item.destroyed or not item.slot in SLOTS: return {"ok": false, "reason": "invalid_item"}
	var config: Dictionary = rules.refine
	if config.is_empty() or not config.get("enabled", false): return {"ok": false, "reason": "not_configured"}
	if item.refine_level < 0: return {"ok": false, "reason": "invalid_item"}
	if item.refine_level >= int(config.max_level): return {"ok": false, "reason": "max_level"}
	for id in config.cost.materials:
		if not camp.materials.has(id): return {"ok": false, "reason": "not_configured"}
	var chance := float(config.success_chances[item.refine_level]) if config.has("success_chances") else float(config.success_chance)
	var floor_level := int(config.failure_floors[item.refine_level]) if config.has("failure_floors") else 0
	var failure_level := mini(item.refine_level, maxi(floor_level, item.refine_level - 1))
	return {"ok": true, "cost": config.cost.duplicate(true), "level": item.refine_level, "next_level": item.refine_level + 1, "success_chance": chance, "failure_level": failure_level}

static func apply(item, profile, rules, camp, expected_level: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if item == null or item.refine_level != expected_level: return {"ok": false, "reason": "conflict"}
	var offer := quote(item, rules, camp)
	if not offer.ok: return offer
	if not profile.stash.pay(offer.cost): return {"ok": false, "reason": "cannot_afford"}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var succeeded := float(offer.success_chance) >= 1.0 or rng.randf() < float(offer.success_chance)
	item.refine_level = int(offer.next_level) if succeeded else int(offer.failure_level)
	# Failed refinement is still a committed paid attempt, never a command error.
	return {"ok": true, "item": item.id, "level": item.refine_level, "success": succeeded, "previous_level": expected_level}
