extends RefCounted
## Boss loot (design/gdd/boss-loot.md, Boss 2026-11-16; logic/boss_loot.gd): the Goblin Chief's accessory set, Relic and
## Boss Coin. One check group per acceptance criterion (AC1-AC7) plus the data, the edge cases and the drop table.
const F := preload("res://tests/online_fixture.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const Commands := preload("res://logic/commands.gd")
const Shop := preload("res://logic/shop.gd")
const Stats := preload("res://logic/stats.gd")
const Zones := preload("res://logic/world_zones.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Item := preload("res://logic/item.gd")
const Loot := preload("res://logic/loot.gd")
const Runner := preload("res://server/profile/runner.gd")
const Squads := preload("res://tests/test_online_squads.gd")
const COIN := "coin_goblin_chief"
const RELIC := "relic_goblin_chief"
const SET := "boss_goblin_chief"


func run(ctx) -> void:
	_data(ctx)
	_boss_set_parity(ctx)
	_ac1_drop_rates(ctx)
	_ac2_first_kill(ctx)
	_ac3_set_steps(ctx)
	_ac4_sockets(ctx)
	_ac5_shop(ctx)
	_shop_random_tier(ctx)
	_ac6_lost_run(ctx)
	_ac7_online(ctx)
	_edges(ctx)

## Every zone boss set (goblin_base + pyramid, Boss 2026-11-18 mummy order) follows the same rules: 5 slots, ids
## boss_<boss>_<slot>, no_drop, an icon file that exists, kind boss with 2/4/6 stat_mod steps and the same tier_mul, a coin
## and a relic that are unsellable camp materials with existing icons, and the pyramid pieces are level-15 gear.
func _boss_set_parity(ctx) -> void:
	var f := F.make()
	var slots := ["back", "bracelet", "earring", "necklace", "ring"]
	var bosses := {
		"goblin_base": {"set": "boss_goblin_chief", "dir": "goblin_chief", "coin": "coin_goblin_chief", "relic": "relic_goblin_chief", "req": 1},
		"pyramid": {"set": "boss_mummy_high_wizard", "dir": "mummy_high_wizard", "coin": "coin_mummy_high_wizard", "relic": "relic_mummy_high_wizard", "req": 15},
		"orc_camp": {"set": "boss_orc_warlock", "dir": "orc_warlock", "coin": "coin_orc_warlock", "relic": "relic_orc_warlock", "req": 20},
	}
	var raw_items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/catalog.json")).get("items", {})  # name_th is not kept by the loader
	var goblin_set: Dictionary = f.rules.catalog.sets["boss_goblin_chief"]
	for zone in bosses:
		var b: Dictionary = bosses[zone]
		var tag := "boss set %s" % b["set"]
		var pieces := BossLoot.set_pieces(f.rules, b["set"])
		ctx.check("%s: exactly the 5 accessory slots, ids boss_%s_<slot>" % [tag, b["dir"]], pieces == slots.map(func(sl): return "boss_%s_%s" % [b["dir"], sl]))
		var good := true
		for id in pieces:
			var e: Dictionary = f.rules.catalog.entry(id)
			var icon := "res://art/items/boss/%s/%s.png" % [b["dir"], str(e.slot)]
			good = good and bool(e.no_drop) and str(e.boss) == zone and str(e.icon_path) == icon and FileAccess.file_exists(icon) 				and not str(e.name).is_empty() and not str(raw_items.get(id, {}).get("name_th", "")).is_empty() 				and f.rules.catalog.req_level(id) == int(b["req"]) and int(e.drop_level) == int(b["req"])
		ctx.check("%s: no_drop, boss=%s, English+Thai names, icon files exist, req_level/drop_level %d" % [tag, zone, int(b["req"])], good)
		var set_def: Dictionary = f.rules.catalog.sets.get(b["set"], {})
		var steps: Array = set_def.get("steps", [])
		ctx.check("%s: kind boss, boss=%s, tier_mul like the goblin set" % [tag, zone], str(set_def.get("kind", "")) == "boss" and str(set_def.get("boss", "")) == zone and set_def.get("tier_mul", {}) == goblin_set.get("tier_mul", {}))
		ctx.check("%s: steps at 2/4/6 pieces, one stat_mod (mul > 0) each" % tag, steps.size() == 3 and steps.map(func(st): return int(st.pieces)) == [2, 4, 6] 			and steps.all(func(st): return st.effects.size() == 1 and str(st.effects[0].type) == "stat_mod" and float(st.effects[0].get("mul", 0.0)) > 0.0 and not str(st.text).is_empty()))
		for id in [b["coin"], b["relic"]]:
			var m: Dictionary = f.camp.materials.get(id, {})
			ctx.check("%s: %s is an unsellable camp material with an icon file" % [tag, id], not m.is_empty() and not m.sellable and FileAccess.file_exists(str(m.icon_path)) and str(m.icon_path).contains("/" + str(b["dir"]) + "/"))
		var relic: Dictionary = f.rules.catalog.relics.get(b["relic"], {})
		ctx.check("%s: relic has name/name_th/text, stat_mod effects, boss=%s, icon file" % [tag, zone], not relic.is_empty() and str(relic.boss) == zone and not relic.effects.is_empty() 			and relic.effects.all(func(e): return str(e.type) == "stat_mod") and FileAccess.file_exists(str(relic.icon_path)) and not str(relic.get("name_th", "")).is_empty())
	# Pyramid: the boss_loot.json entry (added by the loot owner) must name exactly these ids.
	var entry: Dictionary = BossLoot.boss("pyramid")
	ctx.check("boss set pyramid: boss_loot.json entry names the mummy set, coin and relic", entry.get("set", "") == "boss_mummy_high_wizard" and entry.get("coin", "") == "coin_mummy_high_wizard" and entry.get("relic", "") == "relic_mummy_high_wizard")
	# Level-15 gear: a non-starter pyramid piece has the level-15 main stat multiplier, a goblin piece has none.
	var mummy_item = ItemSystem.create_item(f.rules, "bp-mm", "ring", 1, F.rng(5), "", "boss_mummy_high_wizard_ring")
	var goblin_item = ItemSystem.create_item(f.rules, "bp-gb", "ring", 1, F.rng(5), "", "boss_goblin_chief_ring")
	ctx.check("boss set pyramid: pieces are real catalog items of their slot and the level-15 main stat is x%s of the goblin one" % [f.rules.catalog.level_mul(15)],
		mummy_item != null and mummy_item.item_id == "boss_mummy_high_wizard_ring" and goblin_item != null and absf(mummy_item.main_value(f.rules) / goblin_item.main_value(f.rules) - f.rules.catalog.level_mul(15)) < 0.001)
	# Orc Camp (2026-11-21): its own set/coin/relic (no longer the mummy placeholder), level-20 pieces one step above the mummy
	# ones (x level_mul(20) of the goblin piece), set steps and relic above the mummy's.
	var orc_entry: Dictionary = BossLoot.boss("orc_camp")
	ctx.check("boss set orc_camp: boss_loot.json entry names the Warlock set, coin and relic, sold for 500 Warlock coins",
		orc_entry.get("set", "") == "boss_orc_warlock" and orc_entry.get("coin", "") == "coin_orc_warlock" and orc_entry.get("relic", "") == "relic_orc_warlock" and int(orc_entry.get("price_coins", 0)) == 500)
	var orc_item = ItemSystem.create_item(f.rules, "bp-oc", "ring", 1, F.rng(5), "", "boss_orc_warlock_ring")
	ctx.check("boss set orc_camp: level-20 main stat is x%s of the goblin one and above the mummy one" % [f.rules.catalog.level_mul(20)],
		orc_item != null and absf(orc_item.main_value(f.rules) / goblin_item.main_value(f.rules) - f.rules.catalog.level_mul(20)) < 0.001 and orc_item.main_value(f.rules) > mummy_item.main_value(f.rules))
	var mummy_steps: Array = f.rules.catalog.sets["boss_mummy_high_wizard"].steps
	var orc_steps: Array = f.rules.catalog.sets["boss_orc_warlock"].steps
	var steps_up := true
	for k in 3:
		steps_up = steps_up and str(orc_steps[k].effects[0].stat) == str(mummy_steps[k].effects[0].stat) and float(orc_steps[k].effects[0].mul) > float(mummy_steps[k].effects[0].mul)
	ctx.check("boss set orc_camp: each set step is the mummy step's stat, a bit higher", steps_up)
	var sum := func(rid: String) -> float:
		return f.rules.catalog.relics[rid].effects.reduce(func(acc, e): return acc + (float(e.get("mul", 0.0)) if str(e.stat) == "ATK" else 0.0), 0.0)
	ctx.check("boss set orc_camp: the Warlock relic's ATK is above the mummy relic's", sum.call("relic_orc_warlock") > sum.call("relic_mummy_high_wizard"))



static func wave_journey(f: Dictionary, p, seed_value: int = 77):
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var trip = F.Run.start(p, f.camp)
	return Journey.start(data, SquadMember.make_squad(trip, ["longbow"])[0], f.rules, f.loot, f.combat.weapon_ids, seed_value)


static func win(j) -> void:
	j.state = Journey.WON
	j.pay_card_xp()


static func piece(f: Dictionary, slot: String, tier: int = 1, id: String = "") -> Object:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([slot, tier, id])
	return ItemSystem.create_item(f.rules, id if not id.is_empty() else "bp-%s-%d" % [slot, tier], slot, tier, rng, "", "boss_goblin_chief_" + slot)


static func typed(list: Array) -> Array[Item]:
	var out: Array[Item] = []
	for item in list: out.append(item)
	return out


static func boss_items(p) -> Array:
	return p.stash.items.filter(func(item): return item.item_id.begins_with("boss_goblin_chief_"))


func _data(ctx) -> void:
	var f := F.make()
	ctx.check("boss loot: catalog has no errors %s" % [f.rules.catalog.errors], f.rules.catalog.errors.is_empty())
	var pieces := BossLoot.set_pieces(f.rules, SET)
	var slots: Array = pieces.map(func(id): return str(f.rules.catalog.entry(id).slot))
	slots.sort()
	ctx.check("boss loot: the Goblin Chief set is necklace/earring/bracelet/ring/back %s" % [slots], slots == ["back", "bracelet", "earring", "necklace", "ring"])
	ctx.check("boss loot: the set is kind boss in sets.json", str(f.rules.catalog.sets.get(SET, {}).get("kind", "")) == "boss")
	ctx.check("boss loot: every piece has an icon path under art/items/boss/goblin_chief", pieces.all(func(id): return str(f.rules.catalog.entry(id).icon_path).begins_with("res://art/items/boss/goblin_chief/")))
	ctx.check("boss loot: coin and relic are camp materials, not sellable", f.camp.materials.has(COIN) and f.camp.materials.has(RELIC) and not f.camp.materials[COIN].sellable and not f.camp.materials[RELIC].sellable)
	ctx.check("boss loot: the relic is in the catalog with effects", f.rules.catalog.relics.has(RELIC) and not f.rules.catalog.relics[RELIC].effects.is_empty())
	ctx.check("boss loot: goblin_base maps to goblin_waves", str(BossLoot.boss_for_journey("goblin_waves")[0]) == "goblin_base")
	# A missing icon must not crash anything in logic: the catalog only stores the path.
	ctx.check("boss loot: a missing icon file is only a path (logic never loads it)", str(f.rules.catalog.entry("boss_goblin_chief_ring").icon_path) != "")
	var ring_item = piece(f, "ring", 1, "icon-ring")
	var icon = load("res://client/item_assets.gd").icon(ring_item, f.rules.catalog)  # null (slot shape drawn) until the art lands, never a crash
	ctx.check("boss loot: the client icon lookup handles a boss piece (icon or graceful null)", icon == null or icon is Texture2D)
	# Boss pieces never come from a normal monster drop / chest roll.
	var rng := F.rng(3)
	var any_boss := false
	for i in 2000:
		var item = Loot.roll_piece(f.rules, "x-%d" % i, 1, 10, f.combat.weapon_ids, rng)
		any_boss = any_boss or (item != null and item.item_id.begins_with("boss_"))
	ctx.check("boss loot: 2000 normal piece rolls never give a boss piece", not any_boss)


func _ac1_drop_rates(ctx) -> void:
	var f := F.make()
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var p = F.Profile.new_player(f.rules, f.camp, F.rng(9))
	var pieces := 0
	var relics := 0
	var coins_ok := true
	var n := 20000
	for i in n:
		var rng := F.rng(1000 + i)
		var before: int = p.stash.material_count(COIN)
		var s := BossLoot.grant(p, f.rules, f.loot, data, false, 1.0, rng, "sweep-%d" % i)
		coins_ok = coins_ok and int(s.coins) == 1 and p.stash.material_count(COIN) == before + 1
		pieces += s.items.size()
		relics += int(s.relics.get(RELIC, 0))
	var piece_rate := float(pieces) / n
	var relic_rate := float(relics) / n
	ctx.check("AC1 every goblin boss kill gives exactly 1 coin", coins_ok)
	ctx.check("AC1 pieces drop at about 25%% over a seeded sweep (%.4f)" % piece_rate, absf(piece_rate - 0.25) < 0.015)
	ctx.check("AC1 relics drop at about 1%% over a seeded sweep (%.4f)" % relic_rate, absf(relic_rate - 0.01) < 0.003)
	# loot_by_squad scales piece and relic chances, never the coin.
	var p2 = F.Profile.new_player(f.rules, f.camp, F.rng(10))
	var half_pieces := 0
	for i in n:
		half_pieces += BossLoot.grant(p2, f.rules, f.loot, data, false, 0.5, F.rng(1000 + i), "half-%d" % i).items.size()
	ctx.check("AC1 squad factor 0.5 halves the piece rate (%.4f)" % (float(half_pieces) / n), absf(float(half_pieces) / n - 0.125) < 0.012)
	ctx.check("AC1 the coin is always 1 at any factor", p2.stash.material_count(COIN) == n)
	# Through the real run end: a won goblin_waves run pays 1 coin.
	var p3 = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(11)))
	var j = wave_journey(f, p3)
	win(j)
	ctx.check("AC1 a won goblin_waves run pays 1 coin into the stash", p3.stash.material_count(COIN) == 1 and int(j.boss_loot["1"].coins) == 1)
	j.pay_card_xp()
	ctx.check("AC1 a repeated run end never pays twice", p3.stash.material_count(COIN) == 1)
	var saved = Journey.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())), j.data, f.rules, f.camp, f.loot, f.combat.weapon_ids)
	ctx.check("AC1 the run's boss loot summary survives a save/load", saved != null and int(saved.boss_loot.get("1", {}).get("coins", 0)) == 1)


func _ac2_first_kill(ctx) -> void:
	var f := F.make()
	var all_ok := true
	var second_always := true
	var rare_index := 1
	for i in 40:
		var p = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(200 + i)))
		var j = wave_journey(f, p, 300 + i)
		win(j)
		var got := boss_items(p)
		all_ok = all_ok and got.size() == 1 and int(got[0].tier) >= rare_index and bool(j.boss_loot["1"].first_kill)
		all_ok = all_ok and Zones.boss_beaten(p, "goblin_base")
		var j2 = wave_journey(f, p, 900 + i)
		win(j2)
		second_always = second_always and not bool(j2.boss_loot["1"].first_kill)
	ctx.check("AC2 the first kill always gives one piece at rare or better (40 accounts)", all_ok)
	ctx.check("AC2 a second kill is not a first kill (no guarantee)", second_always)
	# Over many second kills some give no piece: the guarantee is gone.
	var p = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(5)))
	p.unlocks[Zones.boss_key("goblin_base")] = true
	var empty := 0
	for i in 40:
		var j = wave_journey(f, p, 5000 + i)
		win(j)
		if j.boss_loot["1"].items.is_empty(): empty += 1
	ctx.check("AC2 after the first kill, kills can give no piece (%d/40 empty)" % empty, empty > 10)


func _ac3_set_steps(ctx) -> void:
	var f := F.make()
	var base := Stats.totals(f.rules, typed([]))
	var items: Array = []
	for slot in ["necklace", "earring", "earring", "bracelet", "bracelet", "ring"]:
		items.append(piece(f, slot, 1, "s-%d" % items.size()))
	var plain := func(list: Array) -> Dictionary:
		# Same pieces without the set: the stats the gear itself gives.
		var t := {}
		for stat in f.rules.stat_ids: t[stat] = float(f.rules.stat_base[stat])
		for item in list:
			var add: Dictionary = item.stat_totals(f.rules)
			for stat in add: t[stat] += add[stat]
		return t
	var steps := {1: [false, false, false], 2: [true, false, false], 3: [true, false, false], 4: [true, true, false], 5: [true, true, false], 6: [true, true, true]}
	for n in [1, 2, 3, 4, 5, 6]:
		var worn: Array = items.slice(0, n)
		var status: Array = BossLoot.set_status(f.rules, worn)
		var active: Array = status[0].steps.map(func(s): return bool(s.active))
		ctx.check("AC3 %d boss pieces: steps 2/4/6 = %s" % [n, active], active == steps[n])
		var t: Dictionary = Stats.totals(f.rules, typed(worn))
		var raw: Dictionary = plain.call(worn)
		var atk_mul := (0.05 if n >= 2 else 0.0) + (0.06 if n >= 6 else 0.0)
		var hp_mul := 0.08 if n >= 4 else 0.0
		ctx.check("AC3 %d pieces: ATK x%.2f, HP x%.2f (rare = tier_mul 1.0)" % [n, 1 + atk_mul, 1 + hp_mul],
			absf(float(t.ATK) - float(raw.ATK) * (1 + atk_mul)) < 0.001 and absf(float(t.HP) - float(raw.HP) * (1 + hp_mul)) < 0.001)
	# Removing one piece turns the step off again (6 -> 5: the 6-piece step is off).
	var five: Array = BossLoot.set_status(f.rules, items.slice(0, 5))[0].steps.map(func(s): return bool(s.active))
	ctx.check("AC3 removing one piece of 6 turns the 6-step off", five == [true, true, false])
	# Tier scaling: the lowest tier among the N best pieces (normal = 0.75).
	var mixed: Array = [piece(f, "necklace", 0, "lo"), piece(f, "ring", 3, "hi")]
	var step2: Dictionary = BossLoot.set_status(f.rules, mixed)[0].steps[0]
	ctx.check("AC3 a step scales with the lowest tier counted (normal + legendary -> 0.75)", step2.tier == "normal" and absf(float(step2.m) - 0.75) < 0.0001 and absf(float(step2.effects[0].mul) - 0.0375) < 0.0001)
	ctx.check("AC3 the set counts at most 8 worn pieces (5 slots, 3 doubled)", f.rules.slots.filter(func(s): return str(s.id) in ["necklace", "earring", "bracelet", "ring", "back"]).reduce(func(a, s): return a + int(s.count), 0) == 8)
	# Wearing them on a real card through the profile.
	var p = f.profile
	var card: String = p.card_deck.squad[0]
	var worn = p.loadout_of(card)
	var before: float = float(Stats.totals(f.rules, worn.items()).ATK)
	worn.equip(piece(f, "necklace", 1, "w1"))
	worn.equip(piece(f, "ring", 1, "w2"))
	ctx.check("AC3 two worn pieces on a card raise its ATK by ~5%% (+ gear)", float(Stats.totals(f.rules, worn.items()).ATK) > before * 1.04)


func _ac4_sockets(ctx) -> void:
	var f := F.make()
	var p = f.profile
	var ring = piece(f, "ring", 1, "sock-ring")
	p.stash.add_item(ring)
	p.stash.add_material(RELIC, 1)
	var r: Dictionary = Commands.apply(f, {"type": "relic_socket", "item": "sock-ring", "relic": RELIC}, F.rng())
	ctx.check("AC4 relic_socket puts the relic in a boss piece %s" % [r], r.ok and ring.relic == RELIC and p.stash.material_count(RELIC) == 0)
	ctx.check("AC4 the socket survives a save/load", F.Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp).stash.items.any(func(i): return i.id == "sock-ring" and i.relic == RELIC))
	r = Commands.apply(f, {"type": "relic_socket", "item": "sock-ring", "relic": RELIC}, F.rng())
	ctx.check("AC4 a full socket refuses", not r.ok and r.error == "socket_full")
	var t_with: Dictionary = Stats.totals(f.rules, typed([ring]))
	var plain = ring.duplicate_item()
	plain.relic = ""
	var t_without: Dictionary = Stats.totals(f.rules, typed([plain]))
	ctx.check("AC4 the worn relic gives ATK +6%% and crit +5", absf(float(t_with.ATK) - float(t_without.ATK) * 1.06) < 0.001 and absf(float(t_with.CRIRATE) - float(t_without.CRIRATE) - 5.0) < 0.001)
	r = Commands.apply(f, {"type": "relic_unsocket", "item": "sock-ring"}, F.rng())
	ctx.check("AC4 relic_unsocket returns the relic intact to the stash", r.ok and ring.relic == "" and p.stash.material_count(RELIC) == 1)
	r = Commands.apply(f, {"type": "relic_unsocket", "item": "sock-ring"}, F.rng())
	ctx.check("AC4 unsocketing an empty socket refuses", not r.ok and r.error == "socket_empty")
	# A non-socket item (a race piece below legendary) refuses.
	var shirt = p.loadout_of(p.card_deck.squad[0]).item_at("shirt", 0)
	ctx.check("AC4 the test shirt is not legendary", shirt != null and int(shirt.tier) < f.rules.tiers.size() - 1)
	r = Commands.apply(f, {"type": "relic_socket", "item": shirt.id, "relic": RELIC}, F.rng())
	ctx.check("AC4 a non-socket item refuses", not r.ok and r.error == "no_socket" and p.stash.material_count(RELIC) == 1)
	# A legendary item has a socket.
	var legend = ItemSystem.create_item(f.rules, "legend-1", "shirt", f.rules.tiers.size() - 1, F.rng(4), "", shirt.item_id)
	p.stash.add_item(legend)
	r = Commands.apply(f, {"type": "relic_socket", "item": "legend-1", "relic": RELIC}, F.rng())
	ctx.check("AC4 a legendary item has a socket", r.ok and legend.relic == RELIC)
	r = Commands.apply(f, {"type": "relic_socket", "item": "sock-ring", "relic": RELIC}, F.rng())
	ctx.check("AC4 socketing without a relic in the stash refuses", not r.ok and r.error == "no_relic")
	r = Commands.apply(f, {"type": "relic_socket", "item": "sock-ring", "relic": "coin_goblin_chief"}, F.rng())
	ctx.check("AC4 a coin is not a relic", not r.ok and r.error == "invalid_relic")
	var away := f.duplicate()
	away["location"] = "stage"
	r = Commands.apply(away, {"type": "relic_unsocket", "item": "legend-1"}, F.rng())
	ctx.check("AC4 sockets change only at camp", not r.ok)


## Boss 2026-11-16: a bought piece rolls its tier from the boss table (was fixed tier 0); one coin type, 500 per piece.
func _shop_random_tier(ctx) -> void:
	var tiers := {}
	var coins_ok := true
	var gold_ok := true
	var same_seed_ok := true
	for seed_value in range(1, 61):
		var f := F.make()
		var p = f.profile
		p.stash.add_material(COIN, 500)
		var gold: int = p.stash.gold
		var r: Dictionary = Commands.apply(f, {"type": "shop_buy", "sku": "boss:boss_goblin_chief_ring"}, F.rng(seed_value))
		if not r.ok:
			coins_ok = false
			continue
		coins_ok = coins_ok and p.stash.material_count(COIN) == 0 and int(r.get("price", 500)) == 500
		gold_ok = gold_ok and p.stash.gold == gold
		var piece = boss_items(p)[-1]
		tiers[int(piece.tier)] = true
		var g := F.make()
		g.profile.stash.add_material(COIN, 500)
		Commands.apply(g, {"type": "shop_buy", "sku": "boss:boss_goblin_chief_ring"}, F.rng(seed_value))
		same_seed_ok = same_seed_ok and int(boss_items(g.profile)[-1].tier) == int(piece.tier)
	ctx.check("shop: 60 seeded buys cover more than one tier %s" % [tiers.keys()], tiers.size() > 1)
	ctx.check("shop: bought tiers are only rare/epic/legendary, never normal %s" % [tiers.keys()], tiers.keys().all(func(t): return t >= 1 and t <= 3))
	ctx.check("shop: a random-tier buy spends exactly 500 coins and no gold", coins_ok and gold_ok)
	ctx.check("shop: the tier is deterministic from the command rng", same_seed_ok)


func _ac5_shop(ctx) -> void:
	var f := F.make()
	var p = f.profile
	var offers := Shop.stock(f.rules, f.camp)
	var ids: Array = offers.map(func(o): return str(o.id))
	ids.sort()
	var all_pieces: Array = BossLoot.set_pieces(f.rules, SET) + BossLoot.set_pieces(f.rules, "boss_mummy_high_wizard") + BossLoot.set_pieces(f.rules, "boss_orc_warlock")
	all_pieces.sort()
	ctx.check("AC5 the shop lists only the boss pieces (5 per boss: goblin + mummy + orc warlock) %s" % [ids], ids == all_pieces)
	var coin_of := func(id: String) -> String:
		return COIN if id.begins_with("boss_goblin_chief_") else "coin_orc_warlock" if id.begins_with("boss_orc_warlock_") else "coin_mummy_high_wizard"
	ctx.check("AC5 each costs 500 coins of its own boss (Goblin Chief / Mummy High Wizard / Orc Warlock)", offers.all(func(o): return int(o.price) == 500 and str(o.currency) == coin_of.call(str(o.id))))
	ctx.check("AC5 relics are never sold", not ids.has(RELIC) and offers.all(func(o): return o.kind == "item"))
	var gold_before: int = p.stash.gold
	p.stash.add_material(COIN, 499)
	var r: Dictionary = Commands.apply(f, {"type": "shop_buy", "sku": "boss:boss_goblin_chief_ring"}, F.rng(6))
	ctx.check("AC5 with 499 coins buying refuses", not r.ok and r.error == "cannot_afford" and p.stash.material_count(COIN) == 499)
	p.stash.add_material(COIN, 101)
	var count: int = boss_items(p).size()
	r = Commands.apply(f, {"type": "shop_buy", "sku": "boss:boss_goblin_chief_ring"}, F.rng(6))
	ctx.check("AC5 buying spends 500 coins and gives the piece", r.ok and p.stash.material_count(COIN) == 100 and boss_items(p).size() == count + 1)
	ctx.check("AC5 buying spends no gold", p.stash.gold == gold_before)
	r = Commands.apply(f, {"type": "shop_buy", "sku": "item:armour_sword_shield_shirt"}, F.rng(6))
	ctx.check("AC5 the old race gold stock is gone", not r.ok and r.error == "invalid_product")
	# Selling gear for gold still works.
	var bought = boss_items(p)[-1]
	var price := Shop.item_sell_price(bought, f.rules)
	r = Commands.apply(f, {"type": "shop_sell", "item": bought.id, "expected_price": price}, F.rng())
	ctx.check("AC5 selling gear for gold is unchanged", r.ok and p.stash.gold == gold_before + price)
	r = Commands.apply(f, {"type": "shop_sell_material", "material": COIN, "count": 1, "expected_price": 1}, F.rng())
	ctx.check("AC5 coins cannot be sold for gold", not r.ok and r.error == "not_sellable")


func _ac6_lost_run(ctx) -> void:
	var f := F.make()
	var p = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(31)))
	var j = wave_journey(f, p)
	j.died()
	ctx.check("AC6 a lost run gives no coin, no piece, no relic", p.stash.material_count(COIN) == 0 and boss_items(p).is_empty() and p.stash.material_count(RELIC) == 0 and j.boss_loot.is_empty())
	var p2 = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(32)))
	var j2 = wave_journey(f, p2)
	j2.completed = 0
	j2.state = Journey.CHOOSING
	j2.abandon()
	ctx.check("AC6 an abandoned run gives no coin", p2.stash.material_count(COIN) == 0)
	# Another journey (not a boss zone) gives nothing.
	var p3 = F.past_tutorial(F.Profile.new_player(f.rules, f.camp, F.rng(33)))
	var data = JourneyData.load_by_id("ink_road", f.combat.enemies.keys())
	var j3 = Journey.start(data, F.Run.start(p3, f.camp), f.rules, f.loot, f.combat.weapon_ids, 7)
	win(j3)
	ctx.check("AC6 a journey without a boss zone gives no boss loot", p3.stash.material_count(COIN) == 0 and j3.boss_loot.is_empty())


func _ac7_online(ctx) -> void:
	# Profile worker: the new commands are allowed and work on a stored profile.
	var runner := Runner.new()
	var made: Dictionary = runner.execute({"v": 1, "state": null, "seed": "0123456789abcde", "name": "", "command": null})
	var f := F.make()
	var p = F.Profile.from_dict(made.profile, f.rules, f.camp)
	var ring = piece(f, "ring", 1, "online-ring")
	p.stash.add_item(ring)
	p.stash.add_material(RELIC, 1)
	p.stash.add_material(COIN, 500)
	var state := {"profile": p.to_dict(), "rng_state": made.rng_state}
	var r: Dictionary = runner.execute({"v": 1, "state": state, "seed": "0123456789abcde", "name": "", "command": {"type": "relic_socket", "item": "online-ring", "relic": RELIC}})
	ctx.check("AC7 profile worker: relic_socket is allowed and works %s" % [r.get("error", "")], r.get("ok", false) and r.profile.stash.materials.get(RELIC, 0) == 0)
	state = {"profile": r.get("profile", state.profile), "rng_state": r.get("rng_state", state.rng_state)}
	r = runner.execute({"v": 1, "state": state, "seed": "0123456789abcde", "name": "", "command": {"type": "relic_unsocket", "item": "online-ring"}})
	ctx.check("AC7 profile worker: relic_unsocket is allowed and returns the relic", r.get("ok", false) and int(r.profile.stash.materials.get(RELIC, 0)) == 1)
	state = {"profile": r.get("profile", state.profile), "rng_state": r.get("rng_state", state.rng_state)}
	r = runner.execute({"v": 1, "state": state, "seed": "0123456789abcde", "name": "", "command": {"type": "shop_buy", "sku": "boss:boss_goblin_chief_back"}})
	ctx.check("AC7 profile worker: the coin shop works", r.get("ok", false) and int(r.profile.stash.materials.get(COIN, 0)) == 0)
	# Party journey (what rooms run): each account gets its own coin and rolls; first kill is per account.
	var a := Squads.squad_of(41, ["human", "viking", "elf"])
	var b := Squads.squad_of(42, ["human", "viking", "elf"])
	b.profile.unlocks[Zones.boss_key("goblin_base")] = true  # b has beaten the Chief before
	var party := Squads.party([a, b])
	win(party.journey)
	ctx.check("AC7 party: each player gets 1 coin", a.profile.stash.material_count(COIN) == 1 and b.profile.stash.material_count(COIN) == 1)
	ctx.check("AC7 party: the first-kill guarantee is per account", bool(party.journey.boss_loot["1"].first_kill) and boss_items(a.profile).size() == 1 and not bool(party.journey.boss_loot["2"].first_kill))
	# A real squad room: a won run ends with the boss loot in the finalized profiles.
	var mgr = Squads.squad_manager()
	var room_made: Dictionary = mgr.create("boss-room-1", 77, Squads.players(2))
	ctx.check("AC7 room created", room_made.get("ok", false))
	if room_made.get("ok", false):
		var room = mgr.rooms["boss-room-1"].room
		room.journey.stage_cleared(1.0)
		ctx.check("AC7 room: the run is won", room.journey.state == Journey.WON)
		var profiles: Dictionary = room.finalize()
		var coins: Array = profiles.values().map(func(d): return int(d.stash.materials.get(COIN, 0)))
		ctx.check("AC7 room: both players' saved profiles have 1 coin %s" % [coins], coins.size() == 2 and coins.all(func(c): return c == 1))
		var firsts: Array = profiles.values().map(func(d): return d.stash.items.filter(func(i): return str(i.item_id).begins_with("boss_goblin_chief_")).size())
		ctx.check("AC7 room: each player's first kill gave a set piece %s" % [firsts], firsts.all(func(c): return c == 1))


func _edges(ctx) -> void:
	var f := F.make()
	var p = f.profile
	# A socketed item that is sold returns its relic first.
	var ring = piece(f, "ring", 1, "edge-ring")
	p.stash.add_item(ring)
	p.stash.add_material(RELIC, 1)
	Commands.apply(f, {"type": "relic_socket", "item": "edge-ring", "relic": RELIC}, F.rng())
	var r: Dictionary = Commands.apply(f, {"type": "shop_sell", "item": "edge-ring", "expected_price": Shop.item_sell_price(ring, f.rules)}, F.rng())
	ctx.check("edge: selling a socketed item returns the relic to the stash", r.ok and p.stash.material_count(RELIC) == 1)
	var neck = piece(f, "necklace", 1, "edge-neck")
	p.stash.add_item(neck)
	Commands.apply(f, {"type": "relic_socket", "item": "edge-neck", "relic": RELIC}, F.rng())
	r = Commands.apply(f, {"type": "discard", "item": "edge-neck", "source": "stash"}, F.rng())
	ctx.check("edge: discarding a socketed item returns the relic", r.ok and p.stash.material_count(RELIC) == 1)
	var back = piece(f, "back", 1, "edge-back")
	p.stash.add_item(back)
	Commands.apply(f, {"type": "relic_socket", "item": "edge-back", "relic": RELIC}, F.rng())
	r = Commands.apply(f, {"type": "shop_sell_batch", "entries": [{"kind": "item", "id": "edge-back"}], "expected_price": Shop.item_sell_price(back, f.rules)}, F.rng())
	ctx.check("edge: batch-selling a socketed item returns the relic", r.ok and p.stash.material_count(RELIC) == 1)
	# A full stash (the relic counter at its ceiling) refuses the sale.
	var full = piece(f, "earring", 1, "edge-full")
	p.stash.add_item(full)
	Commands.apply(f, {"type": "relic_socket", "item": "edge-full", "relic": RELIC}, F.rng())
	p.stash.materials[RELIC] = p.stash.MATERIAL_MAX
	r = Commands.apply(f, {"type": "shop_sell", "item": "edge-full", "expected_price": Shop.item_sell_price(full, f.rules)}, F.rng())
	ctx.check("edge: a full stash refuses to sell a socketed item", not r.ok and r.error == "stash_full" and full.relic == RELIC)
	p.stash.materials.erase(RELIC)
	# Durability 0: the relic's effect stops, like the item's stats.
	var worn = piece(f, "bracelet", 1, "edge-broken")
	worn.relic = RELIC
	var on: float = float(Stats.totals(f.rules, typed([worn])).CRIRATE)
	worn.durability = 0.0
	var plain = worn.duplicate_item()
	plain.relic = ""
	ctx.check("edge: a broken item's relic gives nothing", absf(float(Stats.totals(f.rules, typed([worn])).CRIRATE) - float(Stats.totals(f.rules, typed([plain])).CRIRATE)) < 0.0001 and on > float(Stats.totals(f.rules, typed([plain])).CRIRATE))
