extends SceneTree
## One row per class: idle, run, light attack strike, heavy strike, ultimate strike. build/studio05_classes/*.png
func _initialize():
	call_deferred("run")

func run():
	DirAccess.make_dir_recursive_absolute("res://build/studio05_classes")
	root.size = Vector2i(500, 640)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5a7aa0")
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.fov = 34
	scene.add_child(camera)
	camera.position = Vector3(1.6, 1.1, 3.4)
	camera.look_at(Vector3(0, 0.68, 0))
	camera.current = true
	var hairs := {"sword_shield": "a", "greatsword": "c", "longbow": "f", "magic": "e"}
	for cls in ["sword_shield", "greatsword", "longbow", "magic"]:
		var model = load("res://client/characters/studio05_character_model.gd").new()
		scene.add_child(model)
		model.load_model()
		model.dress({"class": cls, "appearance": {"choices": {}, "studio_hair": hairs[cls], "studio_silver": cls != "sword_shield"}, "weapon": {"path": "res://art/items/weapons/blade.glb", "family": "blade"}})
		print("CLASS ", cls, " bones=", model.bone_count(), " clips=", model._library.clip_names().size() if model._library != null else -1)
		var frames := [["idle", "", "", 0.0], ["run", "", "", 0.0], ["punch_r", "light_1", "strike", 0.5], ["heavy", "heavy", "strike", 0.5], ["punch_r", "ultimate", "strike", 0.5], ["punch_r", "ultimate", "windup", 0.9]]
		var i := 0
		for f in frames:
			model.set_pose(f[0], 0.5, 1.0, true, Vector2(0, 1), false, f[2], f[1], "blade")
			for k in 10:
				model.apply_pose(0.033)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/studio05_classes/%s_%d.png" % [cls, i])
			i += 1
		model.queue_free()
		await process_frame
	quit()
