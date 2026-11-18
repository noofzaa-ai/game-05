extends SceneTree
## Scratch probe (tech-artist 2026-11-18, not committed): a SOLO goblin FIGHT as the Boss's phone plays it.
##   --online : sign in on the LOCAL stack (tools/localstack/up.py + workers.sh), fixture veteran, GameState.start_journey
##              -> 1-player netfox room on the local room worker (the same path as staging solo FIGHT)
##   (default): the same fight on the local session (offline auto-battler)
## Then measures windows of 120 frames: fps p50/p95, draw calls, prims, ping, netfox restore/metadata cost per second,
## stage physics marks. Options: --size=WxH --scale=0.5 --fps=N (Engine.max_fps cap, web-like) --windows=N --slow=1
## (pretend a remembered slow device: no screen pass / hero ink).
const Options := preload("res://client/graphics_options.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")

var online := false
var size := Vector2i(1280, 720)
var scale := 0.5
var cap := 0
var windows := 12
var spikes := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--online": online = true
		elif a.begins_with("--size="): size = Vector2i(int(a.substr(7).split("x")[0]), int(a.substr(7).split("x")[1]))
		elif a.begins_with("--scale="): scale = float(a.substr(8))
		elif a.begins_with("--fps="): cap = int(a.substr(6))
		elif a.begins_with("--windows="): windows = int(a.substr(10))
		elif a == "--spikes": spikes = true
		elif a == "--slow=1":
			var c := ConfigFile.new(); c.set_value("device", "slow", true); c.save(DrawStyle.DEVICE_PATH)
	Options.set_value("render_scale", scale)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = cap
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var gs = root.get_node("GameState")
	if online:
		var state = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://build/localstack/state.json")))
		var acct = root.get_node("Online")
		acct.store.path = "user://probe_%d.json" % Time.get_ticks_usec()
		await acct.connect_account({"version": 1, "enabled": true, "scheme": "http", "host": "127.0.0.1", "port": 7350, "client_key": str(state.server_key)})
		if not await gs.connect_account_profile():
			printerr("PROBE_FAIL profile ", gs.online_error); quit(1); return
		var out: Array = []
		OS.execute("python", [ProjectSettings.globalize_path("res://tools/localstack/fixture.py"), "apply", acct.session.user_id, "veteran"], out, true)
		await gs.account_session.refresh_account()
		gs.profile = gs.account_session.profile
		print("PROBE start online solo: ", gs.start_journey(gs.WAVE_JOURNEY))
	else:
		gs.ensure_profile()
		var deck: Dictionary = gs.profile.card_deck
		for pair in [["sword_shield", "human"], ["greatsword", "viking"], ["longbow", "elf"]]:
			deck["cards"][pair[0]]["race"] = pair[1]
		deck["squad"] = ["sword_shield", "greatsword", "longbow"]
		print("PROBE start local solo: ", gs.start_journey(gs.WAVE_JOURNEY, 7))
	# wait for the stage
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var s = current_scene
		if s != null and s.get("_scene_presented") == true:
			break
	var stage = current_scene
	print("PROBE stage ", stage.name if stage else "none", " after ", Time.get_ticks_msec() - t0, " ms; slow_device=", DrawStyle.slow_device, " screen=", DrawStyle.screen_allowed(), " map=", stage.get("_map_id") if stage else "")
	for i in 240: await process_frame  # first wave closes in
	var marks: Dictionary = stage.get_script().get("perf_marks")
	if OS.get_cmdline_user_args().has("--census"):
		var by := {}
		for n in root.find_children("*", "", true, false):
			if n.is_physics_processing() or n.is_physics_processing_internal():
				var k := (str(n.get_script().resource_path).get_file() if n.get_script() != null else n.get_class()) + (" [internal]" if n.is_physics_processing_internal() and not n.is_physics_processing() else "")
				by[k] = int(by.get(k, 0)) + 1
		for k in by: print("PHYSNODES ", k, " ", by[k])
		print("PHYS ticks_per_second=", Engine.physics_ticks_per_second, " max_steps=", Engine.max_physics_steps_per_frame)
		quit()
		return
	if OS.get_cmdline_user_args().has("--shots"):
		var prev := 0; var saved := 0
		for i in 3000:
			await RenderingServer.frame_post_draw
			var sess = gs.remote_session
			var n: int = sess.fighters.size() if sess != null else 0
			var views: int = stage.get("_views").size() if stage.get("_views") != null else 0
			if n - prev >= 3 and saved < 2:
				for k in [0, 1, 2, 4, 8]:
					root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/po/wave%d_f%d.png" % [saved, k]))
					print("SHOT wave ", saved, " +", k, " fighters=", n, " views=", views, " pending=", stage.get("_pending_views").size())
					for j in (1 if k < 2 else 2 if k == 2 else 4): await RenderingServer.frame_post_draw
					views = stage.get("_views").size()
				saved += 1
			prev = n
		quit()
		return
	if spikes:
		await _spikes(stage, marks, gs)
		quit()
		return
	for w in windows:
		marks.clear()
		var sess = gs.remote_session
		var r0: int = sess.own_actor.restore_us if sess != null and sess.own_actor != null else 0
		var rc0: int = sess.own_actor.restore_count if sess != null and sess.own_actor != null else 0
		var p0: int = sess.own_actor.prediction_us if sess != null and sess.own_actor != null else 0
		var pt0: int = sess.own_actor.prediction_ticks if sess != null and sess.own_actor != null else 0
		var times: Array[float] = []
		var dc := 0.0; var prims := 0.0
		var last := Time.get_ticks_usec(); var w0 := last
		for i in 120:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0); last = now
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var secs := (last - w0) / 1e6
		times.sort()
		var line := "PROBE w=%d fps=%.1f p50=%.1f p95=%.1f max=%.0f dc=%d prims=%d" % [w, 120.0 / secs, times[60], times[114], times[119], roundi(dc / 120), roundi(prims / 120)]
		if sess != null and sess.own_actor != null:
			var m: Dictionary = sess.debug_metrics()
			line += " ping=%d restore_ms_per_s=%.1f restores_per_s=%.1f predict_ms_per_s=%.1f predict_ticks_per_s=%.1f fighters=%d" % [int(m.ping_ms), (sess.own_actor.restore_us - r0) / 1000.0 / secs, (sess.own_actor.restore_count - rc0) / secs, (sess.own_actor.prediction_us - p0) / 1000.0 / secs, (sess.own_actor.prediction_ticks - pt0) / secs, sess.fighters.size()]
		else:
			line += " fighters=%d" % gs.get_session().fighters.size() if gs.get_session() != null and "fighters" in gs.get_session() else ""
		var parts := []
		for k in marks: parts.append("%s=%.1f" % [k, marks[k] / 1000.0 / secs])
		print(line, " | stage_ms_per_s ", " ".join(parts))
	if FileAccess.file_exists(DrawStyle.DEVICE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(DrawStyle.DEVICE_PATH))
	if gs.remote_session != null: gs.stop_online_room()
	await create_timer(1.0).timeout
	quit()


func _spikes(stage, marks: Dictionary, gs) -> void:
	var rows: Array = []
	var types := {}
	var sess = gs.get_session()
	var ev_hook := func() -> void:
		if sess != null and "events" in sess:
			for e in sess.events: types[str(e.get("type", ""))] = int(types.get(str(e.get("type", "")), 0)) + 1
	physics_frame.connect(ev_hook)
	var ph := {"p": 0, "proc": 0, "pre": 0, "a_phys": 0.0, "a_proc": 0.0, "a_draw": 0.0}
	physics_frame.connect(func(): if int(ph["p"]) == 0: ph["p"] = Time.get_ticks_usec())
	process_frame.connect(func():
		ph["proc"] = Time.get_ticks_usec()
		if int(ph["p"]) != 0: ph["a_phys"] = (int(ph["proc"]) - int(ph["p"])) / 1000.0)
	RenderingServer.frame_pre_draw.connect(func():
		ph["pre"] = Time.get_ticks_usec()
		ph["a_proc"] = (int(ph["pre"]) - int(ph["proc"])) / 1000.0)
	RenderingServer.frame_post_draw.connect(func():
		ph["a_draw"] = (Time.get_ticks_usec() - int(ph["pre"])) / 1000.0
		ph["p"] = 0)
	var nt = root.get_node("/root/NetworkTime")
	var nr = root.get_node("/root/NetworkRollback")
	var acc := {"loop": 0, "rb": 0, "ticks": 0, "t0": 0, "r0": 0}
	nt.before_tick_loop.connect(func(): acc["t0"] = Time.get_ticks_usec())
	nt.after_tick_loop.connect(func(): acc["loop"] += Time.get_ticks_usec() - int(acc["t0"]))
	nt.on_tick.connect(func(_d, _t): acc["ticks"] += 1)
	nr.before_loop.connect(func(): acc["r0"] = Time.get_ticks_usec())
	nr.after_loop.connect(func(): acc["rb"] += Time.get_ticks_usec() - int(acc["r0"]))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var last := Time.get_ticks_usec()
	for i in 3000:
		if not is_instance_valid(stage) or current_scene != stage: break
		marks.clear(); types.clear(); acc["loop"] = 0; acc["rb"] = 0; acc["ticks"] = 0
		var rs = gs.remote_session
		var meta0: int = rs.metadata_apply_us if rs != null else 0
		var dec0: int = rs.lag_decode_us if rs != null else 0
		var res0: int = rs.own_actor.restore_us if rs != null and rs.own_actor != null else 0
		var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var vp := root.get_viewport_rid()
		var sess2 = gs.remote_session
		rows.append([ms, i, marks.duplicate(), types.duplicate(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS)*1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp), (sess2.server_state.get("projectiles", []).size() if sess2 != null else -1), acc["loop"] / 1000.0, acc["rb"] / 1000.0, acc["ticks"], ph["a_phys"], ph["a_proc"], ph["a_draw"], ((rs.metadata_apply_us - meta0) / 1000.0 if rs != null else 0.0), ((rs.lag_decode_us - dec0) / 1000.0 if rs != null else 0.0), ((rs.own_actor.restore_us - res0) / 1000.0 if rs != null and rs.own_actor != null else 0.0)])
	var times := rows.map(func(r): return r[0]); times.sort()
	print("SPIKE dist n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f" % [times.size(), times[times.size()/2], times[int(times.size()*.95)], times[int(times.size()*.99)], times[-1]])
	var by := {}
	for r in rows:
		var keys: Array = r[3].keys() if not r[3].is_empty() else ["(none)"]
		for k in keys:
			if not by.has(k): by[k] = [0, 0.0, 0]
			by[k][0] += 1; by[k][1] += r[0]; by[k][2] += int(r[0] > 25.0)
	var tl := 0.0; var rbs := 0.0; var tt := 0.0; var mt := 0.0; var dt := 0.0; var rt := 0.0; var phy := 0.0; var pro := 0.0; var drw := 0.0
	for r in rows: tl += r[10]; rbs += r[11]; tt += r[0]; mt += r[16]; dt += r[17]; rt += r[18]; phy += r[13]; pro += r[14]; drw += r[15]
	print("SHARE of frame time: physics_phase=%.0f%% process_phase=%.0f%% draw_submit=%.0f%% | metadata_apply=%.0f%% decode=%.0f%% restore=%.0f%%" % [phy / tt * 100, pro / tt * 100, drw / tt * 100, mt / tt * 100, dt / tt * 100, rt / tt * 100])
	print("NETFOX tickloop_ms_per_s=%.1f rollback_ms_per_s=%.1f" % [tl / tt * 1000.0, rbs / tt * 1000.0])
	for k in by: print("EVT %s frames=%d mean_ms=%.1f over25=%d" % [k, by[k][0], by[k][1] / by[k][0], by[k][2]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 25):
		var m := []
		for k in r[2]: if r[2][k] > 500: m.append("%s=%.1f" % [k, r[2][k] / 1000.0])
		print("SPIKE %.1f ms split phys=%.1f proc=%.1f draw=%.1f meta=%.1f decode=%.1f restore=%.1f frame=%d nodes%+d dc=%d mproc=%.1f mphys=%.1f rcpu=%.1f proj=%d ticks=%d tickloop=%.1f rollback=%.1f marks[%s] events%s" % [r[0], r[13], r[14], r[15], r[16], r[17], r[18], r[1], r[4], r[5], r[6], r[7], r[8], r[9], r[12], r[10], r[11], " ".join(m), r[3].keys()])
