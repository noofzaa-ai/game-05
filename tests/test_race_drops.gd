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
	_random_everything(ctx, f.rules, picks)


static func piece(rules, i: int, tier: int, slot: String = ""):
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var item = Loot.roll_piece(rules, "t-%d" % i, tier, 4, ["blade", "greatsword", "longbow"], rng)
	if not slot.is_empty() and item.slot != slot:
		var weapon_type := "blade" if slot == "weapon" else ""
		item = preload("res://logic/item_system.gd").create_item(rules, "t-%d" % i, slot, tier, rng, weapon_type)
	return item


static func is_race(rules, item) -> bool:  ## a race weapon / race shield, or (Boss 2026-11-16) a class armour piece
	return not str(rules.catalog.entry(item.item_id).get("race", "")).is_empty() or str(item.item_id).begins_with("armour_")


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
		off_ok = off_ok and str(rules.catalog.entry(shield.item_id).get("race", "")) != "" and shield.item_id.ends_with("_shield") and shield.slot == "offhand" and shield.tier == RARE
	ctx.check("race drops: a dropped offhand becomes a race shield (Boss 2026-11-20: random race, no longer the squad card race)", off_ok)


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
				if int(item.tier) != EPIC or not is_race(rules, item):
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
	_with_pick("squad", "squad", func(): _race_from_squad_body(ctx, rules, picks))  # Boss 2026-11-20: the squad-only rule is now the pick mode "squad"


func _race_from_squad_body(ctx, rules, picks: Array) -> void:
	var seen := {}
	var ok := true
	for i in 1500:
		var item = RaceDrops.convert_piece(rules, piece(rules, 90000 + i, EPIC), picks, RaceDrops.BOSS, 12)
		if not is_race(rules, item) or item.slot == "offhand":
			continue
		if item.slot != "weapon":
			continue  # armour is class-bound (race-free): only race weapons carry the card's race
		var entry: Dictionary = rules.catalog.entry(item.item_id)
		var key := "%s:%s" % [entry["race"], entry["class"]]
		seen[key] = int(seen.get(key, 0)) + 1
		ok = ok and key in ["viking:sword_shield", "elf:greatsword", "elf:longbow"]
	var total := 0
	for key in seen:
		total += int(seen[key])
	var even := seen.size() == 3 and seen.values().all(func(n): return absf(float(n) / float(total) - 1.0 / 3.0) < 0.05)
	ctx.check("race drops (pick mode squad): race and class come only from the squad, about evenly per card (%s)" % str(seen), ok and even)
	ctx.check("race drops: a run with no squad card converts nothing", RaceDrops.picks_for(null).is_empty()
		and RaceDrops.convert_piece(rules, piece(rules, 7, LEGENDARY, "shirt"), [], RaceDrops.BOSS, 12, 15).to_dict() == preload("res://logic/gear_levels.gd").fit(rules, piece(rules, 7, LEGENDARY, "shirt"), 15).to_dict())  # no race change; only the gear level cap (logic/gear_levels.gd) may touch it
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


## Runs `body` with the pick modes forced (the data cache is restored afterwards).
static func _with_pick(race: String, klass: String, body: Callable) -> void:
	var saved: Dictionary = RaceDrops.data()
	var changed: Dictionary = saved.duplicate(true)
	changed["pick"] = {"race": race, "class": klass}
	RaceDrops._cached = changed
	body.call()
	RaceDrops._cached = saved


## Boss 2026-11-20 "random everything": race and class of a dropped weapon, the race of a shield and the class of an armour
## piece are uniform over everything the game has, independent of the squad.
func _random_everything(ctx, rules, picks: Array) -> void:
	var races := {}
	var classes := {}
	var shields := {}
	var armour := {}
	var bad := 0
	var wcount := 0
	for i in 4000:
		for source in [RaceDrops.WAVE, RaceDrops.CHEST, RaceDrops.BOSS]:
			if i % 3 != [RaceDrops.WAVE, RaceDrops.CHEST, RaceDrops.BOSS].find(source):
				continue
			var weapon = RaceDrops.convert_piece(rules, piece(rules, 200000 + i, RARE, "weapon"), picks, source, 5)
			var e: Dictionary = rules.catalog.entry(weapon.item_id)
			if weapon.slot != "weapon" or weapon.tier != RARE or e.is_empty() or str(e["race"]).is_empty() or str(e["class"]).is_empty():
				bad += 1
				continue
			races[e["race"]] = int(races.get(e["race"], 0)) + 1
			classes[e["class"]] = int(classes.get(e["class"], 0)) + 1
			wcount += 1
	for i in 4000:
		var shield = RaceDrops.convert_piece(rules, piece(rules, 300000 + i, EPIC, "offhand"), picks, RaceDrops.WAVE, 5)
		var armour_piece = RaceDrops.convert_piece(rules, piece(rules, 400000 + i, EPIC, "shirt"), picks, RaceDrops.WAVE, 5)
		var se: Dictionary = rules.catalog.entry(shield.item_id)
		if shield.slot != "offhand" or shield.tier != EPIC or str(se.get("race", "")).is_empty():
			bad += 1
		else:
			shields[se["race"]] = int(shields.get(se["race"], 0)) + 1
		var ae: Dictionary = rules.catalog.entry(armour_piece.item_id)
		if armour_piece.slot != "shirt" or armour_piece.tier != EPIC or str(ae.get("class", "")).is_empty() or not str(armour_piece.item_id).begins_with("armour_"):
			bad += 1
		else:
			armour[ae["class"]] = int(armour.get(ae["class"], 0)) + 1
	var all_races: Array = preload("res://logic/race_data.gd").load_default().ids()
	var all_classes: Array = Deck.classes()
	ctx.check("random drops: every produced piece is in the catalog with its tier and slot kept (%d bad)" % bad, bad == 0)
	ctx.check("random drops: weapon races uniform over all %d races (%s)" % [all_races.size(), str(races)], _uniform(races, all_races, wcount))
	ctx.check("random drops: weapon classes uniform over all %d classes (%s)" % [all_classes.size(), str(classes)], _uniform(classes, all_classes, wcount))
	ctx.check("random drops: shield races uniform (%s)" % str(shields), _uniform(shields, all_races, 4000))
	ctx.check("random drops: armour class uniform, any class not only the squad (%s)" % str(armour), _uniform(armour, all_classes, 4000))
	ctx.check("random drops: a magic weapon / magic armour can drop for a squad with no magic card", classes.has("magic") and armour.has("magic"))
	var a = RaceDrops.convert_piece(rules, piece(rules, 777, EPIC, "weapon"), picks, RaceDrops.WAVE, 5)
	var b = RaceDrops.convert_piece(rules, piece(rules, 777, EPIC, "weapon"), [], RaceDrops.WAVE, 5)
	ctx.check("random drops: deterministic for the same item id", a.to_dict() == RaceDrops.convert_piece(rules, piece(rules, 777, EPIC, "weapon"), picks, RaceDrops.WAVE, 5).to_dict())
	ctx.check("random drops: a run with no squad card still converts nothing", b.item_id == piece(rules, 777, EPIC, "weapon").item_id)
	# wearable on a matching card, refused on a non-matching class
	var Profile := preload("res://logic/profile.gd")
	var wear_ok := true
	var refuse_ok := true
	var seen_refusal := false
	for i in 300:
		var w = RaceDrops.convert_piece(rules, piece(rules, 500000 + i, RARE, "weapon"), picks, RaceDrops.WAVE, 5)
		var cls := str(rules.catalog.entry(w.item_id)["class"])
		for card in all_classes:
			var can: bool = Profile.card_can_wear(card, w, rules)
			if card == cls:
				wear_ok = wear_ok and can
			elif not Profile.weapon_families(card).has(w.weapon_type):
				refuse_ok = refuse_ok and not can
				seen_refusal = true
	ctx.check("random drops: a random-class weapon equips on a card of its class and is refused by a class that cannot hold that weapon", wear_ok and refuse_ok and seen_refusal)
	# level cap unchanged: nothing needs more than the cap
	var cap_ok := true
	for i in 300:
		var w = RaceDrops.convert_piece(rules, piece(rules, 600000 + i, EPIC, "weapon"), picks, RaceDrops.WAVE, 5, 1)
		cap_ok = cap_ok and (str(w.id).begins_with("starter-drop-") or rules.catalog.req_level(w.item_id) <= 1)
	ctx.check("random drops: the gear level cap still applies (cap 1 gives level-1 pieces)", cap_ok)
	# boss accessories untouched
	var acc_ok := true
	for i in 200:
		for slot in ["necklace", "ring", "earring", "bracelet", "back"]:
			var raw = preload("res://logic/item_system.gd").create_item(rules, "acc-%d" % i, slot, EPIC, RandomNumberGenerator.new())
			if raw == null:
				continue
			acc_ok = acc_ok and RaceDrops.convert_piece(rules, raw, picks, RaceDrops.BOSS, 12, 15).item_id == raw.item_id
	ctx.check("random drops: accessories (necklace/ring/earring/bracelet/back) are not touched", acc_ok)
	# squad mode = the old behaviour
	var squad_seen := {}
	var squad_ok := true
	_with_pick("squad", "squad", func():
		for i in 1500:
			var item = RaceDrops.convert_piece(rules, piece(rules, 90000 + i, EPIC), picks, RaceDrops.BOSS, 12)
			if item.slot != "weapon" or not is_race(rules, item):
				continue
			var entry: Dictionary = rules.catalog.entry(item.item_id)
			var key := "%s:%s" % [entry["race"], entry["class"]]
			squad_seen[key] = int(squad_seen.get(key, 0)) + 1
			squad_ok = squad_ok and key in ["viking:sword_shield", "elf:greatsword", "elf:longbow"]
		for i in 100:
			var s = RaceDrops.convert_piece(rules, piece(rules, 70000 + i, RARE, "offhand"), picks, RaceDrops.WAVE, 5)
			squad_ok = squad_ok and s.item_id in ["race_viking_shield", "race_elf_shield"])
	ctx.check("random drops: pick mode 'squad' reproduces the old squad-only behaviour (%s)" % str(squad_seen), squad_ok and squad_seen.size() == 3)


static func _uniform(counts: Dictionary, ids: Array, total: int) -> bool:
	if counts.size() != ids.size():
		return false
	for id in ids:
		if absf(float(counts.get(id, 0)) / float(total) - 1.0 / float(ids.size())) > 0.04:
			return false
	return true
