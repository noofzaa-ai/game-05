extends RefCounted
## One-time purge of already-dropped level-15 gear (logic/gear_purge.gd; Boss 2026-11-17). Saves are built with
## migrations erased (= a save from before the purge) and loaded through Profile.from_dict and the profile runner.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const GearPurge := preload("res://logic/gear_purge.gd")
const Runner := preload("res://server/profile/runner.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const KEY := "gear_purge_lv15_v1"


func _make(rules, id: String, slot: String, item_id: String):
	var item = ItemSystem.create_item(rules, id, slot, 1, RandomNumberGenerator.new(), "", item_id)
	item.refine_level = 2
	item.durability = 55.5
	return item


## An old-version save: new player + the fixtures below, no migrations key.
func _old_save(rules, camp) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var p = Profile.new_player(rules, camp, rng)
	p.stash.capacity = 60
	p.card_deck["cards"]["sword_shield"]["progress"] = {"level": 3, "xp": 0}
	p.card_deck["cards"]["greatsword"]["progress"] = {"level": 15, "xp": 0}
	var ss_w: String = rules.catalog.race_piece(CardDeck.gear_race(p.card_deck, "sword_shield"), "sword_shield", "weapon")
	var gs_w: String = rules.catalog.race_piece(CardDeck.gear_race(p.card_deck, "greatsword"), "greatsword", "weapon")
	# card at 3 wears a lv15 weapon; card at 15 wears lv15 weapon + armour (stays)
	p.loadout_of("sword_shield").equip(_make(rules, "drop-w3", "weapon", ss_w))
	p.loadout_of("greatsword").equip(_make(rules, "drop-w15", "weapon", gs_w))
	p.loadout_of("greatsword").equip(_make(rules, "drop-a15", "shirt", "armour_greatsword_shirt"))
	p.stash.items.append(_make(rules, "drop-s1", "weapon", gs_w))
	p.stash.items.append(_make(rules, "drop-s2", "shoes", "armour_magic_shoes"))
	p.stash.items.append(_make(rules, "tier-up-keep", "pants", "armour_longbow_pants"))
	p.stash.items.append(_make(rules, "starter-keep", "shirt", "armour_longbow_shirt"))
	var socketed = _make(rules, "drop-sock", "armband", "armour_magic_armband")
	socketed.relic = "relic_test"
	p.stash.items.append(socketed)
	p.stash.items.append(_make(rules, "boss-1", "necklace", "boss_goblin_chief_necklace"))
	p.vault.items.append(_make(rules, "drop-v1", "pants", "armour_greatsword_pants"))
	p.vault.items.append(_make(rules, "boss-2", "ring", "boss_goblin_chief_ring"))
	var raw: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	raw.erase("migrations")
	raw.erase("migrations_log")
	return raw


func _ids(list: Array) -> Array:
	return list.map(func(i): return i.id)


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var fresh = Profile.new_player(rules, camp, RandomNumberGenerator.new())
	ctx.check("gear purge: a new player is marked purged", GearPurge.done(fresh))
	var raw := _old_save(rules, camp)
	var p = Profile.from_dict(raw.duplicate(true), rules, camp)
	ctx.check("gear purge: old save loads", p != null)
	if p == null:
		return
	var stash := _ids(p.stash.items)
	var vault := _ids(p.vault.items)
	ctx.check("gear purge: lv15 stash/vault drops removed (stash %s vault %s)" % [stash, vault], not stash.has("drop-s1") and not stash.has("drop-s2") and not vault.has("drop-v1") and not stash.has("drop-sock"))
	ctx.check("gear purge: starter, tier-up, boss accessories kept", stash.has("starter-keep") and stash.has("tier-up-keep") and stash.has("boss-1") and vault.has("boss-2"))
	var sword = p.loadout_of("sword_shield")
	var w = sword.item_at("weapon", 0)
	ctx.check("gear purge: card at 3 wearing lv15 weapon gets a starter weapon, never empty", w != null and w.id.begins_with("starter-") and w.id != "drop-w3")
	var gs = p.loadout_of("greatsword")
	ctx.check("gear purge: card at 15 keeps its lv15 weapon and armour", gs.item_at("weapon", 0).id == "drop-w15" and gs.item_at("shirt", 0).id == "drop-a15")
	ctx.check("gear purge: shield (offhand) untouched", sword.item_at("offhand", 0) != null)
	ctx.check("gear purge: relic returned to the stash", p.stash.material_count("relic_test") == 1)
	ctx.check("gear purge: flag set", GearPurge.done(p) and p.to_dict()["migrations"][KEY] == true)
	var log: Array = p.migrations_log.get(KEY, [])
	var logged := {}
	for entry in log:
		logged[entry["id"]] = entry
	ctx.check("gear purge: log has 5 removed items (%d)" % log.size(), log.size() == 5 and logged.has("drop-w3") and logged.has("drop-s1") and logged.has("drop-s2") and logged.has("drop-sock") and logged.has("drop-v1"))
	var e: Dictionary = logged.get("drop-w3", {})
	ctx.check("gear purge: log entry content", str(e.get("where", "")) == "worn:sword_shield:weapon" and e.get("refine") == 2 and is_equal_approx(float(e.get("dur", 0)), 55.5) and e.get("tier") == 1 and int(e.get("at", 0)) > 0 and str(e.get("item_id", "")).begins_with("race_") and str(logged["drop-s1"]["where"]) == "stash" and str(logged["drop-v1"]["where"]) == "vault")
	# idempotent / no-op afterwards, and a legitimate later drop survives a reload
	var saved: Dictionary = p.to_dict()
	var again = Profile.from_dict(JSON.parse_string(JSON.stringify(saved)), rules, camp)
	var again_d: Dictionary = again.to_dict()
	var diff: Array = []
	for k in saved:
		if saved[k] != again_d.get(k):
			diff.append(k)
	ctx.check("gear purge: reload is a no-op (same profile; differs: %s)" % [diff], again != null and diff.is_empty())
	var later = JSON.parse_string(JSON.stringify(saved))
	later["stash"]["items"].append(_make(rules, "drop-later", "weapon", rules.catalog.race_piece("viking", "greatsword", "weapon")).to_dict())
	var reloaded = Profile.from_dict(later, rules, camp)
	ctx.check("gear purge: a lv15 drop after the purge is kept", _ids(reloaded.stash.items).has("drop-later"))
	# a corrupted flag is not permissive: the purge runs
	var bad = JSON.parse_string(JSON.stringify(saved))
	bad["migrations"] = {KEY: "yes"}
	bad["stash"]["items"].append(_make(rules, "drop-bad", "weapon", rules.catalog.race_piece("viking", "greatsword", "weapon")).to_dict())
	var bp = Profile.from_dict(bad, rules, camp)
	ctx.check("gear purge: a corrupted flag counts as not purged", not _ids(bp.stash.items).has("drop-bad") and GearPurge.done(bp))
	# deterministic (timestamps aside)
	var p2 = Profile.from_dict(raw.duplicate(true), rules, camp)
	var a: Dictionary = p.to_dict()
	var b: Dictionary = p2.to_dict()
	for d in [a, b]:
		for entry in d["migrations_log"][KEY]:
			entry.erase("at")
	ctx.check("gear purge: deterministic", a == b)
	# profile runner path equals the offline path
	var runner = Runner.new()
	var res: Dictionary = runner.execute({"v": 1, "state": {"profile": raw.duplicate(true), "rng_state": "1"}, "seed": "abcdef012345678", "name": "Tester", "command": null})
	ctx.check("gear purge: runner ok", res.get("ok", false))
	if res.get("ok", false):
		var rp: Dictionary = res["profile"]
		var rstash: Array = (rp["stash"]["items"] as Array).map(func(i): return i["id"])
		ctx.check("gear purge: runner removes the same stash items and sets the flag", not rstash.has("drop-s1") and rstash.has("tier-up-keep") and rp["migrations"][KEY] == true and (rp["migrations_log"][KEY] as Array).size() == 5)
		ctx.check("gear purge: runner worn weapon refilled with a starter", str(rp["card_gear"]["sword_shield"]["loadout"]["equipped"]["weapon:0"]["id"]).begins_with("starter-"))
	# a saved run bag is purged with a freshly purged profile
	var gs_item: Dictionary = _make(rules, "drop-bag", "weapon", rules.catalog.race_piece("viking", "greatsword", "weapon")).to_dict()
	var st_item: Dictionary = _make(rules, "starter-bag", "pants", "armour_longbow_pants").to_dict()
	var run_raw: Dictionary = {"v": 1, "bag": {"v": 1, "capacity": 10, "gold": "0", "materials": {}, "items": [gs_item, st_item]}, "died": false, "used_rests": [], "profile": raw.duplicate(true)}
	var trip = preload("res://logic/run.gd").from_dict(run_raw, rules, camp)
	ctx.check("gear purge: run bag purged on the first load", trip != null and _ids(trip.bag.items) == ["starter-bag"])
	# an old save without any lv15 item only gets the flag
	var clean: Dictionary = JSON.parse_string(JSON.stringify(Profile.new_player(rules, camp, RandomNumberGenerator.new()).to_dict()))
	clean.erase("migrations")
	var cp = Profile.from_dict(clean, rules, camp)
	ctx.check("gear purge: clean old save only gets the flag", GearPurge.done(cp) and not cp.migrations_log.has(KEY))
