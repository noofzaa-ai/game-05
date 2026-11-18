extends SceneTree
## Look check of the mummy family in the real fighter view (client/fighter_view.gd: ink outline, own materials, the shared stance
## clip libraries), each mummy beside its goblin counterpart, at the same game heights the data gives them.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/monsters/mummy_family_shots.gd -- <out_dir> [--models=res://art/monsters/] [--strips] [--size=1280x720]
## Pairs: <out>/<mummy>_vs_<goblin>_<idle|attack>_<front|side|top>.png (top = about the battle camera's pitch).
## --strips also saves per mummy one strip per clip (three-quarter view, 6-7 frames) and a run strip from behind.

const PAIRS := [
	["mummy", "goblin", "attack_2"],
	["mummy_knight", "goblin_knight", "attack_2"],
	["mummy_mage", "goblin_mage", "cast"],
	["mummy_boss", "goblin_chief", "attack_2"],
	["mummy_archer", "goblin_archer", "shoot"],
]
const GOBLIN_ATTACK := {"goblin": "attack_2", "goblin_knight": "overhead", "goblin_mage": "cast", "goblin_chief": "attack_2", "goblin_archer": "shoot"}
const LIBRARY := {"mummy": "sword_shield", "mummy_knight": "sword_shield", "mummy_mage": "magic", "mummy_boss": "greatsword", "mummy_archer": "bow"}
const HEIGHT := {"mummy": 1.8, "mummy_knight": 2.0, "mummy_mage": 1.9, "mummy_boss": 2.6, "mummy_archer": 1.8}
const CROP := Vector2i(400, 560)

var _stage: Node
var _camera: Camera3D
var _models := "res://art/monsters/"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "user://mummy_family_shots"
	var size := Vector2i(1280, 720)
	var strips := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--models="):
			_models = a.substr(9)
		elif a == "--strips":
			strips = true
		elif a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
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

	for pair in PAIRS:
		var mummy_id: String = pair[0]
		var goblin_id: String = pair[1]
		var h: float = maxf(HEIGHT[mummy_id], float(enemies[goblin_id]["model_height"]))
		var gap := h * 0.55 + 0.4
		var m_view := _mummy_view(mummy_id, spot + Vector3(-gap * 0.5, 0, 0))
		var g_view := _goblin_view(enemies[goblin_id], spot + Vector3(gap * 0.5, 0, 0))
		await _frames(5)
		for pose in ["idle", "attack"]:
			var m_clip: String = "idle" if pose == "idle" else pair[2]
			var g_clip: String = "idle" if pose == "idle" else GOBLIN_ATTACK[goblin_id]
			_pose(m_view, m_clip, pose)
			_pose(g_view, g_clip, pose)
			for angle in ["front", "side", "top"]:
				# side by side for the camera: along x for front/top, along z (the mummy nearer) for the side view
				m_view.position = spot + (Vector3(-gap * 0.5, 0, 0) if angle != "side" else Vector3(0, 0, gap * 0.5))
				g_view.position = spot + (Vector3(gap * 0.5, 0, 0) if angle != "side" else Vector3(0, 0, -gap * 0.5))
				var centre := spot + Vector3(0, h * 0.5, 0)
				var dist := h * 2.2 + gap * 1.6 + 1.5
				match angle:
					"front":
						_camera.global_position = centre + Vector3(0.25, 0.25, 1.0).normalized() * dist
					"side":
						_camera.global_position = centre + Vector3(1.0, 0.15, 0.25).normalized() * dist
					"top":
						_camera.global_position = centre + Vector3(0.0, 1.0, 0.62).normalized() * dist
				_camera.look_at(centre)
				await _save(out, "%s_vs_%s_%s_%s" % [mummy_id, goblin_id, pose, angle])
		g_view.queue_free()
		if strips and mummy_id != "mummy_archer":
			m_view.position = spot
			await _strips(m_view, mummy_id, out, spot)
		m_view.queue_free()
		await _frames(2)
	quit()


func _mummy_view(id: String, at: Vector3) -> Node3D:
	var view := _new_view()
	view.monster_model_path = ("res://art/monsters/" if id == "mummy_archer" else _models) + id + "/" + id + ".glb"
	view.monster_model_height = HEIGHT[id]
	view.monster_animations_path = "res://art/animations/monster_clips_%s.glb" % LIBRARY[id]
	view.monster_nock_mesh = "arrow" if id == "mummy_archer" else ""
	_stage.add_child(view)
	view.position = at
	return view


func _goblin_view(definition: Dictionary, at: Vector3) -> Node3D:
	var view := _new_view()
	view.monster_model_path = definition["model"]
	view.monster_model_height = definition["model_height"]
	view.monster_animations_path = definition["animations"]
	view.monster_clips = definition["clips"]
	view.monster_nock_mesh = definition["nock_mesh"]
	view.monster_tint = definition["model_tint"]
	_stage.add_child(view)
	view.position = at
	return view


func _new_view() -> Node3D:
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	view.base_color = Color(0.72, 0.67, 0.54)
	view.monster_clips = {}
	view.monster_tint = Color.WHITE
	view.ink_outline = true
	return view


## idle at 1.2 s; an attack at its wind-up end (the pose the player reads before the hit).
func _pose(view: Node3D, clip: String, pose: String) -> void:
	var anim: RefCounted = view.monster_animation()
	if anim == null:
		return
	var t := 1.2
	if pose == "attack" and anim.has_clip(clip):
		t = float(anim._clips[clip]["meta"].get("windup_end", anim.length(clip) * 0.5))
	view._anim_clip = clip if anim.has_clip(clip) else "idle"
	view._anim_rate = 0.0
	view._blend = 1.0
	view._anim_time = t
	view._apply_clip()
	var nock := view.find_child("arrow", true, false) as Node3D
	if nock != null:
		nock.visible = pose == "attack"


func _strips(view: Node3D, id: String, out: String, spot: Vector3) -> void:
	var anim: RefCounted = view.monster_animation()
	var h: float = HEIGHT[id]
	for clip in anim.clip_names():
		var looping: bool = anim.is_looping(clip)
		var frames := 6 if looping or clip == "hit" else 7
		await _strip(view, anim, clip, clip, frames, spot, h, Vector3(2.6, 1.5, 5.0), out)
	await _strip(view, anim, "run", "run_back", 6, spot, h, Vector3(-2.4, 1.5, -5.0), out)
	await _strip(view, anim, "idle", "idle_side", 4, spot, h, Vector3(6.0, 1.3, 0.0), out)


func _strip(view: Node3D, anim: RefCounted, clip: String, label: String, frames: int, spot: Vector3, h: float, offset: Vector3, out: String) -> void:
	var k := h / 1.8
	_camera.global_position = spot + offset * k
	_camera.look_at(spot + Vector3(0, 0.85 * k, 0))
	var length: float = anim.length(clip)
	var images: Array[Image] = []
	for i in frames:
		var t: float = length * float(i) / float(frames) if anim.is_looping(clip) else length * float(i) / float(maxi(1, frames - 1))
		view._anim_clip = clip
		view._anim_rate = 0.0
		view._blend = 1.0
		view._anim_time = t
		view._apply_clip()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var centre := _camera.unproject_position(spot + Vector3(0, 0.9 * k, 0))
		var box := Rect2i(Vector2i(centre) - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		images.append(shot.get_region(box))
	var strip := Image.create(CROP.x * frames, CROP.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i(CROP.x * i, 0))
	var name := "%s_strip_%s" % [view.monster_model_path.get_file().get_basename(), label]
	strip.save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _save(dir: String, name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
