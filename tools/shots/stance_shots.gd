extends SceneTree
## Renders the chibi's stances per weapon to PNGs (needs a window: run WITHOUT --headless):
##   godot --path . --script res://tools/shots/stance_shots.gd -- <out_dir>
## One image per state (idle at two breaths, guard held, mid-dodge), one fighter per weapon, each in
## one of the model team's newer outfits so their fit shows too.

const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const STYLES := ["fists", "blade", "dagger", "spear", "hammer"]
const FIGHTERS := [
	["crimson_skull_helmet", "crimson_skull_cuirass", "crimson_skull_bracers", "crimson_skull_pants", "crimson_skull_boots"],
	["shinigami_m_head", "shinigami_m_shirt", "shinigami_m_arms", "shinigami_m_pants", "shinigami_m_shoes", "blade_01"],
	["shinigami_f_head", "shinigami_f_shirt", "shinigami_f_arms", "shinigami_f_pants", "shinigami_f_shoes", "dagger_01"],
	["frostguard_cuirass", "frostguard_bracers", "frostguard_breeches", "frostguard_boots", "spear_01"],
	["golden_scroll_m_head", "golden_scroll_m_shirt", "golden_scroll_m_arms", "golden_scroll_m_pants", "golden_scroll_m_shoes", "hammer_01"],
]
## [file name, pose kind, amount, seconds of idle clock before the shot]
const SHOTS := [["idle_inhale", "idle", 0.0, 0.75], ["idle_exhale", "idle", 0.0, 2.25], ["guard", "guard", 2.0, 0.0], ["dodge", "slide", 0.5, 0.0]]


func _initialize() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1500, 560)
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
	camera.position = Vector3(0.0, 1.2, 8.5)
	viewport.add_child(camera)
	var rng := RandomNumberGenerator.new()
	for shot in SHOTS:
		var models: Array = []
		for index in FIGHTERS.size():
			var model := CharacterModel.new()
			viewport.add_child(model)
			model.load_model()
			model.position.x = -4.4 + 2.2 * index
			var loadout := Loadout.new(rules)
			for item_id in FIGHTERS[index]:
				var base: Dictionary = rules.catalog.entry(item_id)
				loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
			var style := loadout.weapon_style(STYLES)
			model.dress(ItemAssets.looks(loadout, rules.catalog, style))
			model.set_pose(shot[1], shot[2], 0.0, true, Vector2(0.6, 0.8), false, "", "", style)
			models.append(model)
		var ticks := maxi(30, int(float(shot[3]) * 60.0))
		for frame in ticks:
			for model in models:
				model.apply_pose(1.0 / 60.0)
			if frame % 10 == 0:
				await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out_dir.path_join(shot[0] + ".png"))
		for model in models:
			model.queue_free()
		await process_frame
	quit()
