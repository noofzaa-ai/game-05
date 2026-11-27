extends RefCounted
## Lag report follow-ups (Boss 2026-11-27, phone reports): app ping split with fake clocks, the long-task fallback
## label on browsers without a longtask observer, and the slow-device verdict clearing after fast battles.
const Echo := preload("res://client/session/echo_timing.gd")
const Probe := preload("res://runtime/diagnostics/session_probe.gd")
const DrawStyle := preload("res://client/draw_style/draw_style.gd")


func run(ctx) -> void:
	# Old bug: the floor was the session poll two frames back (before the send) -> net 0, stall = whole ping.
	var a := Echo.split(1000, 1042, 1030, -1.0, 3)
	ctx.check("poll bound: stall = processing - last multiplayer poll (12)", a.frame_stall_ms == 12)
	ctx.check("poll bound: net = arrival bound - send - server hold (30-3=27)", a.net_rtt_ms == 27 and a.server_hold_ms == 3 and a.rtt_ms == 42)
	var b := Echo.split(1000, 1146, 900, -1.0)
	ctx.check("a floor before the send never makes the whole ping a stall", b.frame_stall_ms == 146 and b.net_rtt_ms == 0 and b.source == "poll_bound")
	var c := Echo.split(1000, 1146, 1100, 104.0, 4)
	ctx.check("browser event age: stall 104, net 42-4=38", c.frame_stall_ms == 104 and c.net_rtt_ms == 38 and c.source == "browser_event")
	ctx.check("age larger than the ping is clamped", Echo.split(1000, 1020, 1010, 500.0).frame_stall_ms == 20)
	ctx.check("hook JS stamps pong frames of the wire version", Echo.HOOK_JS.contains("%d") and Echo.READ_JS.contains("shift"))
	# Long tasks
	var safari := Probe.long_task_view({"longtask_supported": false, "tasks": [], "raf": {"over_50ms": 7, "max_ms": 134, "frames": 2000}})
	ctx.check("no observer: counted by rAF gaps, labelled", safari.long_tasks.source == "raf_gap" and safari.long_tasks.over_50ms == 7 and safari.long_tasks.max_gap_ms == 134 and not safari.has("tasks"))
	ctx.check("nothing at all: unsupported, not zero", Probe.long_task_view({"longtask_supported": false}).long_tasks.source == "unsupported")
	ctx.check("chrome: the observer is the source", Probe.long_task_view({"longtask_supported": true, "tasks": [{}, {}]}).long_tasks.count == 2)
	# Slow verdict re-evaluation (hysteresis)
	var saved_fps := Engine.max_fps
	var had := FileAccess.file_exists(DrawStyle.DEVICE_PATH)
	var keep := FileAccess.get_file_as_string(DrawStyle.DEVICE_PATH) if had else ""
	Engine.max_fps = 0
	DrawStyle.forget_slow()
	ctx.check("a slow battle marks the device", DrawStyle.record_battle(20.0, 60.0) and DrawStyle._remembered_slow())
	DrawStyle.record_battle(45.0, 60.0)
	ctx.check("one fast battle is not enough", DrawStyle._remembered_slow())
	DrawStyle.record_battle(33.0, 60.0)
	DrawStyle.record_battle(45.0, 60.0)
	ctx.check("a middling battle (33 fps: above slow, below fast) resets the streak", DrawStyle._remembered_slow())
	DrawStyle.record_battle(45.0, 5.0)
	ctx.check("a short battle does not count", DrawStyle._remembered_slow())
	DrawStyle.record_battle(48.0, 60.0)
	ctx.check("two fast battles in a row clear the verdict", not DrawStyle._remembered_slow())
	Engine.max_fps = 30
	DrawStyle.record_battle(20.0, 60.0)
	DrawStyle.record_battle(29.0, 60.0); DrawStyle.record_battle(29.5, 60.0)
	ctx.check("under a 30 cap, holding ~the cap clears it", not DrawStyle._remembered_slow())
	Engine.max_fps = saved_fps
	DrawStyle.forget_slow()
	if had:
		var f := FileAccess.open(DrawStyle.DEVICE_PATH, FileAccess.WRITE); f.store_string(keep); f.close()
