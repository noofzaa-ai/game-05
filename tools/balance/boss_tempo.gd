extends SceneTree
## Boss tempo and monster aggression check (Boss 2026-11-22: bosses ~3x faster, bosses go for ranged cards first,
## orcs never retreat).
##   godot --headless --path . --script res://tools/balance/boss_tempo.gd [-- seeds=6 seconds=60 types=a,b]
## TEMPO table: ONE monster vs a passive squad (sword_shield, longbow, magic standing 8-9 m away, nobody dies), so the
## numbers are the monster's own pace through the real rules: first attack s (spawn to its first attack_started, the
## walk in included), first hit s (to its first damage on a card), attacks and skills per 30 s, retreat ticks (backing
## off, hopping back, fleeing, escaping: EnemyAI.intent), wait ticks (waiting its turn), its first target's class.
## The in-fight count (every monster's AI intent in the real wave journey) is the "monster AI" table of class_sim.gd.
## Tool only: nothing in the game loads this file.

const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const Deck := preload("res://logic/card_deck.gd")
const CombatLoader := preload("res://logic/combat_data_loader.gd")

const TYPES := ["orc_warlock", "mummy_boss", "mummy_high_wizard", "goblin_chief", "orc_grunt", "orc_archer", "orc_mage"]
const SQUAD := ["sword_shield", "longbow", "magic"]
const RETREATS := ["back_off", "hop_back", "flee", "escape"]


func _init() -> void:
	var seeds := 6
	var seconds := 60
	var types: Array = TYPES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = int(arg.substr(6))
		elif arg.begins_with("seconds="):
			seconds = int(arg.substr(8))
		elif arg.begins_with("types="):
			types = Array(arg.substr(6).split(","))
	var combat = CombatLoader.load_default()
	print("BOSS TEMPO  seeds=%d  seconds=%d  passive squad=%s" % [seeds, seconds, ",".join(SQUAD)])
	print("type               | first atk s | first hit s | attacks/30s | skills/30s | retreat ticks | wait ticks | first target")
	for enemy_type in types:
		var total := {"first": 0.0, "hit": 0.0, "attacks": 0, "skills": 0, "retreat": 0, "wait": 0, "targets": {}}
		for s in seeds:
			var r := measure(combat, str(enemy_type), 500 + s * 13, seconds)
			for k in ["first", "hit", "attacks", "skills", "retreat", "wait"]:
				total[k] += r[k]
			total["targets"][r["target"]] = int(total["targets"].get(r["target"], 0)) + 1
		var per30 := 30.0 / float(seconds) / float(seeds)
		print("%-18s | %11.2f | %11.2f | %11.1f | %10.1f | %13d | %10d | %s" % [enemy_type, total["first"] / seeds, total["hit"] / seeds, total["attacks"] * per30, total["skills"] * per30,
			total["retreat"], total["wait"], JSON.stringify(total["targets"])])
		print("TEMPO|%s|first=%.3f|hit=%.3f|attacks30=%.2f|skills30=%.2f|retreat=%d|wait=%d" % [enemy_type, total["first"] / seeds, total["hit"] / seeds, total["attacks"] * per30, total["skills"] * per30, total["retreat"], total["wait"]])
	quit(0)


## One monster vs the passive squad on an open floor. Returns its tempo numbers.
static func measure(combat, enemy_type: String, seed: int, seconds: int) -> Dictionary:
	var world := World.new()
	world.half_width = 16.0
	world.half_depth = 9.0
	world.add_solid(AABB(Vector3(-17.0, -1.0, -10.0), Vector3(34.0, 1.0, 20.0)))  # the floor
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := Sim.new(world, combat, rng)
	var ids := []
	for i in SQUAD.size():
		sim.add_player(i + 1, Vector3(-4.0, 0.05, -2.0 + 2.0 * i))  # melee in front (z -2), longbow, magic
		sim.set_class_style(i + 1, str(Deck.class_data(SQUAD[i]).get("weapon", "")))
		ids.append(i + 1)
	var enemy := 100
	sim.add_enemy(enemy, Vector3(4.0, 0.05, -2.0), enemy_type, 1)  # nearest to the melee card
	var skills := {}
	for k in combat.enemies[enemy_type]["ai"].get("skills", []):
		skills[str(k["move"])] = true
	var style: Dictionary = combat.styles[combat.enemies[enemy_type]["style"]]
	if style.has("special"):
		skills[str(style["special"])] = true
	var first := -1.0
	var hit := -1.0
	var attacks := 0
	var used := 0
	var retreat := 0
	var wait := 0
	var target := "-"
	for tick in seconds * 60:
		sim.tick()
		for id in ids + [enemy]:  # tempo only: nobody dies, nobody stays stunned
			var f: Fighter = sim.fighters[id]
			f.hp = f.max_hp()
		var brain = sim._ai[enemy]
		var intent := str(brain.intent)
		if RETREATS.has(intent):
			retreat += 1
		if intent == "wait":
			wait += 1
		for event in sim.events:
			var kind := str(event["type"])
			if kind == "attack_started" and int(event.get("player", -1)) == enemy:
				attacks += 1
				if skills.has(str(event["move"])):
					used += 1
				if first < 0.0:
					first = float(tick + 1) / 60.0
					var aimed: int = brain.pick_target(sim.fighters[enemy], sim.bodies[enemy], sim.bodies, sim.fighters)
					target = SQUAD[aimed - 1] if aimed >= 1 and aimed <= SQUAD.size() else "?"
			elif (kind == "hit" or kind == "blocked") and int(event.get("attacker", -1)) == enemy and hit < 0.0:
				hit = float(tick + 1) / 60.0
	return {"first": first if first >= 0.0 else float(seconds), "hit": hit if hit >= 0.0 else float(seconds), "attacks": attacks, "skills": used, "retreat": retreat, "wait": wait, "target": target}


## orc_waves as class_sim plays it (level 20, tier-1 gear, starter squad, the pilot): per orc type, ticks per intent.
static func orc_waves(combat, seeds: int) -> Dictionary:
	var sim_tool = load("res://tools/balance/class_sim.gd")
	var counts := {}
	var runner = sim_tool.new_measurer(combat, "orc_waves", 20, 1)
	for s in seeds:
		var sim = runner.start(Array(Deck.STARTER_SQUAD), 2000 + s * 17)
		var ids: Array = range(1, 4)
		var memories := {}
		for id in ids:
			memories[id] = Pilot.new_memory(id * 7919 + s)
		for tick in 60 * 400:
			if sim.living_enemy_count() + sim.pending_wave_count() == 0 or not ids.any(func(id): return sim.fighters[id].is_alive()):
				break
			for id in ids:
				sim.set_input(id, SimInput.decode(Pilot.decide(sim, combat, id, memories[id], tick).encode()))
			sim.tick()
			for eid in sim._ai:
				var f: Fighter = sim.fighters[eid]
				if not f.is_alive() or not str(f.enemy_type).begins_with("orc_"):
					continue
				var row: Dictionary = counts.get(f.enemy_type, {})
				var intent := str(sim._ai[eid].intent)
				row[intent] = int(row.get(intent, 0)) + 1
				counts[f.enemy_type] = row
	return counts
