extends RefCounted
## Gear level cap of drops (logic/gear_levels.gd, data/world/gear_levels.json; Boss 2026-11-17): gear that drops follows what
## the PLAYER has unlocked, in every map. Locked pyramid = only level 1 on the goblin AND the mummy map; open pyramid = 1 and
## 15 on both; a new zone with gear level 25 (fake table + fake catalog piece, no code change) adds 25; a missing value is 1.
const GL := preload("res://logic/gear_levels.gd")
const Zones := preload("res://logic/world_zones.gd")
const RaceDrops := preload("res://logic/race_drops.gd")
const Loot := preload("res://logic/loot.gd")
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const Shop := preload("res://logic/shop.gd")
const TierUp := preload("res://logic/tier_up.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const F := preload("res://tests/online_fixture.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]
const SEEDS := 60


func run(ctx) -> void:
	var f := F.make()
	var rules = f.rules
	ctx.check("gear levels: data is sound %s" % [GL.problems()], GL.problems().is_empty())
	ctx.check("gear levels: goblin 1, pyramid 15 from the data", GL.zone_level("goblin_base") == 1 and GL.zone_level("pyramid") == 15)
	ctx.check("gear levels: a missing or bad zone value is level 1 (never permissive)",
		GL.zone_level("nowhere") == 1 and GL.zone_level("z", {"zones": {"z": "x"}}) == 1 and GL.zone_level("z", {"zones": {"z": 0}}) == 1
		and GL.zone_level("z", {"zones": {"z": 2.5}}) == 1 and GL.level_for_zones([], {}) == 1)
	var fake := {"zones": {"goblin_base": 1, "pyramid": 15, "orc_camp": 25}}
	ctx.check("gear levels: highest OPEN zone decides (fake table with a level-25 zone)",
		GL.level_for_zones(["goblin_base"], fake) == 1 and GL.level_for_zones(["goblin_base", "pyramid"], fake) == 15
		and GL.level_for_zones(["goblin_base", "pyramid", "orc_camp"], fake) == 25)
	# A profile: locked pyramid vs opened (boss beaten + a card at 15).
	var p = Profile.new_player(rules, f.camp, F.rng(5))
	ctx.check("gear levels: new player unlocked level 1", GL.unlocked_level(p) == 1 and GL.unlocked_level(null) == 1)
	p.unlocks["boss_goblin_base"] = true
	for id in p.card_deck["cards"].keys():
		p.card_deck["cards"][id]["progress"] = {"level": 15, "xp": 0}
	_pyramid_playable(false)  # shipped data now gives the pyramid its journey; take it away for the coming-soon case
	ctx.check("gear levels: pyramid still coming-soon (no journey) -> unlocked level 1", GL.unlocked_level(p) == 1)
	_pyramid_playable(true)  # the pyramid gets its journey: it is OPEN for this profile
	ctx.check("gear levels: pyramid open -> unlocked level 15", GL.unlocked_level(p) == 15)
	p.unlocks["boss_goblin_base"] = false
	ctx.check("gear levels: pyramid quest unmet (boss not beaten) -> 1", GL.unlocked_level(p) == 1)
	p.unlocks["boss_goblin_base"] = true
	_pyramid_playable(true)  # back to the shipped state
	_fake_catalog_level25(ctx, rules)
	_counts(ctx, rules)
	_level1_piece(ctx, f)
	_forgery(ctx, f)
	_sim_paths(ctx)


## Test helper: gives the pyramid its journey in the cached zone table (and takes it away again).
func _pyramid_playable(on: bool) -> void:
	Zones.data()
	for z in Zones._cache.get("zones", []):
		if str(z.get("id", "")) == "pyramid":
			z["journey"] = "mummy_waves" if on else ""


## A fake catalog piece with req_level 25 proves a new zone needs only data.
func _fake_catalog_level25(ctx, rules) -> void:
	var e: Dictionary = rules.catalog.entry("armour_longbow_shirt").duplicate(true)
	e["req_level"] = 25
	rules.catalog.items["armour_longbow_shirt_fake25"] = e
	var item = ItemSystem.create_item(rules, "t-1", "shirt", 1, F.rng(3), "", "armour_longbow_shirt")
	ctx.check("gear levels: allowed levels at cap 1/15/25 = [1] / [1,15] / [1,15,25]",
		GL.allowed_levels(rules, item, 1) == [1] and GL.allowed_levels(rules, item, 15) == [1, 15] and GL.allowed_levels(rules, item, 25) == [1, 15, 25])
	var seen := {}
	for i in 90:
		var it = ItemSystem.create_item(rules, "x-%d" % i, "shirt", 1, F.rng(i), "", "armour_longbow_shirt")
		var out = GL.fit(rules, it, 25)
		seen[GL.LEVEL1_PREFIX if str(out.id).begins_with("starter-drop-") else str(out.item_id)] = true
	ctx.check("gear levels: cap 25 drops level 1, 15 and the fake 25 piece %s" % [seen.keys()], seen.size() == 3 and seen.has("armour_longbow_shirt_fake25"))
	rules.catalog.items.erase("armour_longbow_shirt_fake25")


## 60 seeds x many pieces: locked = only level 1 (instance prefix or req_level 1); open = 1 and 15 both appear.
func _counts(ctx, rules) -> void:
	var weapons := ["blade", "greatsword", "longbow"]
	for cap in [1, 15]:
		var lv1 := 0
		var lv15 := 0
		var over := 0
		for s in SEEDS:
			var rng := F.rng(100 + s)
			for k in 10:
				var raw = Loot.roll_piece(rules, "drop-%d-%d" % [s, k], rng.randi() % 3, 4, weapons, rng)
				var item = RaceDrops.convert_piece(rules, raw, [{"race": "elf", "class": "longbow"}, {"race": "human", "class": "sword_shield"}], RaceDrops.WAVE, 3, cap)
				var level: int = 1 if str(item.id).begins_with("starter-") else rules.catalog.req_level(item.item_id)
				if level == 1: lv1 += 1
				elif level == 15: lv15 += 1
				if level > cap: over += 1
		ctx.check("gear levels: cap %d over %d seeds: nothing above the cap (lv1 %d, lv15 %d)" % [cap, SEEDS, lv1, lv15],
			over == 0 and lv1 > 0 and ((cap == 1 and lv15 == 0) or (cap == 15 and lv15 > 0)))
	ctx.check("gear levels: the default cap of convert_piece is 1 (safe low)", _default_is_low(rules))


func _default_is_low(rules) -> bool:
	for i in 40:
		var item = ItemSystem.create_item(rules, "d-%d" % i, "shirt", 1, F.rng(i), "", "armour_longbow_shirt")
		var out = RaceDrops.convert_piece(rules, item, [{"race": "elf", "class": "longbow"}], RaceDrops.WAVE, 1)
		if not str(out.id).begins_with("starter-drop-") and rules.catalog.req_level(out.item_id) > 1:
			return false
	return true


## A level-1 drop wears at any card level, is x1.0, sells in bulk, and tier-ups into the level-15 piece keeping its state.
func _level1_piece(ctx, f: Dictionary) -> void:
	var rules = f.rules
	var p = f.profile
	var piece = ItemSystem.create_item(rules, GL.LEVEL1_PREFIX + "drop-a", "shirt", 2, F.rng(9), "", "armour_longbow_shirt")
	piece.refine_level = 3
	piece.durability = piece.max_durability * 0.5
	ctx.check("level-1 drop: wears at card level 1, main stat x1.0",
		Profile.slot_problem("longbow", piece, rules, 1).is_empty() and is_equal_approx(rules.catalog.main_stat_mul(piece.item_id, piece.id), 1.0))
	var level15 = ItemSystem.create_item(rules, "plain-a", "shirt", 2, F.rng(9), "", "armour_longbow_shirt")
	ctx.check("level-1 drop: a non-drop level-15 piece is still gated and x1.5",
		Profile.slot_problem("longbow", level15, rules, 1) == "level_too_low" and rules.catalog.main_stat_mul(level15.item_id, level15.id) > 1.4)
	p.stash.add_item(piece)
	p.stash.gold = 100000
	for id in p.card_deck["cards"].keys():
		p.card_deck["cards"][id]["progress"] = {"level": 15, "xp": 0}
	var res: Dictionary = TierUp.apply(p, rules, piece, "longbow")
	ctx.check("level-1 drop: tier-up gives the level-15 piece, tier/refine/durability kept %s" % [res],
		res.get("ok", false) and piece.tier == 2 and piece.refine_level == 3 and absf(piece.durability_ratio() - 0.5) < 0.001
		and not str(piece.id).begins_with("starter-") and rules.catalog.req_level(piece.item_id) == 15)
	var sell: Dictionary = Shop.batch_sellable(p, rules, ["white", "blue", "purple", "gold"])
	var kit = ItemSystem.create_item(rules, "starter-kit-v3-x-shirt", "shirt", 0, F.rng(2), "", "armour_longbow_shirt")
	var drop = ItemSystem.create_item(rules, GL.LEVEL1_PREFIX + "drop-b", "shirt", 0, F.rng(2), "", "armour_longbow_shirt")
	p.stash.add_item(kit)
	p.stash.add_item(drop)
	var ids: Array = Shop.batch_sellable(p, rules, rules.tiers.map(func(t): return str(t["id"])))["ids"]
	ctx.check("level-1 drop: bulk sell takes the drop but never the real starter kit", ids.has(drop.id) and not ids.has(kit.id))
	ctx.check("level-1 drop: level_stat_mul falls back to the nearest lower key (25 -> the 15 value), never x1.0",
		is_equal_approx(rules.catalog.level_mul(25), rules.catalog.level_mul(15)) and rules.catalog.level_mul(15) > 1.0 and is_equal_approx(rules.catalog.level_mul(1), 1.0))


## Forgery: a client has no command that creates an item or renames one; a crafted "starter-drop-" id on a piece that can never
## drop (a boss piece) is flagged, and the commands move only pieces the profile holds.
func _forgery(ctx, f: Dictionary) -> void:
	var rules = f.rules
	var boss_id := ""
	for id in rules.catalog.items:
		if bool(rules.catalog.items[id]["no_drop"]):
			boss_id = str(id)
			break
	var crafted = ItemSystem.create_item(rules, GL.LEVEL1_PREFIX + "evil", rules.catalog.entry(boss_id)["slot"], 3, F.rng(4), "", boss_id)
	ctx.check("forgery: a starter-drop- boss piece is flagged, a real level-1 drop is not",
		GL.level1_forged(crafted, rules) and not GL.level1_forged(ItemSystem.create_item(rules, GL.LEVEL1_PREFIX + "ok", "shirt", 0, F.rng(4), "", "armour_longbow_shirt"), rules))
	var state := {"profile": f.profile, "rules": rules, "camp": f.camp, "location": "camp"}
	var refused := true
	for kind in ["grant", "create_item", "add_item", "set_item_id"]:
		refused = refused and not Commands.apply(state, {"type": kind, "item": "starter-drop-x", "id": "starter-drop-x"}, F.rng(1)).get("ok", false)
	ctx.check("forgery: no command can create an item or set an instance id", refused)
	var prof = Profile.new_player(rules, f.camp, F.rng(8))
	prof.stash.add_item(crafted)
	var ok_drop = ItemSystem.create_item(rules, GL.LEVEL1_PREFIX + "real", "shirt", 0, F.rng(4), "", "armour_longbow_shirt")
	prof.stash.add_item(ok_drop)
	var reloaded = Profile.from_dict(prof.to_dict(), rules, f.camp)
	var ids: Array = reloaded.stash.items.map(func(i): return str(i.id))
	ctx.check("forgery: profile load strips the prefix of a forged piece, keeps a real level-1 drop %s" % [ids], ids.has("evil") and not ids.has(GL.LEVEL1_PREFIX + "evil") and ids.has(GL.LEVEL1_PREFIX + "real"))
	ctx.check("forgery: the repair is idempotent", GL.repair_forged(reloaded, rules) == 0)
	var after = RaceDrops.convert_piece(rules, ItemSystem.create_item(rules, "starter-kit-keep", "shirt", 0, F.rng(1), "", "armour_longbow_shirt"), [], RaceDrops.WAVE, 3, 15)
	ctx.check("forgery: fit never re-stamps or changes an existing starter piece", after.id == "starter-kit-keep")


## The authority paths: the sim kill drop uses the KILLER's profile; online players each use their own.
func _sim_paths(ctx) -> void:
	for opened in [false, true]:
		_pyramid_playable(opened)
		var got1 := 0
		var got15 := 0
		for s in 12:
			var fx = preload("res://tests/test_race_passives.gd").squad(["viking", "elf", "elf"])
			var sim = fx.sim
			var player: int = sim.runs.keys()[0]
			var prof = sim.runs[player].profile
			if opened:
				prof.unlocks["boss_goblin_base"] = true
				for id in prof.card_deck["cards"].keys():
					prof.card_deck["cards"][id]["progress"] = {"level": 15, "xp": 0}
			for i in 40:
				var id := 7000 + i
				sim.add_enemy(id, Vector3(30, 0, 30), "goblin_chief" if i % 4 == 0 else "goblin", 4)
				sim.rng.seed = 500 + s * 100 + i
				sim.reward_wave = 3
				var before: int = sim.runs[player].bag.items.size()
				sim._give_drop(id, player)
				for it in sim.runs[player].bag.items.slice(before):
					var lv: int = 1 if str(it.id).begins_with("starter-") else fx.rules.catalog.req_level(it.item_id)
					if lv == 1: got1 += 1
					elif lv == 15: got15 += 1
				sim.runs[player].bag.items.clear()
				sim.remove_player(id)
		ctx.check("gear levels (sim kill drops): pyramid %s -> lv1 %d, lv15 %d" % ["open" if opened else "locked", got1, got15],
			got1 > 0 and (got15 > 0 if opened else got15 == 0))
	_pyramid_playable(false)
