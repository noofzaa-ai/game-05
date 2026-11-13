extends SceneTree
## Per-effect cost of the class skill VFX (art/vfx/class_skills/<id>/effect.tscn) in the project renderer
## (gl_compatibility). For each skill: N copies play in loop in front of a camera for SECONDS; reports average and
## worst frame time, draw calls and primitives at the busiest moment, against an empty baseline. Needs a window:
##   godot --path . --script res://tools/perf/class_skill_vfx_cost.gd -- [copies=3] [seconds=3] [slim=1] [ids,comma]
## slim=1 (default) plays them the way the game does (ClassSkillVfx._slim: phase meshes toggled by visible, no shadows);
## slim=0 plays the raw imported scene.
## Output lines "VFXCOST <id> ..." (vsync is turned off so frame times are real).

const ROOT := "res://art/vfx/class_skills/"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var copies := int(args[0]) if args.size() > 0 else 3
	var seconds := float(args[1]) if args.size() > 1 else 3.0
	var slim := (args[2] != "0") if args.size() > 2 else true
	var only: PackedStringArray = args[3].split(",") if args.size() > 3 else PackedStringArray()
	var vfx = load("res://client/skills/class_skill_vfx.gd").new()
	root.add_child(vfx)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.3, 0.32)
	env.glow_enabled = true
	env.glow_intensity = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 9, 12), Vector3(0, 0.8, 0))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/class_skills/class_skills.json"))
	var base := await _measure([], seconds)
	print("VFXCOST baseline avg=%.2fms worst=%.2fms draws=%d prims=%d" % [base["avg"], base["worst"], base["draws"], base["prims"]])
	for sid in data["skills"].keys():
		if not only.is_empty() and not only.has(sid):
			continue
		var packed: PackedScene = load(ROOT + sid + "/effect.tscn")
		var nodes: Array = []
		for i in copies:
			var inst: Node3D = packed.instantiate()
			inst.set("loop_effect", true)
			inst.position = Vector3((i - (copies - 1) * 0.5) * 3.0, 0, 0)
			root.add_child(inst)
			if slim:
				vfx._slim(sid, inst)
				var ap: AnimationPlayer = vfx._player_of(inst)
				ap.play(vfx._clip_of(ap))
				ap.seek(0.0, true)
			nodes.append(inst)
		var m := await _measure(nodes, seconds)
		print("VFXCOST %s x%d avg=%.2fms (+%.2f) worst=%.2fms draws=%d (+%d) prims=%d" % [sid, copies, m["avg"], m["avg"] - base["avg"], m["worst"], m["draws"], m["draws"] - base["draws"], m["prims"]])
		for n in nodes:
			n.queue_free()
		await process_frame
	quit()


func _measure(_nodes: Array, seconds: float) -> Dictionary:
	for i in 20:
		await process_frame
	var t := 0.0
	var frames := 0
	var worst := 0.0
	var draws := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	while t < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		t += ms / 1000.0
		frames += 1
		worst = maxf(worst, ms)
		draws = maxi(draws, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	return {"avg": t * 1000.0 / frames, "worst": worst, "draws": draws, "prims": prims}
