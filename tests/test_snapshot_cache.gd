extends RefCounted
const Cache := preload("res://server/rooms/snapshot_cache.gd")
const F := preload("res://tests/online_fixture.gd")
const States := preload("res://logic/net_state.gd")
const Wire := preload("res://logic/net_wire.gd")
func run(ctx) -> void:
	var f := F.make()
	preload("res://logic/test_kit.gd").fill(f.profile, f.rules, f.camp, F.rng())
	var cache := Cache.new()
	cache.begin()
	var first := cache.profile(f.profile)
	ctx.check("cached profile matches canonical full kit", first == f.profile.to_dict())
	ctx.check("unchanged profile reuses immutable tree", is_same(first, cache.profile(f.profile)) and first.is_read_only() and first.stash.items.is_read_only() and first.stash.items[0].is_read_only())
	var old_stash = first.stash
	f.profile.loadout.items()[0].durability -= .5
	var worn := cache.profile(f.profile)
	ctx.check("durability invalidates equipped item only", worn == f.profile.to_dict() and is_same(worn.stash, old_stash) and not is_same(worn.loadout, first.loadout))
	ctx.check("old immutable profile remains unchanged", worn.loadout != first.loadout)
	var item = f.profile.stash.items[0]
	for field in ["id", "slot", "tier", "level", "main_stat", "weapon_type", "item_id", "destroyed", "durability", "max_durability"]:
		var previous = item.get(field)
		if previous is String: item.set(field, previous + "-changed")
		elif previous is bool: item.set(field, not previous)
		else: item.set(field, previous + 1)
		ctx.check("cached item exact invalidation " + field, cache.item(item) == item.to_dict())
		item.set(field, previous)
	if not item.substats.is_empty():
		item.substats[0].quality += .01
		ctx.check("in-place substat edit detected", cache.item(item) == item.to_dict())
	f.profile.stash.gold += 5
	f.profile.stash.materials["test_material"] = 3
	f.profile.stash.items.reverse()
	f.profile.appearance["test"] = "changed"
	f.profile.facility_levels["test"] = 2
	f.profile.name = "Changed"
	ctx.check("inventory order balances appearance facilities synced", cache.profile(f.profile) == f.profile.to_dict())
	cache.end()
	cache.begin(); cache.end()
	ctx.check("serialization cache prunes departed ownership", cache._items.is_empty() and cache._profiles.is_empty() and cache._inventories.is_empty() and cache._loadouts.is_empty())
	var manager := preload("res://server/rooms/manager.gd").new()
	manager.create("snapshot-test", 77, [{"id": 1, "profile": F.make().profile.to_dict()}, {"id": 2, "profile": F.make(78).profile.to_dict()}])
	var room = manager.rooms["snapshot-test"].room
	var before: Dictionary = room.public_state(1, true)
	ctx.check("borrowed snapshot never freezes live journey or boss state", not room.boss_intro.is_read_only() and not room.journey.path.is_read_only() and not room.connected.is_read_only() and not room.trip_for(1).profile.appearance.is_read_only())
	var owned = before.meta.profiles[1]
	room.tick()
	var after: Dictionary = room.public_state(1, true)
	ctx.check("transport snapshot retains stable ownership identities", is_same(owned, after.meta.profiles[1]))
	ctx.check("borrowed snapshots deeply immutable", before.is_read_only() and before.meta.is_read_only() and before.entities.is_read_only())
	var copy: Dictionary = room.public_state(1)
	copy.meta.profiles[1].name = "caller edit"
	ctx.check("public caller copy does not mutate transport snapshot", room.public_state(1, true).meta.profiles[1].name != "caller edit")
	var trip = room.trip_for(1)
	trip.profile.loadout.items()[0].durability -= 1
	trip.bag.gold += 7
	room.tick()
	after = room.public_state(1, true)
	var delta := States.difference(after, before, 1, 0)
	var restored := States.apply(before, Wire.decode(Wire.encode(delta)).value)
	ctx.check("sparse delta retains exact ownership updates", restored.meta == after.meta and restored.tick == after.tick and before.meta.profiles[1] == owned)
	ctx.check("peer stash remains redacted", after.meta.profiles[2].stash.items.is_empty() and after.meta.profiles[2].stash.gold == "0")
	var fixture := preload("res://client/session/netfox_session.gd").new(null, f.rules, f.camp, f.loot)
	var view = fixture.make_sim(after, preload("res://logic/map_loader.gd").load_by_id(after.meta.map))
	ctx.check("Netfox metadata creates independent typed entity views", view.fighters.size() == after.entities.size() and view.bodies[1].position == after.entities[1][0][0])
	view.bodies[1].position += Vector3.ONE
	ctx.check("Netfox presentation view never mutates authority snapshot", view.bodies[1].position != after.entities[1][0][0])
