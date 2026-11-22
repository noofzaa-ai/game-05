extends RefCounted
## Boss 2026-11-22 (combat-designer): the bosses act ~3x sooner, go for the ranged cards first, and the orcs charge.
## Locks:
##  - Orc Warlock and Mummy High Wizard move wind-ups / recoveries / cooldowns and AI rest are ~a third of the old
##    values (OLD below = the data before the change) and every telegraphed wind-up still warns >= MIN_WARN ticks;
##    the clip of each move then plays ~3x fast through the view's stretch (startup / clip windup) instead of sliding.
##  - ai.target_priority "ranged_first" (every non-goblin boss): the nearest living longbow/magic card first, the
##    nearest card when no ranged one lives; re-chosen each tick (no lock on the dead); same result twice (deterministic)
##    and after a checkpoint restore.
##  - orc_grunt / orc_archer / orc_mage are ai.aggressive: in a driven N-second fight they never back off, hop back, flee
##    or escape, never wait their turn, and run in; the loader rejects an aggressive monster that could still flee.
## Measurement printout: tools/balance/boss_tempo.gd (tempo) and tools/balance/class_sim.gd (AI rows in the waves).

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Fighter := preload("res://logic/fighter.gd")
const Deck := preload("res://logic/card_deck.gd")
const Pilot := preload("res://logic/auto_pilot.gd")

const MIN_WARN := 20  ## ticks (0.33 s): the shortest wind-up a telegraphed move may have (also the loader's rule)
## The data before the speed-up (startup, recovery, cooldown): each new value must be 0.25-0.45x of it.
const OLD := {
	"orc_warlock_cleave": [26, 32, 0], "orc_warlock_skyfall": [60, 54, 360], "orc_warlock_cataclysm": [96, 60, 540],
	"orc_warlock_bulwark": [20, 150, 420],
	"mummy_hw_bolt": [40, 40, 0], "mummy_hw_curse": [72, 54, 240], "mummy_hw_starfall": [96, 60, 480], "mummy_hw_sandstorm": [70, 40, 0],
	# Boss 2026-11-22 round 2: the Mummy Pharaoh (mini boss of the wave-9 pair) gets the same ~3x from its values then.
	"mummy_boss_combo": [14, 28, 0], "mummy_boss_nova": [40, 40, 300],
}
const OLD_AI := {"orc_warlock": [70, 120], "mummy_high_wizard": [100, 150], "mummy_boss": [70, 120]}  ## cooldown_min / cooldown_max before
## Boss 2026-11-22 round 2: the wave-9 pair's HP doubled from these (applied once).
const OLD_HP := {"mummy_boss": 200, "mummy_high_wizard": 270}
## Big blows: always telegraphed with at least MIN_WARN.
const BIG :=["orc_warlock_skyfall", "orc_warlock_cataclysm", "mummy_hw_curse", "mummy_hw_starfall", "mummy_hw_sandstorm", "mummy_boss_nova"]
const ORCS := ["orc_grunt", "orc_archer", "orc_mage"]
const RETREATS := ["back_off", "hop_back", "flee", "escape"]


func run(ctx) -> void:
	var combat := CombatDataLoader.load_default()
	ctx.check("combat.json loads with no errors %s" % [combat.errors], combat.errors.is_empty())
	_check_timings(ctx, combat)
	_check_target_priority(ctx, combat)
	_check_orcs(ctx, combat)
	_check_loader(ctx)


func _check_timings(ctx, combat) -> void:
	for move_id in OLD:
		var move: Dictionary = combat.moves[move_id]
		var old: Array = OLD[move_id]
		var s := float(move["startup"]) / float(old[0])
		var r := float(move["recovery"]) / float(old[1])
		# (a telegraphed wind-up never goes under MIN_WARN: the bulwark's 20 was already the floor)
		var at_floor := bool(move["telegraph"]) and int(move["startup"]) == MIN_WARN and float(old[0]) / 3.0 <= MIN_WARN
		ctx.check("%s startup %d (was %d, %.2fx%s) and recovery %d (was %d, %.2fx) are about a third" % [move_id, move["startup"], old[0], s, ", at the warning floor" if at_floor else "", move["recovery"], old[1], r],
			((s >= 0.25 and s <= 0.45) or at_floor) and r >= 0.25 and r <= 0.45)
		if int(old[2]) > 0:
			var c := float(move["cooldown"]) / float(old[2])
			ctx.check("%s cooldown %d (was %d) is about a third (%.2fx)" % [move_id, move["cooldown"], old[2], c], c >= 0.25 and c <= 0.4)
		if bool(move["telegraph"]) or BIG.has(move_id):
			ctx.check("%s still warns: telegraphed wind-up %d ticks >= %d (%.2f s)" % [move_id, move["startup"], MIN_WARN, MIN_WARN / 60.0], bool(move["telegraph"]) and int(move["startup"]) >= MIN_WARN)
		# (the Pharaoh's crescent flies on the combo's second cut, inside its recovery: before the move ends)
		var spawn_end := int(move["startup"]) + int(move["active"]) + (int(move["recovery"]) if move_id == "mummy_boss_combo" else 0)
		for spawn in move["spawns"]:
			ctx.check("%s spawns inside the move (frame %d <= %d)" % [move_id, spawn["frame"], spawn_end], float(spawn["frame"]) <= float(spawn_end))
	for area_id in ["hw_curse", "hw_star"]:
		ctx.check("area %s fills for >= %d ticks before it bursts (%d)" % [area_id, MIN_WARN, combat.areas[area_id]["delay"]], int(combat.areas[area_id]["delay"]) >= MIN_WARN)
	for id in OLD_AI:
		var ai: Dictionary = combat.enemies[id]["ai"]
		var lo := float(ai["cooldown_min"]) / float(OLD_AI[id][0])
		var hi := float(ai["cooldown_max"]) / float(OLD_AI[id][1])
		ctx.check("%s rests %d-%d ticks between attacks (was %d-%d: %.2fx / %.2fx)" % [id, ai["cooldown_min"], ai["cooldown_max"], OLD_AI[id][0], OLD_AI[id][1], lo, hi], lo >= 0.25 and lo <= 0.4 and hi >= 0.25 and hi <= 0.4)
		ctx.check("%s opens within 0.2 s (opening_cooldown %d, the old fixed 30)" % [id, ai["opening_cooldown"]], int(ai["opening_cooldown"]) <= 12)
	# The clip plays faster, not slides: the view stretches each phase of the clip over the move's own frames, so the
	# play rate of the wind-up = clip windup_end / startup seconds. ~3x the old rate for each Warlock move.
	var marks = JSON.parse_string(FileAccess.get_file_as_string("res://art/animations/monster_clips_orc_warlock.json"))
	var clips: Dictionary = combat.enemies["orc_warlock"]["clips"]
	for move_id in ["orc_warlock_cleave", "orc_warlock_skyfall", "orc_warlock_cataclysm"]:  # (the bulwark bash is at the floor)
		var clip: Dictionary = marks[str(clips[move_id])]
		var rate := float(clip["windup_end"]) / (float(combat.moves[move_id]["startup"]) / 60.0)
		var old_rate := float(clip["windup_end"]) / (float(OLD[move_id][0]) / 60.0)
		ctx.check("%s: its clip wind-up plays %.1fx (was %.1fx: %.1fx faster)" % [move_id, rate, old_rate, rate / old_rate], rate / old_rate >= 2.2 and rate / old_rate <= 4.0)
	# The Pharaoh's greatsword clips: the combo's whole clip (wind-up, cut, recovery) ~3x; the nova's wind-up sits at the
	# 20-tick warning floor (2x), its strike + recovery ~3x.
	var gs = JSON.parse_string(FileAccess.get_file_as_string("res://art/animations/monster_clips_greatsword.json"))
	var pclips: Dictionary = combat.enemies["mummy_boss"]["clips"]
	for move_id in ["mummy_boss_combo", "mummy_boss_nova"]:
		var mv: Dictionary = combat.moves[move_id]
		var c: Dictionary = gs[str(pclips[move_id])]
		var total := float(mv["startup"]) + float(mv["active"]) + float(mv["recovery"])
		var old_total := float(OLD[move_id][0]) + (5.0) + float(OLD[move_id][1])  # (both had active 5 before)
		var speedup := old_total / total
		ctx.check("%s: the whole clip plays %.1fx faster (%d -> %d ticks for its %.2f s)" % [move_id, speedup, old_total, total, float(c["length"])], speedup >= 2.2 and speedup <= 4.0)
	var crescent: Dictionary = combat.moves["mummy_boss_combo"]["spawns"][0]
	ctx.check("the Pharaoh's sand crescent still flies on the second cut, after the first (frame %d > startup %d)" % [crescent["frame"], combat.moves["mummy_boss_combo"]["startup"]],
		float(crescent["frame"]) > float(combat.moves["mummy_boss_combo"]["startup"]))
	for id in OLD_HP:
		var hp := float(combat.enemies[id]["stats"]["HP"])
		ctx.check("%s HP %d is 2x the %d before (Boss 2026-11-22, applied once)" % [id, hp, OLD_HP[id]], is_equal_approx(hp, 2.0 * float(OLD_HP[id])))
	var dash: Dictionary = combat.moves["orc_warlock_skyfall"]
	ctx.check("the skyfall leap still lands inside its wind-up (dash %d-%d, startup %d)" % [dash["dash_from"], dash["dash_to"], dash["startup"]], float(dash["dash_to"]) <= float(dash["startup"]) and float(dash["dash_from"]) < float(dash["dash_to"]))
	var bulwark: Dictionary = combat.moves["orc_warlock_bulwark"]
	ctx.check("the bulwark is still untouchable through its bash (invuln %d-%d around startup %d)" % [bulwark["invuln_from"], bulwark["invuln_to"], bulwark["startup"]], float(bulwark["invuln_from"]) <= float(bulwark["startup"]) and float(bulwark["invuln_to"]) > float(bulwark["startup"]) + float(bulwark["active"]))


## A world with a floor, three cards (sword_shield in front, longbow, magic behind) and one monster.
static func _arena(combat, enemy_type: String, seed: int) -> GameSim:
	var world := SimWorld.new()
	world.half_width = 16.0
	world.half_depth = 9.0
	world.add_solid(AABB(Vector3(-17.0, -1.0, -10.0), Vector3(34.0, 1.0, 20.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := GameSim.new(world, combat, rng)
	var squad := ["sword_shield", "longbow", "magic"]
	var spots := [Vector3(2.0, 0.05, 4.5), Vector3(-6.0, 0.05, -2.0), Vector3(-7.0, 0.05, 2.0)]  # the sword card nearest, off the lane
	for i in 3:
		sim.add_player(i + 1, spots[i])
		sim.set_class_style(i + 1, str(Deck.class_data(squad[i]).get("weapon", "")))
	sim.add_enemy(100, Vector3(3.0, 0.05, 0.0), enemy_type, 1)
	return sim


func _check_target_priority(ctx, combat) -> void:
	var ranged: Array = combat.ranged_styles()
	ctx.check("the ranged styles come from the data (longbow and magic fire, sword/greatsword strike) %s" % [ranged], ranged.has("longbow") and ranged.has("magic") and not ranged.has("sword_shield") and not ranged.has("greatsword"))
	var bosses: Array = load("res://logic/race_data.gd").load_default().rules.get("boss_types", [])
	for id in bosses:
		var expected := "" if str(id).begins_with("goblin") else "ranged_first"
		ctx.check("boss %s target_priority '%s' (goblin chief untouched)" % [id, combat.enemies[id]["ai"]["target_priority"]], str(combat.enemies[id]["ai"]["target_priority"]) == expected)
	var sim := _arena(combat, "orc_warlock", 7)
	var brain = sim._ai[100]
	var pick := func() -> int: return brain.pick_target(sim.fighters[100], sim.bodies[100], sim.bodies, sim.fighters)
	ctx.check("the Warlock picks the longbow (nearest ranged) over the sword card standing next to it", pick.call() == 2)
	sim.fighters[2].state = Fighter.State.DEAD
	ctx.check("the longbow down: it switches to the magic card at once (no lock on the dead)", pick.call() == 3)
	sim.fighters[3].state = Fighter.State.DOWNED
	ctx.check("no ranged card standing: it falls back to the nearest (the sword card)", pick.call() == 1)
	sim.fighters[2].state = Fighter.State.IDLE
	sim.fighters[3].state = Fighter.State.IDLE
	brain.taunt(1, 120)
	sim.tick()
	ctx.check("a taunt still wins over the priority (it walks at the taunter)", brain.taunted_by(sim.fighters[100], sim.fighters) == 1)
	var plain := _arena(combat, "goblin_chief", 7)
	ctx.check("a boss without the priority (goblin chief) takes the nearest card", plain._ai[100].pick_target(plain.fighters[100], plain.bodies[100], plain.bodies, plain.fighters) == 1)
	# In a driven fight the Warlock's first blow goes to the longbow, and the run is deterministic and checkpoint-safe.
	var a := _drive_boss(combat, 21, -1)
	var b := _drive_boss(combat, 21, -1)
	var c := _drive_boss(combat, 21, 90)
	ctx.check("its first hit lands on the longbow card (%s)" % a["first_victim"], a["first_victim"] == 2)
	ctx.check("same seed, same fight (hits %d, digest equal)" % a["hits"], a["digest"] == b["digest"] and a["hits"] == b["hits"])
	ctx.check("restored from a checkpoint mid-fight: the same fight", a["digest"] == c["digest"])


## The Warlock vs the three cards standing still for 8 s. restore_at >= 0: snapshot there and continue in a NEW sim.
static func _drive_boss(combat, seed: int, restore_at: int) -> Dictionary:
	var sim := _arena(combat, "orc_warlock", seed)
	var first_victim := -1
	var hits := 0
	var trace := []
	for t in 480:
		if t == restore_at:
			var saved := sim.snapshot()
			var fresh := _arena(combat, "orc_warlock", 999)
			if not fresh.restore(saved):
				return {"first_victim": -2, "hits": -1, "digest": "restore failed"}
			sim = fresh
		for id in [1, 2, 3]:
			sim.set_input(id, SimInput.new())
			sim.fighters[id].hp = sim.fighters[id].max_hp()
		sim.tick()
		for event in sim.events:
			if str(event["type"]) in ["hit", "blocked"] and int(event.get("attacker", -1)) == 100:
				hits += 1
				if first_victim < 0:
					first_victim = int(event["target"])
		trace.append("%d:%s:%s" % [t, sim.fighters[100].move_id, str(sim.bodies[100].position.snapped(Vector3.ONE * 0.001))])
	return {"first_victim": first_victim, "hits": hits, "digest": str(hash("|".join(trace)))}


func _check_orcs(ctx, combat) -> void:
	for id in ORCS:
		var ai: Dictionary = combat.enemies[id]["ai"]
		ctx.check("%s is aggressive: no retreat range, hop back, flee or escape; runs in; opens at once %s" % [id, ai],
			bool(ai["aggressive"]) and float(ai["retreat_range"]) == 0.0 and int(ai["retreat_ticks"]) == 0 and float(ai["flee_hp"]) == 0.0
			and str(ai["escape_input"]) == "" and float(ai["run_beyond"]) > 0.0 and int(ai["opening_cooldown"]) == 0)
	# A driven fight: two of each orc vs the auto-piloted squad for 40 s (nobody dies). Never a retreat or a wait.
	var world := SimWorld.new()
	world.half_width = 16.0
	world.half_depth = 9.0
	world.add_solid(AABB(Vector3(-17.0, -1.0, -10.0), Vector3(34.0, 1.0, 20.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sim := GameSim.new(world, combat, rng)
	var squad := ["sword_shield", "longbow", "magic"]
	for i in 3:
		sim.add_player(i + 1, Vector3(-8.0, 0.05, -2.0 + 2.0 * i))
		sim.set_class_style(i + 1, str(Deck.class_data(squad[i]).get("weapon", "")))
	var next := 100
	for id in ORCS:
		for k in 2:
			sim.add_enemy(next, Vector3(8.0 + k, 0.05, -4.0 + 3.0 * (next - 100) / 2.0), id, 20)
			next += 1
	var memories := {}
	for id in [1, 2, 3]:
		memories[id] = Pilot.new_memory(id)
	var bad := {}
	var waits := 0
	var ran_at_start := {}
	var attacked := {}
	var close_seen := {}
	for t in 60 * 40:
		for id in [1, 2, 3]:
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, combat, id, memories[id], t).encode()))
		sim.tick()
		for id in sim.fighters:
			sim.fighters[id].hp = sim.fighters[id].max_hp()
		for eid in sim._ai:
			var intent := str(sim._ai[eid].intent)
			var kind := str(sim.fighters[eid].enemy_type)
			if RETREATS.has(intent):
				bad[kind] = int(bad.get(kind, 0)) + 1
			if intent == "wait":
				waits += 1
			if t < 30 and sim.fighters[eid].running:
				ran_at_start[kind] = true
			if intent == "attack":
				attacked[kind] = true
			var nearest := INF
			for pid in [1, 2, 3]:
				nearest = minf(nearest, sim.bodies[eid].position.distance_to(sim.bodies[pid].position))
			close_seen[kind] = minf(float(close_seen.get(kind, INF)), nearest)
	ctx.check("orcs in a driven 40 s fight: 0 retreat / hop back / flee / escape ticks %s" % [bad], bad.is_empty())
	ctx.check("orcs never wait their turn in a ring (%d wait ticks)" % waits, waits == 0)
	ctx.check("every orc type runs in during the first 0.5 s %s" % [ran_at_start.keys()], ORCS.all(func(o): return ran_at_start.has(o)))
	ctx.check("every orc type attacks %s" % [attacked.keys()], ORCS.all(func(o): return attacked.has(o)))
	ctx.check("the grunt closes to melee and the archer and mage walk in to their (shorter) keep range, from 16 m away %s" % [close_seen],
		float(close_seen.get("orc_grunt", INF)) < 2.5 and ORCS.all(func(o): return float(close_seen.get(o, INF)) <= float(combat.enemies[o]["ai"]["keep_range"]) + 1.0))


func _check_loader(ctx) -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/combat.json"))
	raw["enemies"]["orc_grunt"]["ai"]["flee_hp"] = 0.3
	raw["enemies"]["orc_grunt"]["ai"]["flee_ticks"] = 30
	raw["enemies"]["orc_archer"]["ai"]["target_priority"] = "weakest"
	var bad := CombatDataLoader.parse(JSON.stringify(raw))
	ctx.check("loader: an aggressive monster that flees and an unknown target_priority are errors %s" % [bad.errors], bad.errors.size() == 2)
