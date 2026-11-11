extends SceneTree
## The journey treasure chest in the real game camera (Boss 2026-10-13):
##   1_chest_closed  the gold portal taken: the chest has dropped in, glowing, the "E  open" prompt shown
##   2_chest_open    E pressed: the lid up, the gold burst and the reward in the loot feed
##   3_next_portals  then the next stage's portals rise beside the open chest
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/chest_open_shots.gd -- <out_dir>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://chest_shots"
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_journey("ink_road", 21)
	await _seconds(0.6)
	var journey = game_state.journey
	var stage: Node = current_scene
	journey.nodes[1] = [{"stage": 2, "kind": "combat", "map": "goblin_arena_b"}, {"stage": 2, "kind": "treasure", "map": ""}]
	journey.nodes[2] = [{"stage": 3, "kind": "combat", "map": "goblin_arena_a"}, {"stage": 3, "kind": "challenge", "map": "goblin_arena_b"}, {"stage": 3, "kind": "camp", "map": journey.data.camp_map}]
	var sim = stage.get("_session")._sim
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			sim.fighters[id].hp = 0.0
			sim.fighters[id].state = sim.fighters[id].State.DEAD
	await _seconds(2.2)
	var body = sim.bodies[1]
	body.position = Vector3(0.0, 0.05, 2.0)
	await _seconds(0.2)
	body.position = stage.get("_portals")[1].position
	await _seconds(1.6)
	var chest = stage.get("_chest")
	print("chest model: ", chest.from_model, "  lid sign: ", chest.lid_sign, "  at ", chest.global_position)
	body.position = chest.global_position + Vector3(0.9, 0.0, 1.1)
	await _seconds(0.5)
	await _save(out, "1_chest_closed")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	stage._unhandled_key_input(event)
	await _seconds(0.62)
	await _save(out, "2_chest_open")
	await _seconds(2.2)
	for portal in stage.get("_portals"):
		print("portal ", portal.kind, " at ", portal.position)
	await _save(out, "3_next_portals")
	quit()


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"))
