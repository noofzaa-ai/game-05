extends RefCounted
## Per-card gear (docs/tech/per_card_gear_plan.md, Boss answers 2026-11-11): each class card wears its own
## slots and skill build, the stash is shared, an item is worn by at most one card, class weapon families,
## counted fashion copies.
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const Mall := preload("res://logic/mall.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Cosmetics := preload("res://logic/cosmetic_options.gd")


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var cosmetics = Cosmetics.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var p = Profile.new_player(rules, camp, rng)
	var classes: Array = preload("res://logic/card_deck.gd").classes()
	ctx.check("card gear: a new player has gear for every class card", classes.all(func(c): return p.card_gear.has(c) and p.loadout_of(c).item_at("weapon", 0) != null))
	ctx.check("card gear: Sword & Shield wears the original starter set", p.loadout_of("sword_shield").item_at("weapon", 0).id == "starter-weapon")
	ctx.check("card gear: other cards get starter-card ids", p.loadout_of("magic").item_at("weapon", 0).id == "starter-card-v1-magic-weapon")
	ctx.check("card gear: each card's build follows its class", p.build_of("longbow").get("start") == "bow" and p.build_of("sword_shield").get("start") == "katana")
	ctx.check("card gear: the loadout stand-in is the Sword & Shield card", p.loadout == p.loadout_of("sword_shield"))

	# Migration of a pre-card save: old worn gear + build -> Sword & Shield; the others get starters.
	var old: Dictionary = p.to_dict()
	old.erase("card_gear")
	old.erase("card_fashion")
	old["loadout"]["equipped"]["weapon:0"]["id"] = "old-weapon"
	old["skill_build"]["allocated"] = ["start_katana"]
	var migrated = Profile.from_dict(JSON.parse_string(JSON.stringify(old)), rules, camp)
	ctx.check("card gear: migration puts the old gear on Sword & Shield", migrated != null and migrated.loadout_of("sword_shield").item_at("weapon", 0).id == "old-weapon")
	ctx.check("card gear: migration gives the other cards a starter set", migrated != null and migrated.loadout_of("greatsword").item_at("weapon", 0).id == "starter-card-v1-greatsword-weapon")
	var again = Profile.from_dict(JSON.parse_string(JSON.stringify(old)), rules, camp)
	ctx.check("card gear: migration is deterministic (same save -> same starter rolls)", again.to_dict() == migrated.to_dict())
	ctx.check("card gear: a broken card_gear entry rejects the save", Profile.from_dict(_with(p.to_dict(), "card_gear", {"magic": 3}), rules, camp) == null)
	var round_trip = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), rules, camp)
	ctx.check("card gear: per-card gear survives JSON", round_trip != null and round_trip.to_dict() == p.to_dict())

	# Commands: equip to a card, wrong card, shared stash, unique ids.
	var state := {"profile": p, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}
	var ring = ItemSystem.create_item(rules, "test-ring", "ring", 0, rng)
	p.stash.add_item(ring)
	var ok: Dictionary = Commands.apply(state, {"type": "equip", "item": "test-ring", "source": "stash", "card": "magic"}, rng)
	ctx.check("card gear: equip with a card dresses that card only", ok.get("ok", false) and p.loadout_of("magic").item_at("ring", 0) == ring and p.loadout_of("sword_shield").item_at("ring", 0) == null and not p.stash.items.has(ring))
	ctx.check("card gear: the change is saved under card_gear", ok.get("changes", {}).has("card_gear"))
	ctx.check("card gear: an unknown card is refused", Commands.apply(state, {"type": "equip", "item": "starter-card-v1-magic-shirt", "source": "stash", "card": "ghost"}, rng).get("error") == "invalid_card")
	var off: Dictionary = Commands.apply(state, {"type": "unequip", "slot": "ring", "destination": "stash", "card": "magic"}, rng)
	ctx.check("card gear: unequip from a card goes to the shared stash", off.get("ok", false) and p.stash.items.has(ring) and p.loadout_of("magic").item_at("ring", 0) == null)
	var on_b: Dictionary = Commands.apply(state, {"type": "equip", "item": "test-ring", "source": "stash", "card": "longbow"}, rng)
	ctx.check("card gear: the same piece moves to another card through the stash", on_b.get("ok", false) and p.loadout_of("longbow").item_at("ring", 0) == ring)
	ctx.check("card gear: missing card = the lead card", Commands.apply(state, {"type": "unequip", "slot": "shoes", "destination": "stash"}, rng).get("ok", false) and p.loadout_of("sword_shield").item_at("shoes", 0) == null)
	var sell: Dictionary = Commands.apply(state, {"type": "shop_sell", "item": "test-ring", "expected_price": 1}, rng)
	ctx.check("card gear: an item worn by any card cannot be sold", not sell.get("ok", true))
	var dup = ItemSystem.create_item(rules, "starter-card-v1-magic-weapon", "weapon", 0, rng, "blade", "blade_01")
	p.stash.add_item(dup)
	ctx.check("card gear: an id worn by one card and in the stash is refused", Commands.apply(state, {"type": "repair_all"}, rng).get("error") == "duplicate_item_id")
	p.stash.items.erase(dup)

	# Weapon families come from class data.
	ctx.check("card gear: weapon families are in class data", Profile.weapon_families("magic") == ["blade"] and Profile.weapon_families("sword_shield") == ["blade"])
	var bow = ItemSystem.create_item(rules, "test-bow", "weapon", 0, rng, "longbow")
	ctx.check("card gear: a weapon of another family is refused for the class", not Profile.card_can_wear("sword_shield", bow) and Profile.card_can_wear("sword_shield", ring))
	p.stash.add_item(bow)
	ctx.check("card gear: equip of a wrong family returns wrong_weapon_family", Commands.apply(state, {"type": "equip", "item": "test-bow", "source": "stash", "card": "magic"}, rng).get("error") == "wrong_weapon_family")
	ctx.check("card gear: repair_all accepts a card", Commands.apply(state, {"type": "repair_all", "card": "greatsword"}, rng).get("error", "") in ["", "no_workbench", "cannot_afford"])

	# Counted fashion: one copy dresses one card at a time.
	p.mall_owned = []
	p.diamonds = 9999
	ctx.check("fashion: buying adds one copy", Commands.apply(state, {"type": "mall_buy", "part": "fashion", "choice": "purple"}, rng).get("ok", false) and Mall.owned_count(p, "fashion", "purple") == 1)
	ctx.check("fashion: a card wears the owned copy", Commands.apply(state, {"type": "card_fashion", "class": "magic", "part": "fashion", "choice": "purple"}, rng).get("ok", false))
	ctx.check("fashion: a second card cannot wear the only copy", Commands.apply(state, {"type": "card_fashion", "class": "longbow", "part": "fashion", "choice": "purple"}, rng).get("error") == "no_free_copy")
	Commands.apply(state, {"type": "mall_buy", "part": "fashion", "choice": "purple"}, rng)
	ctx.check("fashion: a second copy dresses a second card", Commands.apply(state, {"type": "card_fashion", "class": "longbow", "part": "fashion", "choice": "purple"}, rng).get("ok", false) and Mall.cards_wearing(p, "fashion", "purple").size() == 2)
	ctx.check("fashion: unowned pieces are refused", Commands.apply(state, {"type": "card_fashion", "class": "magic", "part": "fashion", "choice": "red"}, rng).get("error") == "cosmetic_not_owned")
	var dressed = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), rules, camp)
	ctx.check("fashion: what each card wears survives save/load", dressed != null and Mall.card_look(dressed, "magic")["fashion"] == "purple" and dressed.mall_owned.size() == 2)


func _with(d: Dictionary, key: String, value) -> Dictionary:
	var copy := d.duplicate(true)
	copy[key] = value
	return copy
