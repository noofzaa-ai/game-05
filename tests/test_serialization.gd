extends RefCounted
const F := preload("res://tests/online_fixture.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Item := preload("res://logic/item.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const Journey := preload("res://logic/journey.gd")

func run(ctx) -> void:
	var f := F.make()
	var p = f["profile"]
	p.stash.capacity = 200
	p.stash.gold = 9007199254740993
	p.name = "ผู้เล่น One"
	p.created = true
	p.camp_level = 3
	p.facility_levels["storage"] = 2
	p.appearance = f["cosmetics"].random(F.rng())
	p.appearance["blink_mode"] = "auto"  # Profile.from_dict always normalizes this on load; it is not a persisted choice.
	var count := 0
	for slot in f["rules"].slots:
		for index in int(slot["count"]):
			var item = ItemSystem.create_item(f["rules"], "owned-%d" % count, slot["id"], count % 4, F.rng(count), "blade")
			item.level = count % 11
			item.durability = float(count) + 0.125
			p.loadout.equip(item, index)
			count += 1
	var broken = ItemSystem.create_item(f["rules"], "destroyed", "shirt", 3, F.rng())
	broken.destroyed = true
	p.stash.add_item(broken)
	for material in f["camp"].materials:
		p.stash.add_material(material, 120)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var copy = Profile.from_dict(saved, f["rules"], f["camp"])
	ctx.check("M1-1 every worn slot, rolls, damaged/destroyed gear, wallet and appearance survive JSON", copy != null and copy.to_dict() == p.to_dict() and count >= 14)
	ctx.check("M1-1 computed item stats and stack rules are not persisted", not saved["stash"].has("_stack_sizes") and not saved["loadout"]["equipped"].values()[0].has("stats"))
	# The fixture's stash already carries a starter kit, so "destroyed" is not necessarily
	# items[0]; find it by id instead of assuming position.
	var copy_broken = copy.stash.items.filter(func(i): return i.id == "destroyed")[0]
	var original_broken = p.stash.items.filter(func(i): return i.id == "destroyed")[0]
	copy_broken.destroyed = false
	ctx.check("M1-1 restored profile owns independent items", original_broken.destroyed)
	ctx.check("M1-1 unsupported versions rejected", Item.from_dict({"v": 99}) == null and Profile.from_dict({"v": 9}, f["rules"], f["camp"]) == null)
	var trip = f["run"]
	trip.used_rests.append("rest-one")
	trip.bag.gold = 44
	trip.bag.add_item(broken.duplicate_item())
	trip.died = true
	var restored = Run.from_dict(JSON.parse_string(JSON.stringify(trip.to_dict())), f["rules"], f["camp"])
	ctx.check("M1-1 run bag, death and consumed rests survive JSON", restored.to_dict() == trip.to_dict())
	var j = f["journey"]
	j.hp_fraction = 0.325
	j.gauge = 67.25
	j.choose(0)
	j.last_reward = {"gold": 3, "materials": {"ore": 2}, "items": [broken], "lost_items": [broken.duplicate_item()]}
	var j2 = Journey.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())), f["data"], f["rules"], f["camp"], f["loot"], f["combat"].weapon_ids)
	ctx.check("M1-1 complete journey and reward Item objects survive JSON", j2.to_dict() == j.to_dict())
	j.last_reward = {}
	j2.last_reward = {}
	j.stage_cleared(.5)
	j2.stage_cleared(.5)
	ctx.check("M1-1 restored journey progresses identically", j2.to_dict() == j.to_dict())
