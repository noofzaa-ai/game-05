extends SceneTree
## Shots of a fallen goblin lying, fading out and gone (Boss 2026-11-15: 3 s, then fade, then freed). Run windowed:
##   godot --path . --script res://tools/shots/corpse_fade_shots.gd -- --out=<dir>
## Starts the default wave journey with a 3-card squad, kills the first living goblin by hand, freezes the camera on
## it and saves <out>/corpse_<t>.png at 0.1 s, 2.0 s, 3.1 s (fading), 3.3 s and 3.8 s (freed) after the kill, and
## prints whether the view is still in the stage's view map, valid, and how many nodes the scene has.
const Fighter := preload("res://logic/fighter.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var out := "user://corpse_fade"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var deck: Dictionary = game_state.profile.card_deck
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		deck["cards"][pair[0]]["race"] = pair[1]
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	seed(7)
	game_state.start_journey(game_state.DEFAULT_JOURNEY, 7)
	for i in 240: await process_frame
	var stage: Node = current_scene
	var session = stage.get("_session")
	var views: Dictionary = stage.get("_views")
	var victim := -1
	for id in session.fighters:
		if session.fighters[id].team == "enemy" and session.fighters[id].is_alive():
			victim = id
			break
	var view: Node3D = views[victim]
	var sim = session.get("_sim")
	# A kill by the rules' own path: drop its HP to 0 through a dot-like event so the sim emits "killed" itself.
	sim.fighters[victim].hp = 0.0
	sim.fighters[victim].state = Fighter.State.DEAD
	sim.fighters[victim].state_ticks = 0
	sim.events.append({"type": "killed", "target": victim, "by": 1})
	stage.call("_handle_events")
	var rig = stage.get("_rig")
	var kill_tick: int = session.tick_count
	var spot: Vector3 = view.global_position
	var alone := OS.get_cmdline_user_args().has("--alone")  # only the victim is drawn (a clear look at its fade)
	if rig != null:
		rig.process_mode = Node.PROCESS_MODE_DISABLED  # one fixed camera for every shot
		rig.set_physics_process(false)
	for at in [2.0, 3.05, 3.15, 3.25, 3.35, 3.45, 3.8]:
		while (session.tick_count - kill_tick) / 60.0 < at:  # sim seconds (the window may run behind real time)
			if alone: _hide_others(stage, views, victim)
			await process_frame
		if alone: _hide_others(stage, views, victim)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(out.path_join("corpse_%.2fs.png" % at))
		var camera := root.get_viewport().get_camera_3d()
		if camera != null:  # a 2x crop around where the goblin fell
			var p := camera.unproject_position(spot + Vector3(0, 0.5, 0))
			var box := Rect2i(Vector2i(p) - Vector2i(120, 90), Vector2i(240, 180)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			var crop := image.get_region(box)
			crop.resize(box.size.x * 2, box.size.y * 2, Image.INTERPOLATE_NEAREST)
			crop.save_png(out.path_join("corpse_crop_%.2fs.png" % at))
		var sink := 0.0
		if is_instance_valid(view) and view.get("_body") != null:
			sink = -view.get("_body").position.y
		print("CORPSE t=%.1f in_views=%s view_valid=%s in_sim=%s sink_m=%.2f nodes=%d" % [at, views.has(victim), is_instance_valid(view), session.fighters.has(victim), sink, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	quit()


## Everything but the fallen goblin: other fighters, effects, floating words and numbers, the HUD.
func _hide_others(stage: Node, views: Dictionary, victim: int) -> void:
	for id in views:
		if id != victim: views[id].visible = false
	for node in stage.get_children():
		if node is CanvasLayer:
			node.visible = false
		elif node is Node3D and not views.values().has(node) and not str(node.name).begins_with("Art") and node.get_class() != "WorldEnvironment" and not node is DirectionalLight3D and not node is Camera3D and node.find_child("Camera3D", true, false) == null and not str(node.name) in ["GoblinCampIsland", "FloatingIsland", "Ground"]:
			if node is Label3D or (node.get_script() != null and not str(node.get_script().resource_path).ends_with("fighter_view.gd")):
				node.visible = false
