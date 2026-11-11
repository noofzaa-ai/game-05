extends SceneTree
## Renders a katana and a dagger swing (their trails from the weapon's own points) seen from the
## high game camera, with the HUD loot feed showing a few drops. Needs a window (no --headless):
##   godot --path . --script res://tools/shots/swing_shot.gd -- <out.png>

const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://swing.png"
	root.size = Vector2i(1280, 720)
	await process_frame
	var rules := ItemRulesLoader.load_default()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	root.add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.42, 0.36)
	environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0.0, 7.0, 7.0)
	camera.rotation_degrees.x = -45.0
	root.add_child(camera)
	var rng := RandomNumberGenerator.new()
	var models: Array = []
	var weapons := [["blade_05", "blade", -1.6], ["dagger_06", "dagger", 1.6]]
	for entry in weapons:
		var model := CharacterModel.new()
		root.add_child(model)
		model.load_model()
		model.position.x = entry[2]
		var loadout := Loadout.new(rules)
		loadout.equip(ItemSystem.create_item(rules, "w", "weapon", 0, rng, "", entry[0]))
		model.dress(ItemAssets.looks(loadout, rules.catalog, entry[1]))
		model.trail_color = Color(1.0, 0.75, 0.45) if entry[1] == "blade" else Color(0.6, 1.0, 0.6)
		models.append([model, entry[1]])
	var hud: CanvasLayer = load("res://client/hud.gd").new()
	root.add_child(hud)
	hud.add_loot("+ Golden Blossom Katana  Legendary", Color(1.0, 0.8, 0.2), ItemAssets.icon_for_id("blade_05", rules.catalog))
	hud.add_loot("+ Aegis Red-Crest Helm  Rare", Color(0.4, 0.65, 1.0), ItemAssets.icon_for_id("aegis_helmet", rules.catalog))
	hud.add_loot("+ 24 gold", Color(1.0, 0.85, 0.2))
	hud.add_loot("+ 2 Ore", Color(0.85, 0.85, 0.9))
	var frames := 0
	for phase in ["windup", "strike"]:
		for step in 10:
			for pair in models:
				pair[0].set_pose("heavy", float(step) / 10.0, 0.0, true, Vector2(0.0, 1.0), false, phase, "light_1", pair[1])
				pair[0].apply_pose(1.0 / 60.0)
			await process_frame
			frames += 1
			if phase == "strike" and step == 6:
				break
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
