extends SceneTree
## Renders every clothing set of the catalog (all its pieces worn, default looks) from the front, the
## side, mid-run and the back, one PNG per set, to find skin showing through clothes.
## Needs a window (no --headless):
##   godot --path . --script res://tools/shots/set_fit_shots.gd -- <out_dir> [set_id...]

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://sets"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var rules := ItemRulesLoader.load_default()
	var sets := {}  # set_id -> [catalog item ids]
	for item_id in rules.catalog.items:
		var asset_id := str(rules.catalog.entry(item_id).get("asset_id", ""))
		var set_id := str(ItemAssets.entry(asset_id).get("set_id", ""))
		if not set_id.is_empty() and rules.catalog.entry(item_id)["slot"] != "weapon":
			sets[set_id] = sets.get(set_id, []) + [item_id]
	var wanted: Array = args.slice(1) if args.size() > 1 else sets.keys()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 760)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.3, 0.33, 0.36)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.74, 0.68)
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.3, 1.0)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 0.95, 4.6)
	viewport.add_child(camera)
	var rng := RandomNumberGenerator.new()
	var setups := [["idle", Vector2(0.0, 1.0)], ["idle", Vector2(1.0, 0.0)], ["run", Vector2(0.7, 0.7)], ["idle", Vector2(0.0, -1.0)]]
	for set_id in wanted:
		var models: Array = []
		for index in setups.size():
			var model := CharacterModel.new()
			model.ink_outline = true
			viewport.add_child(model)
			model.load_model()
			model.position.x = -2.4 + 1.6 * index
			var loadout := Loadout.new(rules)
			for item_id in sets.get(set_id, []):
				loadout.equip(ItemSystem.create_item(rules, item_id, rules.catalog.entry(item_id)["slot"], 0, rng, "", item_id))
			var looks := ItemAssets.looks(loadout, rules.catalog, "fists")
			looks["appearance"] = ItemAssets.appearance({})
			model.dress(looks)
			model.set_pose(setups[index][0], 0.0, 1.0, true, setups[index][1], false)
			models.append(model)
		for frame in 24:
			for model in models:
				model.apply_pose(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out_dir.path_join(str(set_id) + ".png"))
		for model in models:
			model.queue_free()
		await process_frame
	quit()
