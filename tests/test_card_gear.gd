extends RefCounted
## Per-card gear (docs/tech/per_card_gear_plan.md, Boss answers 2026-11-11): each class card wears its own
## slots and skill build, the stash is shared, an item is worn by at most one card, class weapon families.
## The old fashion (Mall outfits / hats / back items) is gone (Boss 2026-11-13): old saves are refunded on load.
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
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
	ctx.check("card gear: Sword & Shield wears the class starter kit", p.loadout_of("sword_shield").item_at("weapon", 0).id == "starter-kit-v2-sword_shield-weapon")
	ctx.check("card gear: other cards get starter-kit ids", p.loadout_of("magic").item_at("weapon", 0).id == "starter-kit-v2-magic-weapon")
	ctx.check("card gear: no card carries the old skill build (class-skills.md)", classes.all(func(c): return not p.card_gear[c].has("skill_build")) and not p.to_dict().has("skill_build"))
	ctx.check("card gear: the loadout stand-in is the Sword & Shield card", p.loadout == p.loadout_of("sword_shield"))

	# Migration of a pre-card save: old worn gear + build -> Sword & Shield; the others get starters.
	var old: Dictionary = p.to_dict()
	old.erase("card_gear")
	old["loadout"]["equipped"]["weapon:0"]["id"] = "old-weapon"
	old["skill_build"] = {"v": 1, "start": "katana", "allocated": ["start_katana"], "skills": []}  # an old save's account build
	var migrated = Profile.from_dict(JSON.parse_string(JSON.stringify(old)), rules, camp)
	ctx.check("card gear: migration puts the old gear on Sword & Shield", migrated != null and migrated.loadout_of("sword_shield").item_at("weapon", 0).id == "old-weapon")
	ctx.check("card gear: the old skill build is dropped on load", migrated != null and not migrated.card_gear["sword_shield"].has("skill_build") and not migrated.to_dict().has("skill_build"))
	ctx.check("card gear: migration gives the other cards a starter set", migrated != null and migrated.loadout_of("greatsword").item_at("weapon", 0).id == "starter-kit-v2-greatsword-weapon")
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
	ctx.check("card gear: an unknown card is refused", Commands.apply(state, {"type": "equip", "item": "starter-kit-v2-magic-shirt", "source": "stash", "card": "ghost"}, rng).get("error") == "invalid_card")
	var off: Dictionary = Commands.apply(state, {"type": "unequip", "slot": "ring", "destination": "stash", "card": "magic"}, rng)
	ctx.check("card gear: unequip from a card goes to the shared stash", off.get("ok", false) and p.stash.items.has(ring) and p.loadout_of("magic").item_at("ring", 0) == null)
	var on_b: Dictionary = Commands.apply(state, {"type": "equip", "item": "test-ring", "source": "stash", "card": "longbow"}, rng)
	ctx.check("card gear: the same piece moves to another card through the stash", on_b.get("ok", false) and p.loadout_of("longbow").item_at("ring", 0) == ring)
	ctx.check("card gear: missing card = the lead card", Commands.apply(state, {"type": "unequip", "slot": "shoes", "destination": "stash"}, rng).get("ok", false) and p.loadout_of("sword_shield").item_at("shoes", 0) == null)
	var sell: Dictionary = Commands.apply(state, {"type": "shop_sell", "item": "test-ring", "expected_price": 1}, rng)
	ctx.check("card gear: an item worn by any card cannot be sold", not sell.get("ok", true))
	var dup = ItemSystem.create_item(rules, "starter-kit-v2-magic-weapon", "weapon", 0, rng, "magic", "starter_staff")
	p.stash.add_item(dup)
	ctx.check("card gear: an id worn by one card and in the stash is refused", Commands.apply(state, {"type": "repair_all"}, rng).get("error") == "duplicate_item_id")
	p.stash.items.erase(dup)

	# Weapon families come from class data.
	ctx.check("card gear: weapon families are in class data", Profile.weapon_families("magic") == ["magic"] and Profile.weapon_families("sword_shield") == ["blade"] and Profile.weapon_families("greatsword") == ["greatsword"] and Profile.weapon_families("longbow") == ["longbow"])
	var bow = ItemSystem.create_item(rules, "test-bow", "weapon", 0, rng, "longbow")  # longbow family: the magic card refuses it
	ctx.check("card gear: a weapon of another family is refused for the class", not Profile.card_can_wear("sword_shield", bow) and Profile.card_can_wear("sword_shield", ring))
	p.stash.add_item(bow)
	ctx.check("card gear: equip of a wrong family returns wrong_weapon_family", Commands.apply(state, {"type": "equip", "item": "test-bow", "source": "stash", "card": "magic"}, rng).get("error") == "wrong_weapon_family")
	ctx.check("card gear: repair_all accepts a card", Commands.apply(state, {"type": "repair_all", "card": "greatsword"}, rng).get("error", "") in ["", "no_workbench", "cannot_afford"])

	# Old fashion removed (Boss 2026-11-13): commands are refused, old saves load, get refunded and keep their looks.
	var diamonds_before: int = p.diamonds
	ctx.check("fashion removed: card_fashion is an unknown command", Commands.apply(state, {"type": "card_fashion", "class": "magic", "part": "fashion", "choice": "purple"}, rng).get("error") == "unknown_command")
	for part in ["fashion", "fashion_back", "fashion_hat"]:
		var bought: Dictionary = Commands.apply(state, {"type": "mall_buy", "part": part, "choice": "purple" if part == "fashion" else "bat_club"}, rng)
		ctx.check("fashion removed: mall_buy %s is refused" % part, not bought.get("ok", true) and bought.get("error") == "invalid_cosmetic")
	ctx.check("fashion removed: appearance fashion is refused", Commands.apply(state, {"type": "appearance", "part": "fashion", "choice": "red"}, rng).get("error") == "invalid_appearance")
	ctx.check("fashion removed: a refused purchase costs nothing", p.diamonds == diamonds_before and p.mall_owned.is_empty())
	ctx.check("fashion removed: no fashion parts are offered", not Cosmetics.PARTS.has("fashion") and not Cosmetics.PARTS.has("fashion_back") and not Cosmetics.PARTS.has("fashion_hat"))

	var looks_before: Dictionary = p.card_deck.duplicate(true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	saved["diamonds"] = 1000
	saved["mall_owned"] = ["fashion:purple", "fashion:purple", "fashion_back:angel_wings", "fashion_hat:cat", "gizmo:x"]
	saved["card_fashion"] = {"magic": {"fashion": "purple", "fashion_back": "angel_wings"}, "longbow": {"fashion": "purple"}}
	saved["appearance"]["fashion"] = "purple"
	saved["appearance"]["fashion_display"] = "on"
	saved["appearance"]["fashion_back"] = "angel_wings"
	saved["appearance"]["fashion_hat"] = "cat"
	saved["appearance"]["wear_shirt"] = "off"
	saved["appearance"]["eye_color"] = "violet"
	var loaded = Profile.from_dict(saved, rules, camp)
	ctx.check("old save with fashion: loads", loaded != null)
	if loaded != null:
		# 2 x outfit 150 + back 100 + hat 50 = 450; the unknown "gizmo" entry pays nothing.
		ctx.check("old save with fashion: every owned copy refunded at its old price (%d)" % loaded.diamonds, loaded.diamonds == 1000 + 450)
		ctx.check("old save with fashion: no fashion copies are kept", loaded.mall_owned.is_empty())
		ctx.check("old save with fashion: fashion fields dropped", not loaded.to_dict().has("card_fashion") and not loaded.appearance.has("fashion") and not loaded.appearance.has("fashion_display") and not loaded.appearance.has("fashion_back") and not loaded.appearance.has("fashion_hat") and not loaded.appearance.has("wear_shirt"))
		ctx.check("old save with fashion: card looks kept (hair, outfit, eyes, skin, makeup)", loaded.card_deck == looks_before)
		ctx.check("old save with fashion: the account's own looks kept", str(loaded.appearance.get("eye_color", "")) == "violet")
		var plain = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), rules, camp)
		ctx.check("old save with fashion: gear kept", plain != null and loaded.to_dict()["card_gear"] == plain.to_dict()["card_gear"])
		var reloaded = Profile.from_dict(JSON.parse_string(JSON.stringify(loaded.to_dict())), rules, camp)
		ctx.check("old save with fashion: the refund is paid once (a second load adds nothing)", reloaded != null and reloaded.diamonds == loaded.diamonds)
	var no_wallet: Dictionary = saved.duplicate(true)
	no_wallet.erase("mall_owned")
	var granted = Profile.from_dict(no_wallet, rules, camp)
	ctx.check("a save from before the Mall (worn fashion granted, not bought) gets no refund", granted != null and granted.diamonds == 1000 and granted.mall_owned.is_empty() and not granted.appearance.has("fashion"))

func _with(d: Dictionary, key: String, value) -> Dictionary:
	var copy := d.duplicate(true)
	copy[key] = value
	return copy
