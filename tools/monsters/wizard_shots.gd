extends SceneTree
## Look check of the Mummy High Wizard in the real fighter view (ink outline, own materials, its clip library) beside mummy_boss and
## goblin_chief at their game heights. Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/monsters/wizard_shots.gd -- <out_dir> [--size=844x390] [--strips]
## Writes <out>/scale_<pose>_<view>.png (the three side by side) and with --strips one strip per wizard clip.

const HEIGHT := 3.4
const CLIPS := ["idle", "run", "hit", "death", "cast", "cast_aoe", "summon", "starfall", "sandstorm"]

var _stage: Node
var _camera: Camera3D
var _out := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "user://wizard_shots"
	var size := Vector2i(1280, 720)
	var strips := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a == "--strips":
			strips = true
		else:
			out = a
	_out = out
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

	var wizard := _view("res://art/monsters/mummy_high_wizard/mummy_high_wizard.glb", HEIGHT, "res://art/animations/monster_clips_wizard_boss.glb", {}, Color.WHITE)
	var pharaoh := _view("res://art/monsters/mummy_boss/mummy_boss.glb", 2.6, "res://art/animations/monster_clips_greatsword.glb", {}, Color.WHITE)
	var chief: Dictionary = enemies["goblin_chief"]
	var goblin := _view(chief["model"], chief["model_height"], chief["animations"], chief["clips"], chief["model_tint"])
	var gap := 2.9
	var h := HEIGHT
	var centre := spot + Vector3(0, h * 0.5, 0)
	for pose in ["idle", "cast_aoe", "starfall", "summon", "sandstorm"]:
		_pose(wizard, pose)
		_pose(pharaoh, "idle" if pose == "idle" else "attack_2")
		_pose(goblin, "idle" if pose == "idle" else "attack_2")
		for angle in ["front", "side", "top"]:
			wizard.position = spot + (Vector3(0, 0, 0) if angle != "side" else Vector3(0, 0, gap))
			pharaoh.position = spot + (Vector3(-gap, 0, 0) if angle != "side" else Vector3(0, 0, 0))
			goblin.position = spot + (Vector3(gap, 0, 0) if angle != "side" else Vector3(0, 0, -gap))
			var dist := h * 2.6 + 4.0
			match angle:
				"front":
					_camera.global_position = centre + Vector3(0.25, 0.25, 1.0).normalized() * dist
				"side":
					_camera.global_position = centre + Vector3(1.0, 0.15, 0.25).normalized() * dist
				"top":
					_camera.global_position = centre + Vector3(0.0, 1.0, 0.62).normalized() * dist
			_camera.look_at(centre)
			await _save(out, "scale_%s_%s" % [pose, angle])
	pharaoh.queue_free()
	goblin.queue_free()
	if strips:
		wizard.position = spot
		var anim: RefCounted = wizard.monster_animation()
		for clip in CLIPS:
			var frames := 6 if anim.is_looping(clip) else 8
			await _strip(wizard, anim, clip, frames, spot, Vector3(3.6, 2.0, 7.0))
		await _strip(wizard, anim, "run", 6, spot, Vector3(-3.4, 2.0, -7.0), "run_back")
	quit()


func _view(path: String, height: float, library: String, clips: Dictionary, tint: Color) -> Node3D:
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	view.base_color = Color(0.72, 0.67, 0.54)
	view.monster_clips = clips
	view.monster_tint = tint
	view.ink_outline = true
	view.monster_model_path = path
	view.monster_model_height = height
	view.monster_animations_path = library
	view.monster_nock_mesh = ""
	_stage.add_child(view)
	return view


func _pose(view: Node3D, clip: String) -> void:
	var anim: RefCounted = view.monster_animation()
	if anim == null:
		return
	var t := 1.2
	if clip != "idle" and anim.has_clip(clip):
		t = float(anim._clips[clip]["meta"].get("windup_end", anim.length(clip) * 0.5))
	view._anim_clip = clip if anim.has_clip(clip) else "idle"
	view._anim_rate = 0.0
	view._blend = 1.0
	view._anim_time = t
	view._apply_clip()


func _strip(view: Node3D, anim: RefCounted, clip: String, frames: int, spot: Vector3, offset: Vector3, label := "") -> void:
	var k := HEIGHT / 1.8
	_camera.global_position = spot + offset * k * 0.7
	_camera.look_at(spot + Vector3(0, 0.95 * k, 0))
	var length: float = anim.length(clip)
	var crop := Vector2i(root.size.x / 3, root.size.y)
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
		var centre := _camera.unproject_position(spot + Vector3(0, 1.0 * k, 0))
		var box := Rect2i(Vector2i(centre) - crop / 2, crop).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		images.append(shot.get_region(box))
	var strip := Image.create(crop.x * frames, crop.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i(crop.x * i, 0))
	strip.save_png(_out.path_join("wizard_strip_%s.png" % (label if label != "" else clip)))
	print("saved strip ", clip)


func _save(dir: String, name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
