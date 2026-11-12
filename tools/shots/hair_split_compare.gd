extends SceneTree
## Hair split check (Boss 2026-11-13 item B), run windowed:
##   godot --path . --script res://tools/shots/hair_split_compare.gd
## The same character, pose, clock and camera drawn by the model code before the split (the whole-character
## files; build/hair_split/old_model.gd = `git show HEAD:client/characters/studio05_character_model.gd`) and after
## (base body + hair file). Saves before | after | difference strips to build/hair_split/ and prints the
## number of differing pixels per shot.
const OUT := "res://build/hair_split/"
const OLD := "res://build/hair_split/old_model.gd"
const NEW := "res://client/characters/studio05_character_model.gd"
var _scene: Node3D
var _camera: Camera3D
var _report: Array[String] = []


func _initialize():
	call_deferred("run")


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


func _model(script_path: String, cls: String, hair: String, silver: bool) -> Node3D:
	var model = load(script_path).new()
	_scene.add_child(model)
	model.load_model()
	var appearance := {"choices": {"makeup": "none"}, "studio_hair": hair, "studio_silver": silver, "iris_style": 0}
	model.dress({"class": cls, "appearance": appearance, "weapon": {"path": "", "family": "", "style": ""}})
	model.set_blink_mode("open")
	return model


func _pose(model, kind: String, seconds: float) -> void:
	model.set_pose(kind, 0.0, 1.0, true, Vector2(0, 1), false)
	var steps := int(round(seconds / 0.05))
	for i in steps:
		model.apply_pose(0.05)


func _aim(from: Vector3, target: Vector3, fov: float) -> void:
	_camera.fov = fov
	_camera.position = from
	_camera.look_at(target)


func _shoot(script_path: String, cls: String, hair: String, silver: bool, kind: String, seconds: float, view: String) -> Image:
	var model = _model(script_path, cls, hair, silver)
	_pose(model, kind, seconds)
	match view:
		"front":
			_aim(Vector3(0, 0.75, 3.4), Vector3(0, 0.7, 0), 30)
		"side":
			_aim(Vector3(3.4, 0.75, 0.0), Vector3(0, 0.7, 0), 30)
		"head":
			_aim(Vector3(1.0, 1.15, 1.6), Vector3(0, 1.0, 0), 22)
	await process_frame
	await process_frame
	var image: Image = await _grab()
	model.free()
	await process_frame
	return image


func _compare(name: String, before: Image, after: Image) -> void:
	var w := before.get_width()
	var h := before.get_height()
	var strip := Image.create(w * 3, h, false, Image.FORMAT_RGB8)
	strip.blit_rect(before, Rect2i(0, 0, w, h), Vector2i(0, 0))
	strip.blit_rect(after, Rect2i(0, 0, w, h), Vector2i(w, 0))
	var differing := 0
	var biggest := 0.0
	for y in h:
		for x in w:
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			biggest = maxf(biggest, d)
			if d > 2.0 / 255.0:
				differing += 1
				strip.set_pixel(w * 2 + x, y, Color(1, 0.15, 0.15))
			else:
				strip.set_pixel(w * 2 + x, y, a.darkened(0.75))
	strip.save_png(OUT + name + ".png")
	var line := "%-40s differing pixels %6d / %d  max channel diff %.3f" % [name, differing, w * h, biggest]
	_report.append(line)
	print("CMP ", line)


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(420, 600)
	_scene = Node3D.new()
	root.add_child(_scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("424e69")
	_scene.add_child(env)
	_camera = Camera3D.new()
	_scene.add_child(_camera)
	_camera.current = true
	var cases := [
		["sword_shield", "a", false], ["sword_shield", "e", false], ["sword_shield", "g", false], ["sword_shield", "c", true],
		["greatsword", "c", false], ["greatsword", "f", false], ["greatsword", "g", false], ["greatsword", "b", true],
		["longbow", "e", false], ["longbow", "f", false], ["longbow", "g", true], ["longbow", "a", true],
		["magic", "f", false], ["magic", "g", false], ["magic", "b", true],
	]
	var only := OS.get_environment("ZORX_ONLY")
	for c in cases:
		if not only.is_empty() and not str(c[0]).begins_with(only):
			continue
		for shot in [["idle", 1.3, "front"], ["run", 0.85, "side"], ["idle", 2.1, "head"]]:
			var name := "%s_hair%s%s_%s_%s" % [c[0], c[1], "_silver" if c[2] else "", shot[0], shot[2]]
			var before: Image = await _shoot(OLD, c[0], c[1], c[2], shot[0], shot[1], shot[2])
			var after: Image = await _shoot(NEW, c[0], c[1], c[2], shot[0], shot[1], shot[2])
			_compare(name, before, after)
	var file := FileAccess.open(OUT + "compare_report.txt", FileAccess.WRITE)
	file.store_string("\n".join(_report) + "\n")
	file.close()
	quit()
