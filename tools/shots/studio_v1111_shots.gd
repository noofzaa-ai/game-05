extends SceneTree
## Studio drop 2026-11-11 review (run windowed): every class card's look (class outfit + weapon, the card's
## starter hair) front and side, idle and running; hair G and Silver Silk; iris presets/makeup close-ups;
## the sword & shield shield cases. PNGs in build/studio_v1111/.
const OUT := "res://build/studio_v1111/"
var _scene: Node3D
var _camera: Camera3D


func _initialize():
	call_deferred("run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("SHOT ", name)


func _model(cls: String, hair: String, silver: bool, extra: Dictionary = {}) -> Node3D:
	var model = load("res://client/characters/studio05_character_model.gd").new()
	_scene.add_child(model)
	model.load_model()
	var appearance := {"choices": {"makeup": str(extra.get("makeup", "none"))}, "studio_hair": hair, "studio_silver": silver, "iris_style": int(extra.get("iris", 0))}
	var looks := {"class": cls, "appearance": appearance, "weapon": {"path": "res://art/items/weapons/blade.glb", "family": "blade"}}
	if extra.has("offhand"):
		looks["offhand"] = extra["offhand"]
		looks["refine"] = {"offhand": int(extra.get("refine", 0))}
	model.dress(looks)
	model.set_blink_mode("open")
	return model


func _pose(model, kind: String, frames: int = 12) -> void:
	model.set_pose(kind, 0.0, 1.0, true, Vector2(0, 1), false)
	for i in frames:
		model.apply_pose(0.033)
		await process_frame


func _aim(target: Vector3, from: Vector3, fov: float) -> void:
	_camera.fov = fov
	_camera.position = from
	_camera.look_at(target)


func run():
	var only_faces := OS.get_environment("ZORX_FACES") == "1"
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(560, 760)
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
	if only_faces:
		await _faces()
		quit()
		return
	var starters := {"sword_shield": "a", "greatsword": "c", "longbow": "e", "magic": "f"}
	for cls in starters:
		var model = _model(cls, starters[cls], false)
		for kind in ["idle", "run"]:
			await _pose(model, kind)
			# The model faces +x by default (facing (0,1) turns it toward the camera at +z).
			_aim(Vector3(0, 0.7, 0), Vector3(0, 0.75, 3.6), 30)
			await _shot("%s_%s_front" % [cls, kind])
			_aim(Vector3(0, 0.7, 0), Vector3(3.6, 0.75, 0), 30)
			await _shot("%s_%s_side" % [cls, kind])
			_aim(Vector3(0, 0.7, 0), Vector3(0, 0.75, -3.6), 30)
			await _shot("%s_%s_back" % [cls, kind])
		model.free()
		await process_frame
	# Hair G and Silver Silk (weapons-only gear) on two classes.
	for setup in [["greatsword", "g", false], ["longbow", "g", true], ["magic", "b", true]]:
		var model = _model(setup[0], setup[1], setup[2])
		await _pose(model, "idle")
		_aim(Vector3(0, 0.7, 0), Vector3(1.6, 0.9, 3.2), 30)
		await _shot("%s_hair%s%s" % [setup[0], setup[1], "_silver" if setup[2] else ""])
		model.free()
		await process_frame
	await _faces()
	await _shields()
	quit()


func _faces() -> void:
	# Face close-ups: iris presets and makeup (Studio menus).
	var faces := [[0, "anime_soft"], [1, "sharp_wing"], [3, "natural"], [6, "anime_soft"], [7, "sharp_wing"], [9, "natural"], [10, "anime_soft"]]
	for face in faces:
		var model = _model("sword_shield", "c", false, {"iris": face[0], "makeup": face[1]})
		await _pose(model, "idle")
		_aim(Vector3(0, 0.98, 0), Vector3(0, 1.0, 1.6), 20)
		await _shot("face_iris%02d_%s" % [face[0], face[1]])
		model.free()
		await process_frame
	# Blink: shut lids.
	var blinker = _model("sword_shield", "a", false)
	await _pose(blinker, "idle")
	blinker.set_blink_mode("closed")
	_aim(Vector3(0, 0.98, 0), Vector3(0, 1.0, 1.6), 20)
	await _shot("face_blink_closed")
	blinker.free()
	await process_frame


func _shields() -> void:
	# Shields: empty slot (class shield), the procedural round_shield, round_shield refined +7, longbow (none).
	var cases := [["sword_shield", {}, 0, "shield_empty_slot"], ["sword_shield", {"item_id": "round_shield", "procedural": true, "path": ""}, 0, "shield_round"], ["sword_shield", {"item_id": "round_shield", "procedural": true, "path": ""}, 7, "shield_round_refine7"], ["longbow", {"item_id": "round_shield", "procedural": true, "path": ""}, 0, "shield_longbow_none"]]
	for c in cases:
		var model = _model(c[0], "a", false, {"offhand": c[1], "refine": c[2]})
		await _pose(model, "idle")
		print("SHIELD ", c[3], " kind=", model.shield_kind())
		_aim(Vector3(0, 0.7, 0), Vector3(-2.2, 0.9, 2.8), 30)
		await _shot(c[3])
		model.free()
		await process_frame
