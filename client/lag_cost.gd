extends RefCounted
## Cheap cost counters for the Lag report ("cost" section, Boss 2026-11-18). The phone shows a steady train of
## 170-236 ms frames about once a second; this records, per second, what ran (profile rebuilds, enemy view builds and
## the nodes they create, netfox restores) and, for every frame over SLOW_MS, which coarse phase was busiest, so the next
## report can pin the periodic hitch. Counters are static: any file can note work, only the lag report reads them.
##
## v2 (Boss 2026-11-19: 85 of 90 slow frames were the unmeasured "other"). A frame is now split by the engine's own
## signals into four spans that add up to the frame:
##   physics  first physics_frame -> process_frame: the 60 Hz steps (stage_view tick, view builds, events) and the
##            network poll (state apply), which the engine runs just before process_frame
##   process  process_frame -> frame_pre_draw: every _process (netfox tick + restores, animation, skeletons, effects)
##   draw     frame_pre_draw -> frame_post_draw: render submit (on WebGL the driver can block in here)
##   outside  the rest: time the engine did not run at all (browser, JS garbage collection, compositor, waiting for the
##            next animation frame, a frame cap). On the web the engine clock IS performance.now(), so this is the
##            browser's share of the frame measured on the browser's own clock.
## The busiest phase of a slow frame is one of the named script parts or physics_other / process_other / draw /
## outside (what is left of each span after the named parts in it). Web only: a few device hints the browser exposes
## (battery charging and level, deviceMemory, cores, JS heap; most are missing on iOS Safari) and page visibility
## changes, read when the report is built.
const SLOW_MS := 100
const SECONDS := 10  ## one-second buckets kept
const SLOW_KEPT := 8  ## the latest slow frames kept in full
const COLUMNS := ["second", "frames", "restores", "restore_ms", "profile_full", "profile_full_ms", "profile_inplace", "view_builds", "view_build_ms", "view_nodes", "view_nodes_max_frame", "slow_frames", "netfox_tick_ms", "physics_ms", "process_ms", "draw_ms", "outside_ms"]
const PHASES := ["netfox_tick", "state_apply", "view_build", "view_update", "vfx_audio", "hud_camera", "physics_other", "process_other", "draw", "outside"]
const SLOW_COLUMNS := ["t_since_first_sample_s", "frame_ms", "busiest", "busiest_ms", "netfox_tick_ms", "state_apply_ms", "view_build_ms", "profile_full", "nodes_created", "restores", "physics_ms", "process_ms", "draw_ms", "outside_ms"]
## Read once per report (never per frame). Every field is optional: a browser that lacks one leaves it out.
const DEVICE_JS := "(function(){var o={};try{if(navigator.deviceMemory)o.device_memory_gb=navigator.deviceMemory;if(navigator.hardwareConcurrency)o.cores=navigator.hardwareConcurrency;var m=performance.memory;if(m){o.js_heap_mb=Math.round(m.usedJSHeapSize/1048576);o.js_heap_limit_mb=Math.round(m.jsHeapSizeLimit/1048576);}var b=window.zorxBattery;if(b){o.charging=b.charging;o.battery=b.level;}o.visibility=document.visibilityState;o.visibility_changes=window.zorxVisibilityChanges||0;}catch(e){}return JSON.stringify(o);})()"
## Installed once: counts visibility changes and keeps the battery state (navigator.getBattery, not on iOS Safari).
const DEVICE_HOOK_JS := "(function(){if(window.zorxDeviceHooked)return;window.zorxDeviceHooked=true;window.zorxVisibilityChanges=0;document.addEventListener('visibilitychange',function(){window.zorxVisibilityChanges++;});try{if(navigator.getBattery)navigator.getBattery().then(function(b){var u=function(){window.zorxBattery={charging:b.charging,level:Math.round(b.level*100)/100};};u();b.addEventListener('chargingchange',u);b.addEventListener('levelchange',u);}).catch(function(){});}catch(e){}})()"

static var profile_full := 0  ## whole-Profile rebuilds from a metadata snapshot
static var profile_full_us := 0
static var profile_inplace := 0  ## metadata changes applied without a rebuild (run bag only, or item wear only)
static var view_builds := 0
static var view_build_us := 0
static var view_nodes := 0
static var _frame_nodes := 0
static var _tick_us := 0
static var _tick_start := 0
static var _hooked := false
static var _frame_hooked := false
static var _device_hooked := false
static var buckets: Array = []
static var slow_by_phase := {}
static var slow_total := 0
static var slow_frames: Array = []
static var _last := {}
static var _last_us := 0
static var _started_us := 0
## Engine phase marks (usec). sample() runs inside _process of frame N: the physics span is frame N's, the process and
## draw spans are frame N-1's (finished); together with "outside" they cover the time since the previous sample.
static var _phys_start := 0
static var _proc_start := 0
static var _pre_draw := 0
static var _physics_us := 0
static var _process_us := 0
static var _draw_us := 0


static func note_profile(us: int, in_place: bool) -> void:
	if in_place: profile_inplace += 1
	else:
		profile_full += 1
		profile_full_us += us


static func note_view_build(us: int, nodes: int) -> void:
	view_builds += 1
	view_build_us += us
	view_nodes += nodes
	_frame_nodes += nodes


static func hook(tree: SceneTree) -> void:
	if tree == null: return
	if not _frame_hooked:
		_frame_hooked = true
		tree.physics_frame.connect(func(): if _phys_start == 0: _phys_start = Time.get_ticks_usec())
		tree.process_frame.connect(func():
			_proc_start = Time.get_ticks_usec()
			_physics_us = _proc_start - _phys_start if _phys_start > 0 else 0)
		RenderingServer.frame_pre_draw.connect(func():
			_pre_draw = Time.get_ticks_usec()
			_process_us = _pre_draw - _proc_start if _proc_start > 0 else 0)
		RenderingServer.frame_post_draw.connect(func():
			_draw_us = Time.get_ticks_usec() - _pre_draw if _pre_draw > 0 else 0
			_phys_start = 0)
	if not _device_hooked and OS.has_feature("web"):
		_device_hooked = true
		JavaScriptBridge.eval(DEVICE_HOOK_JS, true)
	if _hooked: return
	var clock = tree.root.get_node_or_null("NetworkTime")
	if clock == null: return
	clock.before_tick_loop.connect(func(): _tick_start = Time.get_ticks_usec())
	clock.after_tick_loop.connect(func(): _tick_us += Time.get_ticks_usec() - _tick_start)
	_hooked = true


## Pure: splits one frame (ms). `named` = the measured script parts; physics / process / draw = the engine spans. The
## parts that run in a span are taken out of it (stage work and state apply: physics; netfox tick: process); what the
## spans do not cover is "outside". Returns every PHASES key.
static func split(frame_ms: float, named: Dictionary, physics_ms: float, process_ms: float, draw_ms: float) -> Dictionary:
	var ms := {}
	for key in ["netfox_tick", "state_apply", "view_build", "view_update", "vfx_audio", "hud_camera"]:
		ms[key] = maxf(0.0, float(named.get(key, 0.0)))
	var in_physics: float = ms["state_apply"] + ms["view_build"] + ms["view_update"] + ms["vfx_audio"] + ms["hud_camera"]
	ms["physics_other"] = maxf(0.0, physics_ms - in_physics)
	ms["process_other"] = maxf(0.0, process_ms - ms["netfox_tick"])
	ms["draw"] = maxf(0.0, draw_ms)
	ms["outside"] = maxf(0.0, frame_ms - maxf(physics_ms, in_physics) - maxf(process_ms, ms["netfox_tick"]) - ms["draw"])
	return ms


## The busiest phase of a split frame (ties: the first in PHASES).
static func busiest(ms: Dictionary) -> String:
	var top: String = PHASES[0]
	for key in PHASES:
		if float(ms.get(key, 0.0)) > float(ms.get(top, 0.0)): top = key
	return top


## Once per rendered frame (client/network_status.gd through lag_report.sample).
static func sample(session, stage_marks: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	hook(Engine.get_main_loop() as SceneTree)
	var actor = session.get("own_actor")
	var cur := {
		"restores": actor.restore_count if actor != null else 0, "restore_us": actor.restore_us if actor != null else 0,
		"apply": int(session.metadata_apply_us) + int(session.lag_decode_us), "tick": _tick_us, "build": view_build_us,
		"update": int(stage_marks.get("remote_views_events", 0)) + int(stage_marks.get("fighter_visuals", 0)),
		"vfx": int(stage_marks.get("projectiles_audio", 0)), "hud": int(stage_marks.get("camera_hud_exits", 0)),
		"pfull": profile_full, "pfull_us": profile_full_us, "pin": profile_inplace, "vb": view_builds, "vn": view_nodes}
	if _started_us == 0: _started_us = now
	if _last_us > 0:
		var frame_ms := maxi(0, roundi(float(now - _last_us) / 1000.0))
		var second := int(now / 1000000)
		if buckets.is_empty() or buckets.back()[0] != second:
			buckets.append([second, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		while buckets.size() > SECONDS: buckets.pop_front()
		var b: Array = buckets.back()
		var d := func(key: String) -> int: return maxi(0, int(cur[key]) - int(_last.get(key, cur[key])))
		var named := {"netfox_tick": d.call("tick") / 1000.0, "state_apply": d.call("apply") / 1000.0, "view_build": d.call("build") / 1000.0,
			"view_update": maxf(0.0, d.call("update") / 1000.0 - d.call("build") / 1000.0), "vfx_audio": d.call("vfx") / 1000.0, "hud_camera": d.call("hud") / 1000.0}
		var physics_ms := _physics_us / 1000.0
		var process_ms := _process_us / 1000.0
		var draw_ms := _draw_us / 1000.0
		var ms := split(float(frame_ms), named, physics_ms, process_ms, draw_ms)
		b[1] += 1
		b[2] += d.call("restores"); b[3] += roundi(d.call("restore_us") / 1000.0)
		b[4] += d.call("pfull"); b[5] += roundi(d.call("pfull_us") / 1000.0); b[6] += d.call("pin")
		b[7] += d.call("vb"); b[8] += roundi(d.call("build") / 1000.0); b[9] += d.call("vn")
		b[10] = maxi(b[10], _frame_nodes)
		b[12] += roundi(named["netfox_tick"])
		b[13] += roundi(physics_ms); b[14] += roundi(process_ms); b[15] += roundi(draw_ms); b[16] += roundi(ms["outside"])
		if frame_ms > SLOW_MS:
			b[11] += 1
			var top := busiest(ms)
			slow_total += 1
			slow_by_phase[top] = int(slow_by_phase.get(top, 0)) + 1
			slow_frames.append([roundi(float(now - _started_us) / 1000000.0), frame_ms, top, roundi(ms[top]), roundi(ms["netfox_tick"]), roundi(ms["state_apply"]), roundi(ms["view_build"]), d.call("pfull"), _frame_nodes, d.call("restores"),
				roundi(physics_ms), roundi(process_ms), roundi(draw_ms), roundi(ms["outside"])])
			while slow_frames.size() > SLOW_KEPT: slow_frames.pop_front()
	_last = cur
	_last_us = now
	_frame_nodes = 0


## Device hints from the browser ({} on native). Read when the report is built, never per frame.
static func device_hints() -> Dictionary:
	if not OS.has_feature("web"): return {}
	var parsed = JSON.parse_string(str(JavaScriptBridge.eval(DEVICE_JS, true)))
	return parsed if parsed is Dictionary else {}


## The report section: small (about 2.5 KB of JSON).
static func export() -> Dictionary:
	return {"v": 2, "columns": COLUMNS, "seconds_oldest_first": buckets.duplicate(true), "slow_ms": SLOW_MS, "slow_total": slow_total, "slow_by_busiest_phase": slow_by_phase.duplicate(),
		"slow_columns": SLOW_COLUMNS, "slow_frames": slow_frames.duplicate(true), "max_fps": Engine.max_fps, "device": device_hints(),
		"totals": {"profile_full": profile_full, "profile_full_ms": roundi(profile_full_us / 1000.0), "profile_inplace": profile_inplace, "view_builds": view_builds, "view_build_ms": roundi(view_build_us / 1000.0), "view_nodes": view_nodes}}


static func reset() -> void:
	profile_full = 0; profile_full_us = 0; profile_inplace = 0; view_builds = 0; view_build_us = 0; view_nodes = 0
	_frame_nodes = 0; buckets = []; slow_by_phase = {}; slow_total = 0; slow_frames = []; _last = {}; _last_us = 0; _started_us = 0
	_physics_us = 0; _process_us = 0; _draw_us = 0
