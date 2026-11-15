extends SceneTree
## Battle frame rate and shots of the 3-card squad's wave fight (hero ink look A/B, 2026-11-15). Run windowed:
##   godot --path . --script res://tools/perf/battle_fps.gd -- [--hero-ink=0|1] [--size=1280x720] [--scale=0.5]
##       [--frames=600] [--shots=<dir>] [--style=on|lite|off]
## Starts the default wave journey with the profile's squad, waits for the fight to close in, measures `frames`
## frames of the running fight (no freeze), then freezes it and saves <shots>/<tag>_{overview,follow}.png (the follow
## view zooms the camera on squad member 1). Prints "BATTLE_FPS hero_ink=.. view=.. avg=.. p50_ms=.. p95_ms=.. p99_ms=..
## dc=.. prims=..". Render scale / AA go through client/graphics_options.gd; user://graphics.cfg is removed at the end
## when it did not exist before.
const Options := preload("res://client/graphics_options.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")


var _t_phys := 0  # first physics_frame of the current frame (0 = none)
var _t_proc := 0
var _t_pre := 0
var _acc_phys := 0.0  # per-frame script+engine time split (ms), summed over a _measure window
var _acc_proc := 0.0
var _acc_draw := 0.0
var _steps := 0


func _initialize() -> void:
	physics_frame.connect(func(): if _t_phys == 0: _t_phys = Time.get_ticks_usec(); _steps += 1)
	process_frame.connect(func(): _t_proc = Time.get_ticks_usec(); if _t_phys != 0: _acc_phys += (_t_proc - _t_phys) / 1000.0)
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec(); if _t_proc != 0: _acc_proc += (_t_pre - _t_proc) / 1000.0)
	RenderingServer.frame_post_draw.connect(func():
		if _t_pre != 0: _acc_draw += (Time.get_ticks_usec() - _t_pre) / 1000.0
		_t_phys = 0)
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	var scale := 0.5
	var frames := 600
	var shots := ""
	var hero := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--scale="): scale = float(a.substr(8))
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--shots="): shots = a.substr(8)
		elif a.begins_with("--hero-ink="): hero = a.substr(11) == "1"
	var had_config := FileAccess.file_exists(Options.PATH)
	Options.set_value("render_scale", scale)
	DrawStyle.heroes_inked = hero
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(size)
	root.size = size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	# New decks start with an empty squad (tutorial, 2026-11-15): give the probe a raced 3-card squad.
	var deck: Dictionary = game_state.profile.card_deck
	for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
		deck["cards"][pair[0]]["race"] = pair[1]
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	seed(7)
	game_state.start_journey(game_state.DEFAULT_JOURNEY, 7)
	await _frames(300)  # loading done, the squad meets the first wave
	var stage: Node = current_scene
	var tag := "hero_ink_%d" % int(hero)
	if OS.get_cmdline_user_args().has("--attribution"):
		await _attribution(stage, frames)
		quit()
		return
	await _measure(stage, tag, "overview", frames)
	await _frozen_ab(stage, shots, "overview", frames / 2)
	stage.set_physics_process(true)
	var rig = stage.get("_rig")
	var views: Dictionary = stage.get("_views")
	var first := -1
	for id in views:
		if str(stage.get("_session").fighters[id].team) == "player":
			first = id
			break
	if first >= 0:
		stage.set("_focus_id", first)
	if rig != null:
		for i in 9: rig._orbit(Vector2.ZERO, 0.85)
	await _frames(90)
	await _measure(stage, tag, "follow", frames / 2)
	await _frozen_ab(stage, shots, "follow", frames / 2)
	if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	quit()


## The same frozen frame with the heroes' ink look on, then off (hulls hidden, toon card_ink off): an exact A/B of
## its cost, and the before/after shots. (Off also hides the thin Studio head/hair hull, a few draws.)
func _frozen_ab(stage: Node, shots: String, view: String, frames: int) -> void:
	stage.set_physics_process(false)
	for on in [true, false]:
		_set_hero_ink(stage, on)
		await _frames(20)
		if not shots.is_empty():
			DirAccess.make_dir_recursive_absolute(shots)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shots.path_join("%s_%s.png" % [view, "after" if on else "before"]))
		await _measure(stage, "frozen_ink_%d" % int(on), view, frames)
	_set_hero_ink(stage, true)


func _set_hero_ink(stage: Node, on: bool) -> void:
	for id in stage.get("_views"):
		if str(stage.get("_session").fighters[id].team) != "player":
			continue
		var view: Node = stage.get("_views")[id]
		for node in view.find_children("*", "MeshInstance3D", true, false):
			if str(node.name).ends_with("_StudioInk"):
				node.visible = on
			for surface in node.get_surface_override_material_count():
				var material = node.get_surface_override_material(surface)
				if material is ShaderMaterial and material.shader != null and str(material.shader.resource_path).ends_with("studio05_toon.gdshader"):
					material.set_shader_parameter("card_ink", on)


func _measure(stage: Node, tag: String, view: String, frames: int) -> void:
	var times: Array[float] = []
	var dc := 0.0
	var prims := 0.0
	var proc := 0.0
	var phys := 0.0
	var rcpu := 0.0
	var rgpu := 0.0
	var hitches := 0
	var vp := root.get_viewport_rid()
	_acc_phys = 0.0; _acc_proc = 0.0; _acc_draw = 0.0; _steps = 0
	var marks = stage.get_script().get("perf_marks")
	if marks is Dictionary: marks.clear()
	var last := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		times.append(ms)
		if ms > 50.0: hitches += 1
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	times.sort()
	var n := float(frames)
	var mean := 0.0
	for t in times: mean += t
	var heroes := 0
	for id in stage.get("_views"):
		if str(stage.get("_session").fighters[id].team) == "player": heroes += 1
	print("BATTLE_FPS %s view=%s heroes=%d avg=%.1f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.1f hitches50=%d dc=%d prims=%d process_ms=%.2f physics_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f | frame_split physics=%.2f process=%.2f draw=%.2f steps/frame=%.2f" % [
		tag, view, heroes, 1000.0 * n / mean, times[int(n * 0.5)], times[int(n * 0.95)], times[int(n * 0.99)],
		times[-1], hitches, roundi(dc / n), roundi(prims / n), proc / n, phys / n, rcpu / n, rgpu / n,
		_acc_phys / n, _acc_proc / n, _acc_draw / n, _steps / n])
	_print_marks(stage, frames)


## Live fight: per script, the process-phase time with that script's nodes processing vs not (they keep their
## last state for the window). Prints "ATTR <script> nodes=<n> process_ms_saved=<ms>".
func _attribution(stage: Node, frames: int) -> void:
	stage.set_physics_process(false)
	await _frames(30)
	var by_script := {}
	for node in root.find_children("*", "", true, false):
		var sc = node.get_script()
		if sc == null or not node.is_processing(): continue
		var key := str(sc.resource_path).get_file()
		if key == "fighter_view.gd": key += ":" + ("hero" if node.get("_model") != null else "monster")
		if key.is_empty(): key = "(builtin)"
		if not by_script.has(key): by_script[key] = []
		by_script[key].append(node)
	for key in by_script:
		var base := 0.0
		var off := 0.0
		for rep in 3:
			base += await _process_ms(frames / 6) / 3.0
			for n in by_script[key]: if is_instance_valid(n): n.set_process(false)
			off += await _process_ms(frames / 6) / 3.0
			for n in by_script[key]: if is_instance_valid(n): n.set_process(true)
		print("ATTR %s nodes=%d process_on=%.2f off=%.2f saved=%.2f" % [key, by_script[key].size(), base, off, base - off])


func _process_ms(frames: int) -> float:
	_acc_proc = 0.0
	for i in frames: await RenderingServer.frame_post_draw
	return _acc_proc / frames


func _print_marks(stage: Node, frames: int) -> void:
	var marks = stage.get_script().get("perf_marks")
	if not marks is Dictionary or _steps == 0: return
	var parts := []
	for k in marks: parts.append("%s=%.2f" % [k, marks[k] / 1000.0 / _steps])
	print("  STEP_MS ", " ".join(parts))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
