extends SceneTree
## Debug probe (movement snap / skill aim investigation 2026-11-15): plays the wave squad headless with the
## auto pilot and prints (1) per-tick step length stats of player fighters, (2) for each class_skill_release,
## how far the frozen cast aim is from the target's position at release.
const F := preload("res://tests/online_fixture.gd")
const Pilot := preload("res://logic/auto_pilot.gd")
const Party := preload("res://logic/coop_journey.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Deck := preload("res://logic/card_deck.gd")

func _init() -> void:
	var f := F.make(31)
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var members: Array = preload("res://logic/squad_member.gd").make_squad(f.run, Array(Deck.STARTER_SQUAD))
	var trips := {}
	for i in members.size(): trips[i + 1] = members[i]
	var journey = Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, 31)
	while journey.state != journey.IN_STAGE and not journey.is_over(): journey.choose(0)
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new(); world.half_width = map.half_width; world.half_depth = map.half_depth
	for solid in map.solids: world.add_solid(solid.box)
	var sim := Sim.new(world, f.combat, F.rng(31))
	journey.populate(sim, map, 1, 100)
	var starter: Array = Array(Deck.STARTER_SQUAD)
	for i in starter.size(): sim.set_class_style(i + 1, str(Deck.class_data(str(starter[i])).get("weapon", "")))
	var mem := {}
	for id in journey.player_ids(): mem[id] = Pilot.new_memory(id)
	var last := {}; var steps := []; var big := 0; var starts := {}
	for tick in 60 * 90:
		for id in journey.player_ids(): sim.set_input(id, SimInput.decode(Pilot.decide(sim, f.combat, id, mem[id], tick, 0.9).encode()))
		sim.tick()
		for id in journey.player_ids():
			var p: Vector3 = sim.bodies[id].position
			if last.has(id):
				var d := Vector2(p.x - last[id].x, p.z - last[id].z).length()
				steps.append(d)
				if d > 0.25: big += 1
			last[id] = p
		for e in sim.events:
			if str(e["type"]) == "class_skill_start": starts[int(e["player"])] = e
			if str(e["type"]) == "class_skill_release" and int(e.get("index", 0)) == 0:
				var s: Dictionary = starts.get(int(e["player"]), {})
				var t := int(s.get("target", -1))
				if t >= 0 and sim.bodies.has(t):
					var aim: Vector3 = e["aim"]; var now: Vector3 = sim.bodies[t].position
					print("SKILL %s caster=%d ticks_since_start=%d aim_vs_target_now=%.2fm" % [e["skill"], e["player"], sim.tick_count - int(s["start"]), Vector2(aim.x - now.x, aim.z - now.z).length()])
	steps.sort()
	print("STEPS n=%d median=%.3f p99=%.3f max=%.3f over0.25m=%d" % [steps.size(), steps[steps.size()/2], steps[int(steps.size()*0.99)], steps[-1], big])
	quit()
