extends SceneTree
## Race heads (Boss 2026-11-14, art/characters/studio05/v1111/race/race_heads.glb): one card as each race through
## the real Studio model, in the card ink look (hub) and the battle toon look, front and 3/4; every hair style
## (a b c e f g i) on every race head (front, 3/4, side, back); then the real class card hub with the four cards
## set to the four races. Run windowed (needs a GPU):
##   godot --path . --script res://tools/shots/race_heads_shots.gd
## Output: art_source/codex_review/race_heads_2026-11-14/*.png (contact sheets: tools/shots/race_heads_sheet.py).

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const RACES := ["human", "elf", "viking", "runeborn"]
const HAIRS := ["a", "b", "c", "e", "f", "g", "i"]
const VIEWS := [["front", 0.0], ["q34", 35.0], ["side", 90.0], ["back", 180.0]]
const OUT := "res://art_source/codex_review/race_heads_2026-11-14/"


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


func _stage(size: Vector2i, card: bool) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.80, 0.68) if card else Color(0.62, 0.66, 0.58)
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
	cam.fov = 30.0
	vp.add_child(cam)
	return {"vp": vp, "cam": cam}


func _appearance(hair: String, race: String) -> Dictionary:
	return {"choices": {"makeup": "none"}, "studio_hair": hair, "studio_silver": false, "iris_style": 0, "race": race}


func _pose(model) -> void:
	model._clock = 0.0  # the same idle frame in every shot (views compare like for like)
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
	for i in 3:
		model.apply_pose(0.11)


func _model(vp: SubViewport, card: bool):
	var model = CharacterModel.new()
	model.card_ink = card
	model.ink_outline = true
	vp.add_child(model)
	model.load_model()
	return model


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	for card in [true, false]:
		var stage := _stage(Vector2i(360, 440), card)
		var vp: SubViewport = stage["vp"]
		var cam: Camera3D = stage["cam"]
		var model = _model(vp, card)
		model.dress({"class": "sword_shield", "appearance": _appearance("a", "human")})
		var look := "card" if card else "toon"
		for race in RACES:
			model.dress({"appearance": _appearance("a", race)})
			for view in [VIEWS[0], VIEWS[1]]:
				model.rotation.y = deg_to_rad(view[1])
				# whole body, then the head
				cam.position = Vector3(0.0, 0.8, 3.3)
				cam.look_at(Vector3(0.0, 0.68, 0.0))
				_pose(model)
				await _save(vp, "%s_body_%s_%s.png" % [look, race, view[0]])
				cam.position = Vector3(0.0, 0.98, 1.35)
				cam.look_at(Vector3(0.0, 0.95, 0.0))
				await _save(vp, "%s_head_%s_%s.png" % [look, race, view[0]])
		if card:
			# every hair on every race head (the card look; the hair-head fit is the same in battle)
			for hair in HAIRS:
				for race in RACES:
					model.dress({"appearance": _appearance(hair, race)})
					for view in VIEWS:
						model.rotation.y = deg_to_rad(view[1])
						cam.position = Vector3(0.0, 0.98, 1.45)
						cam.look_at(Vector3(0.0, 0.95, 0.0))
						_pose(model)
						await _save(vp, "hair_%s_%s_%s.png" % [hair, race, view[0]])
		vp.queue_free()
		await _frames(2)
	await _hub()
	print("RACE_HEADS_SHOTS DONE")
	quit()


## The real class card hub (scenes/card_deck_screen.tscn) with the four cards as the four races.
func _hub() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var deck: Dictionary = gs.profile.card_deck.duplicate(true)
	var ids: Array = deck.get("cards", {}).keys()
	ids.sort()
	var order := {"sword_shield": "human", "greatsword": "elf", "longbow": "viking", "magic": "runeborn"}
	for id in ids:
		if order.has(id):
			deck["cards"][id]["race"] = order[id]
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	screen.show_deck(deck, load("res://client/item_assets.gd").cosmetics())
	await _frames(150)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "hub_four_races.png"))
	screen.queue_free()
	await _frames(2)
