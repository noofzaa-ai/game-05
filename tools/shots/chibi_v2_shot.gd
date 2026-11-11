extends SceneTree
## Renders the NEW chibi_v2 base character the way the game shows the player, next to the current
## model, for the Boss's review (2026-10-12). Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/chibi_v2_shot.gd -- <out_dir>
##
## Per view it captures, for v1 (current) and v2 (new) side by side:
##   - camp paper-doll camera (front / three-quarter / side): bare body + three full sets, with the
##     default face and two hair items (plus the body's own bob)
##   - the fight camera (raised 3/4) playing idle, run and one attack clip, a few frames each, to
##     check skin deformation at the joints.
## Read-only on shipped assets; it only swaps the model path CharacterModel.load_model() loads.

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const V1 := "res://art/characters/chibi-studio/chibi_base_animated.glb"
const V2 := "res://art/characters/chibi-v2/chibi_v2.glb"
const STYLES := ["fists", "blade", "dagger", "spear", "hammer"]

## Three full sets to check outfit fit (real catalog ids).
const SETS := {
	"shinigami_f": ["shinigami_f_head", "shinigami_f_shirt", "shinigami_f_arms", "shinigami_f_pants", "shinigami_f_shoes", "blade_01"],
	"knight": ["knight_cuirass", "knight_bracers", "knight_tassets", "knight_greaves", "hammer_01"],
	"crane": ["crane_wings", "crane_jacket", "crane_sleeves", "crane_skirt", "crane_boots", "dagger_01"],
}
const FACE := "res://art/items/faces/face_smile_01.glb"
const FACE_V2 := "res://art/items/faces_v2/face_v2_smile.glb"  ## v2's own default face (eyes OPEN)
## The 11 v2 faces, same ids/order as data/cosmetics/faces.json.
const FACES_V2 := [
	["smile", "Smile"], ["soft_smile", "Soft Smile"], ["playful", "Playful"],
	["prankster", "Prankster"], ["devious", "Devious"], ["vampire", "Fang"],
	["bored", "Bored"], ["annoyed", "Annoyed"], ["err", "Err..."],
	["sad", "Worried"], ["shout", "Shout"],
]
const HAT_HIDES_HAIR := "res://art/items/clothing/clothing_aegis_helmet_01.glb"  ## hide_hair=true
const HAIR := [
	["bob", ""],
	["wavy_fringe_bob", "res://art/items/hair/hair_ref10_03.glb"],
	["side_sweep", "res://art/items/hair/hair_row4_side_sweep_01.glb"],
]
const SKIN := Color("#f0cdb0")
const HAIR_COLOR := Color("#f0968a")  ## salmon-pink


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://chibi_v2"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var rng := RandomNumberGenerator.new()
	await process_frame

	# Three fixed full sets (plus the bare body) exercise outfit fit on both versions.
	var set_ids := SETS
	await process_frame

	var doll_vp := _make_viewport(Vector2i(700, 950))
	var fight_vp := _make_viewport(Vector2i(1100, 760))
	var doll_cam := Camera3D.new(); doll_cam.fov = 26.0; doll_vp.add_child(doll_cam)
	var fight_cam := Camera3D.new(); fight_cam.fov = 55.0; fight_vp.add_child(fight_cam)
	fight_cam.look_at_from_position(Vector3(0.0, 7.0, 7.0), Vector3(0.0, 0.5, 0.0))

	# --- Paper doll: bare + full sets, for both versions. Front/3-4/side.
	for version in [["v1", V1], ["v2", V2]]:
		for dress_state in (["bare"] + set_ids.keys()):
			for hair in HAIR:
				if dress_state != "bare" and hair[0] != "bob":
					continue  # keep the matrix small: hair variety only on the bare body
				var model: CharacterModel = _build(version[1], rules, rng, dress_state, set_ids, hair, FACE_V2 if version[0] == "v2" else FACE)
				if model == null:
					continue
				doll_vp.add_child(model)
				for _f in 24:
					model.apply_pose(1.0 / 60.0)
				await process_frame
				var tag := "%s_%s_%s" % [version[0], dress_state, hair[0]]
				for angle in [["front", Vector3(0.0, 1.05, 4.6)], ["threequarter", Vector3(3.1, 1.05, 3.4)], ["side", Vector3(4.6, 1.05, 0.0)]]:
					doll_cam.position = angle[1]
					doll_cam.look_at(Vector3(0.0, 0.9, 0.0))
					for _f in 2:
						model.apply_pose(1.0 / 60.0)
						await process_frame
					await RenderingServer.frame_post_draw
					doll_vp.get_texture().get_image().save_png(out_dir.path_join("doll_%s_%s.png" % [tag, angle[0]]))
				model.queue_free()
				await process_frame

	# --- Fight camera: deformation check. idle / run / an attack, a few frames each.
	for version in [["v1", V1], ["v2", V2]]:
		var model: CharacterModel = _build(version[1], rules, rng, set_ids.keys()[0], set_ids, HAIR[0], FACE_V2 if version[0] == "v2" else FACE)
		if model == null:
			continue
		fight_vp.add_child(model)
		var moves := [
			["idle", func(m): m.set_pose("idle", 0.0, 0.0, true, Vector2(0.4, 0.9), false, "", "", "blade")],
			["run", func(m): m.set_pose("run", 0.0, 1.0, true, Vector2(1, 0), false, "", "", "blade")],
			["attack", func(m): m.set_pose("heavy", 0.6, 0.0, true, Vector2(1, 0), false, "strike", "heavy", "blade")],
		]
		for move in moves:
			move[1].call(model)
			for _f in 20:
				model.apply_pose(1.0 / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			fight_vp.get_texture().get_image().save_png(out_dir.path_join("fight_%s_%s.png" % [version[0], move[0]]))
		model.queue_free()
		await process_frame

	# --- Face sheet: each of the 11 v2 faces on the v2 head, at a close head framing and at
	# fight-camera size, so the PO can judge how they read small. Saved one per face per size;
	# compose_v2_faces.py tiles them into two contact sheets.
	var head_vp := _make_viewport(Vector2i(360, 360))
	var head_cam := Camera3D.new(); head_cam.fov = 20.0; head_vp.add_child(head_cam)
	var fit_vp := _make_viewport(Vector2i(220, 300))  # ~character 150 px tall from the fight angle
	var fit_cam := Camera3D.new(); fit_cam.fov = 32.0; fit_vp.add_child(fit_cam)
	for face in FACES_V2:
		var face_file: String = "res://art/items/faces_v2/face_v2_%s.glb" % face[0]
		# close head shot
		var m1: CharacterModel = _build(V2, rules, rng, "bare", set_ids, HAIR[0], face_file)
		if m1 != null:
			head_vp.add_child(m1)
			for _f in 20:
				m1.apply_pose(1.0 / 60.0)
			# frame the head: character is ~1.7 tall, head top ~1.6, head centre ~1.45 in world
			head_cam.position = Vector3(0.0, 1.5, 1.35)
			head_cam.look_at(Vector3(0.0, 1.46, 0.0))
			for _f in 2:
				m1.apply_pose(1.0 / 60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			head_vp.get_texture().get_image().save_png(out_dir.path_join("faceclose_%s.png" % face[0]))
			m1.queue_free()
			await process_frame
		# fight-size shot (raised 3/4, the whole character small)
		var m2: CharacterModel = _build(V2, rules, rng, "bare", set_ids, HAIR[0], face_file)
		if m2 != null:
			fit_vp.add_child(m2)
			m2.set_pose("idle", 0.0, 0.0, true, Vector2(0.4, 0.9), false)
			for _f in 20:
				m2.apply_pose(1.0 / 60.0)
			fit_cam.look_at_from_position(Vector3(0.0, 2.4, 2.4), Vector3(0.0, 0.9, 0.0))
			for _f in 2:
				m2.apply_pose(1.0 / 60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			fit_vp.get_texture().get_image().save_png(out_dir.path_join("facefit_%s.png" % face[0]))
			m2.queue_free()
			await process_frame

	# --- A hat that hides hair (helmet) on v2: hair must disappear, head keeps its shape.
	var hat_model: CharacterModel = _build(V2, rules, rng, "bare", set_ids, HAIR[0], FACE_V2)
	if hat_model != null:
		doll_vp.add_child(hat_model)
		hat_model.dress({"hat": HAT_HIDES_HAIR, "hide_hair": true, "appearance": {"skin": SKIN, "hair": HAIR_COLOR, "face": FACE_V2}})
		for _f in 24:
			hat_model.apply_pose(1.0 / 60.0)
		for angle in [["front", Vector3(0.0, 1.05, 4.6)], ["threequarter", Vector3(3.1, 1.05, 3.4)]]:
			doll_cam.position = angle[1]
			doll_cam.look_at(Vector3(0.0, 0.9, 0.0))
			for _f in 2:
				hat_model.apply_pose(1.0 / 60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			doll_vp.get_texture().get_image().save_png(out_dir.path_join("hat_hides_hair_%s.png" % angle[0]))
		hat_model.queue_free()
		await process_frame

	print("CHIBI_V2_SHOTS_DONE ", out_dir)
	quit()


func _build(path: String, rules, rng, dress_state: String, set_ids: Dictionary, hair: Array, face_path: String = FACE) -> CharacterModel:
	var model := CharacterModel.new()
	model.ink_outline = true
	# swap the model path by overriding the constant at load time
	if not model.load_model(path):
		push_warning("failed to load " + path)
		model.queue_free()
		return null
	var appearance := {"skin": SKIN, "hair": HAIR_COLOR, "face": face_path, "hair_style": hair[1]}
	if dress_state == "bare":
		model.set_appearance(appearance)
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false)
	else:
		var items: Array = set_ids[dress_state]
		var loadout := Loadout.new(rules)
		for item_id in items:
			var base: Dictionary = rules.catalog.entry(item_id)
			if base.is_empty():
				continue
			loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
		var style := loadout.weapon_style(STYLES)
		var looks := ItemAssets.looks(loadout, rules.catalog, style)
		looks["appearance"] = appearance
		model.dress(looks)
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0.4, 0.9), false, "", "", style)
	return model


## Finds up to three wearable sets from the catalog (shinigami_f + two others with the most slots).
func _make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.76, 0.72)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	light.light_energy = 1.0
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.3, 1.0)
	return viewport
