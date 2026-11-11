extends SceneTree
## Visual check of the test05 Studio player: hair A-E, plain/Silver, idle/run/slash/guard, front/side/back,
## with and without a sword. Writes build/studio05/*.png. Run with a window (not --headless).
var model

func _initialize():
	call_deferred("run")

func shot(name: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/studio05/%s.png" % name)

func pose(kind: String, clip := "", phase := "", amount := 0.0, weapon := "") -> void:
	model.set_pose(kind, amount, 1.0, true, Vector2(0, 1), false, phase, clip, weapon)
	for frame in 12:
		model.apply_pose(0.033)
		await process_frame

func run():
	DirAccess.make_dir_recursive_absolute("res://build/studio05")
	root.size = Vector2i(900, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323c52")
	scene.add_child(env)
	model = load("res://client/characters/studio05_character_model.gd").new()
	scene.add_child(model)
	assert(model.load_model())
	var camera := Camera3D.new()
	camera.fov = 30
	scene.add_child(camera)
	camera.position = Vector3(0, 0.8, 3.6)
	camera.look_at(Vector3(0, 0.68, 0))
	camera.current = true
	print("bones=", model.bone_count(), " height=", model.model_height(), " scale=", model.model_scale())
	var only := OS.get_environment("SHOT_ONLY")
	for hair in ["a", "b", "c", "d", "e"]:
		if only != "" and only != "hair":
			break
		for silver in [false, true]:
			model.set_appearance({"choices": {"hair_style": hair, "fashion": "red" if silver else "none"}})
			await pose("idle")
			await shot("hair_%s%s_front" % [hair, "_silver" if silver else ""])
	model.set_appearance({"choices": {"hair_style": "a", "fashion": "none"}})
	model.dress({"weapon": {"path": "res://art/items/weapons/blade.glb", "family": "blade"}} if ResourceLoader.exists("res://art/items/weapons/blade.glb") else {"weapon": {"style": "blade"}})
	for angle in [0, 90, 180, 270]:
		model.rotation_degrees.y = angle
		await pose("idle", "", "", 0.0, "blade")
		await shot("idle_blade_%d" % angle)
		await pose("run", "", "", 0.0, "blade")
		await shot("run_blade_%d" % angle)
	model.rotation_degrees.y = 0
	for phase in ["windup", "strike", "recover"]:
		await pose("punch_r", "light_1", phase, 0.5, "blade")
		await shot("slash_%s" % phase)
	await pose("guard", "", "", 1.0, "blade")
	await shot("guard")
	camera.position = Vector3(0, 1.15, 1.3)
	camera.look_at(Vector3(0, 1.08, 0))
	await pose("idle")
	await shot("face_closeup")
	print("STUDIO05 REVIEW DONE")
	quit()
