extends SceneTree
## Hair I (Boss 2026-11-13, art/characters/studio05/v1111/hair/hair_i.glb) on every class through the real
## Studio model (client/characters/studio05_character_model.gd): the class suit and the four race outfits with
## the race weapon, front / side / back, idle and mid-run; head close-ups (collar check); hair G beside it as the
## reference; and the card hair_color tint. Run windowed (needs a GPU):
##   godot --path . --script res://tools/shots/hair_i_shots.gd
## Output: build/hair_i/*.png (the contact sheet: tools/shots/hair_i_sheet.py).

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const SLOTS := ["shirt", "pants", "armband", "shoes"]
const SIDES := [["front", 0.0], ["side", 90.0], ["back", 180.0]]
const TINTS := ["", "#2a1d17", "#c04080", "#3a5fcd", "#e8d27a"]
const OUT := "res://build/hair_i/"


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(vp: SubViewport, name: String) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _frames(3)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name))


func _stage(size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = CardTokens.PORTRAIT_AMBIENT
	env.ambient_light_energy = CardTokens.PORTRAIT_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	CharacterLight.light_scene(vp, env, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	var cam := Camera3D.new()
	vp.add_child(cam)
	return {"vp": vp, "cam": cam}


func _appearance(hair: String, tint: String) -> Dictionary:
	var a := {"choices": {"makeup": "none"}, "studio_hair": hair, "studio_silver": false, "iris_style": 0}
	if not tint.is_empty():
		a["hair"] = Color(tint)
		a["hair_natural"] = false
	return a


func _looks(cls: String, race: String) -> Dictionary:
	var family := str(CardDeck.class_data(cls).get("weapon", ""))
	var looks := {"weapon": {"path": "", "family": family, "style": family}, "offhand": {}}
	for slot in SLOTS:
		looks[slot] = "" if race == "suit" else "res://art/armor/race_shared/%s_%s.glb" % [race, slot]
	if race != "suit":
		looks["weapon"]["path"] = "res://art/weapons/race_%s/%s.glb" % [race, cls]
		if cls == "sword_shield":
			looks["offhand"] = {"item_id": "race_%s_shield" % race, "asset_id": "procedural_round_shield", "procedural": true, "path": "res://art/weapons/race_%s/shield.glb" % race, "refine_level": 0}
	return looks


func _pose(model, pose: String) -> void:
	model.set_pose(pose, 1.0 if pose == "run" else 0.0, 4.0 if pose == "run" else 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
	for i in 3:
		model.apply_pose(0.11)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var stage := _stage(Vector2i(320, 420))
	var vp: SubViewport = stage["vp"]
	var cam: Camera3D = stage["cam"]
	cam.fov = 30.0
	var model = CharacterModel.new()
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	for cls in CLASSES:
		model.dress({"class": cls, "appearance": _appearance("i", "")})
		for race in ["suit"] + RACES:
			model.dress(_looks(cls, race))
			model.dress({"appearance": _appearance("i", "")})
			for pose in ["idle", "run"]:
				for side in SIDES:
					model.rotation.y = deg_to_rad(side[1])
					cam.fov = 30.0
					cam.position = Vector3(0.0, 0.8, 3.3)
					cam.look_at(Vector3(0.0, 0.68, 0.0))
					_pose(model, pose)
					await _save(vp, "body_%s_%s_%s_%s.png" % [cls, race, pose, side[0]])
			# head close-up: the collar / hood line and the hair ends
			for side in SIDES:
				model.rotation.y = deg_to_rad(side[1])
				cam.fov = 30.0
				cam.position = Vector3(0.0, 1.12, 1.25)
				cam.look_at(Vector3(0.0, 1.05, 0.0))
				_pose(model, "idle")
				await _save(vp, "head_%s_%s_%s.png" % [cls, race, side[0]])
		# hair G (reference) and hair I, class suit, head close-up
		model.dress(_looks(cls, "suit"))
		for hair in ["g", "i"]:
			model.dress({"appearance": _appearance(hair, "")})
			for side in SIDES:
				model.rotation.y = deg_to_rad(side[1])
				cam.position = Vector3(0.0, 1.12, 1.25)
				cam.look_at(Vector3(0.0, 1.05, 0.0))
				_pose(model, "idle")
				await _save(vp, "cmp_%s_%s_%s.png" % [cls, hair, side[0]])
	# card hair_color tints (sword & shield, suit)
	model.dress({"class": "sword_shield"})
	model.dress(_looks("sword_shield", "suit"))
	for tint in TINTS:
		model.dress({"appearance": _appearance("i", tint)})
		model.rotation.y = deg_to_rad(30.0)
		cam.position = Vector3(0.0, 1.12, 1.25)
		cam.look_at(Vector3(0.0, 1.05, 0.0))
		_pose(model, "idle")
		await _save(vp, "tint_%s.png" % (tint.trim_prefix("#") if not tint.is_empty() else "default"))
	print("HAIR_I_SHOTS DONE")
	quit()
