extends SceneTree
## Journey exit portals in the real game camera (Boss 2026-10-13):
##   1_cleared_portals  a cleared fight stage: the three exit portals (fight / rest camp / treasure)
##   2_portal_entering  the player standing in a portal, its ring filling
##   3_rest_camp        the rest camp map: the campfire with its "E rest" prompt and the next portals
##   4_challenge_boss   a cleared stage offering the other kinds (challenge red-orange, boss purple)
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/portal_shots.gd -- <out_dir>

const Journey := preload("res://logic/journey.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://portal_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_journey("ink_road", 21)
	await _seconds(0.6)
	var journey = game_state.journey
	journey.nodes[1] = [{"stage": 2, "kind": "combat", "map": "goblin_arena_b"}, {"stage": 2, "kind": "camp", "map": journey.data.camp_map}, {"stage": 2, "kind": "treasure", "map": ""}]
	var stage: Node = current_scene
	_clear(stage)
	await _seconds(2.2)
	var body = stage.get("_session")._sim.bodies[1]
	body.position = Vector3(0.0, 0.05, -1.5)
	await _seconds(0.6)
	await _save(out, "1_cleared_portals")
	var portals: Array = stage.get("_portals")
	body.position = portals[1].position + Vector3(0.0, 0.0, 0.2)
	await _seconds(0.35)
	await _save(out, "2_portal_entering")
	await _seconds(1.5)  # the camp portal takes the player to the rest camp
	stage = current_scene
	var fire: Dictionary = stage.get("_campfire")
	stage.get("_session")._sim.bodies[1].position = fire["position"] + Vector3(1.2, 0.0, 1.0)
	await _seconds(1.6)
	await _save(out, "3_rest_camp")
	# The other two colors: a challenge and the boss as the next choices of a cleared stage.
	journey.completed = 1
	journey.current = {}
	journey.state = Journey.CHOOSING
	journey.nodes[1] = [{"stage": 2, "kind": "combat", "map": "goblin_arena_a"}]
	journey.nodes[2] = [{"stage": 3, "kind": "challenge", "map": "goblin_arena_a"}, {"stage": 3, "kind": "boss", "map": journey.data.boss_map}, {"stage": 3, "kind": "combat", "map": "goblin_arena_b"}]
	game_state.enter_journey_choice(0)
	await _seconds(0.6)
	stage = current_scene
	_clear(stage)
	await _seconds(2.2)
	stage.get("_session")._sim.bodies[1].position = Vector3(0.0, 0.05, -1.5)
	await _seconds(0.6)
	await _save(out, "4_challenge_boss")
	quit()


func _clear(stage: Node) -> void:
	var sim = stage.get("_session")._sim
	for id in sim.fighters:
		var fighter = sim.fighters[id]
		if fighter.team == "enemy":
			fighter.hp = 0.0
			fighter.state = fighter.State.DEAD


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"))
