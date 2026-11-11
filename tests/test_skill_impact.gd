extends RefCounted
## Skill-tree hits land with weight: hit-stop on the struck target (and on the caster for medium /
## heavy skills), scaled by the skill's impact tier from data/skill_system/integration.json, plus
## the client keys in data/combat/vfx.json (sparks per target, camera kick once per frame).
## Locks the intended ranges; the numbers themselves are placeholders until the Boss plays.

const Training := preload("res://logic/training_ground.gd")
const Inputs := preload("res://logic/sim_input.gd")
const Build := preload("res://logic/skill_build.gd")
const System := preload("res://logic/skills/system.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")

const LIGHT_SWING_HITSTOP := 4  ## data/combat/combat.json light moves
const HEAVY_SWING_HITSTOP := 8  ## heavy moves


func run(ctx) -> void:
	var impact: Dictionary = Build.config().get("impact", {})
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/catalog.json"))
	var missing: Array = catalog.filter(func(id) -> bool: return not impact.get("tiers", {}).has(id))
	ctx.check("every catalog skill has an impact tier %s" % [missing], missing.is_empty())
	var hs: Array = impact.get("target_hitstop", [])
	ctx.check("target hit-stop grows with tier", hs.size() == 4 and int(hs[0]) == 0 and int(hs[1]) < int(hs[2]) and int(hs[2]) < int(hs[3]))
	ctx.check("light skills freeze about as long as a light swing (3-5 ticks)", int(hs[1]) >= LIGHT_SWING_HITSTOP - 1 and int(hs[1]) <= LIGHT_SWING_HITSTOP + 1)
	ctx.check("heavy skills land at least as hard as a heavy swing, at most +50%", int(hs[3]) >= HEAVY_SWING_HITSTOP and int(hs[3]) <= HEAVY_SWING_HITSTOP * 3 / 2)
	ctx.check("hit-stop is capped at 12 ticks (0.2 s) even on a crit", int(impact.get("max_hitstop", 99)) <= 12)
	for heavy in ["eruption", "ground_slam", "lightning_strike", "shatter_smash"]:
		ctx.check("%s is a heavy (tier 3) skill" % heavy, System.impact_tier(heavy) == 3)
	ctx.check("ice_lance is lighter than lightning_strike", System.impact_tier("ice_lance") < System.impact_tier("lightning_strike"))
	ctx.check("basic weapon attacks are untouched (tier 0)", System.impact_tier("basic_attack") == 0)

	var world = load("res://logic/sim_world.gd").new()
	world.half_width = 30
	world.half_depth = 40
	world.add_solid(AABB(Vector3(-60, -1, -60), Vector3(120, 1, 120)))
	var heavy := _spam(world, "blade", "ground_slam")
	var light := _spam(world, "blade", "ice_lance")
	var totem := _spam(world, "blade", "tesla_totem")
	ctx.check("ground_slam hit freezes the target 10-12 ticks (got %d)" % heavy.target_max, heavy.target_max >= 10 and heavy.target_max <= 12)
	ctx.check("ground_slam freezes the caster briefly (got %d)" % heavy.caster_max, heavy.caster_max > 0 and heavy.caster_max <= 4)
	ctx.check("ice_lance hit freezes the target 4-6 ticks (got %d)" % light.target_max, light.target_max >= 4 and light.target_max <= 6)
	ctx.check("ice_lance never freezes the caster", light.caster_max == 0)
	ctx.check("tesla_totem auto-fire is periodic: no hit-stop", totem.target_max == 0 and totem.hits > 0 and totem.periodic)
	ctx.check("spamming a heavy skill freezes a monster under 6%% of the time (got %.1f%%)" % heavy.frozen_pct, heavy.frozen_pct < 6.0)
	ctx.check("skill_hit events carry the skill id and tier", heavy.tagged)

	var lib = VfxLibrary.load_default()
	ctx.check("skill hit keys scale with tier", lib.skill_hit_keys(1, false, false) == ["skill_hit/1"] and lib.skill_hit_keys(3, true, false) == ["skill_hit/3", "skill_hit/crit"])
	ctx.check("periodic skill hits get only small sparks", lib.skill_hit_keys(3, true, true) == ["skill_hit/tick"])
	ctx.check("tier 0 skill hits draw no impact", lib.skill_hit_keys(0, false, false).is_empty() and lib.skill_impact_keys(0, false).is_empty())
	var shake := func(key: String) -> float:
		for layer in lib.layers(key):
			if layer.type == "shake": return float(layer.strength)
		return 0.0
	ctx.check("camera shake grows with tier", shake.call("skill_impact/1") < shake.call("skill_impact/2") and shake.call("skill_impact/2") < shake.call("skill_impact/3"))
	ctx.check("the heaviest skill shake stays under the dead ultimate's (0.13)", shake.call("skill_impact/3") <= 0.13)
	ctx.check("skill hit sparks themselves never shake (camera is once per frame)", ["skill_hit/1", "skill_hit/2", "skill_hit/3", "skill_hit/crit"].all(func(k) -> bool: return shake.call(k) == 0.0))
	var gems: Array = []
	for gem in ["ignite", "bleed", "chill", "shock", "stun", "leech", "thorns", "regen"]:
		if not lib.has("skill_gem/" + gem): gems.append(gem)
	ctx.check("every effect gem has an impact mark %s" % [gems], gems.is_empty())
	ctx.check("every skill has a hit color", catalog.all(func(id) -> bool: return lib.skill_colors.has(id)))


func _spam(world, style: String, skill: String) -> Dictionary:
	var training = Training.new(world, load("res://logic/combat_data_loader.gd").load_default(), Vector3(-18, 0, 3))
	var build := Build.initial(style)
	var rest: Array = build.skills.map(func(r): return r.skill).filter(func(s): return s != skill)
	build.skills = [{"skill": skill, "shape": "", "effect": ""}]
	for other in rest.slice(0, 3): build.skills.append({"skill": other, "shape": "", "effect": ""})
	training.configure({"ATK": 20, "HP": 1000, "STAMINA": 1000}, style, build)
	training.step(Inputs.new())
	var out := {"target_max": 0, "caster_max": 0, "frozen_pct": 0.0, "hits": 0, "periodic": false, "tagged": false}
	var frozen := 0
	for i in range(600):
		var input = Inputs.new()
		if i % 2 == 0:
			input.aim = Vector2(0, -1)
			input.aim_distance = 3
			input.skill_slot = 0
		training.sim.fighters[1].energy = training.sim.fighters[1].max_energy()
		training.step(input)
		for event in training.sim.events:
			if event.type == "skill_hit" and int(event.target) in Training.DUMMY_IDS:
				out.hits += 1
				out.periodic = out.periodic or bool(event.periodic)
				out.tagged = out.tagged or (event.move == "skill:" + skill and int(event.impact) == System.impact_tier(skill))
		var dummy = training.sim.fighters[903]
		out.target_max = maxi(out.target_max, dummy.hitstop)
		frozen += int(dummy.hitstop > 0)
		out.caster_max = maxi(out.caster_max, training.sim.fighters[1].hitstop)
	out.frozen_pct = frozen / 6.0
	training.dispose()
	return out
