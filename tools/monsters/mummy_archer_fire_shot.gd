extends SceneTree
## Pilot check of the SIM side: a mummy archer (defined only in memory, copied from the goblin archer with its own model,
## clip library and move timings; data/ is not touched) shoots a player standing still on the Practice Field. Prints where in the clip
## the arrow leaves and saves PNGs of the release and of the arrow in flight.
## Needs a window:  godot --path . --script res://tools/monsters/mummy_archer_fire_shot.gd -- <out_dir>

const LIB := "res://art/animations/monster_clips_bow.glb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://mummy_fire"
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
	var combat = sim.combat
	var marks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/animations/monster_clips_bow.json"))
	var definition: Dictionary = combat.enemies["goblin_archer"].duplicate(true)
	definition["model"] = "res://art/monsters/mummy_archer/mummy_archer.glb"
	definition["animations"] = LIB
	definition["clips"] = {"mummy_archer_shot": "shoot", "mummy_archer_volley": "volley"}
	definition["style"] = "mummy_archer"
	definition["model_height"] = 1.8
	definition["run_clip_speed"] = marks["run"]["travel_per_second"]
	definition["nock_mesh"] = "arrow"
	definition["color"] = Color(0.72, 0.67, 0.54)
	combat.enemies["mummy_archer"] = definition
	var style: Dictionary = combat.styles["goblin_archer"].duplicate(true)
	for key in style:
		if style[key] == "goblin_archer_shot":
			style[key] = "mummy_archer_shot"
		elif style[key] == "goblin_archer_volley":
			style[key] = "mummy_archer_volley"
	combat.styles["mummy_archer"] = style
	var shot: Dictionary = combat.moves["goblin_archer_shot"].duplicate(true)
	shot["startup"] = 46
	shot["active"] = 4
	shot["recovery"] = 28
	shot["spawns"][0]["frame"] = 46
	shot["spawns"][0]["offset"] = Vector3(0.70, 1.15, 0.14)  # the arrow tip at the release pose (build_mummy_archer.gd prints it), x the fit of 1.8 m
	combat.moves["mummy_archer_shot"] = shot
	var volley: Dictionary = combat.moves["goblin_archer_volley"].duplicate(true)
	volley["startup"] = 62
	volley["active"] = 4
	volley["recovery"] = 34
	for spawn in volley["spawns"]:
		spawn["frame"] = 62
		spawn["offset"] = Vector3(0.70, 1.15, 0.14)
	combat.moves["mummy_archer_volley"] = volley
	var id := 100
	sim.add_enemy(id, Vector3(6.5, 0.05, 2.5), "mummy_archer")
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
	view.monster_run_clip_speed = definition["run_clip_speed"]
	stage.add_child(view)
	views[id] = view
	var released := false
	var in_flight := false
	var attack_start := -1
	for frame in 60 * 25:
		await process_frame
		var fighter = sim.fighters[id]
		if int(fighter.state) == 2 and attack_start < 0:
			pass
		if sim.projectiles.size() > 0 and not released:
			released = true
			print("RELEASE: move=", fighter.move_id, " move_frame=", fighter.move_frame, " clip=", view._anim_clip, " clip time=", view._anim_time, " marks=", marks["shoot"], marks["volley"])
			await _save(out, "1_release", sim, [sim.bodies[id].position, sim.bodies[1].position])
		for projectile in sim.projectiles:
			if not in_flight and int(projectile["age"]) >= 10 and Vector3(projectile["pos"]).distance_to(sim.bodies[1].position) > 1.5:
				in_flight = true
				print("arrow in flight at ", projectile["pos"], " player ", sim.bodies[1].position)
				await _save(out, "2_arrow_in_flight", sim, [projectile["pos"], sim.bodies[1].position, sim.bodies[id].position])
		if released and in_flight:
			break
	print("captured release=", released, " flight=", in_flight)
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
