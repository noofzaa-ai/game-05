extends SceneTree
## In-game goblin check with the game camera, each saved whole and as a close crop around the monsters:
##   1_valley       goblins closing in on Sunward Valley (monster ink outline on a non-ink stage)
##   2_flee         one goblin brought below 30% health, running away
##   3_hit / 4_dead a goblin being hit (tint) and one dying (death clip), the rules frozen
##   5_chief        the Goblin Chief and its goblins on the boss ring (brush_ring)
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/goblin_shot.gd -- <out_dir>

const Fighter := preload("res://logic/fighter.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://goblin_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_stage(game_state.Mode.PVE, "sunward_valley")
	await _frames(70)  # the goblins close in (about a second)
	var stage: Node = current_scene
	var sim = stage.get("_session")._sim
	var views: Dictionary = stage.get("_views")
	var monsters := _monsters(sim)
	await _save(out, "1_valley", sim, views, monsters)
	var runner: Fighter = sim.fighters[monsters[0]]
	runner.hp = runner.max_hp() * 0.25
	await _frames(40)
	await _save(out, "2_flee", sim, views, monsters)
	stage.set_physics_process(false)  # freeze the rules: the two goblins below are set by hand
	var hit: Fighter = sim.fighters[monsters[1]]
	hit.state = Fighter.State.HITSTUN
	views[monsters[1]].flash()
	var dead: Fighter = sim.fighters[monsters[2]]
	dead.hp = 0.0
	dead.state = Fighter.State.DEAD
	for i in 8:
		hit.state_ticks = i
		dead.state_ticks = i
		for id in [monsters[1], monsters[2]]:
			views[id].show_state(sim.bodies[id], sim.fighters[id], sim.combat)
		await process_frame
	await _save(out, "3_hit", sim, views, monsters)
	await _frames(150)
	await _save(out, "4_dead", sim, views, monsters)
	game_state.start_stage(game_state.Mode.PVE, "brush_ring")
	await _frames(90)
	stage = current_scene
	sim = stage.get("_session")._sim
	await _save(out, "5_chief", sim, stage.get("_views"), _monsters(sim))
	quit()


func _monsters(sim) -> Array:
	var ids := []
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			ids.append(id)
	ids.sort()
	return ids


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The whole view, and a crop around the monsters (and the player) at twice the size.
func _save(out: String, name: String, sim, views: Dictionary, monsters: Array) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var box := Rect2(camera.unproject_position(sim.bodies[1].position), Vector2.ZERO)
	for id in monsters:
		if not camera.is_position_behind(views[id].global_position):
			box = box.expand(camera.unproject_position(views[id].global_position))
	box = box.grow(140).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	var crop := image.get_region(Rect2i(box))
	if crop.get_width() < 800:
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
