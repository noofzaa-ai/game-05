extends SceneTree
## Renders one dressed chibi close up, once per render setting, to compare against the model team's
## previews (needs a window: run WITHOUT --headless):
##   godot --path . --script res://tools/shots/closeup_shot.gd -- <out_dir> [distance]
## `distance` (default 3.2) moves the camera back to see what the game's far camera does to the model.

const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const OUTFIT := ["frostguard_cuirass", "frostguard_bracers", "frostguard_breeches", "frostguard_boots", "hammer_froststeel_01"]
## [file name, msaa, mesh LOD threshold in pixels (1 = Godot default, 0 = always full detail)]
const SETTINGS := [["now", Viewport.MSAA_DISABLED, 1.0], ["no_lod", Viewport.MSAA_DISABLED, 0.0], ["no_lod_msaa4", Viewport.MSAA_4X, 0.0], ["now_again", Viewport.MSAA_DISABLED, 1.0]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://shots"
	var distance: float = float(args[1]) if args.size() > 1 else 3.2
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(700, 850)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 25.0, 0.0)
	viewport.add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.38, 0.42, 0.46)
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 0.95, distance)
	viewport.add_child(camera)
	var model := CharacterModel.new()
	viewport.add_child(model)
	model.load_model()
	var loadout := Loadout.new(rules)
	var rng := RandomNumberGenerator.new()
	for item_id in OUTFIT:
		var base: Dictionary = rules.catalog.entry(item_id)
		loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
	var style := loadout.weapon_style(["fists", "blade", "dagger", "spear", "hammer"])
	model.dress(ItemAssets.looks(loadout, rules.catalog, style))
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.35, 0.94), false, "", "", style)
	for frame in 20:
		model.apply_pose(1.0 / 60.0)
	for setting in SETTINGS:
		viewport.msaa_3d = setting[1]
		viewport.mesh_lod_threshold = setting[2]
		for frame in 5:
			model.apply_pose(0.0)  # the same pose in every shot, so only the setting differs
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out_dir.path_join("closeup_%s_d%.0f.png" % [setting[0], distance]))
	quit()
