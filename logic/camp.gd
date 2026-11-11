extends RefCounted
## The rules of the camp: how big the bags are, what the facilities give, camp skills, and paying for
## camp and facility upgrades out of the stash. The numbers are data (data/camp/camp.json).
## EXTENDING: a new facility effect is read here (through CampData.effect_total) where it applies.

const CampData := preload("res://logic/camp_data.gd")
const Profile := preload("res://logic/profile.gd")


## Slots of the run bag the player takes into a stage.
static func bag_slots(profile: Profile, camp: CampData) -> int:
	return camp.run_slots + int(camp.effect_total(profile.facility_levels, "bag_slots"))


static func stash_slots(profile: Profile, camp: CampData) -> int:
	return camp.stash_slots + profile.bonus_stash_slots + int(camp.effect_total(profile.facility_levels, "stash_slots"))


## Call after anything that can change the stash size (an upgrade, a new profile).
static func refresh(profile: Profile, camp: CampData) -> void:
	profile.stash.capacity = stash_slots(profile, camp)


## The fraction taken off repair prices by the facilities (0..0.9).
static func repair_discount(profile: Profile, camp: CampData) -> float:
	return clampf(camp.effect_total(profile.facility_levels, "repair_discount"), 0.0, 0.9)


## Flat stat bonuses from the camp skills the camp level has unlocked: stat -> amount.
static func skill_bonus(profile: Profile, camp: CampData) -> Dictionary:
	var bonus := {}
	for skill in camp.skills:
		if profile.camp_level >= int(skill["camp_level"]):
			for stat in skill["stats"]:
				bonus[stat] = float(bonus.get(stat, 0.0)) + float(skill["stats"][stat])
	return bonus


## Has the player built this facility (level 1 or more)?
static func is_built(profile: Profile, facility_id: String) -> bool:
	return int(profile.facility_levels.get(facility_id, 0)) >= 1


## What the next camp level costs, or {} when the camp is at its top level.
static func next_camp_cost(profile: Profile, camp: CampData) -> Dictionary:
	if profile.camp_level >= camp.max_camp_level():
		return {}
	return camp.camp_levels[profile.camp_level - 1]["cost"]


## Shared by the authoritative command runner and UI; evaluated before any payment.
static func camp_upgrade_blockers(profile: Profile, camp: CampData) -> Array[String]:
	var missing: Array[String] = []
	for id in camp.progression_facilities:
		if int(profile.facility_levels.get(id, 0)) < profile.camp_level: missing.append(id)
	return missing


## Raises the camp level by one, paying from the stash. Returns {"ok": bool, "reason": String}.
static func upgrade_camp(profile: Profile, camp: CampData) -> Dictionary:
	if profile.camp_level >= camp.max_camp_level():
		return {"ok": false, "reason": "max_level"}
	var blockers := camp_upgrade_blockers(profile, camp)
	if not blockers.is_empty():
		return {"ok": false, "reason": "facilities_not_ready", "facilities": blockers}
	if not profile.stash.pay(next_camp_cost(profile, camp)):
		return {"ok": false, "reason": "cannot_afford"}
	profile.camp_level += 1
	refresh(profile, camp)
	return {"ok": true, "reason": ""}


## What the next level of a facility is (its camp level requirement, cost and effects), or {} if none.
static func next_facility_level(profile: Profile, camp: CampData, facility_id: String) -> Dictionary:
	if int(profile.facility_levels.get(facility_id, 0)) >= camp.max_camp_level(): return {}
	return camp.level_data(facility_id, int(profile.facility_levels.get(facility_id, 0)) + 1)


## Builds or upgrades a facility one level, paying from the stash.
## Returns {"ok": bool, "reason": "unknown_facility" | "max_level" | "camp_level_too_low" | "cannot_afford" | ""}.
static func upgrade_facility(profile: Profile, camp: CampData, facility_id: String) -> Dictionary:
	if not camp.facilities.has(facility_id):
		return {"ok": false, "reason": "unknown_facility"}
	var next := next_facility_level(profile, camp, facility_id)
	if next.is_empty():
		return {"ok": false, "reason": "max_level"}
	var next_level := int(profile.facility_levels.get(facility_id, 0)) + 1
	if next_level > profile.camp_level or profile.camp_level < int(next["camp_level"]):
		return {"ok": false, "reason": "camp_level_too_low"}
	if not profile.stash.pay(next["cost"]):
		return {"ok": false, "reason": "cannot_afford"}
	profile.facility_levels[facility_id] = int(profile.facility_levels.get(facility_id, 0)) + 1
	refresh(profile, camp)
	return {"ok": true, "reason": ""}
