extends SceneTree
## Shared orthographic camera and ground plane; reads live role scales. No profile or network calls.
const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const HubNpc := preload("res://client/hub_npc.gd")
func _initialize() -> void:
	call_deferred("capture")

func legacy_clothing(item: String) -> String:
	var source := ProjectSettings.globalize_path("res://../.cache/skill_revisions/game_before_new_v1_20261019/clothing/" + item + ".glb")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_file(source, state) == OK)
	var scene := doc.generate_scene(state)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	var folder := "res://build/model-review-old"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder + "/" + item + ".scn"
	assert(ResourceSaver.save(packed, path) == OK)
	scene.free()
	return path


func capture() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("202b35")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.1
	vp.add_child(light)
	var rows := [["merchant", "Merchant", -3.5], ["storage", "Bank", -1.4], ["blacksmith", "Blacksmith", .8], ["quest", "Quest Board", 3.3]]
	var with_player := OS.get_cmdline_user_args().has("--with-player")
	if with_player:
		rows = [["merchant", "Merchant", -4.3], ["storage", "Bank", -2.4], ["player", "Player (New v1)", -.5], ["blacksmith", "Blacksmith", 1.4], ["quest", "Quest Board", 3.8]]
	if OS.get_cmdline_user_args().has("--with-old-player"):
		rows = [["merchant", "Merchant", -4.9], ["storage", "Bank", -3.0], ["old_player", "Player (previous)", -1.1], ["player", "Player (New v1)", .8], ["blacksmith", "Blacksmith", 2.7], ["quest", "Quest Board", 5.0]]
	for row in rows:
		var role: String = row[0]
		var factor := float(HubNpc.ROLE_VISUAL_SCALE.get(role, 1.0))
		var model: Node3D
		if role in ["player", "old_player"]:
			var player := CharacterModel.new()
			vp.add_child(player)
			assert(player.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb") if role == "old_player" else player.load_model("res://art/characters/new-v1/newv1_base_animated.glb") if OS.get_cmdline_user_args().has("--with-old-player") else player.load_model())
			player.equipment_rest = true
			player.set_appearance(ItemAssets.appearance({"face": "bored", "hair_style": "short_fringe"}))
			player.dress({"shirt": ItemAssets.path("clothing_scout_vest_01"), "pants": ItemAssets.path("clothing_scout_breeches_01"), "shoes": ItemAssets.path("clothing_scout_boots_01")})
			if role == "player" and OS.get_cmdline_user_args().has("--with-old-player"):
				player.set_appearance({"face": "res://art/items/faces/fit_new_v1/face_anime_bored_01.glb", "hair_style": "res://art/items/hair/fit_new_v1/hair_row2_short_fringe_01.glb", "skin": Color("f0cdb0")})
				player.dress({"shirt": "res://art/items/clothing/fit_new_v1/clothing_scout_vest_01.glb", "pants": "res://art/items/clothing/fit_new_v1/clothing_scout_breeches_01.glb", "shoes": "res://art/items/clothing/fit_new_v1/clothing_scout_boots_01.glb"})
			if role == "old_player":
				player.set_appearance({"face": "res://art/items/faces/face_anime_bored_01.glb", "hair_style": "res://art/items/hair/hair_row2_short_fringe_01.glb", "skin": Color("f0cdb0")})
				player.dress({"shirt": legacy_clothing("clothing_scout_vest_01"), "pants": legacy_clothing("clothing_scout_breeches_01"), "shoes": legacy_clothing("clothing_scout_boots_01")})
			player.set_pose("idle", 0.0, 0.0, true, Vector2(0, 1), false, "", "", "fists")
			for frame in 60:
				player.apply_pose(1.0 / 60.0)
			model = player
		else:
			model = load(HubNpc.ROLE_MODELS[role]).instantiate()
			model.scale *= factor
			vp.add_child(model)
		model.position.x = float(row[2])
		var label := Label3D.new()
		label.text = "%s\n%s" % [row[1], "in-game size" if role in ["player", "old_player"] else "%.3fx" % factor]
		label.font_size = 40
		label.pixel_size = .002
		label.modulate = Color("eed8aa")
		label.position = Vector3(float(row[2]), -.32, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		vp.add_child(label)
	var baseline := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(13.1 if OS.get_cmdline_user_args().has("--with-old-player") else 11.0 if with_player else 9.6, .012, .012)
	baseline.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("7c8b98")
	baseline.material_override = mat
	vp.add_child(baseline)
	var camera := Camera3D.new()
	vp.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.6 if OS.get_cmdline_user_args().has("--with-old-player") else 5.6 if with_player else 5.0
	camera.position = Vector3(0, 1.65, 10)
	camera.look_at(Vector3(0, 1.35, 0))
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	vp.get_texture().get_image().save_png(out)
	print("Saved ", out)
	quit()
