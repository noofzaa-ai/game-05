extends SceneTree
## Violent light-and-scatter looks (Boss 2026-11-19, client/vfx/violence.gd + violent_vfx.gd): real battle filmstrips of
## race ultimates, class skills and mummy boss moves, current look vs the shipped one, plus a native perf run.
## Windowed only (not --headless):
##   godot --path . --script res://tools/shots/vfx_violence_shots.gd -- --map=goblin|mummy [--device=phone --size=844x390]
##        [--out=res://build/vfx_violence] [--level=L3]
##   godot --path . --script res://tools/shots/vfx_violence_shots.gd -- --perf --level=current|L3 --map=mummy [--device=phone ...]
## Shots: <out>/<tag>_<map>_<name>_<current|level>_f<n>.png, 7 frames 0.03..2.0 s after the blow (sheet: vfx_violence_sheet.py).
## The fight is frozen while filming (stage physics paused) so both looks hit the same spot. The clock stops while each
## frame is read back, so the strip's times are game seconds. "current" = what the game draws today at that blow (the
## daiyooo bundle / old layers where they exist); the new look is the same plus violent_vfx.play(key).

const Violence := preload("res://client/vfx/violence.gd")
const Effects := preload("res://client/effects.gd")
const TIMES := [0.03, 0.1, 0.2, 0.4, 0.7, 1.2, 2.0]
## name -> [violence key, what today's game draws: "class:<skill>" | "monster:<bundle>" | "keys:<vfx.json keys>" | ""]
const FILMS := {
	"ult_runebreaker": ["race_ult/runeborn_greatsword", "keys:hit,hit/heavy,skill_impact/3"],
	"ult_bloodmoon": ["race_ult/viking_magic", "keys:skill_impact/3"],
	"ult_grove": ["race_ult/elf_sword_shield", "keys:skill_impact/2"],
	"ult_rally": ["race_ult/human_magic", ""],
	"cls_crater_leap": ["class_skill/crater_leap", "class:crater_leap"],
	"cls_repulse_nova": ["class_skill/repulse_nova", "class:repulse_nova"],
	"cls_heartseeker": ["class_skill/heartseeker_shot", "class:heartseeker_shot"],
	"cls_iron_guard": ["class_skill/iron_guard", "class:iron_guard"],
	"boss_starfall": ["monster/hw_star", "monster:hw_starfall"],
	"boss_curse": ["monster/hw_curse", "monster:hw_curse"],
	"boss_nova": ["monster/mummy_boss_nova", "keys:swing/mummy_boss_nova"],
}

var out := "res://build/vfx_violence"
var map := "goblin"
var tag := "desk"
var size := Vector2i(1280, 720)
var perf := false
var level := "L3"
var _clock := 0.0
var stage: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--map="): map = a.substr(6)
		elif a.begins_with("--size="): size = Vector2i(int(a.substr(7).split("x")[0]), int(a.substr(7).split("x")[1]))
		elif a == "--perf": perf = true
		elif a.begins_with("--level="): level = a.substr(8)
		elif a == "--device=phone": tag = "phone"
	Violence.override_level = level if perf else "L3"  # (before the stage builds: the violent node and its prewarm)
	Engine.max_fps = 0 if perf else 60
	if perf: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await _start_battle()
	for i in 150:
		await process_frame
	stage = current_scene
	var session = stage.get("_session")
	stage.set_physics_process(false)
	var spot := _spot(session)
	print("VIOLENCE map=", map, " tag=", tag, " spot=", spot, " phone_variant=", Violence.phone(), " map_id=", stage.get("_map_id"))
	if perf:
		await _perf_run(spot)
		quit()
		return
	for name in FILMS:
		for lvl in ["current", level]:
			await _film(name, lvl, spot)
	print("VIOLENCE_DONE")
	quit()


func _start_battle() -> void:
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	gs.auto_battle = true
	seed(7)
	if map == "goblin":
		gs.start_journey(gs.DEFAULT_JOURNEY, 7)
		return
	gs.account_session = null  # (the pyramid journey offline and ungated, as tools/shots/high_wizard_shots.gd does)
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	var data = load("res://logic/journey_data.gd").load_by_id("mummy_waves", combat.enemies.keys())
	gs.run_loot = {"items": [], "gold": 0, "materials": {}, "wave": 1}
	gs.mode = gs.Mode.PVE
	var cards: Array = gs.squad_looks().slice(0, gs.squad_size).map(func(slot): return str(slot.get("class", "")))
	var fight = gs.get_session()
	fight.squad_classes = cards
	fight.start_journey(data, combat.weapon_ids, 7, {}, cards)
	gs.journey = gs.session.journey
	gs.enter_journey_choice(0)


## The blow lands among the monsters (their mean position on the floor), so it reads against them.
func _spot(session) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for id in session.fighters:
		if session.fighters[id].team == "enemy" and session.fighters[id].is_alive():
			sum += session.bodies[id].position
			n += 1
	if n == 0:
		return session.bodies[stage.get("_local_player_id")].position + Vector3(3.0, 0.0, 0.0)
	return Vector3(sum.x / n, 0.0, sum.z / n)


## Draws what the game shows today at this blow.
func _today(what: String, pos: Vector3) -> void:
	var effects = stage.get("_effects")
	if what.begins_with("class:"):
		var skill := what.substr(6)
		var cv = stage.get("_class_vfx")
		var inst: Node3D = cv._take(skill)
		if inst != null:
			var spec: Dictionary = cv.SPEC.get(skill, {})
			var seek := float(spec.get("impact_seek", spec.get("seek", 0.0)))
			cv._start(inst, seek, pos, Vector3(1, 0, 0) if bool(spec.get("face", false)) else Vector3.ZERO, false)
			cv._live.append({"node": inst, "skill": skill, "player": -1, "age": seek, "length": cv._clip_length(inst), "loop": false, "follow": -1, "buff": "", "orb": false})
	elif what.begins_with("monster:"):
		var bundle := what.substr(8)
		var seek: float = {"hw_starfall": 1.35, "hw_curse": 1.1}.get(bundle, 0.4)
		stage.get("_monster_vfx")._play({"vfx": bundle, "seek": seek, "speed": 1.5}, pos, 0.8, -1)
	elif what.begins_with("keys:"):
		var ctx := Effects.context(pos + Vector3(0, 1.1, 0), pos, Vector2.RIGHT, Color(0.9, 0.8, 0.5), {"scale": 2.0})
		for key in what.substr(5).split(","):
			effects.play(key, ctx)


func _film(name: String, lvl: String, pos: Vector3) -> void:
	seed(11)
	Violence.override_level = lvl
	_clock = 0.0
	_today(str(FILMS[name][1]), pos)
	var violent = stage.get("_monster_vfx").violent
	if lvl != "current" and violent != null:
		violent._flash_clock = 99.0
		violent.play(str(FILMS[name][0]), pos, Vector2.RIGHT)
	stage._spawn_damage_number(pos + Vector3(0, 1.2, 0), 1000 + name.length() * 97, true, false)
	for i in TIMES.size():
		while _clock < TIMES[i]:
			await process_frame
			_clock += root.get_process_delta_time()
		await _grab("%s_%s_%s_%s_f%d" % [tag, map, name, lvl, i])
	Engine.time_scale = 8.0  # (let every effect end before the next take)
	for i in 50:
		await process_frame
	Engine.time_scale = 1.0
	await process_frame


func _grab(file: String) -> void:
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(file + ".png"))
	await process_frame
	await process_frame
	Engine.time_scale = 1.0


## Native perf, a boss wave's worst case: every 1.0 s for 10 s, 3 High Wizard stars (0.23 s apart), a curse, a Pharaoh
## nova, a race ultimate and 3 class skills (nova, crater leap, a shot) land around the spot, each with what the game draws
## today (bundles / old layers) plus the violent look. Level "current" = the same blows without the new look (baseline).
func _perf_run(pos: Vector3) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var effects = stage.get("_effects")
	var violent = stage.get("_monster_vfx").violent
	Engine.max_fps = 0
	for i in 120:
		await process_frame
	var plan := [
		[0.0, "boss_starfall", Vector3(-1.5, 0, -2.5)], [0.23, "boss_starfall", Vector3(0, 0, -2.5)], [0.46, "boss_starfall", Vector3(1.5, 0, -2.5)],
		[0.1, "boss_curse", Vector3(-3, 0, 1)], [0.3, "boss_nova", Vector3(3, 0, 0)], [0.5, "ult_runebreaker", Vector3(0, 0, 2)],
		[0.6, "cls_repulse_nova", Vector3(-2, 0, 2.5)], [0.7, "cls_crater_leap", Vector3(2, 0, 2.5)], [0.8, "cls_heartseeker", Vector3(0, 0, 0)],
	]
	var frames := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var draws := PackedInt32Array()
	var live_max := 0
	var t := 0.0
	var fired := 0
	var last := Time.get_ticks_usec()
	while t < 10.0:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		var dt := root.get_process_delta_time()
		var cycle := fmod(t, 1.0)
		for entry in plan:
			if cycle <= float(entry[0]) and cycle + dt > float(entry[0]):
				var at: Vector3 = pos + Vector3(entry[2])
				_today(str(FILMS[entry[1]][1]), at)
				if level != "current" and violent != null:
					violent.play(str(FILMS[entry[1]][0]), at, Vector2.RIGHT)
				fired += 1
		t += dt
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		live_max = maxi(live_max, effects.live_count())
	var sorted := frames.duplicate()
	sorted.sort()
	var gs := gpu.duplicate()
	gs.sort()
	var dsum := 0
	for d in draws:
		dsum += d
	var n := sorted.size()
	print("PERF map=%s level=%s variant=%s size=%dx%d frames=%d p50=%.2f p95=%.2f p99=%.2f gpu_p50=%.2f gpu_p95=%.2f draws_avg=%.0f live_max=%d blows=%d" % [
		map, level, "phone" if Violence.phone() else "full", size.x, size.y, n, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)],
		gs[n / 2], gs[int(n * 0.95)], float(dsum) / n, live_max, fired])
