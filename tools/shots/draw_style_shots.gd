extends SceneTree
## Draw-style prototype review (tech-artist 2026-11-13, Boss: "feel like watching a cartoon").
## Opens a real auto-battle stage, lets the fight start, freezes the simulation, then for two camera views
## (the arena overview and a closer look) saves a PNG and measures frame time. Needs a window (no --headless):
##   godot --path . --script res://tools/shots/draw_style_shots.gd -- [--style=ink_a|ink_b|ink_c] [--out=<dir>]
##       [--size=1280x720] [--scale=1.0] [--aa=2] [--frames=240] [--audit] [map_id ...]
## --style is read by client/draw_style.gd (the same switch as the web URL ?style=). Output:
## <out>/<map>_{overview,close}.png and lines "DRAWSTYLE <style> <map> <view> frame_ms=.. cpu=.. gpu=.. dc=.. prims=..".
## It sets render scale/AA through client/graphics_options.gd (user://graphics.cfg) and deletes that file at the end.
const Options := preload("res://client/graphics_options.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var out := "res://build/draw_style/before"
	var style := ""
	var size := Vector2i(1280, 720)
	var scale := 1.0
	var aa := 2
	var frames := 240
	var audit := false
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--style="): style = a.substr(8)
		elif a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--scale="): scale = float(a.substr(8))
		elif a.begins_with("--aa="): aa = int(a.substr(5))
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a == "--audit": audit = true
		elif not a.begins_with("--"): ids.append(a)
	if ids.is_empty(): ids = ["goblin_base_gate", "mummy_arena_a"]
	var had_config := FileAccess.file_exists(Options.PATH)
	Options.set_value("render_scale", scale)
	Options.set_value("antialiasing", aa)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(size)
	root.size = size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	DirAccess.make_dir_recursive_absolute(out)
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	for id in ids:
		game_state.start_stage(game_state.Mode.PVE, id)
		await _frames(5)
		var stage: Node = current_scene
		await _frames(240)  # loading label gone, fighters closing in
		stage.set_physics_process(false)  # freeze the fight: every style sees the same moment
		if audit: _audit(stage)
		await _frames(30)
		await _shoot_and_measure(out, style, id, "overview", frames)
		var rig = stage.get("_rig")
		if rig != null:
			for i in 7: rig._orbit(Vector2.ZERO, 0.88)
		await _frames(60)
		await _shoot_and_measure(out, style, id, "close", frames)
	if not had_config: DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	quit()


func _shoot_and_measure(out: String, style: String, id: String, view: String, frames: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [id, view]))
	var rid := root.get_viewport_rid()
	var times: Array[float] = []
	var cpu := 0.0; var gpu := 0.0; var dc := 0.0; var prims := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	times.sort()
	var n := float(frames)
	var mean := 0.0
	for t in times: mean += t
	print("DRAWSTYLE %s %s %s frame_ms=%.2f p50=%.2f p95=%.2f cpu=%.2f gpu=%.2f dc=%d prims=%d" % [
		style if style != "" else "default", id, view, mean / n, times[int(n * 0.5)], times[int(n * 0.95)],
		cpu / n, gpu / n, roundi(dc / n), roundi(prims / n)])


## Prints every drawn geometry of the stage: what kind of material it uses and whether it is toon/outlined.
func _audit(stage: Node) -> void:
	var counts := {}
	for node in stage.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if not g.is_visible_in_tree(): continue
		var group := "other"
		var p: Node = g
		while p != null and p != stage:
			var pname := str(p.name)
			if pname == "ArtScene": group = "map_art"; break
			if p.get_script() != null and str(p.get_script().resource_path).ends_with("fighter_view.gd"): group = "fighter"; break
			if p.get_script() != null and str(p.get_script().resource_path).ends_with("atmosphere.gd"): group = "atmosphere"; break
			p = p.get_parent()
		var mats: Array = []
		var mesh: Mesh = null
		if g is MeshInstance3D: mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null: mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if g.material_override != null: mats.append(g.material_override)
		elif mesh != null:
			for s in mesh.get_surface_count():
				var m: Material = (g as MeshInstance3D).get_active_material(s) if g is MeshInstance3D else mesh.surface_get_material(s)
				mats.append(m)
		for m in mats:
			var kind := _kind(m)
			var key := "%s | %s | %s" % [group, g.get_class(), kind]
			counts[key] = int(counts.get(key, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	for k in keys: print("AUDIT %4d  %s" % [counts[k], k])
	var env := stage.find_children("*", "WorldEnvironment", true, false)
	for e in env:
		var en: Environment = e.environment
		print("AUDIT env tonemap=%d glow=%s fog=%s adj=%s sat=%.2f con=%.2f ambient=%s/%.2f bg=%d" % [en.tonemap_mode, en.glow_enabled, en.fog_enabled, en.adjustment_enabled, en.adjustment_saturation, en.adjustment_contrast, en.ambient_light_color, en.ambient_light_energy, en.background_mode])
	for l in stage.find_children("*", "Light3D", true, false):
		print("AUDIT light %s %s energy=%.2f shadow=%s mask=%d" % [l.get_class(), l.name, l.light_energy, l.shadow_enabled, l.light_cull_mask])


func _kind(m: Material) -> String:
	if m == null: return "null"
	var outline := ""
	var next := m.next_pass
	if next is ShaderMaterial: outline = " +next:" + str((next as ShaderMaterial).shader.resource_path.get_file())
	if m is ShaderMaterial:
		return "Shader:" + str((m as ShaderMaterial).shader.resource_path.get_file()) + outline
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var shading: String = ["unshaded", "per-pixel", "per-vertex"][b.shading_mode]
		var diffuse: String = ["burley", "lambert", "lambert_wrap", "TOON"][b.diffuse_mode]
		return "Std %s %s tex=%s vc=%s alpha=%d%s" % [shading, diffuse, b.albedo_texture != null, b.vertex_color_use_as_albedo, b.transparency, outline]
	return m.get_class()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
