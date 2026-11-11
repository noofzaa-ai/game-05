extends SceneTree
## NOTE: proposal "after2" (B) is now IN the game (client/character_light.gd, 2026-10-08), so "before"
## already shows it and the other passes stack it twice. Kept as a template for the next lighting test.
## Before / after pictures of a proposed character lighting (nothing in the game changes): the same
## dressed chibis in the ink stage and the golden stage from the game's camera 8, in the inventory
## doll, and close up. Needs a window (no --headless):
##   godot --path . --script res://tools/shots/lighting_compare.gd -- <out_dir>
## Proposal: characters get their own soft key and rim light (lights that only touch layer 2, so the
## stage keeps its mood), a little less flat ambient, a stronger ink sun, and less
## specular on gear so armor stops showing white hot spots. (AgX tone mapping was tried: greyer, dropped.)

const Atmosphere := preload("res://client/atmosphere.gd")
const CharacterModel := preload("res://client/character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const CHARACTER_LAYER := 2
const OUTFITS := [
	["frostguard_cuirass", "frostguard_bracers", "frostguard_breeches", "frostguard_boots", "spear_01"],
	["shinigami_f_head", "shinigami_f_shirt", "shinigami_f_arms", "shinigami_f_pants", "shinigami_f_shoes", "dagger_03"],
	["crimson_skull_helmet", "crimson_skull_cuirass", "crimson_skull_bracers", "crimson_skull_pants", "crimson_skull_boots", "hammer_froststeel_01"],
	["golden_scroll_m_head", "golden_scroll_m_shirt", "golden_scroll_m_arms", "golden_scroll_m_pants", "golden_scroll_m_shoes", "blade_05"],
]

var _rules
var _soft_whites := false  ## "after2": also roll off the highlights so white hair and plates keep their shading
var _out := ""


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://shots"
	DirAccess.make_dir_recursive_absolute(_out)
	_rules = ItemRulesLoader.load_default()
	await process_frame  # (the tree must be running before cameras can look_at)
	for pass_index in 3:
		var proposal := pass_index > 0
		_soft_whites = pass_index == 2
		var tag: String = ["before", "after", "after2"][pass_index]
		await _stage_shot("ink", proposal, "battle_ink_" + tag)
		await _stage_shot("golden", proposal, "battle_golden_" + tag)
		await _doll_shot(proposal, "doll_" + tag)
		await _closeup_shot(proposal, "closeup_" + tag)
	quit()


func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _dressed(parent: Node, outfit: Array, ink: bool) -> Node3D:
	var model := CharacterModel.new()
	model.ink_outline = ink
	parent.add_child(model)
	model.load_model()
	var loadout := Loadout.new(_rules)
	var rng := RandomNumberGenerator.new()
	for item_id in outfit:
		var base: Dictionary = _rules.catalog.entry(item_id)
		loadout.equip(ItemSystem.create_item(_rules, item_id, base["slot"], 0, rng, "", item_id))
	var style := loadout.weapon_style(["fists", "blade", "dagger", "spear", "hammer"])
	model.dress(ItemAssets.looks(loadout, _rules.catalog, style))
	model.set_appearance(ItemAssets.appearance({}))  # the default looks (data/cosmetics)
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", style)
	return model


func _capture(viewport: SubViewport, models: Array, file: String) -> void:
	for frame in 40:
		for model in models:
			model.apply_pose(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(_out.path_join(file + ".png"))
	viewport.queue_free()
	await process_frame


## The proposal, applied to one scene: character-only lights, the environment and gear materials.
func _propose(scene: Node, environment: Environment, models: Array, key_energy: float, rim_energy: float) -> void:
	environment.ambient_light_energy *= 0.85
	if _soft_whites:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_white = 3.0
	var key := DirectionalLight3D.new()  # soft light from the camera side: shapes faces and armor
	key.rotation_degrees = Vector3(-38.0, 20.0, 0.0)
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = key_energy
	key.light_cull_mask = 1 << (CHARACTER_LAYER - 1)
	key.light_specular = 0.2
	scene.add_child(key)
	var rim := DirectionalLight3D.new()  # from behind and above: a bright edge that lifts them off the ground
	rim.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim.light_color = Color(0.85, 0.92, 1.0)
	rim.light_energy = rim_energy
	rim.light_cull_mask = 1 << (CHARACTER_LAYER - 1)
	rim.light_specular = 0.6
	scene.add_child(rim)
	for model in models:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.layers |= 1 << (CHARACTER_LAYER - 1)
			for surface in mesh.get_surface_override_material_count():
				var material = mesh.get_active_material(surface)
				if material is BaseMaterial3D:
					var softer: BaseMaterial3D = material.duplicate()
					softer.metallic_specular = minf(softer.metallic_specular, 0.25)
					softer.roughness = maxf(softer.roughness, 0.55)
					mesh.set_surface_override_material(surface, softer)


func _stage_shot(style: String, proposal: bool, file: String) -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var atmosphere := Atmosphere.new()
	atmosphere.style = style
	viewport.add_child(atmosphere)
	var models: Array = []
	for index in OUTFITS.size():
		var model := _dressed(viewport, OUTFITS[index], style == "ink")
		model.position = Vector3(-2.4 + 1.6 * index, 0.0, 0.0)
		models.append(model)
	var camera := Camera3D.new()  # the game's camera 8 ("High")
	camera.fov = 55.0
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 7.0, 7.0)
	camera.look_at(Vector3(0.0, 0.5, 0.0))
	await process_frame
	if proposal:
		var world: WorldEnvironment = atmosphere.find_children("*", "WorldEnvironment", true, false)[0]
		var sun: DirectionalLight3D = atmosphere.find_children("*", "DirectionalLight3D", true, false)[0]
		if style == "ink":
			sun.light_energy = 0.8
			world.environment.adjustment_saturation = 1.0
		_propose(viewport, world.environment, models, 0.7, 1.1)
	await _capture(viewport, models, file)


func _doll_shot(proposal: bool, file: String) -> void:
	var viewport := _viewport(Vector2i(420, 560))
	var environment := Environment.new()  # as client/paper_doll.gd
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.14, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.74, 0.68)
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.95, 0.86)
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 26.0
	camera.position = Vector3(0.0, 1.05, 4.6)
	camera.rotation_degrees.x = -4.0
	viewport.add_child(camera)
	var model := _dressed(viewport, OUTFITS[0], true)
	if proposal:
		_propose(viewport, environment, [model], 0.25, 1.0)
	await _capture(viewport, [model], file)


func _closeup_shot(proposal: bool, file: String) -> void:
	var viewport := _viewport(Vector2i(1280, 640))
	var atmosphere := Atmosphere.new()
	atmosphere.style = "ink"
	viewport.add_child(atmosphere)
	var models: Array = []
	for index in OUTFITS.size():
		var model := _dressed(viewport, OUTFITS[index], true)
		model.position = Vector3(-2.4 + 1.6 * index, 0.0, 0.0)
		models.append(model)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.6, 8.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.9, 0.0))
	await process_frame
	if proposal:
		var world: WorldEnvironment = atmosphere.find_children("*", "WorldEnvironment", true, false)[0]
		var sun: DirectionalLight3D = atmosphere.find_children("*", "DirectionalLight3D", true, false)[0]
		sun.light_energy = 0.8
		world.environment.adjustment_saturation = 1.0
		_propose(viewport, world.environment, models, 0.7, 1.1)
	await _capture(viewport, models, file)
