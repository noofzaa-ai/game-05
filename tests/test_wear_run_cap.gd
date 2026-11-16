extends RefCounted
## Boss 2026-11-16: gear wore out far too fast (a whole 9-wave run drained the bar). One run may cost an item at most
## rules durability.max_loss_per_run_fraction (0.15) of its max durability, and a typical run lands around 8-12%.
## Plays full headless wave-mode runs (the goblin_waves journey, the starter squad, the auto-battle pilot).
const F := preload("res://tests/online_fixture.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Party := preload("res://logic/coop_journey.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const SimInput := preload("res://logic/sim_input.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Wear := preload("res://logic/wear.gd")
const Deck := preload("res://logic/card_deck.gd")

const CAP := 0.15


## One full 9-wave run. Returns {"won", "worst": biggest durability fraction lost by any worn item, "mean", "items": n}.
## `uncapped`: switch the per-run cap off (to measure what the raw wear numbers would do). `roundtrip`: the online
## path, the server plays a copy of the profile loaded from its save.
static func play_run(seed: int, skill: float, uncapped: bool = false, roundtrip: bool = false, tune: Dictionary = {}) -> Dictionary:
	var f := F.make(seed)
	for key in tune:
		f.rules.set(key, tune[key])
	if uncapped:
		f.rules.max_loss_per_run_fraction = -1.0
	var base = f.run
	if roundtrip:
		var copy = Profile.from_dict(JSON.parse_string(JSON.stringify(f.profile.to_dict())), f.rules, f.camp)
		base = Run.start(copy, f.camp)
	var profile = base.profile
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var trips := {}
	var members: Array = SquadMember.make_squad(base, Array(Deck.STARTER_SQUAD))
	for i in members.size():
		trips[i + 1] = members[i]
	var journey = Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, seed)
	while journey.state != journey.IN_STAGE and not journey.is_over():
		journey.choose(0)
	var before := {}
	for item in profile.worn_items():
		before[item] = item.durability
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid.box)
	var sim := Sim.new(world, f.combat, F.rng(seed))
	journey.populate(sim, map, 1, 100)
	for i in Deck.STARTER_SQUAD.size():
		sim.set_class_style(i + 1, str(Deck.class_data(str(Deck.STARTER_SQUAD[i])).get("weapon", "")))
	var memories := {}
	for id in journey.player_ids():
		memories[id] = Pilot.new_memory(id)
	var tick := 0
	while tick < 60 * 600 and (sim.living_enemy_count() + sim.pending_wave_count() > 0):
		var alive := 0
		for id in journey.player_ids():
			if sim.fighters[id].is_alive():
				alive += 1
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, memories[id], tick, skill).encode()))
		if alive == 0:
			break
		sim.tick()
		tick += 1
	var worst := 0.0
	var total := 0.0
	for item in before:
		var lost: float = (float(before[item]) - item.durability) / item.max_durability
		worst = maxf(worst, lost)
		total += lost
	return {"won": sim.living_enemy_count() + sim.pending_wave_count() == 0, "worst": worst, "mean": total / maxf(before.size(), 1), "items": before.size()}


func run(ctx) -> void:
	var rules = F.make().rules
	ctx.check("rules.json carries durability.max_loss_per_run_fraction = 0.15", is_equal_approx(rules.max_loss_per_run_fraction, CAP))

	var typical: Array = []
	for seed in [31, 32, 33, 34]:
		for skill in [0.9, 0.0]:  # a good run and a heavy-loss run (the squad wiped early, many deaths)
			var r := play_run(seed, skill)
			typical.append(r["mean"])
			print("    seed %d skill %.1f won %s worst %.1f%% mean %.1f%%" % [seed, skill, r["won"], r["worst"] * 100.0, r["mean"] * 100.0])
			ctx.check("full 9-wave run (seed %d, skill %.1f): no item loses more than 15%% (worst %.1f%%, %d items)" % [seed, skill, r["worst"] * 100.0, r["items"]], r["worst"] <= CAP + 0.0001 and r["items"] > 0)
	var raw := play_run(31, 0.9, true)
	print("    (no cap, same numbers: seed 31 worst %.1f%% mean %.1f%%)" % [raw["worst"] * 100.0, raw["mean"] * 100.0])
	var sum := 0.0
	for m in typical:
		sum += m
	var mean: float = sum / typical.size()
	ctx.check("typical runs wear gear 4-12%% on average, not always at the cap (mean %.1f%%)" % [mean * 100.0], mean <= 0.12 and mean >= 0.04)
	ctx.check("the raw numbers (cap off) already stay near the cap for a normal run (worst %.1f%%)" % [raw["worst"] * 100.0], raw["worst"] <= 0.20)

	# Many deaths and endless damage: the cap is hard.
	var f := F.make(7)
	var loadout = f.profile.loadout_of("greatsword")
	for i in 40:
		Wear.death(loadout, f.rules)
		Wear.damage_taken(loadout, f.rules, 5000.0, 100.0)
		Wear.hit_landed(loadout, f.rules)
	var hard := true
	for item in loadout.items():
		hard = hard and item.max_durability - item.durability <= CAP * item.max_durability + 0.0001
	ctx.check("40 deaths and huge damage in one run: every item still loses at most 15%", hard)
	ctx.check("a death after the cap is spent changes nothing", not Wear.death(loadout, f.rules))

	# The tracker resets between runs; a repair does not reopen the cap inside one run.
	var weapon = loadout.item_at("weapon")
	ctx.check("the weapon's tally is at the cap", is_equal_approx(weapon.run_wear, CAP * weapon.max_durability))
	var run_b = Run.start(f.profile, f.camp)
	ctx.check("a new run starts every tally at 0", weapon.run_wear == 0.0 and loadout.items().all(func(i): return i.run_wear == 0.0))
	Wear.death(loadout, f.rules)
	ctx.check("the next run wears the item again (by up to 15%)", weapon.run_wear > 0.0 and weapon.run_wear <= CAP * weapon.max_durability + 0.0001)
	weapon.durability = weapon.max_durability  # repaired mid-run
	for i in 10:
		Wear.death(loadout, f.rules)
	ctx.check("a mid-run repair does not reopen the cap", weapon.run_wear <= CAP * weapon.max_durability + 0.0001)

	# Saved profiles: an old save has no tally (loads as 0); a running trip keeps its tally across a save.
	var Item := load("res://logic/item.gd")
	var saved: Dictionary = weapon.to_dict()
	saved.erase("run_wear")
	ctx.check("an item saved before the cap loads (tally 0)", Item.from_dict(saved).run_wear == 0.0)
	var back = Item.from_dict(JSON.parse_string(JSON.stringify(weapon.to_dict())))
	ctx.check("the tally survives save and load", is_equal_approx(back.run_wear, weapon.run_wear))
	var restored = Run.from_dict(JSON.parse_string(JSON.stringify(run_b.to_dict())), f.rules, f.camp)
	ctx.check("restoring a saved run keeps the tally", restored != null and restored.profile.loadout_of("greatsword").item_at("weapon").run_wear == weapon.run_wear)

	# Online = offline: the server plays a profile loaded from its save and gets exactly the same wear.
	var off := play_run(33, 0.9)
	var on := play_run(33, 0.9, false, true)
	ctx.check("online path (profile through its save) wears gear exactly like the offline path", is_equal_approx(off["worst"], on["worst"]) and is_equal_approx(off["mean"], on["mean"]))
