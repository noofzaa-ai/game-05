extends RefCounted
## Repairing worn equipment at camp. Keeping an item in shape is cheap: gold and a little ore per
## point restored. Letting it wear down to nothing is expensive: a much higher gold price and several
## kinds of material. Both scale with the item's tier and are reduced by the workbench's discount.
## EXTENDING: a new repair rule (a repair kit item, free repairs on a quest) is another function here.

const CampData := preload("res://logic/camp_data.gd")
const Camp := preload("res://logic/camp.gd")
const Item := preload("res://logic/item.gd")
const Profile := preload("res://logic/profile.gd")


## What repairing `item` all the way would cost: {"kind": "none"|"normal"|"broken", "points": float,
## "gold": int, "materials": {id: count}}. `discount` is the workbench's fraction off (0..0.9).
static func quote(item: Item, camp: CampData, discount: float = 0.0) -> Dictionary:
	var missing := item.max_durability - item.durability
	if missing <= 0.0 or item.destroyed:
		return {"kind": "none", "points": 0.0, "gold": 0, "materials": {}}
	var kind := "broken" if item.is_broken_down() else "normal"
	var entry: Dictionary = camp.repair[kind]
	var tiers: Array = camp.repair["tier_multiplier"]
	var scale: float = float(tiers[mini(item.tier, tiers.size() - 1)]) * (1.0 - clampf(discount, 0.0, 0.9))
	var materials := {}
	for id in entry["materials_per_point"]:
		var count := ceili(missing * float(entry["materials_per_point"][id]) * scale)
		if count > 0:
			materials[id] = count
	return {"kind": kind, "points": missing, "gold": ceili(missing * float(entry["gold_per_point"]) * scale), "materials": materials}


## Repairs an item fully, paying from the profile's stash. The workbench must be built.
## Returns {"ok": bool, "reason": "nothing_to_repair" | "no_workbench" | "cannot_afford" | "", "cost": Dictionary}.
static func repair(item: Item, profile: Profile, camp: CampData) -> Dictionary:
	var cost := quote(item, camp, Camp.repair_discount(profile, camp))
	if cost["kind"] == "none":
		return {"ok": false, "reason": "nothing_to_repair", "cost": cost}
	if not Camp.is_built(profile, str(camp.repair["facility"])):
		return {"ok": false, "reason": "no_workbench", "cost": cost}
	if not profile.stash.pay(cost):
		return {"ok": false, "reason": "cannot_afford", "cost": cost}
	item.durability = item.max_durability
	return {"ok": true, "reason": "", "cost": cost}


## Repairs every item card `card` wears ("" = the lead card) that needs it, cheapest first, until the
## money or materials run out. Returns {"repaired": int, "skipped": int, "gold": int}.
static func repair_all_worn(profile: Profile, camp: CampData, card: String = "") -> Dictionary:
	var worn := profile.loadout_of(card).items()
	var discount := Camp.repair_discount(profile, camp)
	worn.sort_custom(func(a: Item, b: Item) -> bool: return quote(a, camp, discount)["gold"] < quote(b, camp, discount)["gold"])
	var summary := {"repaired": 0, "skipped": 0, "gold": 0}
	for item in worn:
		var result := repair(item, profile, camp)
		if result["ok"]:
			summary["repaired"] += 1
			summary["gold"] += int(result["cost"]["gold"])
		elif result["reason"] != "nothing_to_repair":
			summary["skipped"] += 1
	return summary
