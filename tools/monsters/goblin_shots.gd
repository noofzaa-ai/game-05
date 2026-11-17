extends SceneTree
## Look check of the five goblins in the real fighter view (ink outline, own-material): per goblin a three-quarter body shot and a
## face close-up, at the window size (monster budget work: run before and after changing a model).
##   godot --path . --script res://tools/monsters/goblin_shots.gd -- --size=1280x720 --tag=before <out_dir>
## Needs a window (not --headless). Saves <out_dir>/<tag>_<WxH>_<monster>_{body,face}.png

const GOBLINS := ["goblin", "goblin_archer", "goblin_chief", "goblin_knight", "goblin_mage"]
var _stage: Node
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	var tag := "shot"
	var out := "user://goblin_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts := a.substr(7).split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--tag="):
			tag = a.substr(6)
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
	for monster in GOBLINS:
		var definition: Dictionary = enemies[monster]
		var view := Node3D.new()
		view.set_script(load("res://client/fighter_view.gd"))
		view.base_color = Color(0.5, 0.55, 0.3)
		view.monster_model_path = definition["model"]
		view.monster_model_height = definition["model_height"]
		view.monster_animations_path = definition["animations"]
		view.monster_clips = definition["clips"]
		view.monster_nock_mesh = definition["nock_mesh"]
		view.monster_tint = definition["model_tint"]
		view.ink_outline = true
		_stage.add_child(view)
		view.position = spot
		await _frames(5)
		var height: float = definition["model_height"]
		view._anim_clip = "idle"
		view._anim_rate = 0.0
		view._blend = 1.0
		view._anim_time = 1.2
		view._apply_clip()
		var nock := view.find_child("arrow", true, false) as Node3D
		if nock != null:
			nock.visible = false
		# three-quarter body shot
		_camera.global_position = spot + Vector3(0.45, 0.55, 1.0).normalized() * (height * 2.7 + 1.0) + Vector3(0, height * 0.2, 0)
		_camera.look_at(spot + Vector3(0, height * 0.5, 0))
		await _save(out, "%s_%dx%d_%s_body" % [tag, size.x, size.y, monster])
		# face close-up (the fight camera's closest zoom is about this near)
		_camera.global_position = spot + Vector3(0.35, 0, 1.0).normalized() * (height * 1.15 + 0.35) + Vector3(0, height * 0.6, 0)
		_camera.look_at(spot + Vector3(0, height * 0.58, 0))
		await _save(out, "%s_%dx%d_%s_face" % [tag, size.x, size.y, monster])
		view.queue_free()
		await _frames(2)
	quit()


func _save(dir: String, name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
