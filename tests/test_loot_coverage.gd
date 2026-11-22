extends RefCounted
## Family loot coverage (2026-11-22, Boss: "the Orc Camp drops NOTHING"). Root cause: data/loot/loot.json by_enemy had no
## entry for orc_grunt / orc_archer / orc_mage / orc_warlock, and Loot.roll gives an empty drop to a type with no table,
## so every orc kill (offline and in a room) paid nothing. Locks: (1) every monster type in combat.json has a loot table
## (and the check really catches a missing one); (2) each orc type drops gold, materials and items at rates like its
## goblin/mummy twin; (3) a driven orc_waves room pays loot events with race pieces for every orc type during the waves,
## brings them to the stash, and the won run pays the Warlock coin; (4) orc_camp boss wins pay set / coin / relic / weapons.
const Loot := preload("res://logic/loot.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Journey := preload("res://logic/journey.gd")
const Profile := preload("res://logic/profile.gd")
const GearLevels := preload("res://logic/gear_levels.gd")
const F := preload("res://tests/online_fixture.gd")
const Squads := preload("res://tests/test_online_squads.gd")
const OrcZone := preload("res://tests/test_orc_zone.gd")
const ORC := ["orc_grunt", "orc_archer", "orc_mage", "orc_warlock"]
## The twin whose table each orc type must share (same structure and rates as the goblin / mummy families).
const TWIN := {"orc_grunt": "mummy", "orc_archer": "goblin_archer", "orc_mage": "goblin_mage", "orc_warlock": "mummy_high_wizard"}


## Monster types in `enemy_ids` with no usable loot table (missing, or pointing at an unknown table).
static func missing_tables(loot, enemy_ids: Array) -> Array:
	return enemy_ids.filter(func(t): return not loot.by_enemy.has(t) or not loot.tables.has(loot.by_enemy[t]))


func run(ctx) -> void:
	var f := F.make()
	_coverage(ctx, f)
	_rolls(ctx, f)
	_room(ctx, f)
	_boss(ctx, f)


func _coverage(ctx, f: Dictionary) -> void:
	ctx.check("loot.json loads with no errors %s" % [f.loot.errors], f.loot.errors.is_empty())
	var missing := missing_tables(f.loot, f.combat.enemies.keys())
	ctx.check("every combat.json monster type has a loot table (missing %s)" % [missing], missing.is_empty())
	var broken = load("res://logic/loot_data.gd").new()
	broken.tables = f.loot.tables
	broken.by_enemy = f.loot.by_enemy.duplicate()
	broken.by_enemy.erase("orc_mage")
	ctx.check("the coverage check catches a monster type with no table", missing_tables(broken, f.combat.enemies.keys()) == ["orc_mage"])
	for t in ORC:
		ctx.check("%s uses the same loot table as %s (%s)" % [t, TWIN[t], f.loot.by_enemy.get(t, "-")], f.loot.by_enemy.get(t, "?") == f.loot.by_enemy.get(TWIN[t], "!"))


func _rolls(ctx, f: Dictionary) -> void:
	for t in ORC:
		var rng := F.rng(2026)
		var n := 1000
		var gold := 0
		var items := 0
		var mats := 0
		for i in n:
			var d: Dictionary = Loot.roll(f.rules, f.loot, t, 3, f.combat.weapon_ids, rng)
			gold += int(d.gold)
			items += d["items"].size()
			mats += 1 if not d["materials"].is_empty() else 0
		var table: Dictionary = f.loot.tables[f.loot.by_enemy[TWIN[t]]]
		var item_chance := 0.0
		for drop in table["drops"]:
			if drop.has("item"): item_chance = float(drop["chance"])
		var rate := float(items) / n
		ctx.check("%s drops per kill over %d rolls: gold %.1f, item rate %.3f (table %.3f), material rate %.2f" % [t, n, float(gold) / n, rate, item_chance, float(mats) / n],
			gold > 0 and items > 0 and mats > 0 and absf(rate - item_chance) < 0.04)


## A driven orc_waves room (as tests/test_orc_zone.gd), but the enemies die through real "killed" events, so the loot
## pipeline (Loot.roll -> RaceDrops -> gear level cap -> run bag) runs for every kill.
func _room(ctx, f: Dictionary) -> void:
	var mgr = Squads.squad_manager()
	var p = OrcZone.after_pyramid(f, [20, 10, 10, 10], 61)
	var stash_before: int = p.stash.items.size()
	var made: Dictionary = mgr.create("orc-loot-1", 91, [{"id": 1, "profile": p.to_dict()}], false, 1, "", "orc_waves")
	ctx.check("loot room: orc_waves room starts %s" % [made.get("error", "")], made.get("ok", false))
	if not made.get("ok", false):
		return
	var room = mgr.rooms["orc-loot-1"].room
	var sim = room.sim
	var FS = preload("res://logic/fighter.gd").State
	var by_type := {}  # orc type -> [kills paid, items]
	var levels := {}
	var races := {}
	var item_total := 0
	var gold_total := 0
	for i in 30000:
		room.tick()
		var killer := -1
		for id in sim.runs:
			if not sim.runs[id].died: killer = id; break
		sim.events.clear()
		for fid in sim.fighters.keys():
			var fighter = sim.fighters[fid]
			if fighter.team == "enemy" and fighter.is_alive():
				fighter.hp = 0; fighter.state = FS.DEAD
				sim.events.append({"type": "killed", "target": fid, "by": killer})
		sim._process_economy()
		for e in sim.events:
			if e["type"] != "loot": continue
			var t: String = sim.fighters[int(e["enemy"])].enemy_type
			if not by_type.has(t): by_type[t] = [0, 0]
			by_type[t][0] += 1
			by_type[t][1] += e["items"].size()
			item_total += e["items"].size()
			gold_total += int(e["gold"])
			for it in e["items"]:
				levels[f.rules.catalog.req_level(str(it["item_id"]))] = true
				races[str(f.rules.catalog.entry(str(it["item_id"])).get("race", ""))] = true
		if room.journey.state != Journey.IN_STAGE: break
	ctx.check("loot room: every orc type paid loot events %s" % [by_type], ORC.all(func(t): return by_type.has(t) and by_type[t][0] > 0))
	ctx.check("loot room: items dropped during the waves (%d items, %d gold)" % [item_total, gold_total], item_total > 0 and gold_total > 0)
	ctx.check("loot room: dropped piece levels respect the orc gear cap 20 %s" % [levels.keys()], not levels.is_empty() and levels.keys().all(func(l): return int(l) <= GearLevels.zone_level("orc_camp")))
	ctx.check("loot room: drops are race pieces of random races %s" % [races.keys()], races.size() >= 2)
	ctx.check("loot room: the run is won", room.journey.state == Journey.WON)
	if room.journey.state != Journey.WON:
		return
	var d: Dictionary = room.finalize().values()[0]
	var coin := str(BossLoot.boss("orc_camp").get("coin", ""))
	ctx.check("loot room settle: the stash holds the wave drops (%d -> %d)" % [stash_before, Array(d.stash.items).size()], Array(d.stash.items).size() >= stash_before + item_total)
	ctx.check("loot room settle: the Warlock win paid its coin", int(d.stash.materials.get(coin, 0)) >= 1)


## orc_camp boss pay on a WON run over many seeds: coin every win, set pieces ~25%, relic ~1%, sword and shield ~10% each.
func _boss(ctx, f: Dictionary) -> void:
	var data = JourneyData.load_by_id("orc_waves", f.combat.enemies.keys())
	var n := 2000
	var coins := 0
	var pieces := 0
	var relics := 0
	var sword := 0
	var shield := 0
	for s in n:
		var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(1)))
		var got: Dictionary = BossLoot.grant(p, f.rules, f.loot, data, false, 1.0, F.rng(s))
		coins += int(got.get("coins", 0))
		relics += int(got.get("relics", {}).get("relic_orc_warlock", 0))
		for it in got.get("items", []):
			if it.item_id == "boss_orc_warlock_sword": sword += 1
			elif it.item_id == "boss_orc_warlock_shield": shield += 1
			elif str(it.item_id).begins_with("boss_orc_warlock_"): pieces += 1
	ctx.check("orc boss over %d wins: coins %d, set pieces %d (~25%%), relics %d (~1%%), sword %d / shield %d (~10%% each)" % [n, coins, pieces, relics, sword, shield],
		coins == n and pieces >= 430 and pieces <= 570 and relics >= 5 and relics <= 40 and sword >= 150 and sword <= 250 and shield >= 150 and shield <= 250)
