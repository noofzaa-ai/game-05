extends SceneTree
## Loot-vanish probe (QA 2026-11-19): plays a real 1-player squad room (server/rooms/room.gd, goblin_waves, the same code
## the staging rooms worker runs) with the auto-pilot, for a stash that is empty / half / nearly full / full, and compares
## every drop with the bag, the settle result, the saved profile and the client-side profile (full rebuild and
## profile_patch).  godot --headless --path . --script res://tools/loot_qa/room_probe.gd -- [seeds] [mode]
## mode: natural (auto-pilot fights it out) | strong (player stats x30 so the run is WON) | weak (player is killed)
const F := preload("res://tests/online_fixture.gd")
const Manager := preload("res://server/rooms/manager.gd")
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Patch := preload("res://runtime/netfox/profile_patch.gd")
const Sim := preload("res://logic/game_sim.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 3
	var mode := str(args[1]) if args.size() > 1 else "strong"
	var fills := {"empty": 0, "nearly_full": 36, "full": 40} if args.size() < 3 else {"empty": 0}
	var out := []
	for fill_name in fills:
		for s in seeds:
			out.append(_one(fill_name, int(fills[fill_name]), 100 + s, mode))
	print("PROBE_RESULT ", JSON.stringify(out))
	quit()

func _stash_to(profile, count: int, rules) -> void:
	# bring the stash to `count` items using starter-style filler pieces (ids that purge/convert never touch)
	var n := 0
	while profile.stash.items.size() > count: profile.stash.items.pop_back()
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	while profile.stash.items.size() < count:
		var it = ItemSystem.create_item(rules, "starter-filler-%d" % n, "shirt", 0, rng, "", "armour_longbow_shirt")
		n += 1
		profile.stash.items.append(it)

func _one(fill_name: String, fill: int, seed_value: int, mode: String) -> Dictionary:
	var mgr = Manager.new(); mgr.squad_rooms = true
	var f := F.make(seed_value)
	_stash_to(f.profile, fill, mgr.rules)
	var raw := [{"id": 1, "profile": JSON.parse_string(JSON.stringify(f.profile.to_dict()))}]
	var before_items: int = f.profile.stash.items.size()
	var made: Dictionary = mgr.create("probe-%s-%d" % [fill_name, seed_value], seed_value, raw)
	if not made.ok: return {"fill": fill_name, "error": str(made)}
	var room = mgr.rooms["probe-%s-%d" % [fill_name, seed_value]].room
	var trip = room.trip_for(1)
	var stash_in: int = trip.profile.stash.items.size()
	var cap_in: int = trip.profile.stash.capacity
	if mode == "strong":
		for id in room.sim.fighters:
			if room.sim.fighters[id].team != "enemy":
				room.sim.fighters[id].stats["ATK"] = float(room.sim.fighters[id].stats["ATK"]) * 40.0
				room.sim.fighters[id].stats["HP"] = float(room.sim.fighters[id].stats["HP"]) * 40.0
				room.sim.fighters[id].hp = room.sim.fighters[id].max_hp()
	var dropped := 0; var stored := 0; var lost := 0; var lost_mats := 0; var events_loot := 0
	var ticks := 0
	var limit := 60 * 60 * 6
	var killed_player := false
	while room.status != "finished" and ticks < limit:
		room.tick(); ticks += 1
		if mode == "weak" and ticks == 60 * 40 and not killed_player:
			killed_player = true
			for id in room.fighter_ids():
				room.sim.fighters[id].hp = 0; room.sim.fighters[id].state = preload("res://logic/fighter.gd").State.DEAD
				room.sim.fighters[id].eliminated = true
				room.sim._finalize_player_death(id)
			room.sim._coop["wiped"] = true
		for e in room.sim.events:
			if str(e.get("type", "")) == "loot":
				events_loot += 1
				stored += (e["items"] as Array).size()
				lost += int(e["lost_items"])
				for k in e["lost_materials"]: lost_mats += int(e["lost_materials"][k])
		if mode == "strong":  # keep the squad alive
			for id in room.fighter_ids():
				if room.sim.fighters.has(id) and room.sim.fighters[id].is_alive(): room.sim.fighters[id].hp = room.sim.fighters[id].max_hp()
	dropped = stored + lost
	var bag_items: int = trip.bag.items.size()
	var state: String = room.journey.state
	var wave_cleared: int = room.journey.waves_cleared
	var bag_cap: int = trip.bag.capacity
	var saved_all: Dictionary = room.finalize(false)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(saved_all["1"]))
	var saved_stash: int = (saved.stash.items as Array).size()
	var saved_cap: int = int(saved.stash.capacity)
	# bag after settle
	var left_in_bag: int = trip.bag.items.size()
	# the server reload of the saved profile (the worker runs Profile.from_dict on the next room / profile RPC)
	var reloaded = Profile.from_dict(JSON.parse_string(JSON.stringify(saved)), mgr.rules, mgr.camp)
	var reloaded_stash: int = reloaded.stash.items.size() if reloaded != null else -1
	# the client: full rebuild vs patch from the previous snapshot block
	var prev: Dictionary = JSON.parse_string(JSON.stringify(f.profile.to_dict()))
	prev.erase("card_deck"); prev.erase("card_gear")
	var next_raw: Dictionary = saved.duplicate(true); next_raw.erase("card_deck"); next_raw.erase("card_gear")
	var live = Profile.from_dict(prev.duplicate(true), mgr.rules, mgr.camp)
	var patched := Patch.apply(live, prev, next_raw, mgr.rules, mgr.camp)
	var live_stash: int = live.stash.items.size()
	var full = Profile.from_dict(next_raw.duplicate(true), mgr.rules, mgr.camp)
	return {"fill": fill_name, "seed": seed_value, "mode": mode, "state": state, "waves": wave_cleared, "ticks": ticks, "stash_in": stash_in, "cap_in": cap_in,
		"loot_events": events_loot, "dropped": dropped, "stored_in_bag": stored, "lost_bag_full": lost, "lost_mats": lost_mats, "bag_cap": bag_cap,
		"bag_items_at_end_before_settle": bag_items, "bag_after_settle": left_in_bag, "saved_stash": saved_stash, "saved_cap": saved_cap,
		"reloaded_stash": reloaded_stash, "patch_applied": patched, "client_patch_stash": live_stash, "client_full_stash": full.stash.items.size() if full != null else -1,
		"vanished_vs_bag": bag_items - (saved_stash - stash_in) - left_in_bag}
