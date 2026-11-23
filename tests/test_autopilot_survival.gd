extends RefCounted
## Auto-pilot survival logic (Boss 2026-11-23: "our AI must not stand there while the boss hits it to death").
## logic/auto_pilot.gd survival functions, driven by the class pilot fields (data/classes/<id>.json pilot:
## telegraph_reaction, retreat_below, boss_kite_distance, stamina_reserve, support_boss_below, alone_caution).
## Locks: leaving a boss wind-up marker / marked ground with a high chance and always for a lethal blow, the low-HP
## kite of the back line, the boss-aware kite distance, the stamina reserve, Warding Veil going earlier on an ally a
## boss is on, determinism and checkpoint restore, and that a pilot profile WITHOUT the new fields behaves exactly as
## before. The behaviour measurement (hits avoided, survival time) is tools/balance/survival_probe.gd.

const Pilot := preload("res://logic/auto_pilot.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const GameSim := preload("res://logic/game_sim.gd")
const Deck := preload("res://logic/card_deck.gd")
const Combat := preload("res://logic/combat.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ClassSkillUse := preload("res://logic/class_skills/use_rules.gd")

const OldPilot := preload("res://tests/fixtures/auto_pilot_pre_survival.gd")  ## logic/auto_pilot.gd before the survival work (git fccc5079)
const SQUAD := ["sword_shield", "longbow", "magic"]


func run(ctx) -> void:
	var combat = CombatDataLoader.load_default()
	_data_checks(ctx)
	_telegraph_checks(ctx, combat)
	_area_checks(ctx, combat)
	_low_hp_checks(ctx, combat)
	_kite_checks(ctx, combat)
	_stamina_checks(ctx, combat)
	_support_checks(ctx, combat)
	_old_profile_checks(ctx, combat)
	_determinism_checks(ctx, combat)


static var _kit := {}


## One account's squad (starter races, starter gear) as the game builds it (logic/squad_member.gd).
static func _members() -> Array:
	if _kit.is_empty():
		var rules = preload("res://logic/item_rules_loader.gd").load_default()
		var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
		_kit = {"rules": rules, "camp": camp, "loot": preload("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(), rules.tiers.size())}
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var profile = preload("res://logic/profile.gd").new_player(_kit["rules"], _kit["camp"], r)
	for card in Deck.classes():
		Deck.set_race(profile.card_deck, card, Deck.starter_race(card))
	profile.unlocks["magic_runeborn"] = true
	return preload("res://logic/squad_member.gd").make_squad(preload("res://logic/run.gd").start(profile, _kit["camp"]), SQUAD)


## Open floor, the squad (race-less cards; their class pilot comes from race_state.class) and one enemy at `boss_at`.
static func _arena(combat, enemy_type: String, boss_at: Vector3, seed: int = 5) -> GameSim:
	var world := SimWorld.new()
	world.half_width = 16.0
	world.half_depth = 9.0
	world.add_solid(AABB(Vector3(-17.0, -1.0, -10.0), Vector3(34.0, 1.0, 20.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := GameSim.new(world, combat, rng)
	var spots := [Vector3(0.0, 0.05, 0.0), Vector3(-6.0, 0.05, -3.0), Vector3(-6.0, 0.05, 3.0)]
	var members: Array = _members()
	for i in 3:
		sim.add_player(i + 1, spots[i])
		sim.attach_run(i + 1, members[i], _kit["rules"], _kit["loot"])  # real squad cards: class pilot, race, class skills
		sim.set_class_style(i + 1, str(Deck.class_data(SQUAD[i]).get("weapon", "")))
		sim.fighters[i + 1].energy = sim.fighters[i + 1].max_energy()
	sim.add_enemy(100, boss_at, enemy_type, 1)
	return sim


static func _settle(sim) -> void:
	for id in sim.bodies:
		sim.bodies[id].grounded = true


## Puts the enemy into `move_id` at `frame`, facing `facing`.
static func _wind_up(sim, combat, move_id: String, frame: float, facing: Vector2i) -> void:
	var boss: Fighter = sim.fighters[100]
	boss.direction = facing
	boss.state = Fighter.State.ATTACK
	boss.move_id = move_id
	boss.move_frame = frame


func _data_checks(ctx) -> void:
	for c in ["sword_shield", "greatsword", "longbow", "magic"]:
		var p: Dictionary = Deck.class_data(c).get("pilot", {})
		ctx.check("%s pilot carries the survival fields" % c, Pilot._has_survival(p) and float(p.get("telegraph_reaction", 0.0)) >= 0.9 and float(p.get("retreat_below", 0.0)) > 0.0 and float(p.get("stamina_reserve", 0.0)) >= 20.0)
	for c in ["longbow", "magic"]:
		ctx.check("%s keeps a boss-aware kite distance wider than 3 m" % c, float(Deck.class_data(c)["pilot"].get("boss_kite_distance", 0.0)) > 3.0)
	ctx.check("magic wards earlier when a boss is on an ally (support_boss_below > the plain 0.6 rule)", float(Deck.class_data("magic")["pilot"].get("support_boss_below", 0.0)) > 0.6)


## (a) A card standing in a boss wind-up marker reacts with the data chance, always when the blow would kill, and
## moves OUT of the marker before it lands.
func _telegraph_checks(ctx, combat) -> void:
	var reacted := 0
	var trials := 200
	for t in trials:
		var sim := _arena(combat, "orc_warlock", Vector3(1.5, 0.05, 0.0))
		_settle(sim)
		_wind_up(sim, combat, "orc_warlock_cataclysm", 2.0, Vector2i(-1, 0))
		var mem := Pilot.new_memory(1000 + t)
		var input = Pilot.decide(sim, combat, 1, mem, 0)
		if input.move.length() > 0.1 or input.dodge or input.guard:
			reacted += 1
	var chance := float(Deck.class_data("sword_shield")["pilot"]["telegraph_reaction"])
	ctx.check("telegraphed boss blow: reacts %d / %d (data %.2f, old reaction 0.8)" % [reacted, trials, chance], reacted >= int(trials * (chance - 0.06)))
	# lethal: always react, whatever the roll
	var always := true
	for t in 60:
		var sim := _arena(combat, "orc_warlock", Vector3(1.5, 0.05, 0.0))
		_settle(sim)
		_wind_up(sim, combat, "orc_warlock_cataclysm", 2.0, Vector2i(-1, 0))
		sim.fighters[1].hp = 1.0
		var input = Pilot.decide(sim, combat, 1, Pilot.new_memory(2000 + t), 0)
		always = always and (input.move.length() > 0.1 or input.dodge)
	ctx.check("a blow that would kill is never ignored (60 rolls)", always)
	# drive it: the card standing in the Cataclysm circle is out (or invulnerable) when it lands
	var sim := _arena(combat, "orc_warlock", Vector3(1.5, 0.05, 0.0))
	_settle(sim)
	sim.fighters[1].hp = 1.0  # lethal: the react is certain, the test is about getting out in time
	var mem := Pilot.new_memory(9)
	var hit := false
	var shape := {}
	for tick in 40:
		if tick == 0:
			_wind_up(sim, combat, "orc_warlock_cataclysm", 0.0, Vector2i(-1, 0))
			sim._ai[100].cooldown = 999
			shape = Combat.telegraph_shape(100, sim.fighters, sim.bodies, combat)
		sim.set_input(1, SimInput.decode(Pilot.decide(sim, combat, 1, mem, tick).encode()))
		sim.set_input(2, SimInput.new())
		sim.set_input(3, SimInput.new())
		sim.tick()
		for event in sim.events:
			if str(event["type"]) == "hit" and int(event["target"]) == 1 and str(event["move"]) == "orc_warlock_cataclysm":
				hit = true
	ctx.check("the card started inside the Cataclysm marker", Pilot.in_telegraph(shape, Vector3(0.0, 0.05, 0.0)))
	ctx.check("and was not hit by it (left the circle or slid through it)", not hit)


## (f) Marked ground: leave it; walking toward a target never steps into one.
func _area_checks(ctx, combat) -> void:
	var sim := _arena(combat, "orc_warlock", Vector3(8.0, 0.05, 0.0))
	_settle(sim)
	sim.areas.append({"id": 77, "def": "hw_curse", "owner": 100, "team": "enemy", "move": "mummy_hw_curse", "pos": Vector3(-6.0, 0.05, -3.0), "radius": 2.0, "age": 30, "delay": 44, "active": 3, "hit": []})
	sim.fighters[2].hp = 1.0
	var input = Pilot.decide(sim, combat, 2, Pilot.new_memory(3), 0)
	ctx.check("a card on a curse mark about to burst moves out of it (%s)" % [input.move], input.move.length() > 0.5 or input.dodge)
	var step := Pilot._safe_move(sim, 1, Vector2(-1.0, -0.5).normalized())
	sim.areas[0]["pos"] = Vector3(-2.7, 0.05, -1.35)  # 3 m away, straight ahead of the step
	var safe := Pilot._safe_move(sim, 1, Vector2(-1.0, -0.5).normalized())
	var ahead := Vector3(safe.x, 0.0, safe.y) * 0.9
	ctx.check("a step toward a marked area turns aside or stops (%s)" % [safe], step.length() > 0.9 and (safe == Vector2.ZERO or Pilot._flat(ahead - Vector3(-2.7, 0.0, -1.35)).length() > 2.4))


## (b) Low HP: the back line stops trading and backs away from the nearest enemy; the focused front line guards.
func _low_hp_checks(ctx, combat) -> void:
	var sim := _arena(combat, "orc_grunt", Vector3(-2.0, 0.05, -3.0))  # 4 m from the longbow (outside Vault Shot's 3 m)
	_settle(sim)
	var bow: Fighter = sim.fighters[2]
	bow.hp = bow.max_hp() * 0.9
	var healthy = Pilot.decide(sim, combat, 2, Pilot.new_memory(4), 0)
	bow.hp = bow.max_hp() * 0.2
	var hurt = Pilot.decide(sim, combat, 2, Pilot.new_memory(4), 0)
	var away := Vector2(-1.0, 0.0)
	ctx.check("a healthy longbow 3 m from a grunt shoots (no retreat)", healthy.move.dot(away) <= 0.5)
	ctx.check("a longbow under retreat_below backs away from it (%s)" % [hurt.move], hurt.move.dot(away) > 0.3 and not hurt.light and not hurt.heavy)
	# front line, hurt, the Warlock idle 1.5 m away and on it: guard instead of swinging
	var sim2 := _arena(combat, "orc_warlock", Vector3(1.5, 0.05, 0.0))
	_settle(sim2)
	sim2.fighters[2].hp = 0.0
	sim2.fighters[2].state = Fighter.State.DEAD
	sim2.fighters[3].hp = 0.0
	sim2.fighters[3].state = Fighter.State.DEAD
	sim2.fighters[100].direction = Vector2i(-1, 0)
	var sword: Fighter = sim2.fighters[1]
	sword.hp = sword.max_hp() * 0.2
	var guarded = Pilot.decide(sim2, combat, 1, Pilot.new_memory(5), 0)
	var iron: int = sword.skill_state["skills"].find("iron_guard")
	ctx.check("a hurt sword card the boss is on guards (or takes Iron Guard) instead of swinging", (guarded.guard or guarded.skill_slot == iron) and not guarded.light and not guarded.heavy)
	sword.skill_state["cd"]["iron_guard"] = 999999  # Iron Guard on cooldown: the plain guard
	var plain = Pilot.decide(sim2, combat, 1, Pilot.new_memory(5), 0)
	ctx.check("with Iron Guard on cooldown it holds a plain guard", plain.guard and not plain.light and not plain.heavy)
	sim2.fighters[100].state = Fighter.State.ATTACK
	sim2.fighters[100].move_id = "orc_warlock_cleave"
	sim2.fighters[100].move_frame = 15.0  # recovering
	var opening = Pilot.decide(sim2, combat, 1, Pilot.new_memory(5), 0)
	ctx.check("and swings back while the boss recovers", not opening.guard)


## (c) A boss on a back-line card: it keeps boss_kite_distance (wider than the plain 3 m kite) and circles.
func _kite_checks(ctx, combat) -> void:
	var sim := _arena(combat, "orc_warlock", Vector3(-2.0, 0.05, 3.0))  # 4 m from the magic card (id 3): it targets ranged first
	_settle(sim)
	var brain = sim._ai[100]
	var target: int = brain.pick_target(sim.fighters[100], sim.bodies[100], sim.bodies, sim.fighters)
	ctx.check("the Warlock targets a back-line card (ranged_first) -> %d" % target, target == 2 or target == 3)
	var d: float = Pilot._flat(sim.bodies[100].position - sim.bodies[target].position).length()
	var input = Pilot.decide(sim, combat, target, Pilot.new_memory(6), 0)
	var away: Vector2 = Pilot._flat(sim.bodies[target].position - sim.bodies[100].position).normalized()
	ctx.check("a back-line card the boss is on, %.1f m away (> 3 m old kite), moves away (%s)" % [d, input.move], d > 3.0 and input.move.dot(away) > 0.3)
	var other := 5 - target
	var calm = Pilot.decide(sim, combat, other, Pilot.new_memory(6), 0)
	ctx.check("the other back-line card (not the boss's target, healthy) does not flee", calm.move.dot(Pilot._flat(sim.bodies[other].position - sim.bodies[100].position).normalized()) < 0.3)
	sim.bodies[target].position = sim.bodies[100].position + Vector3(away.x, 0.0, away.y) * 7.0
	var far = Pilot.decide(sim, combat, target, Pilot.new_memory(6), 0)
	ctx.check("beyond boss_kite_distance it fights again (no flee)", far.move.dot(away) < 0.3)


## (d) Stamina: a guard needing more stamina than left is replaced by a step away; no attack skill under the reserve
## with a boss near; no run under the reserve.
func _stamina_checks(ctx, combat) -> void:
	var sim := _arena(combat, "orc_grunt", Vector3(1.2, 0.05, 0.0))
	_settle(sim)
	var grunt: Fighter = sim.fighters[100]
	grunt.direction = Vector2i(-1, 0)
	var grunt_move := str(combat.styles[grunt.style]["ground_light"])
	_wind_up(sim, combat, grunt_move, 1.0, Vector2i(-1, 0))
	var me: Fighter = sim.fighters[1]
	var cost := Pilot._guard_cost(combat, combat.moves[grunt_move])
	me.energy = cost + 5.0
	var with := Pilot.decide(sim, combat, 1, Pilot.new_memory(1), 0, 1.0)
	me.energy = cost - 1.0
	var without := Pilot.decide(sim, combat, 1, Pilot.new_memory(1), 0, 1.0)
	ctx.check("guards a blow it can pay for (cost %.0f)" % cost, with.guard)
	ctx.check("short of the guard cost: steps away instead of a guard that breaks", not without.guard and without.move.dot(Vector2(-1.0, 0.0)) > 0.5)
	var profile: Dictionary = Deck.class_data("sword_shield")["pilot"]
	var sim2 := _arena(combat, "orc_warlock", Vector3(3.0, 0.05, 0.0))
	sim2.fighters[1].energy = float(profile["stamina_reserve"]) + 5.0
	ctx.check("a 14-stamina skill that would leave less than the reserve waits (boss near)", Pilot._short_of_reserve(sim2, 1, sim2.fighters[1], profile, "shield_rush"))
	sim2.fighters[1].energy = 100.0
	ctx.check("with a full bar it may cast", not Pilot._short_of_reserve(sim2, 1, sim2.fighters[1], profile, "shield_rush"))
	sim2.bodies[100].position = Vector3(12.0, 0.05, 0.0)
	sim2.fighters[1].energy = float(profile["stamina_reserve"]) + 5.0
	ctx.check("no boss near: the reserve does not hold skills", not Pilot._short_of_reserve(sim2, 1, sim2.fighters[1], profile, "shield_rush"))
	# no run below the reserve while walking in
	var sim3 := _arena(combat, "orc_warlock", Vector3(14.0, 0.05, 0.0))
	_settle(sim3)
	sim3.fighters[1].energy = float(profile["stamina_reserve"]) + 2.0
	var walk = Pilot.decide(sim3, combat, 1, Pilot.new_memory(2), 1)
	ctx.check("walking in with stamina at the reserve: no run (%s run=%s)" % [walk.move, walk.run], walk.move.length() > 0.5 and not walk.run)


## (e) Warding Veil goes on an ally a boss is on at support_boss_below (0.8), earlier than the plain 0.6 rule.
func _support_checks(ctx, combat) -> void:
	var sim := _arena(combat, "orc_warlock", Vector3(1.4, 0.05, 0.0))
	sim.fighters[100].direction = Vector2i(-1, 0)
	var sword: Fighter = sim.fighters[1]
	sword.hp = sword.max_hp() * 0.7
	sim.bodies[3].position = Vector3(-4.0, 0.05, 0.0)
	ctx.check("the plain 0.6 rule would not ward the sword card at 70%", ClassSkillUse.hurt_ally(sim, 3, {"below": 0.6, "range": 9.0, "self": true, "most_attacked": true}) == -1)
	ctx.check("pilot_support picks it (boss on it, under 0.8)", Pilot.support_choice(sim, 3, 9.0) == 1)
	ctx.check("the Warding Veil use rule chooses it", int(ClassSkillUse.choose(sim, 3, "warding_veil", 100).get("target", -1)) == 1)
	sword.hp = sword.max_hp() * 0.95
	ctx.check("a healthy ally is not warded", Pilot.support_choice(sim, 3, 9.0) == -1)
	sword.hp = sword.max_hp() * 0.7
	sim.bodies[100].position = Vector3(8.0, 0.05, 6.0)  # boss far and on someone else
	var on := Pilot._boss_on_me(sim, 1)
	ctx.check("no boss on the hurt ally: no early ward (boss on %d)" % on, on == 1 or Pilot.support_choice(sim, 3, 9.0) == -1)
	var sim2 := _arena(combat, "orc_warlock", Vector3(-3.0, 0.05, 3.0))  # nearest ranged = magic (id 3), boss on it
	sim2.fighters[3].hp = sim2.fighters[3].max_hp() * 0.7
	ctx.check("the magic card wards itself when the boss is on it", Pilot.support_choice(sim2, 3, 9.0) == 3)


## A class pilot profile without the survival fields behaves exactly as before (same inputs, tick by tick).
func _old_profile_checks(ctx, combat) -> void:
	var saved := {}
	for c in ["sword_shield", "longbow", "magic"]:
		var p: Dictionary = Deck.class_data(c)["pilot"]
		saved[c] = p.duplicate()
		for f in Pilot.SURVIVAL_FIELDS:
			p.erase(f)
	var a := _trace(combat, 11, 900)
	var old := _trace(combat, 11, 900, -1, OldPilot)
	for c in saved:
		var p: Dictionary = Deck.class_data(c)["pilot"]
		p.clear()
		p.merge(saved[c])
	ctx.check("profiles without the new fields are not in survival mode", not Pilot._has_survival({"reaction": 0.8, "target": "peel"}))
	ctx.check("old profiles: a fight runs (%d inputs)" % a["inputs"], a["inputs"] > 100)
	ctx.check("old profiles: tick-for-tick the same inputs as the pre-change pilot (tests/fixtures/auto_pilot_pre_survival.gd)", a["digest"] == old["digest"])
	var now := _trace(combat, 11, 900)
	ctx.check("with the survival fields the pilot plays differently (the fields are live)", now["digest"] != old["digest"])


## Determinism: the same seed gives the same input stream; a checkpoint restore mid-fight continues identically.
func _determinism_checks(ctx, combat) -> void:
	var a := _trace(combat, 21, 900)
	var b := _trace(combat, 21, 900)
	var c := _trace(combat, 21, 900, 400)
	ctx.check("same seed, same pilot inputs (%d)" % a["inputs"], a["digest"] == b["digest"])
	ctx.check("restored from a checkpoint at tick 400 (pilot memory carried): same inputs", a["digest"] == c["digest"])


## The squad vs the Warlock for `ticks`, the pilot driving; HP topped up so the fight keeps going. restore_at >= 0:
## snapshot the sim there and continue in a NEW sim (the pilot memory is the caller's, as LocalSession/Room keep it).
static func _trace(combat, seed: int, ticks: int, restore_at: int = -1, pilot = Pilot) -> Dictionary:
	var sim := _arena(combat, "orc_warlock", Vector3(4.0, 0.05, 0.0), seed)
	var mems := {}
	for id in [1, 2, 3]:
		mems[id] = pilot.new_memory(id * 7919 + seed)
	var trace := PackedStringArray()
	var inputs := 0
	for t in ticks:
		if t == restore_at:
			var saved := sim.snapshot()
			var fresh := _arena(combat, "orc_warlock", Vector3(4.0, 0.05, 0.0), 999)
			if not fresh.restore(saved, _kit["camp"]):
				return {"digest": "restore failed", "inputs": 0}
			sim = fresh
		for id in [1, 2, 3]:
			var f: Fighter = sim.fighters[id]
			f.hp = maxf(f.hp, f.max_hp() * 0.25 if (t / 120) % 2 == 0 else f.max_hp())
			var input = pilot.decide(sim, combat, id, mems[id], t)
			var wire: PackedByteArray = input.encode()
			trace.append("%d:%d:%s" % [t, id, wire.hex_encode()])
			if input.move.length() > 0.1 or input.light or input.heavy or input.guard or input.dodge or input.skill_slot >= 0:
				inputs += 1
			sim.set_input(id, SimInput.decode(input.encode()))
		sim.tick()
	return {"digest": str(hash("|".join(trace))), "inputs": inputs}
