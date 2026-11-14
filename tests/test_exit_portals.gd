## Journey exit portals (Boss 2026-10-13, after Lost Castle 2): a cleared stage raises one portal per next
## choice in the stage itself, colored by kind; standing in one takes it (journey.choose_next with its
## index); a camp choice loads a safe rest map with a campfire ("E rest"; storing the bag is a button in
## the camp window); a treasure drops a chest that "E  open" opens (once); the boss stage still ends the journey. Logic first (upcoming_choices / choose_next), then the real scenes.

const ExitPortal := preload("res://client/exit_portal.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const StageView := preload("res://client/stage_view.gd")

var _data


func run(ctx) -> void:
	var combat = CombatDataLoader.load_default()
	var rules = ItemRulesLoader.load_default()
	var camp = CampDataLoader.load_default(rules.tiers.size())
	var loot = LootDataLoader.load_default(camp.materials.keys(), rules.tiers.size())
	_data = JourneyData.load_by_id("ink_road", combat.enemies.keys())
	ctx.check("the journey names a rest camp map (camp_map) %s" % _data.camp_map, not _data.camp_map.is_empty())
	_check_logic(ctx, rules, camp, loot, combat)
	_check_colors(ctx)
	_check_spots(ctx)
	await _check_scenes(ctx)


func _new_journey(seed: int, rules, camp, loot, combat) -> Journey:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Journey.start(_data, Run.start(Profile.new_player(rules, camp, rng), camp), rules, loot, combat.weapon_ids, seed)


func _check_logic(ctx, rules, camp, loot, combat) -> void:
	var j := _new_journey(4, rules, camp, loot, combat)
	var camp_maps_ok := true
	for options in j.nodes:
		for node in options:
			if node["kind"] == "camp":
				camp_maps_ok = camp_maps_ok and node["map"] == _data.camp_map
	ctx.check("camp nodes are played on the camp map", camp_maps_ok)
	j.choose(0)
	ctx.check("in a fight there is nothing to pick yet", j.upcoming_choices().is_empty() and j.choose_next(0).is_empty())
	j.stage_cleared(0.7)
	ctx.check("after a clear the portals offer exactly the journey's choices", j.upcoming_choices() == j.choices() and j.upcoming_choices().size() == 3)
	j.nodes[1] = [{"stage": 2, "kind": "camp", "map": _data.camp_map}]
	j.nodes[2] = [{"stage": 3, "kind": "combat", "map": "ink_garden"}, {"stage": 3, "kind": "challenge", "map": "shrine_wall"}]
	j.choose_next(0)
	ctx.check("at a camp the portals show the stage after it (and the camp still allows going home)", j.is_at_camp() and j.upcoming_choices() == j.nodes[2])
	var taken := j.choose_next(1)
	ctx.check("taking a portal from a camp leaves the camp and chooses that index", taken == j.nodes[2][1] and j.state == Journey.IN_STAGE and j.completed == 2 and j.path == ["combat", "camp", "challenge"])


func _check_colors(ctx) -> void:
	var c: Dictionary = ExitPortal.COLORS
	ctx.check("a fight portal is blue", c["combat"].b > c["combat"].r + 0.3 and c["combat"].b > c["combat"].g)
	ctx.check("a rest camp portal is green", c["camp"].g > c["camp"].r + 0.3 and c["camp"].g > c["camp"].b + 0.3)
	ctx.check("a challenge portal is red-orange", c["challenge"].r > c["challenge"].g + 0.3 and c["challenge"].g > c["challenge"].b)
	ctx.check("a treasure portal is gold", c["treasure"].r > 0.8 and c["treasure"].g > 0.6 and c["treasure"].b < 0.4)
	ctx.check("the boss portal is purple", c["boss"].r > c["boss"].g + 0.2 and c["boss"].b > c["boss"].g + 0.4)
	var distinct := {}
	for kind in c:
		distinct[c[kind].to_html()] = true
	ctx.check("every kind has its own color", distinct.size() == c.size())


func _check_spots(ctx) -> void:
	var ok := true
	for map_id in _data.combat_maps + _data.arena_maps + [_data.boss_map, _data.camp_map]:
		var map = MapLoader.load_by_id(map_id)
		var spots := StageView.portal_spots(map, 3)
		ok = ok and spots.size() == 3
		for spot in spots:
			ok = ok and absf(spot.x) < map.half_width and absf(spot.z) < map.half_depth and not StageView._blocked(map, spot, [])
		ok = ok and spots[0].distance_to(spots[1]) >= ExitPortal.RADIUS * 2.5 and spots[1].distance_to(spots[2]) >= ExitPortal.RADIUS * 2.5
	ctx.check("fallback portal spots stand apart, inside the map and off walls on every journey map", ok)
	# A map that writes its own exit spots (level data) gets its portals there; extra choices use the fallback.
	var map = preload("res://logic/map_data.gd").new()
	map.half_width = 12.0
	map.half_depth = 10.0
	map.exit_portals.assign([Vector3(3.0, 0.05, -4.0), Vector3(-3.0, 0.05, -4.0)])
	var spots := StageView.portal_spots(map, 3)
	ctx.check("a map's own exit_portals spots are used, a third choice joins their row (left to right) %s" % [spots], spots.size() == 3 and spots[0] == Vector3(-3.0, 0.05, -4.0) and spots[2] == Vector3(3.0, 0.05, -4.0) and is_equal_approx(spots[1].z, -4.0) and spots[0].x < spots[1].x and spots[1].x < spots[2].x)


## Waits (real time: the portals count physics ticks) until `condition` holds, at most `seconds`.
func _wait(ctx, condition: Callable, seconds: float = 6.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await ctx.process_frame
	return condition.call()


func _kill_all(sim) -> void:
	for id in sim.fighters:
		var fighter = sim.fighters[id]
		if fighter.team == "enemy" and fighter.is_alive():
			fighter.hp = 0.0
			fighter.state = fighter.State.DEAD


## Walks the player off any ring (a portal that rose under them waits for that), then into portal `index`.
func _step_into(ctx, stage: Node, index: int) -> void:
	var body = stage.get("_session").bodies[1]
	body.position = Vector3(0.0, 0.05, 2.0)
	await ctx.create_timer(0.15).timeout
	body.position = stage.get("_portals")[index].position


## Waits for a new stage scene (by instance id: the old scene is freed while waiting).
func _next_scene(ctx, old: Node, needs_sim: bool = true) -> void:
	var old_id := old.get_instance_id()
	await _wait(ctx, func(): return ctx.current_scene != null and ctx.current_scene.get_instance_id() != old_id and (not needs_sim or ctx.current_scene.get("_session") != null))


func _press(stage: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	stage._unhandled_key_input(event)


func _check_scenes(ctx) -> void:
	var game_state: Node = ctx.root.get_node_or_null("GameState")
	if not game_state.ensure_profile():
		ctx.check("profile for the portal flow", false)
		return
	game_state.auto_battle = false  # (these flows walk the player by hand)
	ctx.check("a journey starts", game_state.start_journey("ink_road", 21))
	await _wait(ctx, func(): return ctx.current_scene != null and ctx.current_scene.get("_session") != null)
	var stage: Node = ctx.current_scene
	var journey = game_state.journey
	ctx.check("the journey opens straight into stage 1", stage.scene_file_path == "res://scenes/stage.tscn" and journey.state == Journey.IN_STAGE and journey.stage_number() == 1)
	# The stage-2 choices this test walks through: a fight, the rest camp, a treasure (then stage 3: fight or camp).
	journey.nodes[1] = [{"stage": 2, "kind": "combat", "map": "ink_garden"}, {"stage": 2, "kind": "camp", "map": _data.camp_map}, {"stage": 2, "kind": "treasure", "map": ""}]
	journey.nodes[2] = [{"stage": 3, "kind": "combat", "map": "shrine_wall"}, {"stage": 3, "kind": "camp", "map": _data.camp_map}]
	ctx.check("no portals while monsters live", stage.get("_portals").is_empty())
	_kill_all(stage.get("_session"))
	var rose: bool = await _wait(ctx, func(): return not stage.get("_portals").is_empty())
	var portals: Array = stage.get("_portals")
	ctx.check("after the clear the portals rise: one per choice", rose and portals.size() == 3 and journey.state == Journey.CHOOSING)
	ctx.check("each portal has its kind's color (blue fight, green camp, gold treasure)", rose and portals[0].color == ExitPortal.COLORS["combat"] and portals[1].color == ExitPortal.COLORS["camp"] and portals[2].color == ExitPortal.COLORS["treasure"])
	ctx.check("the route screen is not shown between stages", ctx.current_scene == stage)
	# Walking past does not pick: a moment inside empties again once the player steps out.
	if rose:
		portals[0].update_hold(true, 0.2)
		portals[0].update_hold(false, 0.2)
		ctx.check("a short touch of a ring does not take it", portals[0].hold <= 0.0 and journey.state == Journey.CHOOSING)

	# The treasure portal (Boss 2026-10-13): a chest drops in on this map; E opens it (once), then the
	# next stage's portals rise here.
	ctx.check("no chest before a treasure is taken", stage.get("_chest") == null)
	var bag_items: int = journey.run.bag.items.size()
	await _step_into(ctx, stage, 2)
	var taken: bool = await _wait(ctx, func(): return journey.path.size() == 2 and stage.get("_chest") != null)
	var chest = stage.get("_chest")
	ctx.check("standing in the gold portal takes choice 2 (treasure) and drops a chest on this map", taken and journey.path[-1] == "treasure" and ctx.current_scene == stage and chest != null)
	ctx.check("the chest holds the piece until it is opened (nothing in the bag, no portals)", journey.is_treasure_closed() and journey.run.bag.items.size() == bag_items and stage.get("_portals").is_empty())
	var body = stage.get("_session").bodies[1]
	if chest != null:
		var spot: Vector3 = chest.global_position
		ctx.check("the chest stands inside the map, off walls %s" % spot, absf(spot.x) < stage.get("_map").half_width and absf(spot.z) < stage.get("_map").half_depth and not StageView._blocked(stage.get("_map"), spot, []))
		body.position = spot + Vector3(6.0, 0.0, 6.0)
		await _wait(ctx, func(): return chest.is_ready, 2.0)
		_press(stage, KEY_E)
		ctx.check("E away from the chest does nothing", not chest.is_open and journey.is_treasure_closed())
		body.position = spot + Vector3(0.0, 0.0, 1.0)
		var near: bool = await _wait(ctx, func(): return stage.get("_near_chest"), 2.0)
		var button: Button = stage.get("_chest_button")
		ctx.check("walking up to the chest shows the 'Open' button (tap / click; E is a key shortcut, not printed)", near and button != null and button.visible and button.text == "Open")
		_press(stage, KEY_E)
		var gave: bool = await _wait(ctx, func(): return journey.run.bag.items.size() == bag_items + 1)
		ctx.check("E opens the chest: the lid turns, the piece goes into the bag", gave and chest.is_open and not journey.is_treasure_closed() and absf(chest.lid.rotation.x) > 1.0)
		_press(stage, KEY_E)
		button.pressed.emit()
		await ctx.create_timer(0.3).timeout
		ctx.check("the chest opens once: the piece is given once", journey.run.bag.items.size() == bag_items + 1 and journey.open_treasure().is_empty())
	var next_rose: bool = await _wait(ctx, func(): return stage.get("_portals").size() == 2 and not stage.get("_leaving"))
	ctx.check("after opening, the stage-3 portals rise (fight, camp)", next_rose and stage.get("_portals")[1].kind == "camp")

	# A blue portal: the next fight with its monsters (the green camp portal and its rest map were cut with the campfire).
	await _step_into(ctx, stage, 0)
	await _next_scene(ctx, stage)
	var fight: Node = ctx.current_scene
	ctx.check("a fight choice drops no chest", fight.get("_chest") == null)
	ctx.check("the blue portal starts the next fight", journey.state == Journey.IN_STAGE and fight.get("_session").living_enemy_count() > 0)

	# The boss stage still ends the journey: no portals, the summary.
	journey.completed = 11
	journey.current = {}
	journey.state = Journey.CHOOSING
	game_state.enter_journey_choice(0)
	await _next_scene(ctx, fight)
	var boss: Node = ctx.current_scene
	ctx.check("stage 12 is the boss", journey.current.get("kind", "") == "boss" and boss.get("_boss_id") >= 0)
	var clear_boss := func() -> bool:
		_kill_all(boss.get("_session"))  # (the boss calls a second wave when the field is clear)
		return journey.state == Journey.WON
	await _wait(ctx, clear_boss, 10.0)
	await ctx.create_timer(StageView.PORTAL_DELAY + 0.5).timeout
	ctx.check("beating the boss wins the journey and raises no portals", journey.state == Journey.WON and boss.get("_portals").is_empty())
	_press(boss, KEY_ENTER)
	await _next_scene(ctx, boss, false)
	ctx.check("Enter goes to the journey summary", ctx.current_scene.scene_file_path == "res://scenes/journey.tscn")
	game_state.journey = null
	game_state.go_card_deck()
	for i in 3:
		await ctx.process_frame
