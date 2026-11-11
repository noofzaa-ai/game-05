extends SceneTree
## Ranged combat check with the game camera on the Practice Field: a goblin archer, a goblin mage and
## a goblin knight (their own models and clips) attack a player who
## stands still. Saves the first moment of each, whole and as a close crop:
##   1_arrow   an arrow in flight      2_bolt   a magic bolt in flight      3_hex   a hex circle filling
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/ranged_shot.gd -- <out_dir>

const MONSTERS := {100: ["goblin_archer", Vector3(6.5, 0.05, 2.5)], 101: ["goblin_mage", Vector3(-6.5, 0.05, 5.5)], 102: ["goblin_knight", Vector3(2.0, 0.05, 9.0)]}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://ranged_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_stage(game_state.Mode.PVE, "practice_field")
	await _frames(10)
	var stage: Node = current_scene
	var sim = stage.get("_session")._sim
	var views: Dictionary = stage.get("_views")
	sim.fighters[1].stats["HP"] = 1000000.0
	sim.fighters[1].hp = 1000000.0
	for id in MONSTERS:
		var kind: String = MONSTERS[id][0]
		sim.add_enemy(id, MONSTERS[id][1], kind)
		var definition: Dictionary = sim.combat.enemies[kind]
		var view := Node3D.new()
		view.set_script(load("res://client/fighter_view.gd"))
		view.base_color = definition["color"]
		view.show_health_bar = true
		view.monster_model_path = definition["model"]
		view.monster_model_height = definition["model_height"]
		view.monster_animations_path = definition["animations"]
		view.monster_clips = definition["clips"]
		view.monster_tint = definition["model_tint"]
		view.monster_standin_clips = definition["standin_clips"]
		view.monster_nock_mesh = definition["nock_mesh"]
		stage.add_child(view)
		views[id] = view
	var wanted := {"1_arrow": false, "2_bolt": false, "3_hex": false}
	for frame in 60 * 25:
		await process_frame
		for shot in sim.projectiles:
			var look: String = sim.combat.projectiles[shot["def"]]["look"]
			var key := "1_arrow" if look == "arrow" else "2_bolt"
			var to_player: float = Vector3(shot["pos"]).distance_to(sim.bodies[1].position)
			if not wanted[key] and int(shot["age"]) >= 8 and to_player > 1.5:
				wanted[key] = true
				await _save(out, key, sim, [shot["pos"], sim.bodies[1].position, sim.bodies[shot["owner"]].position])
		for area in sim.areas:
			if not wanted["3_hex"] and float(area["age"]) / float(area["delay"]) > 0.6:
				wanted["3_hex"] = true
				await _save(out, "3_hex", sim, [area["pos"], sim.bodies[1].position, sim.bodies[area["owner"]].position])
		if not wanted.values().has(false):
			break
	print("captured ", wanted)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String, sim, points: Array) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var box := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for point in points:
		box = box.expand(camera.unproject_position(point))
	box = box.grow(150).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	var crop := image.get_region(Rect2i(box))
	if crop.get_width() < 800:
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
