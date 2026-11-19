extends RefCounted
## Squad rooms host any zone wave journey (Boss bug 2026-11-19: FIGHT on the Sand Pyramid did nothing online).
## The server authorises the id per profile: unknown -> invalid_journey, locked zone -> zone_locked.
const F := preload("res://tests/online_fixture.gd")
const Squads := preload("res://tests/test_online_squads.gd")
const Zones := preload("res://logic/world_zones.gd")
const Journey := preload("res://logic/journey.gd")
const BossLoot := preload("res://logic/boss_loot.gd")


static func _open(id: int) -> Dictionary:
	var p = F.make(id).profile
	p.unlocks[Zones.boss_key("goblin_base")] = true
	for card in p.card_deck.cards: p.card_deck.cards[card]["progress"] = {"level": 15, "xp": 0}
	return {"id": id, "profile": p.to_dict()}


static func _locked(id: int) -> Dictionary:
	return {"id": id, "profile": F.make(id).profile.to_dict()}


func run(ctx) -> void:
	var mgr = Squads.squad_manager()
	var ids: Array = Zones.zones().filter(func(z): return not str(z.journey).is_empty()).map(func(z): return str(z.journey))
	ctx.check("zone rooms: every zone journey loads for the room worker", ids.size() >= 2 and ids.all(func(j): return mgr.zone_journey(j) != null))
	ctx.check("zone rooms: unknown journey id is invalid_journey", mgr.create("zr-unknown-1", 77, [_open(1)], false, 1, "", "nope_waves").get("error", "") == "invalid_journey")
	ctx.check("zone rooms: ink_road is not a squad journey", mgr.create("zr-ink-1", 77, [_open(1)], false, 1, "", "ink_road").get("error", "") == "invalid_journey")
	var made: Dictionary = mgr.create("zr-mummy-1", 77, [_open(1)], false, 1, "", "mummy_waves")
	ctx.check("zone rooms: an open profile starts a mummy_waves room", made.get("ok", false) and mgr.rooms["zr-mummy-1"].room.journey.data.id == "mummy_waves")
	ctx.check("zone rooms: locked profile is refused with zone_locked", mgr.create("zr-mummy-2", 77, [_locked(1)], false, 1, "", "mummy_waves").get("error", "") == "zone_locked")
	ctx.check("zone rooms: goblin is the default (no id) and open to everyone", mgr.create("zr-gob-1", 77, [_locked(1)]).ok and mgr.rooms["zr-gob-1"].room.journey.data.id == "goblin_waves")
	ctx.check("zone rooms: explicit goblin_waves works", mgr.create("zr-gob-2", 77, [_locked(1)], false, 1, "", "goblin_waves").ok)
	ctx.check("zone rooms: two players, one locked, are refused", mgr.create("zr-mix-1", 77, [_open(1), _locked(2)], false, 2, "", "mummy_waves").get("error", "") == "zone_locked")
	var duo: Dictionary = mgr.create("zr-duo-1", 77, [_open(1), _open(2)], false, 2, "", "mummy_waves")
	ctx.check("zone rooms: two open players start a mummy_waves room", duo.get("ok", false) and mgr.rooms["zr-duo-1"].room.journey.data.id == "mummy_waves")
	var data = mgr.zone_journey("mummy_waves")
	var goblin = mgr.zone_journey("goblin_waves")
	ctx.check("zone rooms: mummy wave_power_by_squad covers 1..3 players like goblin", data.wave_power_by_squad.size() >= 3 and data.wave_power_by_squad.size() == goblin.wave_power_by_squad.size() and data.wave_power_for(1) > 0.0)
	if not made.get("ok", false): return
	# Drive the room: ticks spawn mummies; the run ends on a win and the settle pays the pyramid boss loot.
	var room = mgr.rooms["zr-mummy-1"].room
	for i in 120: room.tick()
	ctx.check("zone rooms: the mummy room fields fighters after ticks", room.sim.fighters.size() > 1)
	var boss_zone: String = BossLoot.boss_for_journey("mummy_waves")[0]
	ctx.check("zone rooms: boss loot keys the pyramid zone", boss_zone == "pyramid")
	# Wave drive: wipe every living monster each tick until the run ends; the boss pair must show up on the way.
	var seen := {}
	var wire_types := {}
	var wire_bad := []
	var Wire = preload("res://logic/net_wire.gd")
	var last_seq := 0
	var boss_ticks := 0
	var FS = preload("res://logic/fighter.gd").State
	for i in 30000:
		room.tick()
		for rec in room.events:
			if int(rec.sequence) <= last_seq: continue
			last_seq = int(rec.sequence)
			var et := str(rec.event.get("type", ""))
			wire_types[et] = true
			if et in ["area_placed", "projectile_fired", "attack_started"] and Wire.packet(Wire.EVENTS, last_seq, {"events": [rec]}).is_empty(): wire_bad.append(et)
		for fid in room.sim.fighters:
			var f = room.sim.fighters[fid]
			if f.team == "enemy" and f.is_alive():
				seen[f.enemy_type] = true
				if f.enemy_type in ["mummy_high_wizard", "mummy_boss"]:  # let the boss pair act so its moves reach the event stream
					boss_ticks += 1
					if boss_ticks < 1500: continue
				f.hp = 0; f.state = FS.DEAD
		if room.journey.state != Journey.IN_STAGE: break
	ctx.check("zone rooms: wave drive saw the mummy boss pair %s" % [seen.keys()], seen.has("mummy_high_wizard") and seen.size() >= 3)
	ctx.check("zone rooms: wizard events (area_placed, projectile_fired, attack_started) are queued and fit the wire %s %s" % [wire_types.keys(), wire_bad], wire_bad.is_empty() and wire_types.has("attack_started") and wire_types.has("area_placed") and wire_types.has("projectile_fired"))
	ctx.check("zone rooms: wave drive ended in a win", room.journey.state == Journey.WON)
	if room.journey.state == Journey.IN_STAGE: room.journey.stage_cleared(1.0)
	ctx.check("zone rooms: the run is won", room.journey.state == Journey.WON)
	var profiles: Dictionary = room.finalize()
	var d: Dictionary = profiles.values()[0]
	var coin := str(BossLoot.boss("pyramid").get("coin", ""))
	ctx.check("zone rooms: settle pays the pyramid boss coin %s" % coin, not coin.is_empty() and int(d.stash.materials.get(coin, 0)) >= 1)
	ctx.check("zone rooms: the pyramid boss is flagged beaten", bool(d.unlocks.get(Zones.boss_key("pyramid"), false)))
