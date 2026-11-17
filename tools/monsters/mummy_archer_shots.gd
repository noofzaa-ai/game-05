extends SceneTree
## Pilot check: the mummy archer in the real game view (client/fighter_view.gd, ink outline, own-material tint) on the shared
## bow clip library, one PNG strip per clip, plus the short-legs variant on the wrong (shared) and the right (rescaled) library.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/monsters/mummy_archer_shots.gd -- <out_dir>

const MODEL := "res://art/monsters/mummy_archer/mummy_archer.glb"
## a short-legs TEST model: godot --headless --path . --script res://tools/monsters/build_mummy_archer.gd -- --legs=0.75 --name=mummy_archer_short --out=res://build/monster_probe/
const MODEL_SHORT := "res://build/monster_probe/mummy_archer_short.glb"
const LIB := "res://art/animations/monster_clips_bow.glb"
const CROP := Vector2i(380, 520)

var _stage: Node
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://mummy_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 800)
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
	var spot: Vector3 = _stage.get("_session")._sim.bodies[1].position + Vector3(0, 0.05, -1.0)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_stage.add_child(_camera)
	_camera.make_current()

	var view := _view(MODEL, LIB, 1.8, spot)
	await _frames(5)
	print("clips in library: ", view.monster_animation().clip_names())
	for clip in ["idle", "run", "shoot", "volley", "hit", "death"]:
		var length: float = view.monster_animation().length(clip)
		var frames := 7 if clip in ["shoot", "volley", "death"] else 6
		var span: float = length * (1.0 if clip != "hit" else 0.8)
		await _strip(view, out, clip, frames, span, spot, "three_quarter")
		if clip in ["shoot", "volley"]:
			await _strip(view, out, clip + "_side", frames, span, spot, "side")
	# a view from behind to check the loose bandages and the weights
	await _strip(view, out, "run_back", 6, view.monster_animation().length("run"), spot, "back")
	view.queue_free()

	# short legs (x0.75) on the shared library: the hips float without hips_scale, feet on the floor with it
	if ResourceLoader.exists(MODEL_SHORT):
		var wrong := _view(MODEL_SHORT, LIB, 1.8 * 0.93, spot)
		await _frames(5)
		await _strip(wrong, out, "short_legs_hips_scale_1_run", 6, 0.88, spot, "three_quarter", "run")
		await _strip(wrong, out, "short_legs_hips_scale_1_idle", 4, 3.0, spot, "three_quarter", "idle")
		wrong.queue_free()
		var right := _view(MODEL_SHORT, LIB, 1.8 * 0.93, spot, 0.75)
		await _frames(5)
		await _strip(right, out, "short_legs_hips_scale_075_run", 6, 0.88, spot, "three_quarter", "run")
		await _strip(right, out, "short_legs_hips_scale_075_idle", 4, 3.0, spot, "three_quarter", "idle")
		await _strip(right, out, "short_legs_hips_scale_075_shoot", 7, right.monster_animation().length("shoot"), spot, "three_quarter", "shoot")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _view(model: String, library: String, height: float, spot: Vector3, hips_scale := 1.0) -> Node3D:
	var definition: Dictionary = _stage.get("_session")._sim.combat.enemies["goblin_archer"]
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	view.base_color = Color(0.72, 0.67, 0.54)
	view.monster_model_path = model
	view.monster_model_height = height
	view.monster_animations_path = library
	view.monster_clips = {}
	view.monster_nock_mesh = "arrow"
	view.monster_hips_scale = hips_scale
	view.monster_tint = Color.WHITE
	view.ink_outline = true
	_stage.add_child(view)
	view.position = spot
	return view


func _strip(view: Node3D, out: String, name: String, frames: int, span: float, spot: Vector3, angle: String, clip_override := "") -> void:
	var clip := clip_override if clip_override != "" else name.replace("_side", "").replace("_back", "")
	var anim: RefCounted = view.monster_animation()
	var cam_offsets := {"three_quarter": Vector3(2.6, 1.5, 5.0), "side": Vector3(6.0, 1.3, 0.0), "back": Vector3(-2.4, 1.5, -5.0)}
	_camera.global_position = spot + cam_offsets[angle]
	_camera.look_at(spot + Vector3(0, 0.85, 0))
	var images: Array[Image] = []
	for i in frames:
		var t: float = span * float(i) / float(maxi(1, frames - 1)) if not anim.is_looping(clip) else span * float(i) / float(frames)
		view._anim_clip = clip
		view._anim_rate = 0.0
		view._blend = 1.0
		view._anim_time = t
		view._apply_clip()
		var nock := view.find_child("arrow", true, false) as Node3D
		if nock != null:
			nock.visible = clip in ["shoot", "volley"] and t < float(anim._clips[clip]["meta"].get("windup_end", 0.0))
		await _frames(3)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var centre := _camera.unproject_position(spot + Vector3(0, 0.9, 0))
		var box := Rect2i(Vector2i(centre) - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		images.append(shot.get_region(box))
	var strip := Image.create(CROP.x * frames, CROP.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i(CROP.x * i, 0))
	strip.save_png(out.path_join(name + ".png"))
	print("saved ", name)
