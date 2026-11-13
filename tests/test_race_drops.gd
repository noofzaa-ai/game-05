extends RefCounted
## Race gear drops (design/gdd/race-gear-sets.md 3.12, design/gdd/drops-and-rewards.md 3.8; logic/race_drops.gd):
## gold race pieces only from the boss, every boss gold is a race piece, the race comes from the squad that played,
## and the per-source shares match data/loot/race_drops.json over many seeds. Boss 2026-11-13 (legacy items removed):
## every share is 100%, and a wave/chest gold drops as a purple race piece (PO default).
const RP := preload("res://tests/test_race_passives.gd")
const RaceDrops := preload("res://logic/race_drops.gd")
const Loot := preload("res://logic/loot.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Deck := preload("res://logic/card_deck.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]
const RARE := 1
const EPIC := 2
const LEGENDARY := 3
const N := 3000


func run(ctx) -> void:
	var f := RP.squad(["viking", "elf", "elf"])
	var picks: Array = RaceDrops.picks_for(f.journey.runs_by_player.values()[0])
	ctx.check("race drops: picks are the squad's cards with their races",
		picks.map(func(p): return "%s:%s" % [p["race"], p["class"]]) == ["viking:sword_shield", "elf:greatsword", "elf:longbow"])
	_shares(ctx, f.rules, picks)
	_gold_only_boss(ctx, f.rules, picks)
	_race_from_squad(ctx, f.rules, picks)
	_sim_boss_kill(ctx, f)


static func piece(rules, i: int, tier: int, slot: String = ""):
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var item = Loot.roll_piece(rules, "t-%d" % i, tier, 4, ["blade", "greatsword", "longbow"], rng)
	if not slot.is_empty() and item.slot != slot:
		var weapon_type := "blade" if slot == "weapon" else ""
		item = preload("res://logic/item_system.gd").create_item(rules, "t-%d" % i, slot, tier, rng, weapon_type)
	return item


static func is_race(rules, item) -> bool:  ## a race set piece or a race shield
	return not str(rules.catalog.entry(item.item_id).get("race", "")).is_empty()


## Fraction of N shirt pieces of `tier` that become race pieces from (source, wave).
static func rate(rules, picks: Array, tier: int, source: String, wave: int) -> float:
	var hits := 0
	for i in N:
		var item = RaceDrops.convert_piece(rules, piece(rules, i, tier, "shirt"), picks, source, wave)
		if is_race(rules, item) and int(item.tier) == tier and item.slot == "shirt":
			hits += 1
	return float(hits) / float(N)


func _shares(ctx, rules, picks: Array) -> void:
	var cases := [
		[0, RaceDrops.WAVE, 2, 1.0], [RARE, RaceDrops.WAVE, 2, 1.0], [RARE, RaceDrops.WAVE, 6, 1.0], [EPIC, RaceDrops.WAVE, 6, 1.0],
		[RARE, RaceDrops.WAVE, 10, 1.0], [EPIC, RaceDrops.WAVE, 10, 1.0],
		[0, RaceDrops.CHEST, 3, 1.0], [RARE, RaceDrops.CHEST, 3, 1.0], [EPIC, RaceDrops.CHEST, 9, 1.0],
		[0, RaceDrops.BOSS, 12, 1.0], [EPIC, RaceDrops.BOSS, 12, 1.0], [LEGENDARY, RaceDrops.BOSS, 12, 1.0]]
	var ok := true
	var report: Array = []
	for c in cases:
		var r := rate(rules, picks, int(c[0]), str(c[1]), int(c[2]))
		ok = ok and absf(r - float(c[3])) <= 0.03
		report.append("%s w%d t%d %.3f/%.2f" % [c[1], c[2], c[0], r, c[3]])
	ctx.check("race drops: shares by source/wave/tier match data over %d seeds (%s)" % [N, ", ".join(report)], ok)
	var off_ok := true
	for i in 200:
		var shield = RaceDrops.convert_piece(rules, piece(rules, 70000 + i, RARE, "offhand"), picks, RaceDrops.WAVE, 5)
		off_ok = off_ok and shield.item_id in ["race_viking_shield", "race_elf_shield"] and shield.slot == "offhand" and shield.tier == RARE
	ctx.check("race drops: a dropped offhand becomes the race shield of a squad card's race", off_ok)


func _gold_only_boss(ctx, rules, picks: Array) -> void:
	var leaked := 0
	var not_purple := 0
	for wave in range(1, 12):
		for i in 300:
			for source in [RaceDrops.WAVE, RaceDrops.CHEST]:
				var raw = piece(rules, wave * 1000 + i, LEGENDARY)
				var item = RaceDrops.convert_piece(rules, raw, picks, source, wave)
				if not RaceDrops.data()["slots"].has(raw.slot):
					continue
				if int(item.tier) == LEGENDARY:
					leaked += 1
				if int(item.tier) != EPIC or not item.item_id.begins_with("race_"):
					not_purple += 1
	ctx.check("race drops: no wave or chest drop is ever gold", leaked == 0)
	ctx.check("race drops: a wave or chest gold roll drops as a purple race piece", not_purple == 0)
	var generic := 0
	var race_slots := {}
	for i in 600:
		var raw = piece(rules, 50000 + i, LEGENDARY)
		var item = RaceDrops.convert_piece(rules, raw, picks, RaceDrops.BOSS, 12)
		if RaceDrops.data()["slots"].has(raw.slot):
			if not is_race(rules, item) or int(item.tier) != LEGENDARY:
				generic += 1
			race_slots[item.slot] = true
	ctx.check("race drops: every boss legendary in a race slot is a gold race piece (slots seen: %s)" % ", ".join(race_slots.keys()), generic == 0 and race_slots.size() >= 4)


func _race_from_squad(ctx, rules, picks: Array) -> void:
	var seen := {}
	var ok := true
	for i in 1500:
		var item = RaceDrops.convert_piece(rules, piece(rules, 90000 + i, EPIC), picks, RaceDrops.BOSS, 12)
		if not is_race(rules, item) or item.slot == "offhand":
			continue
		var entry: Dictionary = rules.catalog.entry(item.item_id)
		var key := "%s:%s" % [entry["race"], entry["class"]]
		seen[key] = int(seen.get(key, 0)) + 1
		ok = ok and key in ["viking:sword_shield", "elf:greatsword", "elf:longbow"]
	var total := 0
	for key in seen:
		total += int(seen[key])
	var even := seen.size() == 3 and seen.values().all(func(n): return absf(float(n) / float(total) - 1.0 / 3.0) < 0.05)
	ctx.check("race drops: race and class come only from the squad, about evenly per card (%s)" % str(seen), ok and even)
	ctx.check("race drops: a run with no squad card converts nothing", RaceDrops.picks_for(null).is_empty()
		and RaceDrops.convert_piece(rules, piece(rules, 7, LEGENDARY, "shirt"), [], RaceDrops.BOSS, 12).to_dict() == piece(rules, 7, LEGENDARY, "shirt").to_dict())
	var again = RaceDrops.convert_piece(rules, piece(rules, 12345, LEGENDARY, "shirt"), picks, RaceDrops.BOSS, 12)
	var twice = RaceDrops.convert_piece(rules, piece(rules, 12345, LEGENDARY, "shirt"), picks, RaceDrops.BOSS, 12)
	ctx.check("race drops: same item id gives the same race piece and stats", again.item_id == twice.item_id and again.to_dict() == twice.to_dict())


## Through the sim: kill drops of the Chief (boss shares) vs a goblin at wave 2 (no share).
func _sim_boss_kill(ctx, f: Dictionary) -> void:
	var sim = f.sim
	var player: int = sim.runs.keys()[0]
	var boss_items: Array = []
	var goblin_items: Array = []
	for i in 400:
		for kind in ["goblin_chief", "goblin"]:
			var id := 5000 + i * 2 + (0 if kind == "goblin_chief" else 1)
			sim.add_enemy(id, Vector3(30, 0, 30), kind, 4)
			sim.rng.seed = 900 + i
			sim.reward_wave = 2
			var before: int = sim.runs[player].bag.items.size()
			sim._give_drop(id, player)
			var got: Array = sim.runs[player].bag.items.slice(before)
			(boss_items if kind == "goblin_chief" else goblin_items).append_array(got)
			sim.runs[player].bag.items.clear()
			sim.remove_player(id)
	var gold_generic := boss_items.filter(func(it): return int(it.tier) == LEGENDARY and RaceDrops.data()["slots"].has(it.slot) and not is_race(f.rules, it)).size()
	var boss_race := boss_items.filter(func(it): return is_race(f.rules, it)).size()
	var goblin_race := goblin_items.filter(func(it): return is_race(f.rules, it)).size()
	var goblin_gold := goblin_items.filter(func(it): return int(it.tier) == LEGENDARY).size()
	ctx.check("race drops (sim): every Chief and goblin piece is a race piece (%d of %d, %d of %d), no goblin gold, no generic gold from the boss"
		% [boss_race, boss_items.size(), goblin_race, goblin_items.size()], boss_race == boss_items.size() and goblin_race == goblin_items.size() and goblin_gold == 0 and gold_generic == 0)
