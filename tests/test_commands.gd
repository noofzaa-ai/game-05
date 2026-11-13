extends RefCounted
const F := preload("res://tests/online_fixture.gd")
const Commands := preload("res://logic/commands.gd")
const ItemSystem := preload("res://logic/item_system.gd")

func run(ctx) -> void:
	var f := F.make()
	var p = f["profile"]
	var item = ItemSystem.create_item(f["rules"], "spare", "shirt", 1, F.rng())
	p.stash.add_item(item)
	check(ctx, f, {"type": "equip", "item": "missing", "source": "stash"}, false, "item_not_owned")
	check(ctx, f, {"type": "equip", "item": "spare", "source": "stash", "index": 999}, false, "invalid_slot")
	check(ctx, f, {"type": "equip", "item": "spare", "source": "stash", "index": 0.5}, false, "invalid_command")
	check(ctx, f, {"type": "equip", "item": "spare", "source": "stash", "gold": 9999}, false, "invalid_command")
	check(ctx, f, {"type": "equip", "item": "spare", "source": "stash"}, true)
	check(ctx, f, {"type": "unequip", "slot": "shirt", "destination": "stash"}, true)
	check(ctx, f, {"type": "unequip", "slot": "shirt", "destination": "stash"}, false, "nothing_worn")
	check(ctx, f, {"type": "enhance", "item": "spare", "protect": true}, false, "not_configured")
	check(ctx, f, {"type": "upgrade_tier", "item": "spare"}, false, "not_configured")
	check(ctx, f, {"type": "discard", "item": "starter-kit-v3-sword_shield-weapon", "source": "stash"}, false, "item_not_in_container")
	check(ctx, f, {"type": "discard", "item": "spare", "source": "stash"}, true)
	check(ctx, f, {"type": "discard_material", "material": "ore", "count": -1, "source": "stash"}, false, "invalid_count")
	p.stash.add_material("ore", 5)
	check(ctx, f, {"type": "discard_material", "material": "ore", "count": 1, "source": "stash"}, true)
	check(ctx, f, {"type": "set_name", "name": "!"}, false, "too_short")
	check(ctx, f, {"type": "set_name", "name": " Hero "}, true)
	check(ctx, f, {"type": "appearance", "part": "skin", "choice": "unknown"}, false, "invalid_appearance")
	check(ctx, f, {"type": "appearance", "part": "skin", "choice": f["cosmetics"].defaults["skin"]}, true)
	check(ctx, f, {"type": "unknown"}, false, "unknown_command")
	check(ctx, f, {"type": "upgrade_camp"}, false, "cannot_afford")
	check(ctx, f, {"type": "upgrade_facility", "facility": "unknown"}, false, "unknown_facility")
	p.stash.capacity = 1000
	p.stash.gold = 10000000
	for material in f["camp"].materials:
		p.stash.add_material(material, 5000)
	check(ctx, f, {"type": "upgrade_camp"}, true)
	check(ctx, f, {"type": "upgrade_facility", "facility": "storage"}, true)
	var weapon = p.loadout.item_at("weapon")
	check(ctx, f, {"type": "repair", "item": weapon.id}, false, "nothing_to_repair")
	weapon.durability = 50.0
	check(ctx, f, {"type": "repair", "item": weapon.id}, true)
	weapon.durability = 25.0
	check(ctx, f, {"type": "repair_all"}, true)
	f["location"] = "stage"
	check(ctx, f, {"type": "repair_all"}, false, "not_available_here")
	check(ctx, f, {"type": "upgrade_camp"}, false, "not_available_here")
	check(ctx, f, {"type": "upgrade_facility", "facility": "storage"}, false, "not_available_here")
	check(ctx, f, {"type": "set_name", "name": "Valid"}, false, "not_available_here")
	check(ctx, f, {"type": "appearance", "part": "skin", "choice": f["cosmetics"].defaults["skin"]}, false, "not_available_here")
	check(ctx, f, {"type": "repair", "item": weapon.id}, false, "not_available_here")
	check(ctx, f, {"type": "unequip", "slot": "weapon", "destination": "bag"}, false, "not_available_here")
	f["location"] = "rest"
	check(ctx, f, {"type": "unequip", "slot": "weapon", "destination": "bag"}, true)
	check(ctx, f, {"type": "equip", "item": weapon.id, "source": "bag"}, true)
	check(ctx, f, {"type": "unequip", "slot": "weapon", "destination": "stash"}, false, "not_available_here")
	f["run"].bag.capacity = 0
	check(ctx, f, {"type": "unequip", "slot": "weapon", "destination": "bag"}, false, "bag_full")
	f["run"].died = true
	check(ctx, f, {"type": "unequip", "slot": "weapon", "destination": "bag"}, false, "trip_over")
	f["location"] = "camp"
	check(ctx, f, {"type": "discard_material", "material": "ore", "count": 1, "source": "bag"}, false, "trip_over")
	weapon.destroyed = true
	p.stash.items.append(weapon)
	p.loadout.unequip("weapon")
	check(ctx, f, {"type": "equip", "item": weapon.id, "source": "stash"}, false, "item_destroyed")
	p.stash.items.append(weapon.duplicate_item())
	check(ctx, f, {"type": "set_name", "name": "Other"}, false, "duplicate_item_id")
	var a := F.make()
	var b := F.make()
	var rng_a := F.rng(8)
	var rng_b := F.rng(8)
	var command := {"type": "set_name", "name": "Same"}
	ctx.check("M1-2 same seed and command produce identical state/results", Commands.apply(a, command, rng_a) == Commands.apply(b, command, rng_b) and a["profile"].to_dict() == b["profile"].to_dict() and rng_a.state == rng_b.state)

func check(ctx, f: Dictionary, command: Dictionary, success: bool, error: String = "") -> void:
	var before: Dictionary = f["profile"].to_dict()
	var bag: Dictionary = f["run"].bag.to_dict()
	var rng := F.rng()
	var rng_before := rng.state
	# Exercise actual JSON wire types too.
	var result := Commands.apply(f, JSON.parse_string(JSON.stringify(command)), rng)
	ctx.check("M1-2 %s -> %s" % [command, error if not success else "ok"], result["ok"] == success and (success or result.get("error") == error))
	if not success:
		ctx.check("M1-2 failed command is atomic", before == f["profile"].to_dict() and bag == f["run"].bag.to_dict() and rng.state == rng_before)
