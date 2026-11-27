extends RefCounted
## Phone frame cap + Lag report cost split (tech-artist 2026-11-19, Boss: the iPhone ran 20-30 fps with 130-300 ms
## stalls the report could only call "other"):
## - a phone defaults to a 30 fps render cap (graphics_options.gd frame_cap), desktop stays unlimited, the player's own
##   choice wins, and client/graphics_runtime.gd puts it on Engine.max_fps without overriding a cap a tool set;
## - the fight's clocks do not depend on the render rate: physics stays 60 Hz with room to catch up, netfox ticks at 60
##   with up to 8 ticks a frame, so a 30 fps frame runs 2 ticks;
## - client/lag_cost.gd splits a frame into the named script parts + physics / process / draw / outside, the slow
##   frame's busiest part is named, and the section (with the device hints and the cap) stays small in the codec.
## The player's user://graphics.cfg and Engine.max_fps are put back afterwards.

const Options := preload("res://client/graphics_options.gd")
const Cost := preload("res://client/lag_cost.gd")
const Runtime := preload("res://client/graphics_runtime.gd")
const Codec := preload("res://runtime/diagnostics/report_codec.gd")


func run(ctx) -> void:
	var had_config := FileAccess.file_exists(Options.PATH)
	var config_text := FileAccess.get_file_as_string(Options.PATH) if had_config else ""
	var saved_override := Options.device_override
	var saved_fps := Engine.max_fps

	_defaults(ctx)
	_runtime(ctx)
	_clocks(ctx)
	_slow_bar(ctx)
	_split(ctx)
	_section(ctx)

	Engine.max_fps = saved_fps
	Options.force_device(saved_override)
	if had_config:
		var file := FileAccess.open(Options.PATH, FileAccess.WRITE)
		file.store_string(config_text)
		file.close()
	elif FileAccess.file_exists(Options.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	Options.reload_settings()
	Cost.reset()


func _fresh(device: String) -> void:
	if FileAccess.file_exists(Options.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Options.PATH))
	Options.set_slow(false)
	Options.force_device(device)


func _defaults(ctx) -> void:
	_fresh("phone")
	ctx.check("phone: 30 fps render cap by default", int(Options.effective("frame_cap")) == 30 and not Options.is_chosen("frame_cap"))
	_fresh("desktop")
	ctx.check("desktop: no frame cap (0 = unlimited)", int(Options.effective("frame_cap")) == 0)
	_fresh("phone")
	Options.set_value("frame_cap", 0)
	Options.reload_settings()
	ctx.check("phone: the player's 'unlimited' wins and survives a reload", int(Options.effective("frame_cap")) == 0 and Options.is_chosen("frame_cap"))
	Options.set_value("frame_cap", 45)
	ctx.check("only 30 and unlimited are valid caps", int(Options.effective("frame_cap")) == 0)
	_fresh("phone")
	Options.set_slow(true)
	ctx.check("slow mode keeps the cap (it is not in SLOW_OFF)", int(Options.effective("frame_cap")) == 30)
	Options.set_slow(false)
	ctx.check("the panel snapshot has the frame_cap row (Frame rate 30 / 60)", Options.snapshot().has("frame_cap"))
	var applied: Dictionary = Options.report().get("applied", {})
	ctx.check("lag report graphics: the cap and Engine.max_fps are recorded", applied.has("frame_cap") and applied.has("max_fps"))


func _runtime(ctx) -> void:
	_fresh("phone")
	Engine.max_fps = 0
	var runtime := Runtime.new()
	ctx.root.add_child(runtime)  # _ready applies the settings
	ctx.check("runtime: a phone gets Engine.max_fps 30 (%d)" % Engine.max_fps, Engine.max_fps == 30)
	Options.set_value("frame_cap", 0)
	runtime._apply_all()
	ctx.check("runtime: choosing unlimited lifts the cap (%d)" % Engine.max_fps, Engine.max_fps == 0)
	Options.set_value("frame_cap", 30)
	runtime._apply_all()
	Engine.max_fps = 24  # a tool (walk.gd --fps 24, a perf probe) sets its own cap
	Options.set_value("frame_cap", 0)
	runtime._apply_all()
	ctx.check("runtime: a cap set by a tool is left alone (%d)" % Engine.max_fps, Engine.max_fps == 24)
	runtime.queue_free()
	Engine.max_fps = 7
	var late := Runtime.new()
	ctx.root.add_child(late)
	ctx.check("runtime: a cap set before the runtime started (command line) is kept", Engine.max_fps == 7)
	late.queue_free()
	Engine.max_fps = 0


func _slow_bar(ctx) -> void:
	const DrawStyle := preload("res://client/draw_style/draw_style.gd")
	var had := FileAccess.file_exists(DrawStyle.DEVICE_PATH)
	var text := FileAccess.get_file_as_string(DrawStyle.DEVICE_PATH) if had else ""
	var saved_fps := Engine.max_fps
	if had: DirAccess.remove_absolute(ProjectSettings.globalize_path(DrawStyle.DEVICE_PATH))
	Engine.max_fps = 30
	ctx.check("30 fps cap: a battle held at the cap (29.9) is not slow", not DrawStyle.record_battle(29.9, 60.0))
	ctx.check("30 fps cap: 28 fps is not slow either (bar 27)", not DrawStyle.record_battle(28.0, 60.0))
	ctx.check("30 fps cap: 25 fps is slow", DrawStyle.record_battle(25.0, 60.0))
	DrawStyle.forget_slow()
	Engine.max_fps = 0
	ctx.check("uncapped: the bar stays SLOW_FPS (28 is slow)", DrawStyle.record_battle(28.0, 60.0))
	DrawStyle.forget_slow()
	Engine.max_fps = saved_fps
	if had:
		var file := FileAccess.open(DrawStyle.DEVICE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()


func _clocks(ctx) -> void:
	ctx.check("physics stays 60 ticks a second", Engine.physics_ticks_per_second == 60)
	ctx.check("physics can run 2+ steps in a 30 fps frame (max %d)" % Engine.max_physics_steps_per_frame, Engine.max_physics_steps_per_frame >= 2)
	ctx.check("netfox ticks at 60 Hz on its own clock (not synced to the render rate)",
		int(ProjectSettings.get_setting("netfox/time/tickrate", 0)) == 60 and not bool(ProjectSettings.get_setting("netfox/time/sync_to_physics", true)))
	ctx.check("netfox can catch up 2+ ticks in a 30 fps frame (max %d)" % int(ProjectSettings.get_setting("netfox/time/max_ticks_per_frame", 0)),
		int(ProjectSettings.get_setting("netfox/time/max_ticks_per_frame", 0)) >= 2)


func _split(ctx) -> void:
	# A 200 ms frame: 10 ms physics (4 of it state apply), 30 ms process (12 of it netfox), 20 ms draw.
	var ms := Cost.split(200.0, {"netfox_tick": 12.0, "state_apply": 4.0}, 10.0, 30.0, 20.0)
	var keys_ok := true
	for key in Cost.PHASES: keys_ok = keys_ok and ms.has(key)
	ctx.check("split: every phase is present", keys_ok)
	ctx.check("split: outside = frame - physics - process - draw (140 ms)", is_equal_approx(ms["outside"], 140.0))
	ctx.check("split: named parts come out of their span", is_equal_approx(ms["physics_other"], 6.0) and is_equal_approx(ms["process_other"], 18.0))
	var total := 0.0
	for key in ms: total += float(ms[key])
	ctx.check("split: the parts add up to the frame (%.1f)" % total, is_equal_approx(total, 200.0))
	ctx.check("split: a browser stall is 'outside'", Cost.busiest(ms) == "outside")
	ctx.check("split: a GPU stall is 'draw'", Cost.busiest(Cost.split(180.0, {}, 5.0, 10.0, 150.0)) == "draw")
	ctx.check("split: a script stall is 'process_other'", Cost.busiest(Cost.split(180.0, {"netfox_tick": 5.0}, 5.0, 160.0, 10.0)) == "process_other")
	ctx.check("split: a view build stays named", Cost.busiest(Cost.split(120.0, {"view_build": 90.0}, 95.0, 10.0, 10.0)) == "view_build")
	ctx.check("split: never negative when the named parts exceed their span", Cost.split(50.0, {"netfox_tick": 40.0}, 0.0, 10.0, 5.0).values().all(func(v): return float(v) >= 0.0))


func _section(ctx) -> void:
	Cost.reset()
	for s in 10: Cost.buckets.append([s, 30, 20, 90, 0, 0, 2, 0, 0, 0, 0, 3, 110, 12, 300, 200, 400])
	for i in Cost.SLOW_KEPT: Cost.slow_frames.append([i, 210, "outside", 160, 15, 4, 0, 0, 0, 3, 8, 20, 12, 160, 40, 0])
	Cost.slow_total = 90
	Cost.slow_by_phase = {"outside": 80, "draw": 10}
	var section := Cost.export()
	ctx.check("section: v2 with the split columns", section.v == 2 and section.columns.size() == section.seconds_oldest_first[0].size() and section.slow_columns.size() == section.slow_frames[0].size())
	ctx.check("section: records the frame cap and the device hints", section.has("max_fps") and section.get("device") is Dictionary)
	var size := JSON.stringify(section).length()
	ctx.check("section: stays small (%d < 3500 bytes)" % size, size < 3500)
	var encoded := Codec.encode({"v": 2, "client": {"cost": section, "incidents": [], "live": {"events": [], "samples": []}}, "worker": {}})
	var decoded := Codec.decode(encoded)
	ctx.check("section: survives the report codec", encoded.get("ok", false) and decoded.get("client", {}).get("cost", {}).get("slow_by_busiest_phase", {}).get("outside", 0) == 80)
