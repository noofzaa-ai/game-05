extends SceneTree
## Render counters for the goblin_base stages at a fixed graphics setup (default: Boss's PC web report of
## 2026-11-09 -- MSAA 4x, glow, outline, render scale 1.0, no shadows/fog/decorative lights, 1920x912).
## For each map and camera spot: draw calls, primitives, and the share of the map art (ArtScene children
## hidden one at a time). Frame times on this machine are only indicative (native, not the web build).
## Needs a window (no --headless):
##   godot --path . --script res://tools/perf/goblin_stage_render_measure.gd [-- [--aa=N] [--no-glow] [--no-outline]
##       [--spot=start|north|south_west|east] [--frames=N] [--shots=<dir>] [--breakdown] [map_id ...]]
## It writes user://graphics.cfg (the chosen setup): delete it afterwards to get the defaults back.
const MAPS := ["goblin_base_gate", "goblin_base_courtyard", "goblin_base_quarry", "goblin_base_chief", "goblin_base_rest"]
const Options := preload("res://client/graphics_options.gd")
const MapLoader := preload("res://logic/map_loader.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var aa := 4
	var breakdown := false
	var glow := true
	var outline := true
	var spots_only := ""
	var samples := 8
	var shots := ""
	var ids: Array = []
	for a in args:
		if a.begins_with("--aa="): aa = int(a.substr(5))
		elif a == "--breakdown": breakdown = true
		elif a == "--no-glow": glow = false
		elif a == "--no-outline": outline = false
		elif a.begins_with("--spot="): spots_only = a.substr(7)
		elif a.begins_with("--frames="): samples = int(a.substr(9))
		elif a.begins_with("--shots="): shots = a.substr(8)
		else: ids.append(a)
	if ids.is_empty(): ids = MAPS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 912))
	root.size = Vector2i(1920, 912)
	for pair in [["outline", outline], ["glow", glow], ["shadows", false], ["fog", false], ["decorative_lights", false]]:
		Options.set_value(pair[0], pair[1])
	Options.set_value("render_scale", 1.0)
	Options.set_value("antialiasing", aa)
	_samples = samples
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	for id in ids:
		var map = MapLoader.load_by_id(id)
		var t0 := Time.get_ticks_msec()
		game_state.start_stage(game_state.Mode.PVE, id)
		await _frames(4)
		var stage: Node = current_scene
		stage.set_physics_process(false)
		await _frames(60)
		print("%s entry_to_steady_ms=%d" % [id, Time.get_ticks_msec() - t0])
		var views: Dictionary = stage.get("_views")
		var player: Node3D = views[1]
		var spots := {"start": player.global_position, "north": Vector3(0, .05, -map.half_depth * .35),
			"south_west": Vector3(-map.half_width + 1, .05, map.half_depth - .8), "east": Vector3(map.half_width - 1, .05, 0)}
		var art: Node3D = stage.find_child("ArtScene", true, false)
		for spot in spots:
			if spots_only != "" and spot != spots_only: continue
			player.global_position = spots[spot]
			await _frames(50)
			var total := await _measure()
			if shots != "":
				DirAccess.make_dir_recursive_absolute(shots)
				root.get_texture().get_image().save_png(shots.path_join("%s_%s.png" % [id, spot]))
			var line := "%s %-10s dc=%d prims=%d frame_ms=%.1f render_cpu_ms=%.1f render_gpu_ms=%.1f" % [id, spot, total[0], total[1], total[2], total[3], total[4]]
			if art != null:
				art.visible = false
				var bare := await _measure()
				art.visible = true
				line += "   map_art dc=%d prims=%d" % [total[0] - bare[0], total[1] - bare[1]]
				if breakdown and spot == "start":
					for child in art.get_children():
						if not child is GeometryInstance3D or not child.visible: continue
						child.visible = false
						var without := await _measure()
						child.visible = true
						line += "\n    %-18s dc=%d prims=%d" % [child.name, total[0] - without[0], total[1] - without[1]]
			if breakdown and spot == "start":
				print(line); line = "  stage children (not ArtScene):"
				for child in stage.get_children():
					if child == art or not child is Node3D or not child.visible: continue
					child.visible = false
					var without := await _measure()
					child.visible = true
					if total[0] - without[0] != 0 or total[1] - without[1] != 0:
						print("    %-28s dc=%d prims=%d" % [str(child.name).left(28), total[0] - without[0], total[1] - without[1]])
			print(line)
		await _frames(10)
	quit()


var _samples := 8


## [draw calls, primitives, mean frame ms, mean viewport render CPU ms, GPU ms] over _samples frames.
func _measure() -> Array:
	await _frames(3)
	var dc := 0.0; var prims := 0.0; var cpu := 0.0; var gpu := 0.0; var t := Time.get_ticks_usec()
	var rid := root.get_viewport_rid()
	for i in _samples:
		await RenderingServer.frame_post_draw
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var n := float(_samples)
	return [roundi(dc / n), roundi(prims / n), (Time.get_ticks_usec() - t) / 1000.0 / n, cpu / n, gpu / n]


func _frames(n: int) -> void:
	for i in n:
		await process_frame
