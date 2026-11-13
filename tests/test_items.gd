extends RefCounted
## Tests the equipment system: rule book, item creation, tier-ups, enhancement, loadout, stat totals.
## Random behavior is tested with seeded generators, so every run gives the same result.

const GameSim := preload("res://logic/game_sim.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Item := preload("res://logic/item.gd")
const Loadout := preload("res://logic/loadout.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const Stats := preload("res://logic/stats.gd")

const NORMAL := 0
const RARE := 1
const EPIC := 2
const LEGENDARY := 3


func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	ctx.check("the shipped rule book is valid %s" % [rules.errors], rules.is_valid())
	if not rules.is_valid():
		return
	_test_rule_book(ctx, rules)
	_test_rule_validation(ctx)
	_test_create(ctx, rules)
	_test_tier_up(ctx, rules)
	_test_enhancement_basics(ctx, rules)
	_test_enhancement_odds(ctx, rules)
	_test_protection_and_break(ctx, rules)
	_test_determinism(ctx, rules)
	_test_loadout_and_stats(ctx, rules)
	_test_move_speed_reaches_the_simulation(ctx, rules)
	_test_old_upgrade_bonus_rescaled(ctx, rules)


## HP scale 100 (2026-11-13): an item saved before the change keeps its rolls, but its saved HP/ATK/HPREGEN
## upgrade amounts are divided by 10 once on load; other stats and already-new saves are untouched.
func _test_old_upgrade_bonus_rescaled(ctx, rules) -> void:
	var item = ItemSystem.create_item(rules, "old-save", "pants", 2, _rng(5))
	item.substats.clear()
	item.substats.append({"stat": "ATK", "quality": 0.5, "boosts": 0, "upgrade_bonus": 2.0})
	item.substats.append({"stat": "CRIRATE", "quality": 0.5, "boosts": 0, "upgrade_bonus": 0.4})
	item.substats.append({"stat": "HP", "quality": 0.5, "boosts": 0, "upgrade_bonus": 20.0})
	var old_save: Dictionary = item.to_dict()
	old_save.erase("stat_scale")
	var loaded = Item.from_dict(old_save)
	ctx.check("an old save's HP/ATK upgrade amounts are divided by 10, others kept", is_equal_approx(loaded.substats[0]["upgrade_bonus"], 0.2) and is_equal_approx(loaded.substats[1]["upgrade_bonus"], 0.4) and is_equal_approx(loaded.substats[2]["upgrade_bonus"], 2.0))
	var again = Item.from_dict(loaded.to_dict())
	ctx.check("a new save is not rescaled again", is_equal_approx(again.substats[0]["upgrade_bonus"], 0.2) and is_equal_approx(again.substats[2]["upgrade_bonus"], 2.0))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _item_at_level(rules, slot: String, tier: int, level: int, rng: RandomNumberGenerator):
	var item = ItemSystem.create_item(rules, "t", slot, tier, rng)
	item.level = level
	return item


func _test_rule_book(ctx, rules) -> void:
	ctx.check("14 equipment slots in total (offhand added 2026-11-11, hat removed 2026-11-13)", rules.total_slot_count() == 14 and rules.slot("hat").is_empty())
	ctx.check("two earrings, two bracelets, two rings, one armband piece for both arms", rules.slot("earring")["count"] == 2 and rules.slot("bracelet")["count"] == 2 and rules.slot("ring")["count"] == 2 and rules.slot("armband")["count"] == 1)
	ctx.check("weapon and shoes are separate single slots", rules.slot("weapon")["count"] == 1 and rules.slot("shoes")["count"] == 1)
	ctx.check("the necklace gives STAMINA as its main stat", rules.slot("necklace")["main_stat"] == "STAMINA")
	var regen_is_main := false
	for slot in rules.slots:
		regen_is_main = regen_is_main or ["HPREGEN", "STAREGEN", "ULTREGEN"].has(slot["main_stat"])
	ctx.check("the regeneration stats are not the main stat of any slot (they roll as sub stats)", not regen_is_main)
	ctx.check("four tiers: white, blue, purple, gold", rules.tiers.map(func(t): return t["color"]) == ["white", "blue", "purple", "gold"])
	ctx.check("sub stat counts follow the tier: 1, 2, 3, 4", rules.tiers.map(func(t): return t["substat_count"]) == [1, 2, 3, 4])
	ctx.check("enhancement goes up to +10", rules.max_level == 10)
	ctx.check("the thirteen director stats exist", rules.stat_ids == ["HP", "ATK", "DEF", "ATKSPD", "MOVESPD", "CRIRATE", "CRIDMG", "EFFECT_ACC", "EFFECT_RES", "HPREGEN", "STAREGEN", "ULTREGEN", "STAMINA"])
	ctx.check("STAMINA (the size of the stamina bar) starts at 100", rules.stat_base["STAMINA"] == 100.0)
	ctx.check("a character regains stamina at 32 per second by default", rules.stat_base["STAREGEN"] == 32.0 and rules.stat_base["HPREGEN"] == 0.0 and rules.stat_base["ULTREGEN"] == 0.0)
	ctx.check("odds: +1 to +3 never fail", rules.odds_by_level[1]["success"] == 1.0 and rules.odds_by_level[3]["success"] == 1.0)
	ctx.check("odds: +10 can break, +4 cannot", rules.odds_by_level[10]["break"] > 0.0 and rules.odds_by_level[4]["break"] == 0.0)


func _test_rule_validation(ctx) -> void:
	var good := FileAccess.get_file_as_string(ItemRulesLoader.RULES_PATH)
	ctx.check("broken JSON is reported", not ItemRulesLoader.parse("{ nope").is_valid())
	ctx.check("wrong version is reported", not ItemRulesLoader.parse(good.replace("\"version\": 1", "\"version\": 7")).is_valid())
	ctx.check("probabilities that do not add to 1 are reported", not ItemRulesLoader.parse(good.replace("\"success\": 0.7", "\"success\": 0.9")).is_valid())
	ctx.check("an unknown main stat is reported", not ItemRulesLoader.parse(good.replace("\"main_stat\": \"ATK\"", "\"main_stat\": \"MAGIC\"")).is_valid())
	ctx.check("a missing enhancement level is reported", not ItemRulesLoader.parse(good.replace("\"levels\": [9, 10]", "\"levels\": [9, 9]")).is_valid())
	ctx.check("a tier table of the wrong size is reported", not ItemRulesLoader.parse(good.replace("[40, 70, 110, 160]", "[40, 70]")).is_valid())


func _test_create(ctx, rules) -> void:
	var rng := _rng(1)
	var counts_ok := true
	var distinct_ok := true
	var quality_ok := true
	var main_ok := true
	for tier in 4:
		for attempt in 50:
			var item = ItemSystem.create_item(rules, "x", "ring", tier, rng)
			counts_ok = counts_ok and item.substats.size() == tier + 1
			var stats: Array[String] = []
			for sub in item.substats:
				distinct_ok = distinct_ok and not stats.has(sub["stat"]) and sub["stat"] != item.main_stat
				stats.append(sub["stat"])
				quality_ok = quality_ok and sub["quality"] >= 0.0 and sub["quality"] <= 1.0
			main_ok = main_ok and item.main_stat == "EFFECT_RES"
	ctx.check("sub stat count matches the tier (1/2/3/4)", counts_ok)
	ctx.check("sub stats are distinct and never repeat the main stat", distinct_ok)
	ctx.check("sub stat roll quality stays within 0..1", quality_ok)
	ctx.check("main stat comes from the slot", main_ok)
	ctx.check("unknown slot gives no item", ItemSystem.create_item(rules, "x", "tail", 0, rng) == null)
	ctx.check("unknown tier gives no item", ItemSystem.create_item(rules, "x", "ring", 9, rng) == null)

	var values: Array[float] = []
	for tier in 4:
		values.append(ItemSystem.create_item(rules, "x", "weapon", tier, rng).main_value(rules))
	ctx.check("main stat rises with every tier %s" % [values], values[0] < values[1] and values[1] < values[2] and values[2] < values[3])

	var sub_ok := true
	for tier in 4:
		for attempt in 100:
			var item = ItemSystem.create_item(rules, "x", "weapon", tier, rng)
			for index in item.substats.size():
				var range_for_stat: Vector2 = rules.substat_range[item.substats[index]["stat"]]
				var multiplier: float = rules.tier_multiplier[tier]
				var value: float = item.substat_value(index, rules)
				sub_ok = sub_ok and value >= range_for_stat.x * multiplier - 0.0001 and value <= range_for_stat.y * multiplier + 0.0001
	ctx.check("sub stat values stay inside the tier's range", sub_ok)


func _test_tier_up(ctx, rules) -> void:
	var rng := _rng(2)
	var item = ItemSystem.create_item(rules, "x", "pants", NORMAL, rng)
	var first_sub: Dictionary = item.substats[0].duplicate()
	var main_before: float = item.main_value(rules)
	var value_before: float = item.substat_value(0, rules)

	ctx.check("tier-up works from normal", ItemSystem.upgrade_tier(rules, item, rng))
	ctx.check("now rare with 2 sub stats", item.tier == RARE and item.substats.size() == 2)
	ctx.check("the first sub stat is kept", item.substats[0]["stat"] == first_sub["stat"] and item.substats[0]["quality"] == first_sub["quality"])
	ctx.check("the kept sub stat is worth more at the higher tier", item.substat_value(0, rules) > value_before)
	ctx.check("the main stat grew with the tier", item.main_value(rules) > main_before)

	ItemSystem.upgrade_tier(rules, item, rng)
	ItemSystem.upgrade_tier(rules, item, rng)
	ctx.check("legendary has 4 sub stats", item.tier == LEGENDARY and item.substats.size() == 4)
	ctx.check("there is no tier above legendary", not ItemSystem.upgrade_tier(rules, item, rng))
	ctx.check("tier is unchanged after a refused upgrade", item.tier == LEGENDARY and item.substats.size() == 4)

	var gone = ItemSystem.create_item(rules, "y", "pants", NORMAL, rng)
	gone.destroyed = true
	ctx.check("a destroyed item cannot be upgraded", not ItemSystem.upgrade_tier(rules, gone, rng))


func _test_enhancement_basics(ctx, rules) -> void:
	var rng := _rng(3)
	var item = ItemSystem.create_item(rules, "x", "weapon", EPIC, rng)
	var base: float = item.main_value(rules)
	var all_succeeded := true
	for step in 3:
		var result: Dictionary = ItemSystem.enhance(rules, item, rng)
		all_succeeded = all_succeeded and result["outcome"] == "success"
	ctx.check("+1 to +3 always succeed", all_succeeded and item.level == 3)
	ctx.check("main stat is +8%% per level (got %.3f for base %.3f)" % [item.main_value(rules), base], absf(item.main_value(rules) - base * 1.24) < 0.001)

	var boosts := 0
	for sub in item.substats:
		boosts += sub["boosts"]
	ctx.check("each success boosted exactly one sub stat once (total %d)" % boosts, boosts == 3)

	var fresh = ItemSystem.create_item(rules, "z", "weapon", EPIC, rng)
	var before: Array[float] = []
	for index in fresh.substats.size():
		before.append(fresh.substat_value(index, rules))
	var result: Dictionary = ItemSystem.enhance(rules, fresh, rng)
	var changed := 0
	for index in fresh.substats.size():
		if fresh.substat_value(index, rules) > before[index]:
			changed += 1
	ctx.check("a success raises one sub stat's value and reports which", changed == 1 and result["boosted_substat"] >= 0)

	fresh.level = 10
	ctx.check("a +10 item cannot be enhanced further", ItemSystem.enhance(rules, fresh, rng)["outcome"] == "maxed" and fresh.level == 10)


func _test_enhancement_odds(ctx, rules) -> void:
	# Many attempts with a fixed seed, compared with the table for +9 (success .30 stay .30 down .25 break .15).
	var rng := _rng(4)
	var tally := {"success": 0, "stay": 0, "down": 0, "break": 0}
	var attempts := 20000
	for i in attempts:
		var item = _item_at_level(rules, "ring", NORMAL, 8, rng)
		tally[ItemSystem.enhance(rules, item, rng)["outcome"]] += 1
	var odds: Dictionary = rules.odds_by_level[9]
	var close := true
	for outcome in tally:
		var seen := float(tally[outcome]) / float(attempts)
		close = close and absf(seen - float(odds[outcome])) < 0.02
	ctx.check("enhancement results match the table %s" % [tally], close)

	var item = _item_at_level(rules, "ring", NORMAL, 5, rng)
	var down = null
	for i in 1000:
		var probe = _item_at_level(rules, "ring", NORMAL, 5, rng)
		var result: Dictionary = ItemSystem.enhance(rules, probe, rng)
		if result["outcome"] == "down":
			down = probe
			ctx.check("'down' lowers the level by exactly one", result["level_before"] == 5 and result["level_after"] == 4 and probe.level == 4)
			break
	ctx.check("a 'down' result was observed at +6 odds", down != null)


func _test_protection_and_break(ctx, rules) -> void:
	var rng := _rng(5)
	var breaks := 0
	var downs := 0
	var survivors_ok := true
	for i in 5000:
		var item = _item_at_level(rules, "ring", NORMAL, 9, rng)
		var result: Dictionary = ItemSystem.enhance(rules, item, rng, true)
		breaks += 1 if result["outcome"] == "break" else 0
		downs += 1 if result["outcome"] == "down" else 0
		survivors_ok = survivors_ok and not item.destroyed
	ctx.check("a protection item prevents breaking and level loss", breaks == 0 and downs == 0 and survivors_ok)

	var broke = null
	for i in 2000:
		var item = _item_at_level(rules, "ring", NORMAL, 9, rng)
		if ItemSystem.enhance(rules, item, rng)["outcome"] == "break":
			broke = item
			break
	ctx.check("without protection an item can break", broke != null and broke.destroyed)
	if broke != null:
		ctx.check("a broken item cannot be enhanced again", ItemSystem.enhance(rules, broke, rng)["outcome"] == "invalid")
		ctx.check("a broken item cannot be equipped", not Loadout.new(rules).equip(broke))


func _test_determinism(ctx, rules) -> void:
	var results: Array = []
	for run_index in 2:
		var rng := _rng(99)
		var item = ItemSystem.create_item(rules, "x", "weapon", LEGENDARY, rng)
		var log: Array[String] = []
		for i in 25:
			log.append(ItemSystem.enhance(rules, item, rng)["outcome"])
			if item.destroyed:
				break
		results.append([item.level, item.destroyed, log, item.substats])
	ctx.check("the same seed always gives the same item history", results[0] == results[1])


func _test_loadout_and_stats(ctx, rules) -> void:
	var rng := _rng(6)
	var loadout := Loadout.new(rules)
	var ring_a = ItemSystem.create_item(rules, "a", "ring", NORMAL, rng)
	var ring_b = ItemSystem.create_item(rules, "b", "ring", RARE, rng)
	var ring_c = ItemSystem.create_item(rules, "c", "ring", EPIC, rng)
	ctx.check("two rings can be worn", loadout.equip(ring_a, 0) and loadout.equip(ring_b, 1))
	ctx.check("a third ring position does not exist", not loadout.equip(ring_c, 2))
	ctx.check("a negative position does not exist", not loadout.equip(ring_c, -1))
	var weapon = ItemSystem.create_item(rules, "w", "weapon", RARE, rng)
	ctx.check("weapon has one position only", loadout.equip(weapon) and not loadout.equip(weapon, 1))
	ctx.check("item_at returns what was worn", loadout.item_at("ring", 1) == ring_b)

	var bare := Stats.totals(rules, Loadout.new(rules).items())
	ctx.check("a character with no gear has the base stats (HP scale 100: 100 HP, 10 ATK)", bare["HP"] == 100.0 and bare["ATK"] == 10.0 and bare["CRIDMG"] == 150.0)
	var geared := Stats.totals(rules, loadout.items())
	var expected_atk: float = 10.0 + weapon.main_value(rules)
	for item in [ring_a, ring_b]:
		for index in item.substats.size():
			if item.substats[index]["stat"] == "ATK":
				expected_atk += item.substat_value(index, rules)
	for index in weapon.substats.size():
		if weapon.substats[index]["stat"] == "ATK":
			expected_atk += weapon.substat_value(index, rules)
	ctx.check("worn gear adds up into the stats (ATK %.2f)" % geared["ATK"], absf(geared["ATK"] - expected_atk) < 0.001)
	ctx.check("gear never lowers a stat", geared["HP"] >= bare["HP"] and geared["DEF"] >= bare["DEF"])

	ring_b.destroyed = true
	var after := Stats.totals(rules, loadout.items())
	ctx.check("a destroyed item stops counting", loadout.items().size() == 2 and after["EFFECT_RES"] <= geared["EFFECT_RES"])
	ctx.check("unequip returns the item and frees the slot", loadout.unequip("ring", 0) == ring_a and loadout.item_at("ring", 0) == null)


func _test_move_speed_reaches_the_simulation(ctx, rules) -> void:
	var rng := _rng(7)
	var shoes = ItemSystem.create_item(rules, "s", "shoes", LEGENDARY, rng)
	var loadout := Loadout.new(rules)
	loadout.equip(shoes)
	var totals := Stats.totals(rules, loadout.items())
	var multiplier := Stats.move_multiplier(totals)
	ctx.check("legendary shoes make the character faster (x%.2f)" % multiplier, multiplier > 1.1)
	ctx.check("no gear means normal speed", Stats.move_multiplier(Stats.totals(rules, [])) == 1.0)

	var distances: Array[float] = []
	for speed in [1.0, multiplier]:
		var world := SimWorld.new()
		world.half_width = 50.0
		world.add_solid(AABB(Vector3(-60, -0.4, -4), Vector3(120, 0.4, 8)))
		var sim := GameSim.new(world)
		var body = sim.add_player(1, Vector3(0, 0.05, 0))
		body.move_speed_multiplier = speed
		var input := SimInput.new()
		input.move = Vector2.RIGHT
		sim.set_input(1, input)
		for i in 60:
			sim.tick()
		distances.append(body.position.x)
	ctx.check("a higher MOVESPD covers more ground in the simulation (%.2f vs %.2f)" % [distances[0], distances[1]], absf(distances[1] / distances[0] - multiplier) < 0.01)
