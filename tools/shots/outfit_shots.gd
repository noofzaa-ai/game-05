extends SceneTree
## Renders the chibi wearing catalog outfits to PNGs (needs a window: run WITHOUT --headless):
##   godot --path . --script res://tools/shots/outfit_shots.gd -- <out_dir>
## One image per outfit, front and three-quarter, idle and mid-run, so fit problems show at a glance.

const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const OUTFITS := {
	"bare": [],
	"starter": ["blade_01", "scout_vest", "scout_boots"],
	"aegis_blade": ["aegis_helmet", "aegis_cuirass", "aegis_bracers", "aegis_tassets", "aegis_sabatons", "blade_05"],
	"mage_daggers": ["mage_hood", "mage_tunic", "mage_sleeves", "mage_robe", "mage_boots", "dagger_03"],
	"crane_spear": ["crane_wings", "crane_jacket", "crane_sleeves", "crane_skirt", "crane_boots", "spear_01"],
}


func _initialize() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 520)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 25.0, 0.0)
	viewport.add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.82, 0.84, 0.86)
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.2, 7.5)
	viewport.add_child(camera)
	var rng := RandomNumberGenerator.new()
	for outfit in OUTFITS:
		var models: Array = []
		var setups := [["idle", Vector2(0.0, 1.0)], ["idle", Vector2(0.7, 0.7)], ["run", Vector2(1.0, 0.0)], ["idle", Vector2(0.0, -1.0)]]
		for index in setups.size():
			var model := CharacterModel.new()
			viewport.add_child(model)
			model.load_model()
			model.position.x = -3.0 + 2.0 * index
			var loadout := Loadout.new(rules)
			for item_id in OUTFITS[outfit]:
				var base: Dictionary = rules.catalog.entry(item_id)
				loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
			model.dress(ItemAssets.looks(loadout, rules.catalog, loadout.weapon_style(["fists", "blade", "dagger", "spear", "hammer"])))
			var weapon := loadout.weapon_style(["fists", "blade", "dagger", "spear", "hammer"])
			model.set_pose(setups[index][0], 0.0, 1.0, true, setups[index][1], false, "", "", weapon)
			models.append(model)
		for frame in 30:
			for model in models:
				model.apply_pose(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out_dir.path_join(outfit + ".png"))
		for model in models:
			model.queue_free()
		await process_frame
	quit()
