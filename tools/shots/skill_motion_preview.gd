extends SceneTree
## Class-skill motion preview (design/gdd/class-skills.md 3.2-3.5) on the in-game Studio model with its class
## look. Per skill: contact-sheet frames (6 across the window, three views, release frame flagged) and a 30 fps
## frame sequence for the class video. Run WITH a window (not --headless):
##   godot --path . --script res://tools/shots/skill_motion_preview.gd
## Env: SKILL_FILE=res://tools/shots/skill_windows_v2.json + OUT_DIR=res://build/.../frames/ (other window set),
## SKILLS=S1,G2 (subset), TIMING=1 (timing-check strips, see TIMING_STRIPS; STRIPS=a,b subset), NO_SKILLS=1.
## Output: build/skill_motion_preview/frames/... (assembled by tools/shots/skill_motion_compose.py)
const ItemAssets := preload("res://client/item_assets.gd")
var OUT := "res://build/skill_motion_preview/frames/"
const FPS := 30.0
const BLEND := 0.12  ## GDD 5.3: windows blend out to the class idle over 0.12 s (used between segments too)
const LEAD := 0.35  ## idle shown before and after each skill in the video

## Segment: [clip, start, end, speed, [release clip-times]]. Release times are clip times inside that segment.
const SKILLS := {
	"S1": {"cls": "sword_shield", "name": "Shield Rush", "segs": [["attack_3", 1.417, 2.40, 1.0, [1.817]]]},
	"S2": {"cls": "sword_shield", "name": "Iron Guard", "segs": [["block", 0.0, 0.60, 1.0, []], ["block_idle", 0.0, 0.5, 1.0, []], ["attack_4", 0.25, 1.10, 1.5, [0.65]], ["block_idle", 0.0, 0.4, 1.0, []], ["block_2", 0.0, 0.80, 1.0, []]]},
	"S3": {"cls": "sword_shield", "name": "Intercept", "segs": [["jump", 0.10, 1.60, 1.0, [1.10]], ["block", 0.0, 0.45, 1.0, []]]},
	"S4": {"cls": "sword_shield", "name": "Breaker Slam", "segs": [["slash_4", 3.00, 4.22, 1.0, [3.40]]]},
	"G1": {"cls": "greatsword", "name": "Reaping Arc", "segs": [["gs_slash_3", 0.233, 1.453, 1.0, [0.633]]]},
	"G2": {"cls": "greatsword", "name": "Crater Leap", "segs": [["gs_jump_attack", 0.0, 1.60, 1.0, [0.85]]]},
	"G3": {"cls": "greatsword", "name": "Hook Sweep", "segs": [["gs_slash_4", 0.0, 0.987, 1.0, [0.167]]]},
	"G4": {"cls": "greatsword", "name": "Battle Trance", "segs": [["gs_power_up", 0.017, 1.237, 1.0, [0.417]]]},
	"L1": {"cls": "longbow", "name": "Heartseeker", "segs": [["lb_draw_arrow", 0.0, 1.033, 1.0, []], ["lb_aim_recoil", 0.0, 0.70, 1.0, [0.10]]]},
	"L2": {"cls": "longbow", "name": "Pinning Shot", "segs": [["lb_aim_recoil", 0.0, 0.70, 0.8, [0.10]]]},
	"L3": {"cls": "longbow", "name": "Rapid Fire", "segs": [["lb_aim_recoil", 0.0, 0.32, 1.28, [0.10]], ["lb_aim_recoil", 0.0, 0.32, 1.28, [0.10]], ["lb_aim_recoil", 0.0, 0.32, 1.28, [0.10]], ["lb_aim_recoil", 0.0, 0.32, 1.28, [0.10]]]},
	"L4": {"cls": "longbow", "name": "Vault Shot", "segs": [["lb_dodge_backward", 0.0, 1.20, 1.0, []], ["lb_aim_recoil", 0.0, 0.70, 1.0, [0.10]]]},
	"M1": {"cls": "magic", "name": "Arcane Orb", "segs": [["mg_spell_1h_cast_spell_01", 0.033, 1.253, 1.0, [0.433]]]},
	"M2": {"cls": "magic", "name": "Repulse Nova", "segs": [["mg_spell_2h_magic_area_attack_01", 0.767, 1.987, 1.0, [1.167]]]},
	"M3": {"cls": "magic", "name": "Starfall", "segs": [["mg_spell_2h_magic_attack_05", 1.533, 2.753, 1.0, [1.933]]]},
	"M4": {"cls": "magic", "name": "Warding Veil", "segs": [["mg_spell_2h_cast_spell_01", 0.70, 1.92, 1.0, [1.10]]]},
}
## Timing checks: [name, class, clip, from, to, step] -> a strip of frames with the clip time.
const TIMING_STRIPS := [
	["jump_full", "sword_shield", "jump", 0.0, 2.10, 0.15],
	["jump_land", "sword_shield", "jump", 1.70, 2.10, 0.05],
	["gs_jump_attack_full", "greatsword", "gs_jump_attack", 0.0, 2.10, 0.15],
	["gs_jump_attack_land", "greatsword", "gs_jump_attack", 0.85, 1.35, 0.05],
	["lb_aim_overdraw_full", "longbow", "lb_aim_overdraw", 0.0, 3.75, 0.35],
	["lb_aim_recoil_fine", "longbow", "lb_aim_recoil", 0.0, 0.40, 0.05],
	["jump_2_full", "sword_shield", "jump_2", 0.0, 2.40, 0.2],
	["gs_slide_attack_full", "greatsword", "gs_slide_attack", 0.0, 2.10, 0.15],
	["gs_slash_4_full", "greatsword", "gs_slash_4", 0.0, 1.75, 0.125],
	["attack_3_full", "sword_shield", "attack_3", 0.0, 4.30, 0.3],
	["slash_4_full", "sword_shield", "slash_4", 0.0, 6.10, 0.4],
	["power_up", "sword_shield", "power_up", 0.0, 99.0, 0.25],
	["kick", "sword_shield", "kick", 0.0, 99.0, 0.15],
	["gs_power_up_full", "greatsword", "gs_power_up", 0.0, 3.50, 0.25],
	["gs_slash_3_fine", "greatsword", "gs_slash_3", 0.55, 1.00, 0.05],
	["mg_area_01_full", "magic", "mg_spell_2h_magic_area_attack_01", 0.0, 2.95, 0.2],
	["mg_attack_05_full", "magic", "mg_spell_2h_magic_attack_05", 0.0, 3.50, 0.25],
	["mg_cast_2h_full", "magic", "mg_spell_2h_cast_spell_01", 0.0, 2.15, 0.15],
	["mg_cast_1h_fine", "magic", "mg_spell_1h_cast_spell_01", 0.30, 0.80, 0.05],
	["attack_4_full", "sword_shield", "attack_4", 0.0, 2.50, 0.2],
	["block_2_full", "sword_shield", "block_2", 0.0, 1.70, 0.15],
	["attack_3_fine", "sword_shield", "attack_3", 1.60, 2.10, 0.05],
	["crouching_2", "sword_shield", "crouching_2", 0.0, 1.55, 0.2],
	["mg_area_02_full", "magic", "mg_spell_2h_magic_area_attack_02", 0.0, 99.0, 0.2],
	["ss_attack", "sword_shield", "attack", 0.0, 99.0, 0.3],
	["ss_attack_2", "sword_shield", "attack_2", 0.0, 99.0, 0.2],
	["ss_slash", "sword_shield", "slash", 0.0, 99.0, 0.2],
	["ss_slash_3", "sword_shield", "slash_3", 0.0, 99.0, 0.25],
	["ss_casting", "sword_shield", "casting", 0.0, 99.0, 0.4],
	["ss_casting_2", "sword_shield", "casting_2", 0.0, 99.0, 0.15],
	["gs_attack", "greatsword", "gs_attack", 0.0, 99.0, 0.08],
]

var scene: Node3D
var cam_front: Camera3D
var cam_side: Camera3D
var cam_high: Camera3D
var models := {}

func _initialize():
	call_deferred("run")

func make_model(cls: String):
	var model = load("res://client/characters/studio05_character_model.gd").new()
	scene.add_child(model)
	model.load_model()
	var weapon := str(model.class_data(cls).get("weapon", ""))
	model.dress({"class": cls, "appearance": ItemAssets.card_appearance({"class": cls}, ItemAssets.appearance({})), "weapon": {"path": "", "family": weapon, "style": weapon}})
	model.blink_enabled = false
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0, 1), false)
	for i in 30:
		model.apply_pose(0.05)
	model.visible = false
	return model

func build_stage() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2b3446")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.6
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	# ground with a 25 cm checker so foot sliding shows, and a cross at the start spot
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var c := Color("4a5568") if ((x / 8) + (y / 8)) % 2 == 0 else Color("3c4556")
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(4, 4, 1)  # 2 m per texture repeat, 8 cells -> 25 cm cells
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = mat
	scene.add_child(ground)
	for axis in [Vector3(0.5, 0.004, 0.02), Vector3(0.02, 0.004, 0.5)]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = axis
		bar.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("e0b04a")
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar.material_override = m
		bar.position.y = 0.002
		scene.add_child(bar)
	cam_front = Camera3D.new()
	cam_front.fov = 34
	scene.add_child(cam_front)
	cam_front.position = Vector3(2.0, 1.45, 3.0)
	cam_front.look_at(Vector3(0, 0.62, 0))
	cam_side = Camera3D.new()
	cam_side.fov = 34
	scene.add_child(cam_side)
	cam_side.position = Vector3(3.7, 0.95, 0.0)
	cam_side.look_at(Vector3(0, 0.62, 0))
	cam_high = Camera3D.new()  # board-like: high and far
	cam_high.fov = 30
	scene.add_child(cam_high)
	cam_high.position = Vector3(1.6, 3.6, 3.4)
	cam_high.look_at(Vector3(0, 0.5, 0))

func show_only(cls: String) -> void:
	for k in models:
		models[k].visible = k == cls

func put(model, active: Dictionary) -> void:
	model._skill_clip = active
	model.apply_pose(10.0)  # follow = 1: the exact sampled pose (blends are done in `active`)

func save(path: String, cam: Camera3D) -> void:
	cam.current = true
	for i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func timeline(skill: Dictionary) -> Dictionary:
	var segs: Array = skill["segs"]
	var starts := []
	var total := 0.0
	for s in segs:
		starts.append(total)
		total += (float(s[2]) - float(s[1])) / float(s[3])
	var releases := []
	for i in segs.size():
		for r in segs[i][4]:
			releases.append(starts[i] + (float(r) - float(segs[i][1])) / float(segs[i][3]))
	return {"starts": starts, "total": total, "releases": releases}

## The pose at `t` seconds from the skill start: idle -> seg0 -> seg1 ... -> idle, each change blended over BLEND.
func pose_at(model, skill: Dictionary, tl: Dictionary, t: float) -> Dictionary:
	var segs: Array = skill["segs"]
	var idle := str(model.class_data(skill["cls"]).get("states", {}).get("idle", "idle"))
	var lib = model._library
	var seg_blend := float(skill.get("blend", BLEND))
	if t < 0.0:
		var w := clampf((t + BLEND) / BLEND, 0.0, 1.0)
		var first: Array = segs[0]
		if w <= 0.0:
			return {"set": lib, "clip": idle, "time": 0.0}
		return {"set": lib, "clip": first[0], "time": float(first[1]), "from": idle, "from_time": 0.0, "weight": w}
	if t >= tl["total"]:
		var last: Array = segs[segs.size() - 1]
		var w := clampf((t - tl["total"]) / BLEND, 0.0, 1.0)
		return {"set": lib, "clip": idle, "time": 0.0, "from": last[0], "from_time": float(last[2]), "weight": w}
	var i := segs.size() - 1
	while i > 0 and t < tl["starts"][i]:
		i -= 1
	var s: Array = segs[i]
	var local := t - float(tl["starts"][i])
	var ct := float(s[1]) + local * float(s[3])
	var active := {"set": lib, "clip": s[0], "time": ct}
	if i > 0 and local < seg_blend:
		var p: Array = segs[i - 1]
		active["from"] = p[0]
		active["from_time"] = float(p[2])
		active["weight"] = local / seg_blend
	return active

func run():
	var skills: Dictionary = SKILLS
	if OS.get_environment("SKILL_FILE") != "":
		skills = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SKILL_FILE")))
		skills.erase("_comment")
	if OS.get_environment("OUT_DIR") != "":
		OUT = OS.get_environment("OUT_DIR")
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(480, 560)
	build_stage()
	for cls in ["sword_shield", "greatsword", "longbow", "magic"]:
		models[cls] = make_model(cls)
	var only := OS.get_environment("SKILLS")
	var info := {}
	for id in skills:
		if OS.get_environment("NO_SKILLS") == "1" or (only != "" and not (id in only.split(","))):
			continue
		var skill: Dictionary = skills[id]
		var model = models[skill["cls"]]
		show_only(skill["cls"])
		var tl := timeline(skill)
		var dir: String = OUT + str(id) + "/"
		DirAccess.make_dir_recursive_absolute(dir)
		# contact sheet: 6 evenly spaced times over the window; the one nearest the first release snaps to it
		var sheet := []
		for k in 6:
			sheet.append(tl["total"] * k / 5.0)
		if not tl["releases"].is_empty():
			var r: float = tl["releases"][0]
			var best := 1
			for k in range(1, 5):
				if absf(sheet[k] - r) < absf(sheet[best] - r):
					best = k
			sheet[best] = r
		var labels := []
		for k in 6:
			var active := pose_at(model, skill, tl, sheet[k])
			put(model, active)
			await save(dir + "sheet_%d_a.png" % k, cam_front)
			await save(dir + "sheet_%d_b.png" % k, cam_side)
			await save(dir + "sheet_%d_c.png" % k, cam_high)
			var is_rel := false
			for r in tl["releases"]:
				if absf(r - sheet[k]) < 0.001:
					is_rel = true
			labels.append({"t": sheet[k], "clip": active["clip"], "clip_time": active["time"], "release": is_rel})
		var n := 0
		var t := -LEAD
		var end: float = tl["total"] + LEAD
		var frames := []
		while t <= end + 0.0001:
			var active := pose_at(model, skill, tl, t)
			put(model, active)
			var rel := false
			for r in tl["releases"]:
				if absf(r - t) < 0.5 / FPS:
					rel = true
			await save(dir + "vid_%04d.png" % n, cam_front)
			frames.append({"t": t, "clip": active["clip"], "clip_time": active["time"], "release": rel})
			n += 1
			t += 1.0 / FPS
		info[id] = {"name": skill["name"], "cls": skill["cls"], "total": tl["total"], "releases": tl["releases"], "sheet": labels, "frames": frames}
		print("SKILL ", id, " total=", tl["total"], " frames=", n)
	if OS.get_environment("TIMING") == "1":
		var strip_only := OS.get_environment("STRIPS")
		for strip in TIMING_STRIPS:
			if strip_only != "" and not (str(strip[0]) in strip_only.split(",")):
				continue
			var model = models[strip[1]]
			show_only(strip[1])
			var dir: String = OUT + "timing_" + str(strip[0]) + "/"
			DirAccess.make_dir_recursive_absolute(dir)
			var tt := float(strip[3])
			var stop := minf(float(strip[4]), model._library.length(strip[2]))
			var k := 0
			var times := []
			while tt <= stop + 0.0001:
				put(model, {"set": model._library, "clip": strip[2], "time": tt})
				await save(dir + "%02d_a.png" % k, cam_side)
				await save(dir + "%02d_b.png" % k, cam_front)
				times.append(tt)
				k += 1
				tt += float(strip[5])
			info["timing_" + strip[0]] = {"clip": strip[2], "times": times}
			print("TIMING ", strip[0], " ", k)
	var log := FileAccess.open(OUT + ("skills_%s.json" % (only if only != "" else (("timing_" + OS.get_environment("STRIPS").md5_text().left(6)) if OS.get_environment("NO_SKILLS") == "1" else "all"))), FileAccess.WRITE)
	log.store_string(JSON.stringify(info, "  "))
	log.close()
	for cls in models:
		models[cls].tint(Color(0, 0, 0, 0))
	quit()
