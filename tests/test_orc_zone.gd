extends RefCounted
## The Orc Camp zone, end to end (2026-11-21; Boss warning: the pyramid quest was once done but the map would not open).
## orc_waves.json (9 waves, orc family only, the Orc Warlock at wave 9, no heal), zones.json wiring, the War Drums quest
## gate on a fixture profile -> the zone OPENS -> the client start_journey really starts the orc fight offline; the room
## manager hosts orc_waves for an open profile and refuses a locked one; a driven room reaches the Warlock, wins, pays the
## orc boss loot, flags boss_orc_camp and counts the daily boss. Plus the boss weapon_drops roll (ON for pyramid and orc_camp, Boss 2026-11-21).
const Zones := preload("res://logic/world_zones.gd")
const Quests := preload("res://logic/zone_quests.gd")
const Daily := preload("res://logic/daily_quests.gd")
const GearLevels := preload("res://logic/gear_levels.gd")
const Commands := preload("res://logic/commands.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Journey := preload("res://logic/journey.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Squads := preload("res://tests/test_online_squads.gd")
const JOURNEY := "orc_waves"
const ORC := ["orc_grunt", "orc_archer", "orc_mage", "orc_warlock"]


static func set_levels(p, levels: Array) -> void:
	var ids: Array = p.card_deck["cards"].keys()
	for i in ids.size():
		p.card_deck["cards"][ids[i]]["progress"] = {"level": int(levels[i]) if i < levels.size() else 1, "xp": 0}


## A profile that finished the pyramid (both earlier bosses beaten) with the given card levels.
static func after_pyramid(f: Dictionary, levels: Array, seed_value: int = 41):
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(seed_value)))
	p.unlocks[Zones.boss_key("goblin_base")] = true
	p.unlocks[Zones.boss_key("pyramid")] = true
	set_levels(p, levels)
	return p


func run(ctx) -> void:
	var f := F.make()
	_journey_data(ctx, f)
	_gate(ctx, f)
	_rooms(ctx, f)
	_weapon_drops(ctx, f)
	_warlock_loot(ctx, f)
	await _client_start(ctx, f)


## The Warlock pays its OWN accessory set (2026-11-21, replaces the mummy placeholder): set pieces, coin and relic are
## orc_warlock ids; pieces are level-20 gear (gear_levels.json orc_camp), wearable at card level 20 and never at 19, and the
## one-time lv15 gear purge never runs again on a new player who holds them.
func _warlock_loot(ctx, f: Dictionary) -> void:
	var entry: Dictionary = BossLoot.boss("orc_camp")
	ctx.check("warlock loot: orc_camp pays boss_orc_warlock, coin_orc_warlock, relic_orc_warlock, its sword + shield weapon drops ON",
		entry.get("set", "") == "boss_orc_warlock" and entry.get("coin", "") == "coin_orc_warlock" and entry.get("relic", "") == "relic_orc_warlock"
		and bool(entry.get("weapon_drops_enabled", false)) and Array(entry.get("weapon_drops", [])).map(func(w): return str(w.item)) == ["boss_orc_warlock_sword", "boss_orc_warlock_shield"])
	var data = JourneyData.load_by_id(JOURNEY, f.combat.enemies.keys())
	var pieces := 0
	var foreign := 0
	for s in 120:
		var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(s)))
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var got: Dictionary = BossLoot.grant(p, f.rules, f.loot, data, s == 0, 1.0, rng)
		for i in got["items"]:
			if str(i.item_id).begins_with("boss_orc_warlock_"):
				pieces += 1
			else:
				foreign += 1
		if p.stash.material_count("coin_mummy_high_wizard") > 0 or p.stash.material_count("coin_orc_warlock") < 1:
			foreign += 1
	ctx.check("warlock loot: 120 orc wins pay Warlock coins and Warlock pieces only (%d pieces, %d foreign)" % [pieces, foreign], pieces > 0 and foreign == 0)
	var gear_level := GearLevels.zone_level("orc_camp")
	var purge := preload("res://logic/gear_purge.gd")
	for id in BossLoot.set_pieces(f.rules, "boss_orc_warlock"):
		var item = preload("res://logic/item_system.gd").create_item(f.rules, "wl-" + id, str(f.rules.catalog.entry(id).slot), 1, F.rng(3), "", id)
		var p = Profile.new_player(f.rules, f.camp, F.rng(7))
		p.stash.items.append(item)
		ctx.check("warlock loot %s: req/drop level = orc gear level %d, wearable at 20 not 19, survives the one-time purge" % [id, gear_level],
			gear_level == 20 and f.rules.catalog.req_level(id) == gear_level and int(f.rules.catalog.entry(id).drop_level) == gear_level
			and Profile.slot_problem("sword_shield", item, f.rules, 20) == "" and Profile.slot_problem("sword_shield", item, f.rules, 19) == "level_too_low"
			and purge.done(p) and not purge.purge(p, f.rules)["ran"] and p.stash.items.has(item))


func _journey_data(ctx, f: Dictionary) -> void:
	var data = JourneyData.load_by_id(JOURNEY, f.combat.enemies.keys())
	ctx.check("orc_waves loads with no errors %s" % [data.errors], data.is_valid())
	ctx.check("orc_waves: wave mode, 9 waves, no between-wave heal", data.wave_mode and data.stage_count == 9 and data.stages.size() == 9 and is_zero_approx(data.wave_heal_fraction))
	ctx.check("orc_waves: the night camp is the arena, boss and camp map %s" % [data.arena_maps], data.arena_maps == ["orc_camp_night"] and data.boss_map == "orc_camp_night" and data.camp_map == "orc_camp_night")
	ctx.check("orc_waves: wave_power_by_squad covers 1..6 players", data.wave_power_by_squad.size() == 6 and data.wave_power_by_squad.all(func(x): return float(x) > 0.0))
	var types := {}
	for stage in data.stages:
		for e in stage["enemies"]:
			types[str(e["type"])] = true
		for e in stage.get("challenge", {}).get("enemies", []):
			types[str(e["type"])] = true
	ctx.check("orc_waves: only the orc family %s" % [types.keys()], types.keys().all(func(t): return ORC.has(t)))
	var last: Array = data.stages[-1]["enemies"].filter(func(e): return bool(e.get("boss", false)))
	ctx.check("wave 9: the Orc Warlock alone is the boss (pair pending Boss)", last.size() == 1 and str(last[0]["type"]) == "orc_warlock" and int(last[0]["count"]) == 1)
	ctx.check("waves 1..8 have no boss", range(8).all(func(i): return data.stages[i]["enemies"].all(func(e): return not bool(e.get("boss", false)))))
	ctx.check("the archer debuts in wave 2 and the mage in wave 4", data.stages[1]["enemies"].any(func(e): return e["type"] == "orc_archer") and data.stages[3]["enemies"].any(func(e): return e["type"] == "orc_mage"))


func _gate(ctx, f: Dictionary) -> void:
	var z := Zones.zone("orc_camp")
	ctx.check("zones.json: orc_camp plays orc_waves, boss Orc Warlock (th/en)", str(z.get("journey", "")) == JOURNEY and str(z.get("boss_en", "")) == "Orc Warlock" and not str(z.get("boss_th", "")).is_empty())
	ctx.check("zones.json has no problems %s" % [Zones.problems()], Zones.problems().is_empty())
	ctx.check("gear_levels: orc_camp = 20, no problems %s" % [GearLevels.problems()], GearLevels.zone_level("orc_camp") == 20 and GearLevels.problems().is_empty())
	var locked = after_pyramid(f, [15, 10, 10, 9])
	ctx.check("quest not met (one card Lv9, best 15): orc LOCKED, start refused, fight_problem zone_locked",
		not Quests.met(locked, "orc_camp") and Zones.state(locked, "orc_camp") == Zones.LOCKED and Zones.start_journey_for(locked, "orc_camp") == ""
		and Commands.fight_problem(locked, JOURNEY) == "zone_locked")
	var no_boss = after_pyramid(f, [20, 10, 10, 10])
	no_boss.unlocks.erase(Zones.boss_key("pyramid"))
	ctx.check("cards ok but the High Wizard not beaten: still LOCKED", Zones.state(no_boss, "orc_camp") == Zones.LOCKED)
	var done = after_pyramid(f, [20, 10, 10, 10])
	ctx.check("War Drums done (all Lv10, one Lv20, pyramid boss): quest met", Quests.met(done, "orc_camp") and Quests.main_state(done, "orc_camp") == Quests.MAIN_DONE)
	ctx.check("... the orc zone is OPEN and the map start gives orc_waves", Zones.state(done, "orc_camp") == Zones.OPEN and Zones.start_journey_for(done, "orc_camp") == JOURNEY)
	ctx.check("... the furthest open zone is the orc camp", str(Zones.current_zone(done).get("id", "")) == "orc_camp")
	ctx.check("... the server-side fight gate lets orc_waves through", Commands.fight_problem(done, JOURNEY) == "")
	ctx.check("... the unlocked gear level is 20", GearLevels.unlocked_level(done) == 20)


static func _room_entry(p, id: int) -> Dictionary:
	return {"id": id, "profile": p.to_dict()}


func _rooms(ctx, f: Dictionary) -> void:
	var mgr = Squads.squad_manager()
	ctx.check("room worker: orc_waves is a hostable zone journey", mgr.zone_journey(JOURNEY) != null)
	var open_p = after_pyramid(f, [20, 10, 10, 10], 51)
	var open_entry := _room_entry(open_p, 1)
	ctx.check("room: a locked profile is refused with zone_locked", mgr.create("orc-locked-1", 77, [_room_entry(after_pyramid(f, [15, 10, 10, 9], 52), 1)], false, 1, "", JOURNEY).get("error", "") == "zone_locked")
	var made: Dictionary = mgr.create("orc-solo-1", 77, [open_entry], false, 1, "", JOURNEY)
	ctx.check("room: the quest-done profile starts an orc_waves room %s" % [made.get("error", "")], made.get("ok", false) and mgr.rooms["orc-solo-1"].room.journey.data.id == JOURNEY)
	if not made.get("ok", false):
		return
	var room = mgr.rooms["orc-solo-1"].room
	var FS = preload("res://logic/fighter.gd").State
	var seen := {}
	var waves_seen := {}
	var boss_ticks := 0
	for i in 30000:
		room.tick()
		var any_enemy := false
		for fid in room.sim.fighters:
			var fighter = room.sim.fighters[fid]
			if fighter.team == "enemy" and fighter.is_alive():
				any_enemy = true
				seen[fighter.enemy_type] = true
				if fighter.enemy_type == "orc_warlock":
					boss_ticks += 1
					if boss_ticks < 600: continue  # let the Warlock act a moment
				fighter.hp = 0; fighter.state = FS.DEAD
		if any_enemy:
			waves_seen[int(room.sim._waves_released) + 1] = true  # (the wave on the field, as the room's meta.wave)
		if room.journey.state != Journey.IN_STAGE: break
	ctx.check("room drive: only orcs fought, the Warlock among them %s" % [seen.keys()], seen.has("orc_warlock") and seen.keys().all(func(t): return ORC.has(t)))
	ctx.check("room drive: all 9 waves came %s" % [waves_seen.keys()], waves_seen.size() == 9)
	ctx.check("room drive: the run is won", room.journey.state == Journey.WON)
	if room.journey.state != Journey.WON:
		return
	# Boss 2026-11-26 "boss Warlock does not drop items": the room paid journey.boss_loot but never sent it to the client, so the
	# online run summary (RemoteJourney -> journey_screen _add_boss_loot) showed no coin / set piece / boss weapon.
	var viewer: int = room.connected.keys()[0]
	var meta: Dictionary = room.public_state(viewer).meta
	var remote = preload("res://client/session/remote_journey.gd").new()
	remote.update(meta, null)
	var mine: Dictionary = remote.boss_loot.get(str(viewer), {})
	ctx.check("room snapshot: the won run sends the viewer's boss loot %s" % [meta.get("boss_loot", {}).keys()],
		meta.has("boss_loot") and str(mine.get("coin", "")) == "coin_orc_warlock" and int(mine.get("coins", 0)) >= 1
		and (mine.get("items", []) as Array).all(func(i): return i != null and str(i.item_id).begins_with("boss_orc_warlock")))
	var d: Dictionary = room.finalize().values()[0]
	var coin := str(BossLoot.boss("orc_camp").get("coin", ""))
	ctx.check("settle: boss_orc_camp flagged", bool(d.unlocks.get(Zones.boss_key("orc_camp"), false)))
	ctx.check("settle: the orc boss loot paid its coin %s" % coin, not coin.is_empty() and int(d.stash.materials.get(coin, 0)) >= 1)
	var back = Profile.from_dict(d, f.rules, f.camp)
	ctx.check("settle: the daily boss counts the Orc Warlock", back != null and Daily.progress(back, int(Time.get_unix_time_from_system())).any(func(q): return q.id == "daily_boss" and q.current >= 1))


## Boss weapon drops (Boss 2026-11-21: ON for the pyramid crook + staff and the Warlock sword + shield, 10% each since Boss 2026-11-22). Per zone:
## the data, ~10% each over 2000 wins, the drop lands in the stash as the right slot (the shield in "offhand"), the set
## piece / relic rolls of a seed are the same as with drops OFF (a test copy of the entry), and OFF gives no weapon.
func _weapon_drops(ctx, f: Dictionary) -> void:
	var zones := {"pyramid": ["mummy_waves", "boss_mummy_boss_crook", "boss_mummy_high_wizard_staff"],
		"orc_camp": [JOURNEY, "boss_orc_warlock_sword", "boss_orc_warlock_shield"]}
	for zone in zones:
		var data = JourneyData.load_by_id(str(zones[zone][0]), f.combat.enemies.keys())
		var a: String = zones[zone][1]
		var b: String = zones[zone][2]
		var entry: Dictionary = BossLoot.boss(zone)
		ctx.check("%s weapon_drops: %s + %s at 10%% each, ON" % [zone, a, b], bool(entry.get("weapon_drops_enabled", false))
			and Array(entry.get("weapon_drops", [])).map(func(w): return str(w.item)) == [a, b] and Array(entry.weapon_drops).all(func(w): return is_equal_approx(float(w.chance), 0.10)))
		var saved: Dictionary = BossLoot._cached
		var off: Dictionary = saved.duplicate(true)
		off["bosses"][zone].erase("weapon_drops_enabled")
		var n_a := 0
		var n_b := 0
		var off_weapons := 0
		var same := true
		var slots_ok := true
		for s in 2000:
			var p1 = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(1)))
			var p2 = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(1)))
			var r1 := RandomNumberGenerator.new(); r1.seed = s
			var r2 := RandomNumberGenerator.new(); r2.seed = s
			BossLoot._cached = off
			var off_got: Dictionary = BossLoot.grant(p1, f.rules, f.loot, data, false, 1.0, r1)
			BossLoot._cached = saved
			var on_got: Dictionary = BossLoot.grant(p2, f.rules, f.loot, data, false, 1.0, r2)
			off_weapons += off_got["items"].filter(func(i): return i.item_id == a or i.item_id == b).size()
			var set_on: Array = on_got["items"].filter(func(i): return str(f.rules.catalog.entry(i.item_id).get("set", "")) != "")
			same = same and set_on.size() == off_got["items"].size() and on_got["relics"] == off_got["relics"]
			for i in on_got["items"]:
				if i.item_id == a or i.item_id == b:
					n_a += 1 if i.item_id == a else 0
					n_b += 1 if i.item_id == b else 0
					slots_ok = slots_ok and i.slot == str(f.rules.catalog.entry(i.item_id).slot) and p2.stash.items.has(i)
		BossLoot._cached = saved
		ctx.check("%s weapon drops ON: each ~10%% of 2000 wins (%s %d, %s %d)" % [zone, a, n_a, b, n_b], n_a >= 150 and n_a <= 250 and n_b >= 150 and n_b <= 250)
		ctx.check("%s weapon drops: in the stash in their catalog slot (the shield in offhand)" % zone, slots_ok)
		ctx.check("%s weapon drops: the set piece and relic rolls of each seed match drops OFF" % zone, same)
		ctx.check("%s weapon drops OFF (test copy): 2000 wins give no boss weapon" % zone, off_weapons == 0)


## The client half (Boss warning): the GameState start path really starts the orc fight offline for the quest-done
## profile, and refuses it while the quest is not met.
func _client_start(ctx, f: Dictionary) -> void:
	var tree: SceneTree = ctx
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null or not gs.ensure_profile():
		ctx.check("GameState profile available", false)
		return
	var old_auto: bool = gs.auto_battle
	var old_zone: String = gs.selected_zone
	gs.auto_battle = true
	var p = gs.profile
	var saved_unlocks: Dictionary = p.unlocks.duplicate(true)
	var saved_cards: Dictionary = p.card_deck["cards"].duplicate(true)
	p.unlocks[Zones.boss_key("goblin_base")] = true
	p.unlocks[Zones.boss_key("pyramid")] = true
	set_levels(p, [15, 10, 10, 9])
	gs.selected_zone = "orc_camp"
	ctx.check("client: quest not met -> fight_journey falls back, start_journey(orc_waves) refused", gs.fight_journey() != JOURNEY and not gs.start_journey(JOURNEY, 5))
	set_levels(p, [20, 10, 10, 10])
	ctx.check("client: quest done -> the map pick starts orc_waves", gs.fight_journey() == JOURNEY)
	ctx.check("client: start_journey(orc_waves) succeeds", gs.start_journey(JOURNEY, 5))
	var stage: Node = null
	for i in 240:
		await tree.process_frame
		stage = tree.current_scene
		if stage != null and stage.get("_session") != null and stage.get("_session").living_enemy_count() > 0:
			break
	var sim = stage.get("_session") if stage != null else null
	var types := {}
	if sim != null:
		for fid in sim.fighters:
			if sim.fighters[fid].team == "enemy":
				types[sim.fighters[fid].enemy_type] = true
	ctx.check("client: the fight runs on the orc night map with orcs %s" % [types.keys()], gs.journey != null and gs.journey.data.id == JOURNEY and sim != null and not types.is_empty() and types.keys().all(func(t): return ORC.has(t)))
	ctx.check("client: the map is orc_camp_night", stage != null and str(stage.get("map_id") if stage.get("map_id") != null else gs.journey_map_id(gs.journey.current)) == "orc_camp_night")
	gs.go_card_deck()  # leave the fight (later tests run camp commands on GameState's session)
	for i in 10:
		await tree.process_frame
	gs.journey = null  # (as test_journey / test_exit_portals: GameState keeps the journey after the hub, later camp commands would see it)
	gs.auto_battle = old_auto
	gs.selected_zone = old_zone
	p.unlocks = saved_unlocks
	p.card_deck["cards"] = saved_cards
