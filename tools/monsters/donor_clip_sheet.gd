extends SceneTree
## Contact sheets of donor (player) clips, to pick monster clip segments by eye. Needs a window (not --headless).
##   godot --path . --script res://tools/monsters/donor_clip_sheet.gd -- <body.glb> <armor.glb|-> <out_dir> clip[:from:to] ...
## One PNG per clip: 10 frames from `from` to `to` (default the whole clip), three-quarter front view, time stamped in the file name list.

const CELL := Vector2i(220, 300)
const FRAMES := 10


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var body := (load(args[0]) as PackedScene).instantiate() as Node3D
	DisplayServer.window_set_size(Vector2i(CELL.x * 2, CELL.y * 2))
	root.size = Vector2i(CELL.x * 2, CELL.y * 2)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(body)
	if args[1] != "-":
		var armor := (load(args[1]) as PackedScene).instantiate() as Node3D
		body.add_child(armor)
		# drive the armor skeleton from the body skeleton
		var bsk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for m in armor.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).skeleton = m.get_path_to(bsk)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.55, 0.35, 0.85)
	cam.look_at(Vector3(0, 0.22, 0.05))
	cam.fov = 40
	cam.make_current()
	var player := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var out: String = args[2]
	DirAccess.make_dir_recursive_absolute(out)
	for i in range(3, args.size()):
		var parts: PackedStringArray = args[i].split(":")
		var clip := parts[0]
		var anim := player.get_animation(clip)
		var from := float(parts[1]) if parts.size() > 1 else 0.0
		var to := float(parts[2]) if parts.size() > 2 else anim.length
		var sheet := Image.create(CELL.x * FRAMES / 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
		player.play(clip)
		player.pause()
		var stamps := []
		for f in FRAMES:
			var t := from + (to - from) * f / float(FRAMES - 1)
			player.seek(t, true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(CELL.x, CELL.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * (f % (FRAMES / 2)), CELL.y * (f / (FRAMES / 2))))
			stamps.append("%.2f" % t)
		sheet.save_png(out.path_join("%s.png" % clip))
		print(clip, " frames at ", stamps)
	quit()
