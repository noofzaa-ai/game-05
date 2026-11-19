extends RefCounted
## The Mummy High Wizard (combat-designer 2026-11-18; Boss 2026-11-17: the wave-9 boss pair with the Mummy Pharaoh).
## Locks: its kit is three moves on clips the wizard library really has, timed from the clip marks; every blow is
## marked on the ground first (telegraph / ground area); its baked daiyooo-vfx bundles exist and are wired (data
## only, no procedural slash under the signature moves); in a scripted duel the AI really casts all three; and the
## finale tuning stays in the measured range (data/journeys/mummy_waves.json _tuning_boss_pair).

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Combat := preload("res://logic/combat.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")
const ProjectileView := preload("res://client/projectile_view.gd")
const MonsterVfx := preload("res://client/monster_vfx.gd")

const ID := "mummy_high_wizard"
const KIT := {"mummy_hw_bolt": "cast", "mummy_hw_curse": "cast_aoe", "mummy_hw_starfall": "starfall", "mummy_hw_sandstorm": "sandstorm"}
const MapLoader := preload("res://logic/map_loader.gd")
const Journey := preload("res://logic/journey.gd")
const Zones := preload("res://logic/world_zones.gd")


func run(ctx) -> void:
	var combat := CombatDataLoader.load_default()
	ctx.check("combat.json loads with no errors %s" % [combat.errors], combat.errors.is_empty())
	var enemy: Dictionary = combat.enemies.get(ID, {})
	ctx.check("the High Wizard exists with its own style", not enemy.is_empty() and str(enemy["style"]) == ID)
	if enemy.is_empty():
		return
	_check_kit(ctx, combat, enemy)
	_check_vfx(ctx, combat)
	_check_duel(ctx, combat)
	_check_finale(ctx, combat)
	_check_boss_resistance(ctx, combat)
	_check_boss_statuses(ctx, combat)
	_check_skill_list(ctx)
	_check_boss_spots(ctx, combat)
	_check_zone(ctx)


func _check_kit(ctx, combat, enemy: Dictionary) -> void:
	var style: Dictionary = combat.styles[ID]
	ctx.check("light = the golden bolt, heavy = the sandstorm", style["ground_light"] == "mummy_hw_bolt" and style["ground_heavy"] == "mummy_hw_sandstorm")
	var skill_moves: Array = enemy["ai"]["skills"].map(func(k): return str(k["move"]))
	ctx.check("its ai.skills are the starfall then the curse, each with its own cooldown %s" % [skill_moves], skill_moves == ["mummy_hw_starfall", "mummy_hw_curse"] and skill_moves.all(func(m): return int(combat.moves[m]["cooldown"]) > 0))
	ctx.check("its escape is the heavy (sandstorm)", str(enemy["ai"]["attack_input"]) == "light" and str(enemy["ai"].get("escape_input", "")) == "heavy")
	ctx.check("it is visibly the biggest pyramid monster (3.4 m vs the Pharaoh)", float(enemy["model_height"]) >= float(combat.enemies["mummy_boss"]["model_height"]) * 1.25)
	ctx.check("it is tougher than the Pharaoh it fights beside (HP and poise)", float(enemy["stats"]["HP"]) > float(combat.enemies["mummy_boss"]["stats"]["HP"]) and float(enemy["poise"]) > float(combat.enemies["mummy_boss"]["poise"]))
	var marks = JSON.parse_string(FileAccess.get_file_as_string("res://art/animations/monster_clips_wizard_boss.json"))
	for move_id in KIT:
		var move: Dictionary = combat.moves[move_id]
		var clip: String = KIT[move_id]
		ctx.check("%s plays the wizard clip '%s'" % [move_id, clip], str(enemy["clips"].get(move_id, "")) == clip and marks is Dictionary and marks.has(clip))
		if marks is Dictionary and marks.has(clip):
			var windup := float(marks[clip]["windup_end"]) * 60.0
			ctx.check("%s wind-up %d ticks is the clip's %.0f within 0.6-1.0x (the clip plays at most 1.7x fast)" % [move_id, int(move["startup"]), windup], float(move["startup"]) >= windup * 0.6 and float(move["startup"]) <= windup * 1.0)
		if move_id != "mummy_hw_bolt":  # (the bolt is a plain homing shot, like the mage's)
			ctx.check("%s is telegraphed (warned on the ground)" % move_id, bool(move["telegraph"]))
	for area_id in ["hw_curse", "hw_star"]:
		var area: Dictionary = combat.areas[area_id]
		ctx.check("area %s cannot be guarded, warns at least 0.8 s and has its own client look" % area_id, not bool(area["guardable"]) and int(area["delay"]) >= 48 and ProjectileView.LOOKS.has(str(area["look"])))
	var star: Array = combat.moves["mummy_hw_starfall"]["spawns"]
	ctx.check("the starfall drops 3 marks one after another (a chasing barrage)", star.size() == 3 and float(star[2]["frame"]) > float(star[1]["frame"]) and float(star[1]["frame"]) > float(star[0]["frame"]))
	var storm: Dictionary = combat.moves["mummy_hw_sandstorm"]
	ctx.check("the sandstorm is a ring all around it reaching past its trigger range", absf(storm["hit_offset"].x) < 0.01 and float(storm["hit_size"].x) * 0.5 >= float(combat.enemies[ID]["ai"]["escape_range"]) - 1.0)


func _check_vfx(ctx, combat) -> void:
	var spec := MonsterVfx.load_spec()
	var lib = VfxLibrary.load_default()
	ctx.check("vfx.json still loads %s" % [lib.errors], lib.is_valid())
	for key in spec:
		ctx.check("monster_vfx %s: its bundle is installed (%s)" % [key, spec[key]["vfx"]], MonsterVfx.scene_path(str(spec[key]["vfx"])) != "" and FileAccess.file_exists("res://art/vfx/monster/%s/recipe.json" % spec[key]["vfx"]))
	var mv = MonsterVfx.new()
	var bundles: Array = mv.vfx_for_types([ID], combat)
	bundles.sort()
	ctx.check("the wizard's fight prewarms its five bundles %s" % [bundles], bundles == ["hw_bolt", "hw_curse", "hw_sandstorm", "hw_starfall", "hw_summon"])
	mv.free()
	for move_id in KIT:
		var swing: String = lib.swing_key(move_id)
		ctx.check("%s has its own (camera-only) swing key, not the shared slash (%s)" % [move_id, swing], swing == "swing/" + move_id and lib.layers(swing).all(func(l): return str(l.get("type")) == "shake"))
	ctx.check("pack layout ships the monster bundles in the battle vfx pack", FileAccess.get_file_as_string("res://tools/web/pack_layout.json").contains("res://art/vfx/monster/"))


## A scripted duel: a target dummy far away, then close. It must curse, starfall and (once close) sandstorm.
func _check_duel(ctx, combat) -> void:
	var world := SimWorld.new()
	world.half_width = 8.0
	world.half_depth = 4.5
	world.add_solid(AABB(Vector3(-8, -0.4, -4.5), Vector3(16, 0.4, 9)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(1, Vector3(-3.0, 0.05, 0.0), {"HP": 100000, "STAMINA": 1000})
	sim.fighters[1].hp = 100000.0
	sim.add_enemy(2, Vector3(5.0, 0.05, 0.0), ID, 4)
	var seen := {}
	var areas := {}
	var telegraph_circle := false
	for t in 60 * 40:
		if t == 60 * 25:
			sim.bodies[1].position = sim.bodies[2].position + Vector3(-2.5, 0.0, 0.0)  # step into its storm range
		sim.set_input(1, SimInput.new())
		sim.tick()
		var shape := Combat.telegraph_shape(2, sim.fighters, sim.bodies, combat)
		telegraph_circle = telegraph_circle or (not shape.is_empty() and str(shape["kind"]) == "circle")
		for event in sim.events:
			if str(event["type"]) == "attack_started" and int(event["player"]) == 2:
				seen[str(event["move"])] = true
			if str(event["type"]) == "area_placed":
				areas[str(event["kind"])] = true
	ctx.check("in 40 s of a duel it casts all four: bolt, curse, starfall and sandstorm %s" % [seen.keys()], seen.has("mummy_hw_bolt") and seen.has("mummy_hw_curse") and seen.has("mummy_hw_starfall") and seen.has("mummy_hw_sandstorm"))
	ctx.check("its curse and star marks are placed on the ground %s" % [areas.keys()], areas.has("hw_curse") and areas.has("hw_star"))
	ctx.check("its wind-ups show a circle telegraph", telegraph_circle)


func _check_finale(ctx, combat) -> void:
	var data = JourneyData.load_by_id("mummy_waves", combat.enemies.keys())
	var last: Dictionary = data.stages[-1]
	# Boss 2026-11-19 retune, round 2 (mummy ATK ~2x the original, HP near the original, ~70% win for the level-15 tier-1
	# starter squad): finale 0.65 with squad power 1.68 = 71% (60 seeds); finale 0.75 with squad power 1.6 = 83% (60).
	# The band is that sweep's useful range; outside it the finale is a wall or a walk-over.
	ctx.check("finale power stays in the measured band 0.6-0.72 (0.65 = 71%% win, level 15 tier 1 starter squad): %.2f" % float(last["power"]), float(last["power"]) >= 0.6 and float(last["power"]) <= 0.72)
	ctx.check("the boss pair comes with the escort mummies only (the ranged escorts were dropped for balance)", last["enemies"].all(func(e): return ["mummy_boss", "mummy_high_wizard", "mummy"].has(str(e["type"]))))
	ctx.check("the tuning note records the measurement", str(JSON.parse_string(FileAccess.get_file_as_string("res://data/journeys/mummy_waves.json")).get("_tuning_hard_hits_round2", "")).contains("1.68 -> 71.2%, CHOSEN"))


## Boss 2026-11-19: every boss except the goblin family has CTRL_RES 100 (data/races/rules.json boss_types): no stun, shock,
## sleep, stagger, knockback or launch. Debuffs and DoTs must still land (players' debuff builds), so their summed
## resistance stays well under 100.
func _check_boss_resistance(ctx, combat) -> void:
	var Effects = load("res://logic/effects.gd")
	var bosses: Array = load("res://logic/race_data.gd").load_default().rules.get("boss_types", [])
	ctx.check("boss_types lists the two pyramid bosses %s" % [bosses], bosses.has("mummy_boss") and bosses.has("mummy_high_wizard"))
	var world := SimWorld.new()
	world.half_width = 8.0
	world.half_depth = 4.5
	var sim := GameSim.new(world, combat, RandomNumberGenerator.new())
	sim.add_player(1, Vector3(-3.0, 0.05, 0.0))
	var next := 2
	for id in bosses:
		if str(id).begins_with("goblin"):
			continue  # Boss 2026-11-19: the goblin family is the exception
		var stats: Dictionary = combat.enemies[id]["stats"]
		ctx.check("boss %s has CTRL_RES >= 100 (%s)" % [id, stats.get("CTRL_RES", 0)], float(stats.get("CTRL_RES", 0.0)) >= 100.0)
		sim.add_enemy(next, Vector3(3.0, 0.05, 0.0), str(id), 4)
		var boss = sim.fighters[next]
		ctx.check("boss %s: immune to the physical control results (stagger, knockback, launch)" % id, Effects.control_resist_immune(boss))
		var events: Array[Dictionary] = []
		var rng := RandomNumberGenerator.new()
		var landed := false
		for effect in ["stun", "shock", "sleep"]:
			landed = landed or Effects.apply(1, sim.fighters[1], next, boss, {"id": effect, "chance": 100.0, "duration": 0}, combat, rng, events)
		ctx.check("boss %s: a 100%% stun, shock or sleep never lands" % id, not landed)
		var debuff: float = Effects.resistance_total(boss, "debuff", "slow")
		var dot: float = Effects.resistance_total(boss, "dot", "burn")
		ctx.check("boss %s: debuffs and DoTs can still land (resistance %.0f / %.0f < 60)" % [id, debuff, dot], debuff < 60.0 and dot < 60.0)
		# (chance 200: the boss's EFFECT_RES is subtracted first, then the chance is clamped to 100 = certain)
		ctx.check("boss %s: a sure slow still lands (not immune to debuffs)" % id, Effects.apply(1, sim.fighters[1], next, boss, {"id": "slow", "chance": 200.0, "duration": 0}, combat, rng, events))
		next += 1


## Boss 2026-11-19 ('the boss skills must inflict statuses on the player'): the statuses each boss move gives, control
## only on big telegraphed moves at a chance under 100, and the hit order of the family (boss > knight > mage/archer > grunt).
const BOSS_STATUSES := {
	"mummy_hw_bolt": ["weaken", "bleed"], "mummy_hw_curse": ["curse", "exhaust"], "mummy_hw_starfall": ["burn", "shock"],
	"mummy_hw_sandstorm": ["slow", "weaken"], "mummy_boss_combo": ["bleed"], "mummy_boss_nova": ["curse", "wound"],
	"mummy_knight_bash": ["stun", "sunder"], "mummy_mage_curse": ["curse", "exhaust"], "mummy_grasp": ["curse", "bleed"],
}


func _check_boss_statuses(ctx, combat) -> void:
	for move_id in BOSS_STATUSES:
		var move: Dictionary = combat.moves[move_id]
		var ids: Array = move["effects"].map(func(e): return str(e["id"]))
		ctx.check("%s gives %s %s" % [move_id, BOSS_STATUSES[move_id], ids], BOSS_STATUSES[move_id].all(func(e): return ids.has(e)))
	var control_ok := true
	for move_id in combat.moves:
		if not str(move_id).begins_with("mummy"):
			continue
		var move: Dictionary = combat.moves[move_id]
		for entry in move["effects"]:
			if str(combat.effects[str(entry["id"])].get("control", "")) != "":
				control_ok = control_ok and bool(move["telegraph"]) and float(entry["chance"]) < 100.0
	ctx.check("mummy control statuses (stun/shock/sleep) only on telegraphed moves, never certain", control_ok)
	ctx.check("the sandstorm (a ring around the wizard) carries no control status", combat.moves["mummy_hw_sandstorm"]["effects"].all(func(e): return str(combat.effects[str(e["id"])].get("control", "")) == ""))
	var atk := func(id: String) -> float: return float(combat.enemies[id]["stats"]["ATK"])
	ctx.check("mummy family hit order: bosses > knight > mage, archer > grunt (%s)" % [["mummy_high_wizard", "mummy_boss", "mummy_knight", "mummy_mage", "mummy_archer", "mummy"].map(func(i): return atk.call(i))],
		minf(atk.call("mummy_high_wizard"), atk.call("mummy_boss")) > atk.call("mummy_knight") and atk.call("mummy_knight") > maxf(atk.call("mummy_mage"), atk.call("mummy_archer")) and minf(atk.call("mummy_mage"), atk.call("mummy_archer")) >= atk.call("mummy"))
	# Boss 2026-11-19 round 2: ATK about 2x the pre-change mummy values, HP back near them (round 1's HP /4 is gone).
	var original := {"mummy": [15.0, 45.0], "mummy_archer": [14.0, 33.0], "mummy_mage": [16.5, 36.0], "mummy_knight": [18.0, 165.0], "mummy_boss": [18.8, 225.0], "mummy_high_wizard": [20.0, 300.0]}
	for id in original:
		var stats: Dictionary = combat.enemies[id]["stats"]
		var atk_ratio: float = float(stats["ATK"]) / float(original[id][0])
		var hp_ratio: float = float(stats["HP"]) / float(original[id][1])
		ctx.check("round 2: %s ATK %.2fx the original (1.8-2.3x) and HP %.2fx (0.75-1.0x)" % [id, atk_ratio, hp_ratio], atk_ratio >= 1.8 and atk_ratio <= 2.3 and hp_ratio >= 0.75 and hp_ratio <= 1.0)


## ai.skills (Boss 2026-11-18 option a): the loader rejects a bad list; each skill keeps its own cooldown; a monster
## without the list is untouched; the named move never goes on the wire (SimInput.encode keeps its 7 bytes).
func _check_skill_list(ctx) -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/combat.json"))
	raw["enemies"][ID]["ai"]["skills"] = [{"move": "no_such_move", "chance": 50}, {"move": "mummy_hw_bolt", "chance": 50}]
	var bad := CombatDataLoader.parse(JSON.stringify(raw))
	ctx.check("ai.skills: an unknown move and a move without a cooldown are load errors %s" % [bad.errors], bad.errors.size() == 2)
	var combat := CombatDataLoader.load_default()
	ctx.check("every other monster has no ai.skills (their AI is the old one-special path)", combat.enemies.keys().all(func(id): return id == ID or combat.enemies[id]["ai"].get("skills", []).is_empty()))
	var input := SimInput.new()
	input.special = true
	input.special_move = "mummy_hw_curse"
	ctx.check("special_move is copied with the input", input.duplicate_input().special_move == "mummy_hw_curse")
	var bytes: PackedByteArray = input.encode()
	ctx.check("special_move is not on the wire (still %d bytes, decodes to empty)" % SimInput.wire_size(), bytes.size() == SimInput.wire_size() and SimInput.decode(bytes).special_move == "")
	# Its own cooldown per skill: after a curse, the next special it starts is not the curse until 240 ticks pass.
	var world := SimWorld.new()
	world.half_width = 8.0
	world.half_depth = 4.5
	world.add_solid(AABB(Vector3(-8, -0.4, -4.5), Vector3(16, 0.4, 9)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(1, Vector3(-3.0, 0.05, 0.0), {"HP": 100000, "STAMINA": 1000})
	sim.fighters[1].hp = 100000.0
	sim.add_enemy(2, Vector3(5.0, 0.05, 0.0), ID, 4)
	var last := {}
	var too_soon := false
	for t in 60 * 40:
		sim.set_input(1, SimInput.new())
		sim.tick()
		for event in sim.events:
			if str(event["type"]) == "attack_started" and int(event["player"]) == 2:
				var move := str(event["move"])
				var cd := int(combat.moves[move].get("cooldown", 0))
				if cd > 0 and last.has(move) and t - int(last[move]) < cd:
					too_soon = true
				last[move] = t
	ctx.check("each skill waits out its own cooldown (no curse/starfall again before it is up)", not too_soon and last.has("mummy_hw_curse") and last.has("mummy_hw_starfall"))


## Boss 2026-11-18: the pair must not share a spot. The second boss stands BOSS_STEP further back, inside the board and
## clear of every solid, on each pyramid arena; the first boss keeps the old spot (goblin finale unchanged).
func _check_boss_spots(ctx, combat) -> void:
	var data = JourneyData.load_by_id("mummy_waves", combat.enemies.keys())
	for map_id in data.arena_maps:
		var map = MapLoader.load_by_id(str(map_id))
		var first: Vector3 = Journey.boss_spot(map, 0)
		var second: Vector3 = Journey.boss_spot(map, 1)
		var body := AABB(Vector3(second.x - 0.4, second.y + 0.05, second.z - 0.4), Vector3(0.8, 1.8, 0.8))
		var clear: bool = not map.solids.any(func(solid): return (solid["box"] as AABB).intersects(body))
		ctx.check("%s: boss 1 at the old spot %s, boss 2 at %s: >= 1.2 m apart, on the board, not in a solid" % [map_id, first, second],
			first.is_equal_approx(Journey.BOSS_SPOT) and first.distance_to(second) >= 1.2 and absf(second.x) <= map.half_width - 0.5 and absf(second.z) <= map.half_depth - 0.5 and clear)


## The pair clears with wave 9: that marks the pyramid boss beaten (the High Wizard is the zone boss's name).
func _check_zone(ctx) -> void:
	var saved = Zones._cache
	Zones._cache = null  # read the real data/world/zones.json (another test may have left its own zones cached)
	var zone: Dictionary = Zones.zone_of_journey("mummy_waves")
	ctx.check("the pyramid zone names the High Wizard as its boss (%s / %s)" % [zone.get("boss_en"), zone.get("boss_th")], str(zone.get("boss_en", "")) == "Mummy High Wizard" and str(zone.get("boss_th", "")) == "จอมเวทฟาโรห์")
	var holder := ProfileStub.new()
	ctx.check("clearing wave 9 of 9 marks the pyramid boss beaten; 8 of 9 does not", not Zones.on_battle_result(holder, "mummy_waves", 8, 9) and Zones.on_battle_result(holder, "mummy_waves", 9, 9) and bool(holder.unlocks.get(Zones.boss_key("pyramid"), false)))
	Zones._cache = saved


class ProfileStub:
	var unlocks: Dictionary = {}
