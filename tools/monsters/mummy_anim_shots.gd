extends SceneTree
## Animator check of every mummy type AS THE FIGHT DRAWS IT: the combat.json definition the loader resolved (model, clip library,
## clips, run_clip_speed, hips_scale) in the real fighter view (ink outline, own materials), the run played at the view's own rate
## for the monster's real walking speed. Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/monsters/mummy_anim_shots.gd -- <out_dir> [--size=844x390] [--only=mummy,mummy_boss]
## Per mummy:
##   <id>_strip_<clip>_<view>.png  idle, run, attacks, hit, death; view = side or top (the fight camera's steep pitch); 7 frames
##   <id>_contact.png              side view stroboscope: the monster walks at its real speed for one cycle, 8 exposures on one image
##                                 (a planted foot stays on ONE spot while the body passes over it; a sliding foot smears)
##   <id>_fight.png                the whole monster at the battle camera's distance, mid-stride (what the Boss sees)

const IDS := ["mummy", "mummy_archer", "mummy_knight", "mummy_mage", "mummy_boss", "mummy_high_wizard"]
const CROP := Vector2i(300, 360)
const WALK := 3.8  ## logic/movement.gd SPEED

var _stage: Node
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "user://mummy_anim_shots"
	var size := Vector2i(1280, 720)
	var only: Array = IDS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(","))
		else:
			out = a
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_stage(game_state.Mode.PVE, "practice_field")
	await _frames(10)
	_stage = current_scene
	_stage.set_physics_process(false)
	var views: Dictionary = _stage.get("_views")
	for id in views:
		views[id].visible = false
	var enemies: Dictionary = _stage.get("_session")._sim.combat.enemies
	var spot: Vector3 = _stage.get("_session")._sim.bodies[1].position + Vector3(0, 0.05, -1.0)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_stage.add_child(_camera)
	_camera.make_current()
	for id in only:
		var e: Dictionary = enemies[id]
		var view := _view(e, spot)
		await _frames(4)
		var anim: RefCounted = view.monster_animation()
		print(id, " model=", e["model"], " set=", e["animations"], " clips=", anim.clip_names() if anim != null else "NONE", " rcs=", e["run_clip_speed"])
		if anim == null:
			view.queue_free()
			continue
		var h: float = e["model_height"]
		var speed: float = WALK * maxf(0.1, 1.0 + float(e["stats"]["MOVESPD"]) / 100.0)
		var reference: float = e["run_clip_speed"] if float(e["run_clip_speed"]) > 0.0 else 2.44
		var rate := clampf(speed / (reference * float(view.get("_fit"))), 0.6, 1.4)
		print("  walk %.2f m/s, run clip rate %.3f (raw %.3f)" % [speed, rate, speed / (reference * float(view.get("_fit")))])
		var clips: Array = ["idle", "run"]
		for clip in anim.clip_names():
			if not clip in ["idle", "run", "hit", "death"]:
				clips.append(clip)
		clips.append_array(["hit", "death"])
		for clip in clips:
			if anim.has_clip(clip):
				await _strip(view, anim, clip, spot, h, "side", out, id)
				await _strip(view, anim, clip, spot, h, "top", out, id)
		await _strip(view, anim, "run", spot, h, "front", out, id)
		await _contact(view, anim, spot, h, speed, rate, out, id)
		await _fight(view, anim, spot, h, out, id)
		view.queue_free()
		await _frames(2)
	quit()


func _view(e: Dictionary, at: Vector3) -> Node3D:
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	view.base_color = e["color"]
	view.ink_outline = true
	view.monster_model_path = e["model"]
	view.monster_model_height = e["model_height"]
	view.monster_animations_path = e["animations"]
	view.monster_clips = e["clips"]
	view.monster_tint = e["model_tint"]
	view.monster_standin_clips = e["standin_clips"]
	view.monster_nock_mesh = e["nock_mesh"]
	view.monster_hips_scale = float(e.get("hips_scale", 1.0))
	view.monster_run_clip_speed = float(e.get("run_clip_speed", 0.0))
	_stage.add_child(view)
	view.position = at
	return view


func _pose(view: Node3D, clip: String, t: float) -> void:
	view._anim_clip = clip
	view._anim_rate = 0.0
	view._blend = 1.0
	view._anim_time = t
	view._apply_clip()


## The monster faces +Z. side = camera on +X (profile, walking to the right of the image is +Z... the left), top = the battle
## camera's steep pitch from the front-ish, front = from +Z.
func _place_camera(spot: Vector3, h: float, angle: String) -> void:
	var k := h / 1.8
	var centre := spot + Vector3(0, 0.85 * k, 0)
	match angle:
		"side":
			_camera.global_position = centre + Vector3(5.6, 0.6, 0.0) * k
		"front":
			_camera.global_position = centre + Vector3(0.6, 0.9, 5.6) * k
		"top":
			_camera.global_position = centre + Vector3(0.0, 4.6, 3.0) * k
	_camera.look_at(centre)


func _strip(view: Node3D, anim: RefCounted, clip: String, spot: Vector3, h: float, angle: String, out: String, id: String) -> void:
	_place_camera(spot, h, angle)
	var length: float = anim.length(clip)
	var looping: bool = anim.is_looping(clip)
	var frames := 7
	var images: Array[Image] = []
	var stamps := []
	for i in frames:
		var t: float = length * float(i) / float(frames) if looping else length * float(i) / float(frames - 1)
		if clip == "idle":
			t = minf(t, length)
		_pose(view, clip, t)
		stamps.append("%.2f" % t)
		images.append(await _grab(spot, h))
	_save_row(images, out.path_join("%s_strip_%s_%s.png" % [id, clip, angle]))
	print("  saved %s_strip_%s_%s %s" % [id, clip, angle, stamps])


func _grab(spot: Vector3, h: float) -> Image:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var centre := _camera.unproject_position(spot + Vector3(0, 0.85 * h / 1.8, 0))
	var box := Rect2i(Vector2i(centre) - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	return shot.get_region(box)


func _save_row(images: Array[Image], path: String) -> void:
	var strip := Image.create(CROP.x * images.size(), CROP.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i(CROP.x * i, 0))
	strip.save_png(path)


## One run cycle at the real ground speed: the view moves along +Z while its clip advances at the view's rate; 8 exposures
## composited (pixels that differ from the empty background are kept, later exposures on top) plus a ground line.
func _contact(view: Node3D, anim: RefCounted, spot: Vector3, h: float, speed: float, rate: float, out: String, id: String) -> void:
	var k := h / 1.8
	var cycle: float = anim.length("run") / rate  ## seconds of game time per loop
	var travel := speed * cycle
	var centre := spot + Vector3(0, 0.45 * k, travel * 0.5)
	_camera.global_position = centre + Vector3(maxf(6.0 * k, travel * 2.4), 0.25 * k, 0.0)
	_camera.look_at(centre)
	view.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var plate := root.get_texture().get_image()
	view.visible = true
	var composite := plate.duplicate() as Image
	var exposures := 8
	for i in exposures:
		var game_t := cycle * float(i) / float(exposures)
		view.position = spot + Vector3(0, 0, speed * game_t)
		_pose(view, "run", game_t * rate)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var b := plate.get_pixel(x, y)
				if absf(c.r - b.r) + absf(c.g - b.g) + absf(c.b - b.b) > 0.12:
					var tint := Color.from_hsv(float(i) / exposures, 0.35, 1.0)
					composite.set_pixel(x, y, c.lerp(c * tint, 0.5))
	view.position = spot
	var ground_y := int(_camera.unproject_position(spot).y)
	for x in composite.get_width():
		if ground_y >= 0 and ground_y < composite.get_height():
			composite.set_pixel(x, ground_y, Color(1, 0.2, 0.2))
	composite.save_png(out.path_join("%s_contact.png" % id))
	print("  saved %s_contact (cycle %.2f s, %.2f m per cycle)" % [id, cycle, travel])


## The battle camera's distance (stage_view: steep pitch), the monster mid-stride, next to nothing: what a player sees.
func _fight(view: Node3D, anim: RefCounted, spot: Vector3, h: float, out: String, id: String) -> void:
	var cam: Camera3D = _stage.get_viewport().get_camera_3d() if false else null
	_camera.global_position = spot + Vector3(0.0, 11.0, 7.5)
	_camera.look_at(spot + Vector3(0, 0.5, 0))
	_pose(view, "run", anim.length("run") * 0.3)
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_fight.png" % id))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
