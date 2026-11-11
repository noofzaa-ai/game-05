extends SceneTree
## The goblin family in game, at their data sizes, with the game camera: each variant standing next
## to goblins and the player, on the golden stage (Sunward Valley) and the ink stage (Ink Garden),
## and the Goblin Chief on its boss ring (brush_ring). Saved whole and as a close crop.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/family_shot.gd -- <out_dir>

const LINEUP := ["goblin", "goblin_archer", "goblin_mage", "goblin_knight", "goblin_chief"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://family_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	for stage_id in ["sunward_valley", "ink_garden"]:
		game_state.start_stage(game_state.Mode.PVE, stage_id)
		await _frames(10)
		var stage: Node = current_scene
		var sim = stage.get("_session")._sim
		stage.set_physics_process(false)  # a still line-up: the rules wait, the views keep idling
		var views: Dictionary = stage.get("_views")
		var player: Vector3 = sim.bodies[1].position
		for id in views:
			if id != 1:
				views[id].visible = false  # (the stage's own goblins: the line-up stands alone)
		var ids := []
		for index in LINEUP.size():
			var id := 200 + index
			var xs: Array = [-4.0, -2.7, -1.4, 1.3, 2.45] if stage_id == "sunward_valley" else [-4.6, -3.0, -1.4, 1.6, 3.6]  # (open floor; the player in the gap)
			var spot := player + Vector3(xs[index], 0.0, -1.0)
			if stage_id == "sunward_valley":
				spot.z = clampf(spot.z, -2.0, 2.0)
			sim.add_enemy(id, spot, LINEUP[index])
			sim.bodies[id].position = spot
			sim.fighters[id].direction = Vector2i(0, 1)  # facing the camera
			views[id] = _view(stage, sim.combat.enemies[LINEUP[index]])
			ids.append(id)
		for frame in 50:
			for id in ids:
				views[id].show_state(sim.bodies[id], sim.fighters[id], sim.combat)
			views[1].show_state(sim.bodies[1], sim.fighters[1], sim.combat)
			await process_frame
		await _save(out, "family_" + stage_id, sim, ids)
	game_state.start_stage(game_state.Mode.PVE, "brush_ring")
	await _frames(45)
	var ring = current_scene.get("_session")._sim
	var enemies := []
	for id in ring.fighters:
		if ring.fighters[id].team == "enemy":
			enemies.append(id)
	await _save(out, "chief_brush_ring", ring, enemies)
	quit()


func _view(stage: Node, definition: Dictionary) -> Node3D:
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
	return view


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String, sim, ids: Array) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var box := Rect2(camera.unproject_position(sim.bodies[1].position), Vector2.ZERO)
	for id in ids:
		box = box.expand(camera.unproject_position(sim.bodies[id].position))
		box = box.expand(camera.unproject_position(sim.bodies[id].position + Vector3.UP * 2.0))
	box = box.grow(90).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	var crop := image.get_region(Rect2i(box))
	if crop.get_width() < 800:
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
