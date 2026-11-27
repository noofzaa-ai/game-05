extends Node
## Fight cost table (scene version: ships in the web export; web: play.html?bench=1&journey=orc_waves&...)
## Fight cost table (tech-artist 2026-11-27, Boss "the fps drops"). Run windowed with the web renderer:
##   godot --path . --rendering-driver opengl3 --script res://tools/perf/fight_cost.gd -- --journey=orc_waves
##       [--size=1920x987] [--scale=0.75] [--aa=2] [--style=on|lite|off] [--device=phone] [--frames=240]
##       [--shots=<dir>] [--live]
## Opens the zone's wave journey offline with a raised 3-card squad, skips the early waves (their monsters are
## removed in the sim) until the BOSS wave is on the field, lets it fight for a few seconds, then freezes the
## simulation (animations, VFX and HUD keep running) and measures the same frame with each feature on and off:
## "COST <toggle> frame_ms=.. fps=.. draw_ms=.. process_ms=.. dc=.. prims=.. (delta vs base)".
## --live measures the running fight (no freeze) instead of toggles. Removes user://graphics.cfg afterwards when
## it did not exist before.
const Options := preload("res://client/graphics_options.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")

var _t_pre := 0
var _t_proc := 0
var _acc_draw := 0.0
var _acc_proc := 0.0
var _shots := ""


var root: Window
var _moved := false
var process_frame: Signal


func _ready() -> void:
	if _moved:
		return
	var runner := Node.new()
	runner.set_script(get_script())
	runner.set("_moved", true)
	get_tree().root.add_child.call_deferred(runner)
	runner.ready.connect(runner._initialize, CONNECT_DEFERRED | CONNECT_ONE_SHOT)


func quit(code: int = 0) -> void:
	print("COST done")
	if not OS.has_feature("web"): get_tree().quit(code)


func _initialize() -> void:
	root = get_tree().root
	process_frame = get_tree().process_frame
	process_frame.connect(func(): _t_proc = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		_t_pre = Time.get_ticks_usec()
		if _t_proc != 0: _acc_proc += (_t_pre - _t_proc) / 1000.0)
	RenderingServer.frame_post_draw.connect(func(): if _t_pre != 0: _acc_draw += (Time.get_ticks_usec() - _t_pre) / 1000.0)
	call_deferred("run")


func _args() -> Array:
	var out: Array = Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("location.search", true)
		for p in str(q).trim_prefix("?").split("&"): out.append("--" + p.uri_decode())
	return out


func _arg(name: String, fallback: String) -> String:
	for a in _args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback


func run() -> void:
	var parts := _arg("size", "1920x987").split("x")
	var size := Vector2i(int(parts[0]), int(parts[1]))
	var frames := int(_arg("frames", "240"))
	var journey := _arg("journey", "goblin_waves")
	_shots = _arg("shots", "")
	var had_config := FileAccess.file_exists(Options.PATH)
	if _arg("device", "") == "phone": Options.force_device("phone")
	Options.set_value("render_scale", float(_arg("scale", "0.75")))
	Options.set_value("antialiasing", int(_arg("aa", "2")))
	Options.set_value("shadows", _arg("shadows", "0") == "1")
	if _arg("style", "") != "": Options.set_value("drawn_style", _arg("style", "on"))
	if _arg("cap", "") != "": Options.set_value("frame_cap", int(_arg("cap", "0")))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var deck: Dictionary = gs.profile.card_deck
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		if deck["cards"].has(pair[0]): deck["cards"][pair[0]]["race"] = pair[1]
	for id in deck["cards"]:
		deck["cards"][id]["progress"] = {"level": 25, "xp": 0}
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	for z in ["goblin_base", "pyramid", "orc_camp"]: gs.profile.unlocks["boss_" + z] = true
	seed(7)
	if not gs.start_journey(journey, 7):
		print("COST cannot start ", journey)
		quit(1)
		return
	await _frames(240)
	var stage: Node = get_tree().current_scene
	var sim = gs.session._sim
	# Skip to the boss wave: remove the field's monsters until no wave is queued.
	var guard := 0
	while sim.pending_wave_count() > 0 and guard < 40:
		guard += 1
		for id in sim.fighters:
			var f = sim.fighters[id]
			if f.team == "enemy" and f.is_alive():
				f.hp = 0.0
				f.state = f.State.DEAD
		await _frames(40)
	for id in sim.fighters:  # keep the squad alive for the measurement
		if sim.fighters[id].team != "enemy": sim.fighters[id].stats["HP"] = 1.0e7; sim.fighters[id].hp = 1.0e7
	await _frames(420)  # the boss wave walks in and the fight starts (VFX, numbers, statuses)
	var alive := 0
	for id in sim.fighters: if sim.fighters[id].is_alive(): alive += 1
	print("COST setup journey=%s size=%s scale=%s aa=%s style=%s device=%s alive=%d views=%d" % [journey, size, Options.value("render_scale"), Options.value("antialiasing"), DrawStyle.mode(), Options.device_class(), alive, stage.get("_views").size()])
	print("COST applied adapter=%s penalty=%s vp_scale=%.2f msaa=%d ssaa=%d screen_pass=%s" % [Options.web_renderer(), Options.scale_penalty(), root.scaling_3d_scale, root.msaa_3d, root.screen_space_aa, _nodes(func(n): return n.name == "InkScreenPass" and n.visible).size()])
	if _args().has("--gate"):
		stage.set_physics_process(false)
		await _frames(30)
		var ok := await _gate(journey, frames)
		if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
		quit(0 if ok else 1)
		return
	if _args().has("--matrix"):
		stage.set_physics_process(false)
		await _frames(30)
		await _matrix(frames)
	elif _args().has("--floor"):
		stage.set_physics_process(false)
		await _frames(30)
		await _floor(frames)
	elif _args().has("--live"):
		for i in 6: await _measure("live_%d" % i, frames)
	else:
		stage.set_physics_process(false)
		await _frames(30)
		await _toggles(stage, frames)
	if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	quit()


func _nodes(pred: Callable) -> Array:
	return root.find_children("*", "", true, false).filter(pred)


func _toggles(stage: Node, frames: int) -> void:
	var base := await _measure("base", frames, {})
	await _shot("base")
	if _args().has("--hulls"):
		var tally := {}
		for h in _nodes(func(n): return str(n.name).ends_with("_StudioInk") and n.is_visible_in_tree()):
			var tris := 0
			for sf in h.mesh.get_surface_count(): tris += h.mesh.surface_get_array_index_len(sf) / 3
			var key := str(h.name).trim_suffix("_StudioInk")
			tally[key] = int(tally.get(key, 0)) + tris
		var keys := tally.keys()
		keys.sort_custom(func(a, b): return tally[a] > tally[b])
		for k in keys: print("COST hull %s tris=%d" % [k, tally[k]])
	var groups := {
		"screen_pass": _nodes(func(n): return n.name == "InkScreenPass"),
		"stage_brush_hulls": _nodes(func(n): return n.name == "InkBrush"),
		"monster_ink_hulls": _nodes(func(n): return n.name == "InkOutline" and n is GeometryInstance3D),
		"hero_ink_hulls": _nodes(func(n): return str(n.name).ends_with("_StudioInk")),
		"label3d_sprites": _nodes(func(n): return n is Label3D or n is SpriteBase3D),
		"hud_canvas": _nodes(func(n): return n is CanvasLayer and n.visible),
		"omni_lights": _nodes(func(n): return n is OmniLight3D and n.visible),
		"vfx_nodes": _nodes(func(n): return n is GPUParticles3D or n is CPUParticles3D or (n is Node3D and n.get_script() != null and str(n.get_script().resource_path).get_file() in ["effect_player.gd", "violent_vfx.gd", "status_vfx.gd"])),
	}
	groups["all_3d_geometry"] = _nodes(func(n): return n is GeometryInstance3D and n.visible)
	groups["all_2d"] = _nodes(func(n): return n is CanvasLayer and n.visible)
	for key in groups:
		var nodes: Array = groups[key]
		if nodes.is_empty():
			print("COST %s (none)" % key)
			continue
		base = await _measure("  ref", frames / 2, {})  # a fresh reference right before each toggle (A/B, no drift)
		for n in nodes: n.visible = false
		await _frames(10)
		await _measure("no_" + key, frames, base, nodes.size())
		if key == "screen_pass": await _shot("no_screen_pass")
		for n in nodes: n.visible = true
	var env: Environment = null
	for we in _nodes(func(n): return n is WorldEnvironment): env = we.environment
	if env != null:
		var glow := env.glow_enabled
		env.glow_enabled = false
		await _frames(10)
		await _measure("no_glow(was %s)" % glow, frames, base)
		env.glow_enabled = glow
	if env != null:
		for prop in [["background_mode", Environment.BG_COLOR], ["fog_enabled", false], ["adjustment_enabled", false], ["tonemap_mode", Environment.TONE_MAPPER_LINEAR], ["ambient_light_source", Environment.AMBIENT_SOURCE_COLOR], ["reflected_light_source", Environment.REFLECTION_SOURCE_DISABLED]]:
			var was = env.get(prop[0])
			if was == prop[1]: continue
			base = await _measure("  ref", frames / 2, {})
			env.set(prop[0], prop[1])
			await _frames(10)
			await _measure("env_%s=%s(was %s)" % [prop[0], prop[1], was], frames, base)
			env.set(prop[0], was)
		if env.sky != null: print("COST sky material=%s process=%d radiance=%d" % [env.sky.sky_material.get_class() if env.sky.sky_material else "-", env.sky.process_mode, env.sky.radiance_size])
	var cam := root.get_camera_3d()
	if cam != null:
		base = await _measure("  ref", frames / 2, {})
		cam.current = false
		await _frames(10)
		await _measure("no_camera_3d", frames, base)
		cam.current = true
	var vp := root
	base = await _measure("  ref", frames / 2, {})
	var msaa := vp.msaa_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	await _frames(10)
	await _measure("msaa_off(was %d)" % msaa, frames, base)
	vp.msaa_3d = msaa
	var sc := vp.scaling_3d_scale
	for s in [0.5, 1.0]:
		base = await _measure("  ref", frames / 2, {})
		vp.scaling_3d_scale = s
		await _frames(10)
		await _measure("scale_%.2f" % s, frames, base)
	vp.scaling_3d_scale = sc
	# Everything 3D except the map: the fighters alone.
	var all_ink := _nodes(func(n): return n.name in ["InkScreenPass", "InkBrush", "InkOutline"] or str(n.name).ends_with("_StudioInk"))
	for n in all_ink: n.visible = false
	await _frames(10)
	await _measure("no_ink_at_all", frames, base)
	await _shot("no_ink_at_all")
	for n in all_ink: n.visible = true
	await _measure("base_again", frames, base)


func _measure(tag: String, frames: int, base: Dictionary = {}, count: int = -1) -> Dictionary:
	var times: Array[float] = []
	var dc := 0.0
	var prims := 0.0
	_acc_draw = 0.0
	_acc_proc = 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		if times[-1] > 25.0 and _args().has("--hitches"):
			print("COST hitch %s frame=%d ms=%.1f draw_ms=%.1f nodes=%d" % [tag, i, times[-1], (now - _t_pre) / 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n := float(frames)
	var mean := 0.0
	for t in times: mean += t
	mean /= n
	times.sort()
	var over50 := times.filter(func(t): return t > 50.0).size()
	var r := {"ms": mean, "p95": times[int(n * 0.95)], "max": times[-1], "over50": over50, "draw": _acc_draw / n, "proc": _acc_proc / n, "dc": dc / n, "prims": prims / n}
	var delta := ""
	if not base.is_empty():
		delta = " | d_ms=%+.2f d_draw=%+.2f d_dc=%+d d_prims=%+dk" % [r.ms - base.ms, r.draw - base.draw, roundi(r.dc - base.dc), roundi((r.prims - base.prims) / 1000.0)]
	print("COST %s%s frame_ms=%.2f fps=%.0f p95=%.2f max=%.1f over50=%d draw_ms=%.2f process_ms=%.2f dc=%d prims=%dk%s" % [tag, "" if count < 0 else "[%d]" % count, r.ms, 1000.0 / r.ms, r.p95, r.max, r.over50, r.draw, r.proc, roundi(r.dc), roundi(r.prims / 1000.0), delta])
	return r


func _shot(name: String) -> void:
	if _shots.is_empty(): return
	DirAccess.make_dir_recursive_absolute(_shots)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n: await process_frame


## The cost of an empty 3D frame: hide every mesh, then remove one more thing at a time (cumulative).
func _floor(frames: int) -> void:
	await _measure("floor_base", frames)
	for n in _nodes(func(n): return n is GeometryInstance3D and n.visible): n.visible = false
	await _frames(10)
	await _measure("floor_no_geometry", frames)
	for l in _nodes(func(n): return n is Light3D and n.visible): l.visible = false
	await _frames(10)
	await _measure("floor_+no_lights", frames)
	var vp := root
	vp.msaa_3d = Viewport.MSAA_DISABLED
	await _frames(10)
	await _measure("floor_+msaa_off", frames)
	for we in _nodes(func(n): return n is WorldEnvironment): we.environment = null
	var cam := root.get_camera_3d()
	if cam != null: cam.environment = null
	await _frames(10)
	await _measure("floor_+no_environment", frames)
	vp.scaling_3d_scale = 1.0
	await _frames(10)
	await _measure("floor_+scale_1", frames)
	print("COST floor viewport flags: transparent_bg=%s use_hdr_2d=%s debanding=%s screen_space_aa=%d scaling_mode=%d" % [vp.transparent_bg, vp.use_hdr_2d, vp.use_debanding, vp.screen_space_aa, vp.scaling_3d_mode])
	for v in _nodes(func(n): return n is SubViewport): print("COST subviewport %s size=%s update=%d" % [v.get_path(), v.size, v.render_target_update_mode])


## Render scale x MSAA x screen pass on the same frozen frame (the screen pass forced visible or hidden).
func _matrix(frames: int) -> void:
	var screens := _nodes(func(n): return n.name == "InkScreenPass")
	for sc in [1.0, 0.75, 0.5]:
		for aa in [2, 0, -1]:  # -1 = FXAA (screen-space), no MSAA
			for screen in [false, true]:
				if screens.is_empty() and screen: continue
				root.scaling_3d_scale = sc
				root.msaa_3d = Viewport.MSAA_2X if aa == 2 else Viewport.MSAA_DISABLED
				root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == -1 else Viewport.SCREEN_SPACE_AA_DISABLED
				for n in screens: n.visible = screen
				await _frames(15)
				await _measure("matrix scale=%.2f aa=%d screen=%s" % [sc, aa, screen], frames)
				if sc == 1.0 and aa == 2: await _shot("matrix_s100_aa2_screen%d" % int(screen))
				if sc == 1.0 and aa == -1: await _shot("matrix_s100_fxaa_screen%d" % int(screen))
				if sc == 1.0 and aa == 0: await _shot("matrix_s100_aa0_screen%d" % int(screen))
				if sc == 0.75 and aa == 2: await _shot("matrix_s075_aa2_screen%d" % int(screen))
				if sc == 0.5 and aa == 0: await _shot("matrix_s050_aa0_screen%d" % int(screen))


## Budget gate (data/perf/budgets.json): the frozen boss-wave frame against this zone's draw calls / primitives and
## the CPU part of the frame (process + draw submission). Prints "GATE PASS|FAIL ...".
func _gate(journey: String, frames: int) -> bool:
	var budgets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/perf/budgets.json"))
	var profile := "phone" if Options.device_class() == "phone" else "desktop"
	var row: Dictionary = budgets["zones"].get(journey, {}).get(profile, {})
	var r := await _measure("gate", frames)
	var cpu := float(r.proc)
	var fails := []
	if r.dc > float(row.get("draw_calls", 1e9)): fails.append("draw_calls %d > %d" % [r.dc, row.draw_calls])
	if r.prims > float(row.get("primitives", 1e12)): fails.append("primitives %d > %d" % [r.prims, row.primitives])
	if cpu > float(budgets["frame_cpu_ms"][profile]): fails.append("process_ms %.2f > %.2f" % [cpu, budgets["frame_cpu_ms"][profile]])
	print("GATE %s %s %s dc=%d prims=%d process_ms=%.2f %s" % ["PASS" if fails.is_empty() else "FAIL", journey, profile, r.dc, r.prims, cpu, ", ".join(fails)])
	return fails.is_empty()
