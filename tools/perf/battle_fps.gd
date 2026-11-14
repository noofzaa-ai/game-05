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


func _initialize() -> void:
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
	seed(7)
	game_state.start_journey(game_state.DEFAULT_JOURNEY, 7)
	await _frames(300)  # loading done, the squad meets the first wave
	var stage: Node = current_scene
	var tag := "hero_ink_%d" % int(hero)
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
	var last := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	times.sort()
	var n := float(frames)
	var mean := 0.0
	for t in times: mean += t
	var heroes := 0
	for id in stage.get("_views"):
		if str(stage.get("_session").fighters[id].team) == "player": heroes += 1
	print("BATTLE_FPS %s view=%s heroes=%d avg=%.1f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f dc=%d prims=%d" % [
		tag, view, heroes, 1000.0 * n / mean, times[int(n * 0.5)], times[int(n * 0.95)], times[int(n * 0.99)],
		roundi(dc / n), roundi(prims / n)])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
