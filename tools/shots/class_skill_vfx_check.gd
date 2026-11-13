extends SceneTree
## Loader check for the daiyooo-vfx class skill effects (art/vfx/class_skills/<id>/effect.tscn).
## Not wired into the game. Instances every effect in the project's renderer (gl_compatibility),
## checks it has an AnimationPlayer clip, counts meshes/surfaces/triangles, seeks to a few times
## and saves one PNG grid per class. Needs a window (no --headless) for the PNGs:
##   godot --path . --script res://tools/shots/class_skill_vfx_check.gd -- <out_dir>
## Prints one "VFXCHECK" line per effect and "VFXCHECK_DONE fails=N" at the end.

const SKILLS_PATH := "res://data/class_skills/class_skills.json"
const ROOT := "res://art/vfx/class_skills/"
const CELL := Vector2i(420, 320)
const SAMPLE_FRACTIONS := [0.2, 0.45, 0.7]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://class_skill_vfx"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKILLS_PATH))
	var classes: Dictionary = data["classes"]
	var fails := 0
	print("VFXCHECK renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method"), " driver=", RenderingServer.get_current_rendering_driver_name())
	for cls in classes.keys():
		var ids: Array = classes[cls]
		for frac in SAMPLE_FRACTIONS:
			var result: Dictionary = await _render_class(cls, ids, frac)
			fails += int(result["fails"])
			var img: Image = result["image"]
			if img != null:
				img.save_png(out_dir.path_join("%s_t%02d.png" % [cls, int(frac * 100)]))
	print("VFXCHECK_DONE fails=", fails)
	quit(1 if fails > 0 else 0)


func _render_class(cls: String, ids: Array, frac: float) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL.x * ids.size(), CELL.y)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 0.6
	# README suggestion for bloom (glow is supported by the Compatibility renderer in 4.3+).
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 1.0
	env.glow_bloom = 0.2
	env.glow_hdr_threshold = 0.95
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	viewport.add_child(light)
	# Ground grid for scale (1 m tiles), board-like camera.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 8)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.25, 0.26, 0.28)
	ground.material_override = gmat
	ground.position = Vector3((ids.size() - 1) * 3.0, -0.01, 0)
	viewport.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40.0
	viewport.add_child(cam)
	cam.look_at_from_position(Vector3((ids.size() - 1) * 3.0, 6.5, 11.0), Vector3((ids.size() - 1) * 3.0, 0.8, 0.0))
	var fails := 0
	var players: Array = []
	for n in ids.size():
		var sid: String = ids[n]
		var path := ROOT + sid + "/effect.tscn"
		var packed := load(path) as PackedScene
		if packed == null:
			print("VFXCHECK FAIL ", sid, " cannot load ", path)
			fails += 1
			continue
		var inst := packed.instantiate() as Node3D
		if inst == null:
			print("VFXCHECK FAIL ", sid, " instantiate returned null")
			fails += 1
			continue
		inst.position = Vector3(n * 6.0, 0.0, 0.0)
		viewport.add_child(inst)
		var player := _find_player(inst)
		var clip := ""
		var length := 0.0
		if player != null:
			for a in player.get_animation_list():
				if a != "RESET":
					clip = a
					length = player.get_animation(a).length
					break
		var stats := _mesh_stats(inst)
		if player == null or clip == "":
			print("VFXCHECK FAIL ", sid, " no AnimationPlayer clip")
			fails += 1
		elif frac == SAMPLE_FRACTIONS[0]:
			print("VFXCHECK OK ", sid, " clip=", clip, " length=%.2f" % length, " meshes=", stats["meshes"], " surfaces=", stats["surfaces"], " materials=", stats["materials"], " tris=", stats["tris"], " anim_tracks=", player.get_animation(clip).get_track_count())
		players.append([player, clip, length])
	await process_frame
	for p in players:
		if p[0] != null and p[1] != "":
			p[0].play(p[1])
			p[0].seek(float(p[2]) * frac, true)
			p[0].pause()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	await process_frame
	return {"fails": fails, "image": img}


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null


func _mesh_stats(node: Node) -> Dictionary:
	var s := {"meshes": 0, "surfaces": 0, "tris": 0, "materials": 0}
	var mats := {}
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null:
			s["meshes"] += 1
			var m: Mesh = n.mesh
			for i in m.get_surface_count():
				s["surfaces"] += 1
				var arr := m.surface_get_arrays(i)
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx != null and idx.size() > 0:
					s["tris"] += idx.size() / 3
				else:
					s["tris"] += arr[Mesh.ARRAY_VERTEX].size() / 3
				var mat := m.surface_get_material(i)
				if mat != null:
					mats[mat.get_rid()] = true
	s["materials"] = mats.size()
	return s
