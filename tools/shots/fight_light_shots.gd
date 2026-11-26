extends SceneTree
## Fight readability check (tech-artist 2026-11-25, Boss: fight scene too dark, VFX hierarchy): the real stage of each
## zone's fight board, windowed, at --size=WxH. Per map: <out>/<tag>_<map>_<WxH>_fight.png after 6 s of the live fight
## (seed fixed), then a 300-frame perf window of the running fight: prints
## "FIGHT_LIGHT map=.. size=.. p50_ms=.. p95_ms=.. dc_avg=.. fx_max=..".
##   godot --path . --script res://tools/shots/fight_light_shots.gd -- --tag=before --size=844x390 --out=<dir> [map ...]
const MAPS := ["goblin_base_courtyard", "mummy_pyramid_hall", "orc_camp_night", "elder_grove_heart"]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	var out := OS.get_environment("TEMP").path_join("zorx_fight_light")
	var tag := "shot"
	var maps: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--tag="): tag = a.substr(6)
		else: maps.append(a)
	if maps.is_empty():
		maps = MAPS
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	for id in maps:
		seed(11)
		gs.start_stage(gs.Mode.PVE, id)
		await _frames(360)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s_%s_%dx%d_fight.png" % [tag, id, size.x, size.y]))
		var times: Array[float] = []
		var dc := 0.0
		var fx_max := 0
		var stage = current_scene
		var effects = stage.get("_effects") if stage != null else null
		var last := Time.get_ticks_usec()
		for i in 300:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			if effects != null:
				fx_max = maxi(fx_max, effects.live_count())
		times.sort()
		print("FIGHT_LIGHT map=%s size=%dx%d p50_ms=%.2f p95_ms=%.2f dc_avg=%.0f fx_max=%d" % [id, size.x, size.y,
			times[150], times[285], dc / 300.0, fx_max])
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
