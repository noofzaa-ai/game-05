extends SceneTree
## Renders class skill VFX at fixed clip times, one PNG strip per effect (for before/after review of the draw-call fix).
##   godot --path . --script res://tools/perf/class_skill_vfx_frames.gd -- <assets_root> <out_dir> <slim 0|1> <ids,comma> [tag]
## assets_root e.g. res://art/vfx/class_skills/ ; slim=1 plays them the way the game does (ClassSkillVfx._slim).
## Prints "VFXFRAME <id> t=<s> draws=<n>" per frame.

const CELL := Vector2i(400, 300)
const FRACTIONS := [0.08, 0.18, 0.3, 0.45, 0.65]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var out_dir: String = args[1]
	var slim := args[2] != "0"
	var ids: PackedStringArray = args[3].split(",")
	var tag: String = args[4] if args.size() > 4 else ("slim" if slim else "raw")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(CELL)
	root.size = CELL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.3, 0.27)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(0, 5.5, 7.5), Vector3(0, 1.0, 0))
	var vfx = load("res://client/skills/class_skill_vfx.gd").new()
	root.add_child(vfx)
	for sid in ids:
		var packed: PackedScene = load(src.path_join(sid).path_join("effect.tscn"))
		var inst: Node3D = packed.instantiate()
		inst.set("autoplay", false)
		root.add_child(inst)
		if slim:
			vfx._slim(sid, inst)
		var ap: AnimationPlayer = vfx._player_of(inst)
		var clip: StringName = vfx._clip_of(ap)
		var length: float = ap.get_animation(clip).length
		var strip := Image.create(CELL.x * FRACTIONS.size(), CELL.y, false, Image.FORMAT_RGBA8)
		for i in FRACTIONS.size():
			var t: float = FRACTIONS[i] * length
			ap.play(clip)
			ap.seek(t, true)
			ap.pause()
			for k in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
			print("VFXFRAME %s t=%.2f draws=%d" % [sid, t, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		strip.save_png(out_dir.path_join("%s_%s.png" % [sid, tag]))
		inst.queue_free()
		await process_frame
	quit()
