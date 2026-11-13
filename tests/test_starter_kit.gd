extends RefCounted
## Class starter kits (design/gdd/race-gear-sets.md Part A 3.2-3.3, 8 AC1-AC4; Boss 2026-11-13): every class card of
## a new player wears a full white kit with its own weapon family, nothing goes to the stash, and old saves get the
## kit once in their empty slots only.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const CardDeck := preload("res://logic/card_deck.gd")

const ARMOR_SLOTS := ["hat", "shirt", "pants", "armband", "shoes"]
const ACCESSORY_SLOTS := ["necklace", "earring", "bracelet", "ring", "back"]
const WEIGHT := {"sword_shield": "heavy", "greatsword": "heavy", "longbow": "light", "magic": "cloth"}
const FAMILY := {"sword_shield": "blade", "greatsword": "greatsword", "longbow": "longbow", "magic": "magic"}


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var p = Profile.new_player(rules, camp, rng)
	ctx.check("starter kit: a kit for every class in data", CardDeck.classes().all(func(c): return Profile.starter_kits().get("kits", {}).has(c)))
	for card in CardDeck.classes():
		var worn = p.loadout_of(card)
		var weapon = worn.item_at("weapon", 0)
		ctx.check("starter kit %s: class weapon family %s" % [card, FAMILY.get(card)], weapon != null and weapon.weapon_type == FAMILY.get(card) and Profile.card_can_wear(card, weapon, rules) and rules.catalog.entry(weapon.item_id)["weapon_type"] == weapon.weapon_type)
		var armor_ok := true
		for slot in ARMOR_SLOTS:
			var item = worn.item_at(slot, 0)
			armor_ok = armor_ok and item != null and item.item_id == "starter_%s_%s" % [WEIGHT[card], slot] and rules.catalog.entry(item.item_id)["armor_class"] == WEIGHT[card]
		ctx.check("starter kit %s: hat/shirt/pants/armband/shoes of weight %s" % [card, WEIGHT[card]], armor_ok)
		var white := true
		for item in worn.items():
			white = white and item.tier == 0 and str(rules.catalog.entry(item.item_id).get("set", "")).is_empty() and item.substats.size() <= int(rules.tiers[0]["substat_count"])
		ctx.check("starter kit %s: every piece white and set-free" % card, white)
		ctx.check("starter kit %s: accessories start empty" % card, ACCESSORY_SLOTS.all(func(s): return worn.item_at(s, 0) == null))
		var expected := 6 + (1 if rules.slot_open_for("offhand", card) else 0)
		ctx.check("starter kit %s: %d pieces worn (%d)" % [card, expected, worn.items().size()], worn.items().size() == expected)
	ctx.check("starter kit: Sword & Shield keeps its round shield", p.loadout_of("sword_shield").item_at("offhand", 0) != null and p.loadout_of("sword_shield").item_at("offhand", 0).item_id == "round_shield")
	ctx.check("starter kit: a new player has no gear in the stash (no blue armour gift)", p.stash.items.is_empty())
	ctx.check("starter kit: new player is at kit version 2", p.starter_kit_version == 2)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 9999
	var q = Profile.new_player(rules, camp, rng2)
	var same := true
	for card in CardDeck.classes():
		same = same and _gear(p, card) == _gear(q, card)
	ctx.check("starter kit: the same items on every authority (fixed seed per class and slot)", same)
	for id in rules.catalog.items:
		if str(id).begins_with("starter_"):
			ctx.check("starter kit: %s never drops (drop_level 99)" % id, not rules.catalog.candidates(rules.catalog.entry(id)["slot"], rules.catalog.entry(id)["weapon_type"], 98).has(id))

	# Old save (pre-kit): S&S wears a rare blade + epic shirt, greatsword holds a blade, magic has nothing in pants.
	var old: Dictionary = p.to_dict()
	old.erase("starter_kit_version")
	var gs_blade = ItemSystem.create_item(rules, "old-gs-blade", "weapon", 1, rng, "blade", "blade_02")
	var ss_shirt = ItemSystem.create_item(rules, "old-shirt", "shirt", 2, rng, "", "armor_ash_steel_shirt")
	var ss_weapon = ItemSystem.create_item(rules, "old-weapon", "weapon", 1, rng, "blade", "blade_01")
	var ss = old["card_gear"]["sword_shield"]["loadout"]["equipped"]
	var gs = old["card_gear"]["greatsword"]["loadout"]["equipped"]
	for key in ss.keys():
		ss.erase(key)
	ss["weapon:0"] = ss_weapon.to_dict()
	ss["shirt:0"] = ss_shirt.to_dict()
	gs.erase("hat:0")
	gs["weapon:0"] = gs_blade.to_dict()
	for key in old["card_gear"]["magic"]["loadout"]["equipped"].keys():
		old["card_gear"]["magic"]["loadout"]["equipped"].erase(key)
	var raw := JSON.stringify(old)
	var m = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("starter kit migration: the old save loads", m != null)
	if m == null:
		return
	var s_worn = m.loadout_of("sword_shield")
	ctx.check("starter kit migration: worn gear is kept (rare blade, epic shirt)", s_worn.item_at("weapon", 0).id == "old-weapon" and s_worn.item_at("shirt", 0).id == "old-shirt" and s_worn.item_at("shirt", 0).tier == 2)
	ctx.check("starter kit migration: empty slots are filled with the white kit", s_worn.item_at("hat", 0) != null and s_worn.item_at("hat", 0).item_id == "starter_heavy_hat" and s_worn.item_at("pants", 0).tier == 0 and s_worn.item_at("shoes", 0).item_id == "starter_heavy_shoes")
	ctx.check("starter kit migration: an emptied hat is filled again by the kit once", m.loadout_of("greatsword").item_at("hat", 0) != null and m.loadout_of("greatsword").item_at("hat", 0).id == "starter-kit-v2-greatsword-hat")
	var gs_weapon = m.loadout_of("greatsword").item_at("weapon", 0)
	ctx.check("starter kit migration: a greatsword holding a blade gets its class weapon", gs_weapon != null and gs_weapon.weapon_type == "greatsword" and gs_weapon.item_id == "starter_greatsword")
	ctx.check("starter kit migration: the old blade goes to the stash", m.stash.items.any(func(i): return i.id == "old-gs-blade"))
	ctx.check("starter kit migration: a bare card gets the full kit", m.loadout_of("magic").items().size() == 6 and m.loadout_of("magic").item_at("weapon", 0).weapon_type == "magic")
	ctx.check("starter kit migration: version saved as 2", m.starter_kit_version == 2 and int(m.to_dict().get("starter_kit_version", 0)) == 2)
	var reload = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	ctx.check("starter kit migration: reloading changes nothing (no duplicates)", reload != null and reload.to_dict() == m.to_dict())
	var again = Profile.from_dict(JSON.parse_string(raw), rules, camp)
	ctx.check("starter kit migration: deterministic (same save -> same items)", again != null and again.to_dict() == m.to_dict())
	# After the grant, a slot the player empties stays empty on reload.
	var after = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), rules, camp)
	after.unequip_to_stash("hat", 0, "longbow")
	var later = Profile.from_dict(JSON.parse_string(JSON.stringify(after.to_dict())), rules, camp)
	ctx.check("starter kit migration: runs once (an emptied slot stays empty)", later.loadout_of("longbow").item_at("hat", 0) == null)
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
