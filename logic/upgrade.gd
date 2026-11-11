extends RefCounted
## Server RNG picks a new distinct row until four, then one existing row to boost.
static func quote(item, rules, camp) -> Dictionary:
	if item == null or item.destroyed or rules.slot(item.slot).is_empty() or item.tier < 0 or item.tier >= rules.tiers.size(): return {"ok": false, "reason": "invalid_item"}
	var cfg: Dictionary = rules.upgrade
	if cfg.is_empty() or not cfg.get("enabled", false): return {"ok": false, "reason": "not_configured"}
	if item.upgrade_count < 0 or item.substats.size() > int(cfg.max_substats): return {"ok": false, "reason": "invalid_item"}
	if item.upgrade_count >= int(cfg.max_attempts): return {"ok": false, "reason": "max_level"}
	var seen := {}
	for sub in item.substats:
		if not sub.stat in rules.stat_ids or sub.stat == item.main_stat or seen.has(sub.stat): return {"ok": false, "reason": "invalid_item"}
		seen[sub.stat] = true
	for id in cfg.cost.materials:
		if not camp.materials.has(id): return {"ok": false, "reason": "not_configured"}
	return {"ok": true, "cost": cfg.cost.duplicate(true), "add_row": item.substats.size() < int(cfg.max_substats), "used": item.upgrade_count, "max": int(cfg.max_attempts)}


static func apply(item, profile, rules, camp, expected_count: int, rng: RandomNumberGenerator) -> Dictionary:
	if item == null or item.upgrade_count != expected_count: return {"ok": false, "reason": "conflict"}
	var offer := quote(item, rules, camp)
	if not offer.ok: return offer
	if not profile.stash.can_afford(offer.cost): return {"ok": false, "reason": "cannot_afford"}
	var candidates: Array[String] = []
	if offer.add_row:
		for stat in rules.stat_ids:
			if stat == item.main_stat: continue
			var taken := false
			for sub in item.substats:
				if sub.stat == stat: taken = true
			if not taken: candidates.append(stat)
		if candidates.is_empty(): return {"ok": false, "reason": "invalid_item"}
	if not profile.stash.pay(offer.cost): return {"ok": false, "reason": "cannot_afford"}
	var index: int
	var bonus := 0.0
	if offer.add_row:
		var stat: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		item.substats.append({"stat": stat, "quality": rng.randf(), "boosts": 0, "upgrade_bonus": 0.0})
		index = item.substats.size() - 1
	else:
		index = rng.randi_range(0, item.substats.size() - 1)
		var sub: Dictionary = item.substats[index]
		bonus = float(rules.upgrade.increments[sub.stat][item.tier])
		sub["upgrade_bonus"] = float(sub.get("upgrade_bonus", 0.0)) + bonus
	item.upgrade_count += 1
	return {"ok": true, "item": item.id, "count": item.upgrade_count, "row": index, "stat": item.substats[index].stat, "added_row": offer.add_row, "bonus": bonus}
