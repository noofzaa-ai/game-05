extends RefCounted
## Cheap cost counters for the Lag report ("cost" section, Boss 2026-11-18). The phone shows a steady train of
## 170-236 ms frames about once a second; this records, per second, what ran (profile rebuilds, enemy view builds and
## the nodes they create, netfox restores) and, for every frame over SLOW_MS, which coarse phase was busiest, so the next
## report can pin the periodic hitch. Counters are static: any file can note work, only the lag report reads them.
const SLOW_MS := 100
const SECONDS := 10  ## one-second buckets kept
const SLOW_KEPT := 8  ## the latest slow frames kept in full
const COLUMNS := ["second", "frames", "restores", "restore_ms", "profile_full", "profile_full_ms", "profile_inplace", "view_builds", "view_build_ms", "view_nodes", "view_nodes_max_frame", "slow_frames", "netfox_tick_ms"]
const PHASES := ["netfox_tick", "state_apply", "view_build", "view_update", "vfx_audio", "hud_camera", "other"]

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
static var buckets: Array = []
static var slow_by_phase := {}
static var slow_total := 0
static var slow_frames: Array = []
static var _last := {}
static var _last_us := 0
static var _started_us := 0


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
	if _hooked or tree == null: return
	var clock = tree.root.get_node_or_null("NetworkTime")
	if clock == null: return
	clock.before_tick_loop.connect(func(): _tick_start = Time.get_ticks_usec())
	clock.after_tick_loop.connect(func(): _tick_us += Time.get_ticks_usec() - _tick_start)
	_hooked = true


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
			buckets.append([second, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		while buckets.size() > SECONDS: buckets.pop_front()
		var b: Array = buckets.back()
		var d := func(key: String) -> int: return maxi(0, int(cur[key]) - int(_last.get(key, cur[key])))
		b[1] += 1
		b[2] += d.call("restores"); b[3] += roundi(d.call("restore_us") / 1000.0)
		b[4] += d.call("pfull"); b[5] += roundi(d.call("pfull_us") / 1000.0); b[6] += d.call("pin")
		b[7] += d.call("vb"); b[8] += roundi(d.call("build") / 1000.0); b[9] += d.call("vn")
		b[10] = maxi(b[10], _frame_nodes)
		b[12] += roundi(d.call("tick") / 1000.0)
		if frame_ms > SLOW_MS:
			b[11] += 1
			var ms := {"netfox_tick": d.call("tick") / 1000.0, "state_apply": d.call("apply") / 1000.0, "view_build": d.call("build") / 1000.0,
				"view_update": maxf(0.0, d.call("update") / 1000.0 - d.call("build") / 1000.0), "vfx_audio": d.call("vfx") / 1000.0, "hud_camera": d.call("hud") / 1000.0}
			var named := 0.0
			for key in ms: named += ms[key]
			ms["other"] = maxf(0.0, float(frame_ms) - named)  # draw, engine, browser: everything not measured above
			var top := "other"
			for key in PHASES:
				if ms[key] > ms[top]: top = key
			slow_total += 1
			slow_by_phase[top] = int(slow_by_phase.get(top, 0)) + 1
			slow_frames.append([roundi(float(now - _started_us) / 1000000.0), frame_ms, top, roundi(ms[top]), roundi(ms["netfox_tick"]), roundi(ms["state_apply"]), roundi(ms["view_build"]), d.call("pfull"), _frame_nodes, d.call("restores")])
			while slow_frames.size() > SLOW_KEPT: slow_frames.pop_front()
	_last = cur
	_last_us = now
	_frame_nodes = 0


## The report section: small (about 1.5 KB of JSON).
static func export() -> Dictionary:
	return {"v": 1, "columns": COLUMNS, "seconds_oldest_first": buckets.duplicate(true), "slow_ms": SLOW_MS, "slow_total": slow_total, "slow_by_busiest_phase": slow_by_phase.duplicate(),
		"slow_columns": ["t_since_first_sample_s", "frame_ms", "busiest", "busiest_ms", "netfox_tick_ms", "state_apply_ms", "view_build_ms", "profile_full", "nodes_created", "restores"],
		"slow_frames": slow_frames.duplicate(true),
		"totals": {"profile_full": profile_full, "profile_full_ms": roundi(profile_full_us / 1000.0), "profile_inplace": profile_inplace, "view_builds": view_builds, "view_build_ms": roundi(view_build_us / 1000.0), "view_nodes": view_nodes}}


static func reset() -> void:
	profile_full = 0; profile_full_us = 0; profile_inplace = 0; view_builds = 0; view_build_us = 0; view_nodes = 0
	_frame_nodes = 0; buckets = []; slow_by_phase = {}; slow_total = 0; slow_frames = []; _last = {}; _last_us = 0; _started_us = 0
