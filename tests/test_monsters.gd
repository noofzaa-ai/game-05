extends RefCounted
## Tests monsters with their own models and animation sets (the goblin first): its data, its numbers
## against the starter player, its hit-and-run AI, and the view (textured material kept under the
## state tint, ink outline on the skinned mesh, clips found and played, clean fallbacks).
## (Run `godot --headless --path . --import` once after changing a .glb.)

const AnimationSet := preload("res://client/animation_set.gd")
const Combat := preload("res://logic/combat.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Fighter := preload("res://logic/fighter.gd")
const FighterView := preload("res://client/fighter_view.gd")
const GameSim := preload("res://logic/game_sim.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const SimBody := preload("res://logic/sim_body.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const FAMILY := ["goblin", "goblin_archer", "goblin_mage", "goblin_knight"]  ## the chief is the boss
const GOBLIN_MODEL := "res://art/monsters/goblin/goblin.glb"
const GOBLIN_SET := "res://art/animations/goblin.glb"

var _data


func run(ctx) -> void:
	_data = CombatDataLoader.load_default()
	ctx.check("the combat data with the goblin is valid %s" % [_data.errors], _data.is_valid())
	_test_goblin_data(ctx)
	_test_goblin_balance(ctx)
	_test_goblin_ai(ctx)
	_test_goblin_spawns(ctx)
	_test_goblin_flee(ctx)
	_test_goblin_view(ctx)
	_test_fallbacks(ctx)
	_test_family_views(ctx)


func _test_goblin_data(ctx) -> void:
	ctx.check("a goblin monster exists", _data.enemies.has("goblin"))
	if not _data.enemies.has("goblin"):
		return
	var goblin: Dictionary = _data.enemies["goblin"]
	ctx.check("it uses its own model, smaller than the player (%.2f m)" % goblin["model_height"], goblin["model"] == GOBLIN_MODEL and ResourceLoader.exists(GOBLIN_MODEL) and goblin["model_height"] > 0.9 and goblin["model_height"] < 1.1)
	ctx.check("it names its animation set and a clip per move", goblin["animations"] == GOBLIN_SET and goblin["clips"].get("goblin_jab") == "attack_1" and goblin["clips"].get("goblin_lunge") == "attack_2")
	var style: Dictionary = _data.styles[goblin["style"]]
	ctx.check("its moves are its own (not the player's dagger)", style["ground_light"] == "goblin_jab" and style["ground_heavy"] == "goblin_lunge" and style["special"] == "goblin_lunge")
	var jab: Dictionary = _data.moves["goblin_jab"]
	var lunge: Dictionary = _data.moves["goblin_lunge"]
	ctx.check("the jab is quick (%d startup), the lunge telegraphed (%d startup)" % [jab["startup"], lunge["startup"]], jab["startup"] <= 12 and lunge["telegraph"] and lunge["startup"] >= 25)
	ctx.check("both moves move only as their clips do (no surge); the lunge reaches further and is rare", jab["advance"] == 0.0 and lunge["advance"] == 0.0 and lunge["hit_offset"].x > jab["hit_offset"].x and lunge["cooldown"] >= 240)
	ctx.check("its hurt box is its own 0.98 m body", goblin["body_height"] == 0.98 and _data.enemies["dummy_grunt"]["body_height"] == 1.8)
	ctx.check("it is cowardly: it flees below 30% health for a moment", goblin["ai"]["flee_hp"] > 0.2 and goblin["ai"]["flee_hp"] < 0.4 and goblin["ai"]["flee_ticks"] > 0)
	var chief: Dictionary = _data.enemies["goblin_chief"]
	ctx.check("the Goblin Chief uses its own crowned model, untinted, its body 1.6-1.8x a goblin's", chief["model"] == "res://art/monsters/goblin_chief/goblin_chief.glb" and ResourceLoader.exists(chief["model"]) and chief["model_tint"] == Color.WHITE and chief["body_height"] / goblin["body_height"] >= 1.6 and chief["body_height"] / goblin["body_height"] <= 1.8 and chief["model_height"] > chief["body_height"])
	ctx.check("and much tougher: more HP, poise, no fleeing", chief["stats"]["HP"] >= goblin["stats"]["HP"] * 4.0 and chief["poise"] > 0.0 and chief["ai"]["flee_hp"] == 0.0)
	ctx.check("it hops back after attacking", goblin["ai"]["retreat_ticks"] > 0)
	# Broken animation data is reported.
	var root: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatDataLoader.DATA_PATH))
	root["enemies"]["goblin"]["animations"] = "art/goblin.json"
	root["enemies"]["goblin"]["clips"] = {"no_such_move": "attack_1"}
	root["enemies"]["goblin"]["ai"]["retreat_ticks"] = -1
	root["enemies"]["goblin"]["ai"]["flee_hp"] = 1.5
	root["enemies"]["goblin"]["body_height"] = 0
	ctx.check("a bad animation path, clip move, retreat, flee fraction and body height are reported", CombatDataLoader.parse(JSON.stringify(root)).errors.size() == 5)
	# The animator's clips: when the set exists, every clip the goblin plays is in it and the attacks
	# have their marks. (Without the file the goblin is a static model: see _test_fallbacks.)
	AnimationSet.clear_cache()
	var clips = AnimationSet.load_file(GOBLIN_SET)
	if clips == null:
		ctx.check("(goblin clips not built yet: static model)", true)
		return
	var missing := []
	for clip in ["idle", "run", "attack_1", "attack_2", "hit", "death"]:
		if not clips.has_clip(clip):
			missing.append(clip)
	ctx.check("the goblin set has idle, run, attack_1/2, hit and death (missing %s)" % [missing], missing.is_empty())
	ctx.check("idle and run loop, death does not", clips.is_looping("idle") and clips.is_looping("run") and not clips.is_looping("death"))
	for clip in ["attack_1", "attack_2"]:
		if clips.has_clip(clip):
			var windup: float = clips.attack_time(clip, "strike", 0.0)
			var strike: float = clips.attack_time(clip, "recover", 0.0)
			ctx.check("%s has its marks (%.2f / %.2f / %.2f s)" % [clip, windup, strike, clips.length(clip)], windup > 0.0 and strike > windup and clips.length(clip) > strike)


## Against the starter gear (ATK 135, DEF 92, HP 1120): a goblin is a light pack enemy, so a jab is
## a nibble and the lunge hurts about as much as a grunt's heavy; it dies to about one combo.
func _test_goblin_balance(ctx) -> void:
	var rng := RandomNumberGenerator.new()
	var player := Fighter.new()
	player.stats = _data.full_stats({"HP": 1120, "ATK": 135, "DEF": 92, "CRIRATE": 0})
	var goblin := Fighter.new()
	goblin.stats = _data.enemy_stats("goblin")
	goblin.stats["CRIRATE"] = 0.0
	var jab := float(Combat.compute_damage(goblin, player, _data.moves["goblin_jab"], _data, rng)["damage"]) / 1120.0
	var lunge := float(Combat.compute_damage(goblin, player, _data.moves["goblin_lunge"], _data, rng)["damage"]) / 1120.0
	ctx.check("a goblin jab takes 3-5%% of the starter player's HP (%.1f%%), the lunge 9-14%% (%.1f%%)" % [jab * 100.0, lunge * 100.0], jab >= 0.03 and jab <= 0.05 and lunge >= 0.09 and lunge <= 0.14)
	var attacker := Fighter.new()
	attacker.stats = _data.full_stats({"ATK": 135, "CRIRATE": 0})
	var hits := ceili(float(goblin.stats["HP"]) / float(Combat.compute_damage(attacker, goblin, _data.moves["blade_light_1"], _data, rng)["damage"]))
	var grunt := Fighter.new()
	grunt.stats = _data.enemy_stats("dummy_grunt")
	var grunt_hits := ceili(float(grunt.stats["HP"]) / float(Combat.compute_damage(attacker, grunt, _data.moves["blade_light_1"], _data, rng)["damage"]))
	ctx.check("a goblin dies to about one sword combo (%d light hits; grunt %d)" % [hits, grunt_hits], hits >= 3 and hits <= 5 and hits < grunt_hits)
	var stats: Dictionary = _data.enemies["goblin"]["stats"]
	var speed := 3.8 * (1.0 + float(stats["MOVESPD"]) / 100.0)
	ctx.check("it runs at %.2f m/s: faster than a grunt, slower than the player, inside the run clip's 1.46-3.4 m/s" % speed, speed > 1.46 and speed < 3.4 and stats["MOVESPD"] > _data.enemies["dummy_grunt"]["stats"]["MOVESPD"])


## A goblin against a player who stands still: it stabs, then backs off instead of standing there.
func _test_goblin_ai(ctx) -> void:
	var world := SimWorld.new()
	world.half_width = 50.0
	world.half_depth = 10.0
	world.add_solid(AABB(Vector3(-60, -0.4, -12), Vector3(120, 0.4, 24)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sim := GameSim.new(world, _data, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"HP": 100000, "DEF": 0, "STAMINA": 1000})
	sim.add_enemy(10, Vector3(3.0, 0.05, 0), "goblin")
	var attacks := {}
	var hits := {}
	var current_move := ""
	var retreats := 0
	var ends := 0
	var was_attacking := false
	var end_distance := -1.0
	var since_end := 0
	for i in 1800:
		sim.tick()
		for event in sim.events:
			if event["type"] == "attack_started" and event["player"] == 10:
				attacks[event["move"]] = attacks.get(event["move"], 0) + 1
				current_move = event["move"]
			if event["type"] == "hit" and event["attacker"] == 10:
				hits[current_move] = hits.get(current_move, 0) + 1
		var goblin: Fighter = sim.fighters[10]
		var distance: float = sim.bodies[10].position.distance_to(sim.bodies[1].position)
		if was_attacking and goblin.state != Fighter.State.ATTACK:
			ends += 1
			end_distance = distance
			since_end = 0
		was_attacking = goblin.state == Fighter.State.ATTACK
		if end_distance >= 0.0:
			since_end += 1
			if since_end == 24:
				if distance > end_distance + 0.6:
					retreats += 1
				end_distance = -1.0
	var total: int = attacks.values().reduce(func(a, b): return a + b, 0)
	ctx.check("in 30 s it attacks often (%s)" % [attacks], total >= 8 and attacks.has("goblin_jab"))
	ctx.check("and sometimes lunges (%d)" % attacks.get("goblin_lunge", 0), attacks.get("goblin_lunge", 0) >= 1)
	ctx.check("from its striking spot both moves land on a player standing still (hits %s)" % [hits], hits.get("goblin_jab", 0) * 4 >= attacks.get("goblin_jab", 0) * 3 and hits.get("goblin_lunge", 0) >= attacks.get("goblin_lunge", 0))
	ctx.check("after most attacks it hops back at least 0.6 m (%d of %d)" % [retreats, ends], ends > 0 and retreats * 4 >= ends * 3)


## Boss 2026-10-10: goblins only, then the goblin family with the spawn plan the Boss approved the
## same day (placed 2026-10-12): stages 1-2 plain goblins, the archer from stage 3, the mage from
## stage 5, the knight from stage 6, mixed after that; the boss is the Goblin Chief with goblins, an
## archer and a mage. Sunward Valley stays plain goblins. The old monsters stay defined (unused).
func _test_goblin_spawns(ctx) -> void:
	var only_goblins := true
	var maps := []
	for id in ["sunward_valley", "ink_garden", "shrine_wall", "brush_ring"]:
		var map = MapLoader.load_by_id(id)
		maps.append("%s %d" % [id, map.enemy_spawns.size()])
		for spawn in map.enemy_spawns:
			var family: bool = FAMILY.has(spawn["type"]) and (id != "sunward_valley" or spawn["type"] == "goblin")
			only_goblins = only_goblins and (family or (id == "brush_ring" and spawn["type"] == "goblin_chief"))
	ctx.check("every map spawns only the goblin family (the chief only in the boss ring, Sunward Valley plain goblins) %s" % [maps], only_goblins)
	ctx.check("the practice field stays empty", MapLoader.load_by_id("practice_field").enemy_spawns.is_empty())
	ctx.check("the old monsters are still defined", _data.enemies.has("dummy_grunt") and _data.enemies.has("brute") and _data.enemies.has("charger"))
	var journey = JourneyData.load_by_id("ink_road", _data.enemies.keys())
	ctx.check("the journey data with goblins is valid %s" % [journey.errors], journey.is_valid())
	var fights_ok := true
	var threats := []
	for stage in journey.stages:
		for fight in [stage, stage.get("challenge", {})]:
			for enemy in fight.get("enemies", []):
				fights_ok = fights_ok and (FAMILY.has(enemy["type"]) or (enemy["type"] == "goblin_chief" and bool(enemy.get("boss", false))))
		threats.append(snappedf(Journey.threat(stage, _data, journey.boss), 0.01))
	ctx.check("every journey fight is the goblin family; the boss is the Goblin Chief (threat by stage %s)" % [threats], fights_ok and journey.stages[11]["enemies"][0]["type"] == "goblin_chief")
	var first_seen := {}
	for index in journey.stages.size():
		for enemy in journey.stages[index]["enemies"]:
			if not first_seen.has(enemy["type"]):
				first_seen[enemy["type"]] = index + 1
	var boss_types: Array = journey.stages[11]["enemies"].map(func(e): return e["type"])
	ctx.check("the plan: archer first in stage 3, mage in 5, knight in 6; the boss brings goblins, an archer and a mage (%s)" % [first_seen], first_seen.get("goblin") == 1 and first_seen.get("goblin_archer") == 3 and first_seen.get("goblin_mage") == 5 and first_seen.get("goblin_knight") == 6 and boss_types.has("goblin") and boss_types.has("goblin_archer") and boss_types.has("goblin_mage"))
	var first := 0
	for enemy in journey.stages[0]["enemies"]:
		first += int(enemy["count"]) if enemy["type"] == "goblin" else 0
	ctx.check("the first journey stage is a goblin pack (%d)" % first, first >= 3)


## A goblin brought below 30% health runs away (running), then comes back to fight.
func _test_goblin_flee(ctx) -> void:
	var world := SimWorld.new()
	world.half_width = 50.0
	world.half_depth = 10.0
	world.add_solid(AABB(Vector3(-60, -0.4, -12), Vector3(120, 0.4, 24)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var sim := GameSim.new(world, _data, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"HP": 100000, "DEF": 0, "STAMINA": 1000})
	sim.add_enemy(10, Vector3(1.5, 0.05, 0), "goblin")
	ctx.check("its body in the rules is 0.98 m tall (hits above it miss)", is_equal_approx(sim.bodies[10].aabb().size.y, 0.98) and is_equal_approx(sim.bodies[1].aabb().size.y, SimBody.HEIGHT))
	for i in 30:
		sim.tick()
	sim.fighters[10].hp = sim.fighters[10].max_hp() * 0.25
	var start: float = sim.bodies[10].position.distance_to(sim.bodies[1].position)
	var farthest := start
	var ran := false
	for i in 90:
		sim.tick()
		farthest = maxf(farthest, sim.bodies[10].position.distance_to(sim.bodies[1].position))
		ran = ran or sim.fighters[10].running
	var closest := farthest
	for i in 600:
		sim.tick()
		closest = minf(closest, sim.bodies[10].position.distance_to(sim.bodies[1].position))
	ctx.check("below 30%% health it runs away (%.1f m -> %.1f m)" % [start, farthest], farthest > start + 3.0 and ran)
	ctx.check("and then comes back to fight (%.1f m)" % closest, closest < 2.0)


func _test_goblin_view(ctx) -> void:
	var view := _monster_view(GOBLIN_MODEL, GOBLIN_SET, true)
	var meshes: Array = view.find_children("*", "MeshInstance3D", true, false)
	var body: MeshInstance3D = null
	for mesh in meshes:
		if mesh.name == "goblin":
			body = mesh
	ctx.check("the goblin view shows its model", body != null)
	if body == null:
		view.free()
		return
	var material = body.get_surface_override_material(0)
	var original = body.mesh.surface_get_material(0)
	ctx.check("it keeps its own textured material, as a per-instance copy", material is BaseMaterial3D and material != original and material.albedo_texture != null and material.albedo_texture == original.albedo_texture and body.material_override == null)
	var outline: MeshInstance3D = body.get_node_or_null("InkOutline")
	ctx.check("its skinned body has an ink outline moved by the same skeleton", outline != null and outline.skin == body.skin and not outline.skeleton.is_empty() and outline.get_node(outline.skeleton) is Skeleton3D)
	var fighter := Fighter.new()
	fighter.team = "enemy"
	fighter.direction = Vector2i(0, 1)
	var sim_body := SimBody.new()
	sim_body.grounded = true
	view.show_state(sim_body, fighter, _data)
	var normal: Color = material.albedo_color
	fighter.state = Fighter.State.HITSTUN
	view.show_state(sim_body, fighter, _data)
	ctx.check("a hit tints by multiplying its color; the texture stays (%s)" % material.albedo_color, material.albedo_color.g < normal.g and material.albedo_color.r <= normal.r and material.albedo_texture == original.albedo_texture)
	ctx.check("the shared model material is untouched", original.albedo_color == normal)
	fighter.state = Fighter.State.IDLE
	view.show_state(sim_body, fighter, _data)
	ctx.check("the tint clears afterwards", material.albedo_color.is_equal_approx(normal))
	var clips = view.monster_animation()
	if clips == null:
		ctx.check("(no goblin clips yet: the view is static)", AnimationSet.load_file(GOBLIN_SET) == null)
		view.free()
		return
	ctx.check("the view found the goblin's animation set", clips.has_clip("attack_1"))
	var skeleton: Skeleton3D = view.find_children("*", "Skeleton3D", true, false)[0]
	var hips := skeleton.find_bone("hips")
	fighter.state = Fighter.State.ATTACK
	fighter.move_id = "goblin_lunge"
	fighter.move_frame = 0.0
	view.show_state(sim_body, fighter, _data)
	var start := skeleton.get_bone_pose_position(hips)
	var start_turn := skeleton.get_bone_pose_rotation(skeleton.find_bone("spine")) if skeleton.find_bone("spine") >= 0 else Quaternion()
	fighter.move_frame = float(_data.moves["goblin_lunge"]["startup"]) + 5.0
	view.show_state(sim_body, fighter, _data)
	var moved := skeleton.get_bone_pose_position(hips).distance_to(start) > 0.001 or not skeleton.get_bone_pose_rotation(skeleton.find_bone("spine")).is_equal_approx(start_turn)
	ctx.check("the lunge plays attack_2 in step with the move (the hips move)", moved)
	fighter.state = Fighter.State.DEAD
	fighter.state_ticks = 0
	view.show_state(sim_body, fighter, _data)
	var dead_start := skeleton.get_bone_pose_position(hips)
	view._process(3.0)
	ctx.check("death plays (and holds its last pose)", skeleton.get_bone_pose_position(hips).distance_to(dead_start) > 0.001)
	view.free()


func _test_fallbacks(ctx) -> void:
	# No animation set: the goblin is a static model that still keeps its texture.
	var still := _monster_view(GOBLIN_MODEL, "res://art/animations/no_such_monster.glb", false)
	ctx.check("without an animation set the goblin is a static model", still.monster_animation() == null and not still.find_children("*", "MeshInstance3D", true, false).is_empty())
	ctx.check("a monster model has the ink outline on every stage (not only ink stages)", not still.ink_outline and not still.find_children("InkOutline", "MeshInstance3D", true, false).is_empty())
	var fighter := Fighter.new()
	fighter.team = "enemy"
	var small := SimBody.new()
	small.height = 0.98
	still._build_health_bar()
	still._build_warning_sign()
	still.show_state(small, fighter, _data)
	ctx.check("its health bar and warning sit above its own 0.98 m body (%.2f, %.2f)" % [still._bar_root.position.y, still._warning.position.y], is_equal_approx(still._bar_root.position.y, 1.38) and is_equal_approx(still._warning.position.y, 1.98))
	still.free()
	# The flat-colored monster_01 still takes the shared state color, as before.
	var grunt := _monster_view("res://art/monsters/monster_01.glb", "", false)
	var flat := true
	for mesh in grunt.find_children("*", "MeshInstance3D", true, false):
		flat = flat and mesh.material_override is StandardMaterial3D and mesh.material_override.albedo_color.is_equal_approx(Color(0.75, 0.3, 0.3))
	ctx.check("monster_01 keeps its flat state-color material", flat and grunt.monster_animation() == null)
	grunt.free()


## The goblin family on their own models: each is drawn at its data size, finds clips (its own set,
## or the goblin clips its model carries as a stand-in, with the marks next to it), plays a stand-in
## clip for a move whose own clip is not made yet, and runs with planted feet.
func _test_family_views(ctx) -> void:
	for id in ["goblin_archer", "goblin_mage", "goblin_knight", "goblin_chief"]:
		var definition: Dictionary = _data.enemies[id]
		var view := _family_view(id)
		var model: Node3D = view._turn.get_child(0) if view._turn != null else null
		ctx.check("%s: its own model is drawn %.2f m tall (scale %.3f)" % [id, definition["model_height"], view._fit], model != null and view._fit > 0.9 and view._fit < 1.9)
		var clips = view.monster_animation()
		ctx.check("%s: it has clips to play (idle, run, hit, death)" % id, clips != null and clips.has_clip("idle") and clips.has_clip("run") and clips.has_clip("death"))
		if clips == null:
			view.free()
			continue
		var body := SimBody.new()
		body.grounded = true
		for move_id in definition["clips"]:
			var fighter := Fighter.new()
			fighter.team = "enemy"
			fighter.state = Fighter.State.ATTACK
			fighter.move_id = move_id
			fighter.move_frame = 1.0
			view.show_state(body, fighter, _data)
			ctx.check("%s: its %s plays its own clip '%s'" % [id, move_id, view._anim_clip], view._anim_clip == definition["clips"][move_id])
		var struck := Fighter.new()
		struck.team = "enemy"
		struck.state = Fighter.State.HITSTUN
		view.show_state(body, struck, _data)
		var hit_plays: bool = view._anim_clip == "hit"
		struck.state = Fighter.State.DEAD
		view.show_state(body, struck, _data)
		ctx.check("%s: hit plays when struck and death when it dies" % id, hit_plays and view._anim_clip == "death")
		# Idle and run fade into each other instead of popping.
		var walker := Fighter.new()
		walker.team = "enemy"
		view.show_state(body, walker, _data)
		view._process(0.5)
		body.velocity = Vector3(2.0, 0.0, 0.0)
		view.show_state(body, walker, _data)
		var fading: bool = view._anim_clip == "run" and view._from_clip == "idle" and view._blend < 0.01
		view._process(0.05)
		var midway: bool = view._blend > 0.2 and view._blend < 0.5
		view._process(0.2)
		ctx.check("%s: idle fades into run over %.2f s" % [id, FighterView.MONSTER_BLEND_TIME], fading and midway and view._blend == 1.0)
		body.velocity = Vector3.ZERO
		var speed := 3.8 * (1.0 + float(definition["stats"]["MOVESPD"]) / 100.0)
		var rate: float = speed / (FighterView.MONSTER_RUN_SPEED * view._fit)
		ctx.check("%s: its run clip plays at %.2fx for %.2f m/s, inside 0.6-1.4x (feet planted)" % [id, rate, speed], rate >= 0.6 and rate <= 1.4)
		view.free()
	# The archer's arrow is on the string only from the start of a shot until it is loosed.
	var archer := _family_view("goblin_archer")
	var nock: Node3D = archer._nock
	var shooter := Fighter.new()
	shooter.team = "enemy"
	var body := SimBody.new()
	body.grounded = true
	archer.show_state(body, shooter, _data)
	var idle_hidden := nock != null and not nock.visible
	shooter.state = Fighter.State.ATTACK
	shooter.move_id = "goblin_archer_shot"
	shooter.move_frame = 10.0
	archer.show_state(body, shooter, _data)
	var drawn := nock != null and nock.visible
	shooter.move_frame = float(_data.moves["goblin_archer_shot"]["startup"]) + 1.0
	archer.show_state(body, shooter, _data)
	ctx.check("the archer's arrow shows while it draws and not when idle or after the release", idle_hidden and drawn and not nock.visible)
	# Arrows and bolts leave from the weapon on the real release frame (the clip's pose at the spawn's
	# frame, at the game's render scale): the arrow tip, the staff's crystal.
	for probe in [["goblin_archer", "goblin_archer_shot", "arrow"], ["goblin_archer", "goblin_archer_volley", "arrow"], ["goblin_mage", "goblin_mage_bolt", "staff"]]:
		var view := _family_view(probe[0])
		var spawn: Dictionary = _data.moves[probe[1]]["spawns"][1 if probe[1] == "goblin_archer_volley" else 0]
		var firing := Fighter.new()
		firing.team = "enemy"
		firing.state = Fighter.State.ATTACK
		firing.move_id = probe[1]
		firing.move_frame = float(spawn["frame"])
		view.show_state(body, firing, _data)
		var tip := _front_point(view, probe[2])
		var offset: Vector3 = spawn["offset"]
		var expected := Vector3(-offset.z, offset.y, offset.x)  # facing +Z: forward = +z, the right side = -x
		ctx.check("%s: it leaves from the %s's tip on frame %d (tip %s, spawn %s, %.2f m apart)" % [probe[1], probe[2], spawn["frame"], tip, expected, tip.distance_to(expected)], tip.distance_to(expected) < 0.1)
		view.free()
	# Extra bones (bow_string): a clip without them leaves them at rest, a clip with a bone the model
	# lacks does not break, and a position track on an extra bone is applied.
	var skeleton: Skeleton3D = archer.find_children("*", "Skeleton3D", true, false)[0]
	var string_bone := skeleton.find_bone("bow_string")
	var test_clip := Animation.new()
	test_clip.length = 1.0
	var track := test_clip.add_track(Animation.TYPE_POSITION_3D)
	test_clip.track_set_path(track, NodePath("Skeleton3D:bow_string"))
	test_clip.position_track_insert_key(track, 0.0, Vector3(0.0, 0.0, -0.07))
	var missing := test_clip.add_track(Animation.TYPE_ROTATION_3D)
	test_clip.track_set_path(missing, NodePath("Skeleton3D:no_such_bone"))
	test_clip.rotation_track_insert_key(missing, 0.0, Quaternion(Vector3.UP, 0.5))
	var custom = AnimationSet.new()
	custom._clips["pull"] = {"animation": test_clip, "rotation": {"no_such_bone": missing}, "position": {"bow_string": track}, "meta": {}}
	archer._anim = custom
	archer._set_clip("pull", 0.0, 0.0)
	ctx.check("a clip moves the extra bow_string bone and skips a bone the model lacks", string_bone >= 0 and skeleton.get_bone_pose_position(string_bone).is_equal_approx(Vector3(0.0, 0.0, -0.07)))
	archer.free()
	# A glowing part (a material named *_glow, the mage's crystal) keeps its light under the tints.
	var holder := Node3D.new()
	var crystal := MeshInstance3D.new()
	var shape := BoxMesh.new()
	var glow := StandardMaterial3D.new()
	glow.resource_name = "goblin_mage_glow"
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.9, 1.0)
	glow.emission_energy_multiplier = 4.0
	glow.albedo_texture = PlaceholderTexture2D.new()
	shape.material = glow
	crystal.mesh = shape
	holder.add_child(crystal)
	var robe := MeshInstance3D.new()
	robe.mesh = BoxMesh.new()
	var cloth := StandardMaterial3D.new()
	robe.mesh.material = cloth
	holder.add_child(robe)
	var mage: Node3D = FighterView.new()
	mage._use_own_materials(holder, [crystal, robe])
	var hurt := Fighter.new()
	hurt.state = Fighter.State.HITSTUN
	mage._tint_own_materials(hurt, _data, false)
	var lit: StandardMaterial3D = crystal.get_surface_override_material(0)
	var dressed: StandardMaterial3D = robe.get_surface_override_material(0)
	ctx.check("the crystal keeps its cyan glow (energy %.1f) while the rest takes the hit glow" % lit.emission_energy_multiplier, lit.emission.is_equal_approx(Color(0.2, 0.9, 1.0)) and lit.emission_energy_multiplier > 3.0 and dressed.emission.r > 0.1)
	mage.free()
	holder.free()


## The most forward point (+Z, the facing) of a weapon mesh hanging on a bone, in the view's space,
## as the skeleton is posed now (worked out by hand: the view is not in a scene tree in the tests).
func _front_point(view: Node3D, mesh_name: String) -> Vector3:
	var mesh: MeshInstance3D = view.find_child(mesh_name, true, false)
	var attachment: BoneAttachment3D = mesh.get_parent()
	var skeleton: Skeleton3D = attachment.get_parent()
	var to_view := skeleton.transform
	var node := skeleton.get_parent()
	while node != view:
		to_view = node.transform * to_view
		node = node.get_parent()
	var full := to_view * skeleton.get_bone_global_pose(skeleton.find_bone(attachment.bone_name)) * mesh.transform
	var best := Vector3(0.0, 0.0, -INF)
	for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var point: Vector3 = full * vertex
		if point.z > best.z:
			best = point
	return best


func _family_view(id: String) -> Node3D:
	var definition: Dictionary = _data.enemies[id]
	var view: Node3D = FighterView.new()
	view.monster_model_path = definition["model"]
	view.monster_model_height = definition["model_height"]
	view.monster_animations_path = definition["animations"]
	view.monster_clips = definition["clips"]
	view.monster_standin_clips = definition["standin_clips"]
	view.monster_nock_mesh = definition["nock_mesh"]
	view.monster_tint = definition["model_tint"]
	view._ready()
	return view


func _monster_view(model: String, animations: String, outline: bool) -> Node3D:
	var view: Node3D = FighterView.new()
	view.monster_model_path = model
	view.monster_model_height = 0.98
	view.monster_animations_path = animations
	view.monster_clips = {"goblin_jab": "attack_1", "goblin_lunge": "attack_2"}
	view.base_color = Color(0.75, 0.3, 0.3)
	view.ink_outline = outline
	view._ready()
	return view
