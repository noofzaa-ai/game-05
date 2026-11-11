extends SceneTree
## Contact sheet frames of one studio05 clip: CLIP=casting_2 godot --path . --script res://tools/shots/studio05_clip.gd
func _initialize():
	call_deferred("run")

func run():
	var clip := OS.get_environment("CLIP") if OS.get_environment("CLIP") != "" else "casting_2"
	DirAccess.make_dir_recursive_absolute("res://build/studio05_clip")
	root.size = Vector2i(600, 700)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323c52")
	scene.add_child(env)
	var model = load("res://client/characters/studio05_character_model.gd").new()
	scene.add_child(model)
	model.load_model()
	model.dress({"weapon": {"path": "res://art/items/weapons/blade.glb", "family": "blade"}})
	var camera := Camera3D.new()
	camera.fov = 30
	scene.add_child(camera)
	camera.position = Vector3(0.8, 0.9, 3.2)
	camera.look_at(Vector3(0, 0.68, 0))
	camera.current = true
	var length: float = model._library.length(clip)
	print("CLIP ", clip, " length ", length)
	for i in 8:
		var t := length * float(i) / 8.0
		model._skill_clip = {"set": model._library, "clip": clip, "time": t}
		model.apply_pose(0.016)
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/studio05_clip/%s_%d.png" % [clip, i])
	quit()
