extends RefCounted
## Legacy item conversion (logic/legacy_items.gd; Boss 2026-11-13 "remove everything from the old item system"): an old
## save's legacy pieces (worn by any card, in the stash, the vault and a saved run bag) become race pieces of the same
## slot and tier, keeping the instance id, upgrades, refine, substats and durability; worn pieces take the wearing card's
## race and class, unworn ones the first squad card's race. Once (legacy_item_version), deterministic and idempotent on
## the client load and on the server profile runner path.
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const LegacyItems := preload("res://logic/legacy_items.gd")
const CardDeck := preload("res://logic/card_deck.gd")


## A saved item dictionary with a legacy item_id (the old catalog's ids are gone, so it is built by hand like a save).
static func legacy(id: String, slot: String, item_id: String, tier: int, level: int, refine: int, weapon_type: String = "") -> Dictionary:
	var item := preload("res://logic/item.gd").new()
	item.id = id
	item.slot = slot
	item.tier = tier
	item.level = level
	item.upgrade_count = level + 2
	item.refine_level = refine
	item.main_stat = "ATK" if slot == "weapon" else ("HP" if slot == "pants" else "DEF")
	item.weapon_type = weapon_type
	item.substats.append({"stat": "CRIRATE", "quality": 0.75, "boosts": level, "upgrade_bonus": 1.5})
	item.substats.append({"stat": "ATKSPD", "quality": 0.25, "boosts": 0, "upgrade_bonus": 0.0})
	item.durability = 62.5
	var saved: Dictionary = item.to_dict()
	saved["item_id"] = item_id  # set after building: the old id is no longer a catalog item
	return saved


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var fresh = Profile.new_player(rules, camp, rng)
	ctx.check("legacy items: a new player is already at the conversion version", fresh.legacy_item_version == LegacyItems.VERSION)

	# A realistic pre-removal save: the S&S card (Human) wears an upgraded epic blade_05, Ash steel shirt +7 refine 3 and
	# round_shield; the greatsword card (Viking) wears an old Obsidian leather armband; the stash holds a legendary
	# Royal cloth shoes and a starter_staff; the vault an old scout_vest and a destroyed blade_02. No legacy flag.
	var old: Dictionary = JSON.parse_string(JSON.stringify(fresh.to_dict()))
	old.erase("legacy_item_version")
	old["card_deck"]["cards"]["sword_shield"]["race"] = "human"
	old["card_deck"]["cards"]["greatsword"]["race"] = "viking"
	old["card_deck"]["squad"] = ["longbow", "sword_shield", "greatsword"]
	old["card_deck"]["cards"]["longbow"]["race"] = "elf"
	var ss: Dictionary = old["card_gear"]["sword_shield"]["loadout"]["equipped"]
	ss["weapon:0"] = legacy("old-katana", "weapon", "blade_05", 2, 6, 2, "blade")
	ss["shirt:0"] = legacy("old-cuirass", "shirt", "armor_ash_steel_shirt", 2, 7, 3)
	ss["offhand:0"] = legacy("old-shield", "offhand", "round_shield", 1, 2, 0)
	old["card_gear"]["greatsword"]["loadout"]["equipped"]["armband:0"] = legacy("old-armband", "armband", "armor_obsidian_leather_armband", 1, 3, 1)
	(old["stash"]["items"] as Array).append(legacy("old-shoes", "shoes", "armor_royal_cloth_shoes", 3, 9, 4))
	(old["stash"]["items"] as Array).append(legacy("old-staff", "weapon", "starter_staff", 0, 0, 0, "magic"))
	(old["vault"]["items"] as Array).append(legacy("old-vest", "shirt", "scout_vest", 1, 1, 0))
	var broken := legacy("old-broken", "weapon", "blade_02", 1, 4, 0, "blade")
	broken["destroyed"] = true
	(old["vault"]["items"] as Array).append(broken)
	var raw := JSON.stringify(old)
	var p = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("legacy items: the old save loads", p != null)
	if p == null:
		return
	var by_id := {}
	for list in p.worn_lists():
		for item in list:
			by_id[item.id] = item
	for item in p.stash.items + p.vault.items:
		by_id[item.id] = item
	var expect := {
		"old-katana": "race_human_sword_shield_weapon", "old-cuirass": "race_human_sword_shield_shirt", "old-shield": "race_human_shield",
		"old-armband": "race_viking_greatsword_armband",
		"old-shoes": "race_elf_magic_shoes", "old-staff": "race_elf_magic_weapon", "old-vest": "race_elf_sword_shield_shirt", "old-broken": "race_elf_sword_shield_weapon"}
	var wrong: Array = []
	for id in expect:
		if not by_id.has(id) or by_id[id].item_id != expect[id]:
			wrong.append("%s=%s" % [id, by_id[id].item_id if by_id.has(id) else "missing"])
	ctx.check("legacy items: worn pieces take the card's race and class, unworn the first squad card's race (wrong: %s)" % [wrong], wrong.is_empty())
	var katana = by_id.get("old-katana")
	var kept: bool = katana != null and katana.tier == 2 and katana.level == 6 and katana.refine_level == 2 and katana.upgrade_count == 8 \
		and katana.substats.size() == 2 and katana.substats[0]["stat"] == "CRIRATE" and katana.substats[0]["boosts"] == 6 and is_equal_approx(float(katana.substats[0]["upgrade_bonus"]), 1.5) \
		and is_equal_approx(katana.durability, 62.5) and katana.weapon_type == "blade"
	ctx.check("legacy items: tier, level, refine, upgrade count, substats and durability are kept", kept)
	var shoes = by_id.get("old-shoes")
	ctx.check("legacy items: a legendary stays legendary, slot kept", shoes != null and shoes.tier == 3 and shoes.level == 9 and shoes.refine_level == 4 and shoes.slot == "shoes")
	ctx.check("legacy items: a destroyed piece stays destroyed", by_id.has("old-broken") and by_id["old-broken"].destroyed)
	ctx.check("legacy items: the S&S card still wears its converted gear (no starter piece pushed it out)", p.loadout_of("sword_shield").item_at("weapon", 0).id == "old-katana" and p.loadout_of("sword_shield").item_at("shirt", 0).id == "old-cuirass" and p.loadout_of("sword_shield").item_at("offhand", 0).id == "old-shield")
	var unknown := 0
	for item in by_id.values():
		if rules.catalog.entry(item.item_id).is_empty() and item.slot in ["weapon", "offhand", "shirt", "pants", "armband", "shoes"]:
			unknown += 1
	ctx.check("legacy items: no weapon, shield or armour piece is left with an unknown item id", unknown == 0)
	ctx.check("legacy items: version saved", p.legacy_item_version == LegacyItems.VERSION and int(p.to_dict().get("legacy_item_version", 0)) == LegacyItems.VERSION)
	ctx.check("legacy items: the stats come from the race piece (main stat of the new slot)", by_id["old-cuirass"].main_stat == "DEF" and by_id["old-katana"].stat_totals(rules).size() >= 2)
	var again = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("legacy items: deterministic (same save -> same profile)", again != null and again.to_dict() == p.to_dict())
	var reload = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), rules, camp)
	ctx.check("legacy items: reloading changes nothing", reload != null and reload.to_dict() == p.to_dict())
	# Idempotent even without the flag (a server field list that drops it): a converted piece never converts again.
	var no_flag: Dictionary = p.to_dict()
	no_flag.erase("legacy_item_version")
	var replay = Profile.from_dict(JSON.parse_string(JSON.stringify(no_flag)), rules, camp)
	ctx.check("legacy items: converting twice changes nothing", replay != null and replay.to_dict() == p.to_dict())
	# A later race change of the card does not re-dress already converted gear.
	var swapped: Dictionary = p.to_dict()
	swapped["card_deck"]["cards"]["sword_shield"]["race"] = "runeborn"
	var s2 = Profile.from_dict(JSON.parse_string(JSON.stringify(swapped)), rules, camp)
	ctx.check("legacy items: runs once (a later race change keeps the converted pieces)", s2.loadout_of("sword_shield").item_at("weapon", 0).item_id == "race_human_sword_shield_weapon")

	# Server path: the profile runner loads the same old save (state + rng) and returns converted, idempotent gear.
	var runner := preload("res://server/profile/runner.gd").new()
	var request := {"v": 1, "state": {"profile": JSON.parse_string(raw), "rng_state": "77"}, "seed": "00000000000004d", "name": "Hero", "command": null}
	var borrowed: Dictionary = request.state.profile.duplicate(true)
	var first: Dictionary = runner.execute(request)
	var unmutated: bool = request.state.profile == borrowed
	var served: String = JSON.stringify(first.get("profile", {}))
	ctx.check("legacy items (server runner): the old save converts", first.get("ok", false) and served.contains("race_human_sword_shield_weapon") and not served.contains("blade_05") and not served.contains("round_shield") and int(first.profile.get("legacy_item_version", 0)) == LegacyItems.VERSION)
	request.state = {"profile": first.profile, "rng_state": first.rng_state}
	var second: Dictionary = runner.execute(request)
	ctx.check("legacy items (server runner): a second load is identical", second.get("ok", false) and second.profile == first.profile)
	ctx.check("legacy items (server runner): the borrowed request state is not mutated", unmutated)

	# A saved run bag with a legacy piece.
	var trip = Run.start(p, camp)
	var bag: Dictionary = trip.to_dict(false)
	(bag["bag"]["items"] as Array).append(legacy("old-bag-pants", "pants", "armor_ash_leather_pants", 1, 0, 0))
	var restored = Run.from_dict(JSON.parse_string(JSON.stringify(bag)), rules, camp, p)
	ctx.check("legacy items: a saved run bag's piece converts (first squad card's race, light -> longbow)", restored != null and restored.bag.items.any(func(i): return i.id == "old-bag-pants" and i.item_id == "race_elf_longbow_pants" and i.tier == 1))
