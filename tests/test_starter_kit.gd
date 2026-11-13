extends RefCounted
## Starter kits (design/gdd/race-gear-sets.md Part A 3.2-3.3, 8 AC1-AC4; Boss 2026-11-13): every class card of a new
## player wears its OWN race's white starter outfit for its class (race weapon in the class family + shirt, pants,
## armband, shoes), nothing goes to the stash, and old saves get the outfit once in their empty slots only. The head
## armour slot is gone: an old save's hat items are refunded once at their sell price.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const Shop := preload("res://logic/shop.gd")

const ARMOR_SLOTS := ["shirt", "pants", "armband", "shoes"]
const ACCESSORY_SLOTS := ["necklace", "earring", "bracelet", "ring", "back"]
const WEIGHT := {"sword_shield": "heavy", "greatsword": "heavy", "longbow": "light", "magic": "cloth"}
const FAMILY := {"sword_shield": "blade", "greatsword": "greatsword", "longbow": "longbow", "magic": "magic"}
const RACES := ["human", "viking", "elf", "runeborn"]


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var p = Profile.new_player(rules, camp, rng)
	ctx.check("starter kit: a kit for every class in data", CardDeck.classes().all(func(c): return Profile.starter_kits().get("kits", {}).has(c)))
	ctx.check("starter kit: no hat slot any more", rules.slot("hat").is_empty() and not rules.catalog.items.values().any(func(e): return e["slot"] == "hat"))
	for card in CardDeck.classes():
		var race := CardDeck.race_of(p.card_deck, card)
		var worn = p.loadout_of(card)
		var weapon = worn.item_at("weapon", 0)
		ctx.check("starter kit %s: %s race weapon of family %s" % [card, race, FAMILY.get(card)], weapon != null and weapon.item_id == "race_%s_%s_weapon" % [race, card] and weapon.weapon_type == FAMILY.get(card) and Profile.card_can_wear(card, weapon, rules))
		var armor_ok := true
		for slot in ARMOR_SLOTS:
			var item = worn.item_at(slot, 0)
			armor_ok = armor_ok and item != null and item.item_id == "race_%s_%s_%s" % [race, card, slot] and rules.catalog.entry(item.item_id)["armor_class"] == WEIGHT[card]
		ctx.check("starter kit %s: own race outfit, shirt/pants/armband/shoes of weight %s" % [card, WEIGHT[card]], armor_ok)
		var white := true
		for item in worn.items():
			white = white and item.tier == 0 and item.substats.size() <= int(rules.tiers[0]["substat_count"])
		ctx.check("starter kit %s: every piece white" % card, white)
		ctx.check("starter kit %s: accessories start empty" % card, ACCESSORY_SLOTS.all(func(s): return worn.item_at(s, 0) == null))
		var expected := 5 + (1 if rules.slot_open_for("offhand", card) else 0)
		ctx.check("starter kit %s: %d pieces worn (%d)" % [card, expected, worn.items().size()], worn.items().size() == expected)
	ctx.check("starter kit: Sword & Shield starts with its race shield", p.loadout_of("sword_shield").item_at("offhand", 0) != null and p.loadout_of("sword_shield").item_at("offhand", 0).item_id == "race_%s_shield" % CardDeck.race_of(p.card_deck, "sword_shield"))
	ctx.check("starter kit: a new player has no gear in the stash (no blue armour gift)", p.stash.items.is_empty())
	ctx.check("starter kit: new player is at kit version 3", p.starter_kit_version == 3)
	# Every class x race has its white starter outfit in the catalog (5 pieces), and a card of that race gets it.
	var all_ok := true
	for card in CardDeck.classes():
		for race in RACES:
			for slot in ["weapon"] + ARMOR_SLOTS:
				all_ok = all_ok and Profile.starter_piece(rules, card, slot, race) == "race_%s_%s_%s" % [race, card, slot]
	ctx.check("starter kit: every class x race has its starter outfit (16 x 5 pieces)", all_ok)
	var deck_rng := RandomNumberGenerator.new()
	deck_rng.seed = 5
	var q = Profile.new_player(rules, camp, deck_rng)
	q.card_gear.erase("longbow")
	CardDeck.set_race(q.card_deck, "longbow", "viking")
	q.ensure_starter_cards(rules)
	ctx.check("starter kit: a Viking longbow card starts in the Viking longbow outfit", q.loadout_of("longbow").item_at("shirt", 0).item_id == "race_viking_longbow_shirt" and q.loadout_of("longbow").item_at("weapon", 0).item_id == "race_viking_longbow_weapon")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 9999
	var r = Profile.new_player(rules, camp, rng2)
	var same := true
	for card in CardDeck.classes():
		same = same and _gear(p, card) == _gear(r, card)
	ctx.check("starter kit: the same items on every authority (fixed seed per class and slot)", same)
	# Boss 2026-11-13: the old items are gone; every catalog item is a race piece and every one can drop.
	ctx.check("starter kit: the catalog holds only race pieces, and they all drop", rules.catalog.items.keys().all(func(id): return str(id).begins_with("race_") and rules.catalog.candidates(rules.catalog.entry(id)["slot"], rules.catalog.entry(id)["weapon_type"], 1).has(id)))

	# Old save (pre-kit): S&S wears a rare blade + epic shirt, greatsword holds a blade and lost its pants, magic is bare.
	var old: Dictionary = p.to_dict()
	old.erase("starter_kit_version")
	var gs_blade = ItemSystem.create_item(rules, "old-gs-blade", "weapon", 1, rng, "blade", "race_human_sword_shield_weapon")
	var ss_shirt = ItemSystem.create_item(rules, "old-shirt", "shirt", 2, rng, "", "race_human_sword_shield_shirt")
	var ss_weapon = ItemSystem.create_item(rules, "old-weapon", "weapon", 1, rng, "blade", "race_human_sword_shield_weapon")
	var ss = old["card_gear"]["sword_shield"]["loadout"]["equipped"]
	var gs = old["card_gear"]["greatsword"]["loadout"]["equipped"]
	for key in ss.keys():
		ss.erase(key)
	ss["weapon:0"] = ss_weapon.to_dict()
	ss["shirt:0"] = ss_shirt.to_dict()
	gs.erase("pants:0")
	gs["weapon:0"] = gs_blade.to_dict()
	for key in old["card_gear"]["magic"]["loadout"]["equipped"].keys():
		old["card_gear"]["magic"]["loadout"]["equipped"].erase(key)
	# The removed head slot: a worn hat (epic) and a stashed hat (rare) from before 2026-11-13.
	var hat_worn := ItemSystem.create_item(rules, "old-hat-worn", "shirt", 2, rng).to_dict()
	hat_worn["slot"] = "hat"
	hat_worn["item_id"] = "armor_ash_steel_hat"
	ss["hat:0"] = hat_worn
	var hat_stash := ItemSystem.create_item(rules, "old-hat-stash", "shirt", 1, rng).to_dict()
	hat_stash["slot"] = "hat"
	(old["stash"]["items"] as Array).append(hat_stash)
	var gold_before := int(old["stash"]["gold"])
	var raw := JSON.stringify(old)
	var m = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("starter kit migration: the old save loads", m != null)
	if m == null:
		return
	var prices: Array = Shop.config()["sell"]["equipment_by_tier"]
	ctx.check("hat removed: every hat item (worn and stashed) is refunded at its sell price (%d -> %d)" % [gold_before, m.stash.gold], m.stash.gold == gold_before + int(prices[2]) + int(prices[1]))
	var no_hat: bool = not m.stash.items.any(func(i): return i.slot == "hat")
	for list in m.worn_lists():
		no_hat = no_hat and not list.any(func(i): return i.slot == "hat")
	ctx.check("hat removed: no hat item is left anywhere", no_hat and not JSON.stringify(m.to_dict()).contains("\"hat:0\""))
	var reloaded = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	ctx.check("hat removed: the refund is paid once", reloaded != null and reloaded.stash.gold == m.stash.gold)
	var s_worn = m.loadout_of("sword_shield")
	ctx.check("starter kit migration: worn gear is kept (rare blade, epic shirt)", s_worn.item_at("weapon", 0).id == "old-weapon" and s_worn.item_at("shirt", 0).id == "old-shirt" and s_worn.item_at("shirt", 0).tier == 2)
	ctx.check("starter kit migration: empty slots get the white race outfit", s_worn.item_at("pants", 0) != null and s_worn.item_at("pants", 0).item_id == "race_human_sword_shield_pants" and s_worn.item_at("pants", 0).tier == 0 and s_worn.item_at("shoes", 0).item_id == "race_human_sword_shield_shoes")
	ctx.check("starter kit migration: an emptied slot is filled by the kit once", m.loadout_of("greatsword").item_at("pants", 0) != null and m.loadout_of("greatsword").item_at("pants", 0).id == "starter-kit-v3-greatsword-pants")
	var gs_weapon = m.loadout_of("greatsword").item_at("weapon", 0)
	ctx.check("starter kit migration: a greatsword holding a blade gets its race weapon", gs_weapon != null and gs_weapon.weapon_type == "greatsword" and gs_weapon.item_id == "race_viking_greatsword_weapon")
	ctx.check("starter kit migration: the old blade goes to the stash", m.stash.items.any(func(i): return i.id == "old-gs-blade"))
	ctx.check("starter kit migration: a bare card gets the full kit", m.loadout_of("magic").items().size() == 5 and m.loadout_of("magic").item_at("weapon", 0).weapon_type == "magic")
	ctx.check("starter kit migration: version saved as 3", m.starter_kit_version == 3 and int(m.to_dict().get("starter_kit_version", 0)) == 3)
	var reload = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	ctx.check("starter kit migration: reloading changes nothing (no duplicates)", reload != null and reload.to_dict() == m.to_dict())
	var again = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("starter kit migration: deterministic (same save -> same items)", again != null and again.to_dict() == m.to_dict())
	# A v2 save (white class kit already given) keeps its class kit pieces; only empty slots get the race outfit.
	var v2: Dictionary = p.to_dict()
	v2["starter_kit_version"] = 2
	v2["card_gear"]["longbow"]["loadout"]["equipped"]["shirt:0"] = ItemSystem.create_item(rules, "starter-kit-v2-longbow-shirt", "shirt", 0, rng, "", "race_elf_longbow_shirt").to_dict()
	v2["card_gear"]["longbow"]["loadout"]["equipped"].erase("shoes:0")
	var v2p = Profile.from_dict(JSON.parse_string(JSON.stringify(v2)), rules, camp)
	ctx.check("starter kit v2 save: worn class kit piece kept, empty slot gets the race piece", v2p.loadout_of("longbow").item_at("shirt", 0).id == "starter-kit-v2-longbow-shirt" and v2p.loadout_of("longbow").item_at("shoes", 0).item_id == "race_elf_longbow_shoes")
	# After the grant, a slot the player empties stays empty on reload.
	var after = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	after.unequip_to_stash("armband", 0, "longbow")
	var later = Profile.from_dict(JSON.parse_string(JSON.stringify(after.to_dict())), rules, camp)
	ctx.check("starter kit migration: runs once (an emptied slot stays empty)", later.loadout_of("longbow").item_at("armband", 0) == null)
	var ids := {}
	var unique := true
	for list in later.worn_lists():
		for item in list:
			unique = unique and not ids.has(item.id)
			ids[item.id] = true
	for item in later.stash.items:
		unique = unique and not ids.has(item.id)
		ids[item.id] = true
	ctx.check("starter kit migration: every item id is unique", unique)


func _gear(p, card: String) -> Array:
	var out: Array = []
	for item in p.loadout_of(card).items():
		out.append(item.to_dict())
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out
