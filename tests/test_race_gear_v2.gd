extends RefCounted
## Race gear revision (design/gdd/race-gear-sets.md "Boss revision 2026-11-16"): the race set is the WEAPON only (bonus tests:
## tests/test_race_sets.gd), armour is CLASS-bound (armour_<class>_<slot>, any race wears it), the class armour and the
## race weapons are the level-15 generation (catalog req_level, enforced by the equip command), old race armour ids in a save
## migrate to the class armour keeping tier/durability/refine/substats, the Equipment tab filter hides other classes' armour.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Commands := preload("res://logic/commands.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RaceDrops := preload("res://logic/race_drops.gd")
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const ARMOUR := ["shirt", "pants", "armband", "shoes"]
const RACES := ["human", "viking", "elf", "runeborn"]


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var cosmetics = preload("res://logic/cosmetic_options.gd").load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1116
	_catalog(ctx, rules)
	_class_bound(ctx, rules)
	_level_gate(ctx, rules, camp, cosmetics, rng)
	_migration(ctx, rules, camp, rng)
	_drops(ctx, rules)


func _catalog(ctx, rules) -> void:
	var armour: Array = rules.catalog.items.keys().filter(func(id): return str(id).begins_with("armour_"))
	var race_armour: Array = rules.catalog.items.keys().filter(func(id): return str(id).begins_with("race_") and ARMOUR.has(rules.catalog.entry(id)["slot"]))
	ctx.check("race gear v2: 16 class armour pieces, no race armour left (%d / %d)" % [armour.size(), race_armour.size()], armour.size() == 16 and race_armour.is_empty())
	var ok := true
	for cls in CLASSES:
		for slot in ARMOUR:
			var e: Dictionary = rules.catalog.entry("armour_%s_%s" % [cls, slot])
			ok = ok and str(e.get("class", "")) == cls and e["set"] == "" and e["req_level"] == 15 and e["slot"] == slot
		for race in RACES:
			ok = ok and rules.catalog.entry("race_%s_%s_weapon" % [race, cls])["req_level"] == 15
	ctx.check("race gear v2: class armour and race weapons need level 15, armour has no set", ok)
	ctx.check("race gear v2: the race shield has no level gate", rules.catalog.req_level("race_human_shield") == 1)


func _class_bound(ctx, rules) -> void:
	var ok := true
	var refuses := true
	for card in CLASSES:
		for other in CLASSES:
			for slot in ARMOUR:
				var item = ItemSystem.create_item(rules, "t-%s-%s" % [other, slot], slot, 0, RandomNumberGenerator.new(), "", "armour_%s_%s" % [other, slot])
				var problem := Profile.slot_problem(card, item, rules)
				if other == card:
					ok = ok and problem.is_empty()
				else:
					refuses = refuses and problem == "wrong_armour_class"
	ctx.check("class armour: a card wears its own class armour", ok)
	ctx.check("class armour: another class's armour is refused (wrong_armour_class)", refuses)
	# Any race wears the class armour: the item is the same whoever the race; the card race never enters the rule.
	var same := true
	for card in CLASSES:
		var shirt = ItemSystem.create_item(rules, "t-shirt", "shirt", 0, RandomNumberGenerator.new(), "", "armour_%s_shirt" % card)
		for race in RACES:
			same = same and rules.catalog.race_piece(race, card, "shirt") == shirt.item_id and Profile.card_can_wear(card, shirt, rules)
	ctx.check("class armour: every race resolves to the same class armour and may wear it", same)
	# The Equipment tab filter agrees with the equip rule (hides other classes' armour).
	var items: Array = []
	for id in rules.catalog.items:
		var e: Dictionary = rules.catalog.entry(id)
		if str(e.get("boss", "")).is_empty():
			items.append(ItemSystem.create_item(rules, "f-" + str(id), str(e["slot"]), 0, RandomNumberGenerator.new(), "", str(id)))
	var filter_ok := true
	for card in CLASSES:
		var shown: Array = Profile.wearable_items(card, items, rules)
		var armour_ids: Array = shown.filter(func(i): return ARMOUR.has(i.slot)).map(func(i): return i.item_id)
		filter_ok = filter_ok and armour_ids.size() == 4 and armour_ids.all(func(id): return str(id).begins_with("armour_" + card + "_"))
	ctx.check("class armour: the Equipment tab filter shows only the card's own class armour", filter_ok)


func _level_gate(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = Profile.new_player(rules, camp, rng)
	var state := {"profile": p, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}
	var piece = ItemSystem.create_item(rules, "lvl15-shirt", "shirt", 1, rng, "", "armour_sword_shield_shirt")
	var blade = ItemSystem.create_item(rules, "lvl15-blade", "weapon", 1, rng, "", "race_human_sword_shield_weapon")
	p.stash.add_item(piece)
	p.stash.add_item(blade)
	var low: Dictionary = Commands.apply(state, {"type": "equip", "item": "lvl15-shirt", "source": "stash", "card": "sword_shield"}, rng)
	ctx.check("level 15 gate: a level-1 card is refused class armour (%s)" % [low.get("error", "")], not low.get("ok", false) and low.get("error", "") == "level_too_low" and p.stash.items.has(piece))
	var low_weapon: Dictionary = Commands.apply(state, {"type": "equip", "item": "lvl15-blade", "source": "stash", "card": "sword_shield"}, rng)
	ctx.check("level 15 gate: a level-1 card is refused a race weapon", low_weapon.get("error", "") == "level_too_low" and p.stash.items.has(blade))
	p.card_deck["cards"]["sword_shield"]["progress"] = {"level": 14, "xp": 0}
	ctx.check("level 15 gate: level 14 is still refused", Commands.apply(state, {"type": "equip", "item": "lvl15-shirt", "source": "stash", "card": "sword_shield"}, rng).get("error", "") == "level_too_low")
	p.card_deck["cards"]["sword_shield"]["progress"] = {"level": 15, "xp": 0}
	var ok: Dictionary = Commands.apply(state, {"type": "equip", "item": "lvl15-shirt", "source": "stash", "card": "sword_shield"}, rng)
	ctx.check("level 15 gate: level 15 equips the class armour", ok.get("ok", false) and p.loadout_of("sword_shield").item_at("shirt", 0) == piece)
	var ok_weapon: Dictionary = Commands.apply(state, {"type": "equip", "item": "lvl15-blade", "source": "stash", "card": "sword_shield"}, rng)
	ctx.check("level 15 gate: level 15 equips the race weapon", ok_weapon.get("ok", false) and p.loadout_of("sword_shield").item_at("weapon", 0) == blade)
	# Starter kit pieces stay level 1 (a level-1 card wears them, and re-wearing a starter piece is allowed).
	var fresh = Profile.new_player(rules, camp, rng)
	var starter = fresh.loadout_of("magic").item_at("shirt", 0)
	ctx.check("level 15 gate: the starter kit stays level 1 (%s)" % starter.id, starter.id.begins_with("starter-") and fresh.wear_problem("magic", starter, rules).is_empty())
	# The wrong-class refusal comes before the level one; the equip command's error is the shared rule's.
	var wrong = ItemSystem.create_item(rules, "wrong-shirt", "shirt", 0, rng, "", "armour_longbow_shirt")
	ctx.check("level 15 gate: wear_problem reports the class first, then the level", fresh.wear_problem("magic", wrong, rules) == "wrong_armour_class" and fresh.wear_problem("longbow", wrong, rules) == "level_too_low")


func _migration(ctx, rules, camp, rng: RandomNumberGenerator) -> void:
	var p = Profile.new_player(rules, camp, rng)
	var old: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var gs: Dictionary = old["card_gear"]["greatsword"]["loadout"]["equipped"]
	var ss: Dictionary = old["card_gear"]["sword_shield"]["loadout"]["equipped"]
	var made: Array = []  # [instance id, old item_id]
	var add := func(bag: Variant, key: String, id: String, slot: String, tier: int, old_id: String) -> void:
		var item = ItemSystem.create_item(rules, id, slot, tier, RandomNumberGenerator.new(), "", "armour_greatsword_" + slot)
		item.level = 4
		item.refine_level = 2
		item.durability = 41.5
		item.upgrade_count = 3
		item.relic = ""
		var d: Dictionary = item.to_dict()
		d["item_id"] = old_id
		if bag is Dictionary:
			bag[key] = d
		else:
			(bag as Array).append(d)
		made.append([id, old_id, tier, d["substats"].size(), item.refine_level, 41.5])
	add.call(gs, "shirt:0", "worn-shirt", "shirt", 2, "race_viking_greatsword_shirt")      # right class, kept worn
	add.call(ss, "pants:0", "worn-wrong", "pants", 1, "race_elf_magic_pants")               # another class's armour on the S&S card
	add.call(old["stash"]["items"], "", "stash-boots", "shoes", 3, "race_runeborn_longbow_shoes")
	add.call(old["vault"]["items"], "", "vault-band", "armband", 1, "race_human_sword_shield_armband")
	var items_before := made.size()
	var m = Profile.from_dict(JSON.parse_string(JSON.stringify(old)), rules, camp)
	ctx.check("armour migration: the old save loads", m != null)
	if m == null:
		return
	var everything: Array = []
	for list in m.worn_lists():
		everything.append_array(list)
	everything.append_array(m.stash.items)
	everything.append_array(m.vault.items)
	var all_ok := true
	var report: Array = []
	for row in made:
		var found = null
		for item in everything:
			if item.id == row[0]:
				found = item
		if found == null:
			all_ok = false
			report.append(row[0] + " LOST")
			continue
		var entry: Dictionary = rules.catalog.entry(found.item_id)
		var good: bool = found.item_id.begins_with("armour_") and entry["slot"] == found.slot and found.tier == row[2] and found.level == 4 and found.refine_level == row[4] and absf(found.durability - row[5]) < 0.01 and found.substats.size() == row[3] and found.upgrade_count == 3
		all_ok = all_ok and good
		report.append("%s=%s" % [row[0], found.item_id])
	ctx.check("armour migration: every old race armour piece survives as class armour with its tier, durability, refine, upgrades, substats (%s)" % ", ".join(report), all_ok and items_before == 4)
	ctx.check("armour migration: worn right-class piece stays worn", m.loadout_of("greatsword").item_at("shirt", 0).id == "worn-shirt" and m.loadout_of("greatsword").item_at("shirt", 0).item_id == "armour_greatsword_shirt")
	ctx.check("armour migration: another class's armour leaves the card for the stash, a starter piece takes the slot", m.stash.items.any(func(i): return i.id == "worn-wrong" and i.item_id == "armour_magic_pants") and m.loadout_of("sword_shield").item_at("pants", 0) != null and m.loadout_of("sword_shield").item_at("pants", 0).item_id == "armour_sword_shield_pants")
	var armour_ids: Array = []
	for item in everything:
		if ARMOUR.has(item.slot):
			armour_ids.append(item.item_id)
	ctx.check("armour migration: no race_* armour id remains anywhere", armour_ids.all(func(id): return str(id).begins_with("armour_")))
	var reload = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	ctx.check("armour migration: idempotent (reload changes nothing)", reload != null and reload.to_dict() == m.to_dict())
	var runner := preload("res://server/profile/runner.gd").new()
	var served: Dictionary = runner.execute({"v": 1, "state": {"profile": old, "rng_state": "1"}, "seed": "00000000000004d", "name": "Hero", "command": null})
	var text := JSON.stringify(served.get("profile", {}))
	ctx.check("armour migration: the server profile runner migrates the same save", served.get("ok", false) and text.contains("armour_magic_pants") and not text.contains("race_elf_magic_pants") and text.contains("stash-boots"))


func _drops(ctx, rules) -> void:
	var picks: Array = [{"race": "viking", "class": "greatsword"}, {"race": "elf", "class": "longbow"}]
	var weapon_ok := true
	var armour_ok := true
	var shield_ok := true
	for i in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = 500 + i
		for slot in ["weapon", "shirt", "pants", "armband", "shoes", "offhand"]:
			var tier := i % 3
			var raw = ItemSystem.create_item(rules, "d-%d-%s" % [i, slot], slot, tier, rng, "blade" if slot == "weapon" else "")
			var item = RaceDrops.convert_piece(rules, raw, picks, RaceDrops.WAVE, 3)
			var entry: Dictionary = rules.catalog.entry(item.item_id)
			if slot == "weapon":
				weapon_ok = weapon_ok and item.item_id.begins_with("race_") and not str(entry["race"]).is_empty() and Profile.weapon_families(entry["class"]).has(item.weapon_type) and item.tier == tier
			elif slot == "offhand":
				shield_ok = shield_ok and item.item_id.ends_with("_shield")
			else:
				armour_ok = armour_ok and item.item_id == "armour_%s_%s" % [entry["class"], slot] and item.slot == slot and item.tier == tier and Profile.card_can_wear(entry["class"], item, rules)
	ctx.check("race drops v2: the race share makes race weapons (Boss 2026-11-20: random race + class, not the squad card), same tier", weapon_ok)
	ctx.check("race drops v2: armour drops are the class armour of a random class (Boss 2026-11-20, no race), same slot and tier", armour_ok)
	ctx.check("race drops v2: the shield stays the race shield", shield_ok)
