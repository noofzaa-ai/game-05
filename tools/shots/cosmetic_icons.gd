extends SceneTree
## Renders the pictures of the Look tab's model choices that have none of their own (or only a grey
## one): every hair style (in its own colors, on the default face and skin) and any whole replacement
## head offered as a face, into
## art/cosmetics/icons/<part>_<id>.png. Run again after adding hair styles (needs a window, no --headless):
##   godot --path . --script res://tools/shots/cosmetic_icons.gd
## then `godot --headless --path . --import`.

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const ItemAssets := preload("res://client/item_assets.gd")

const OUT := "res://art/cosmetics/icons/"
const SIZE := 160


func _initialize() -> void:
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.29, 0.33, 0.36)  # as the model team's face previews
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.74, 0.68)
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	light.light_energy = 1.1
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.25, 1.0)
	var model := CharacterModel.new()
	model.ink_outline = true
	viewport.add_child(model)
	model.load_model()
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false)
	var camera := Camera3D.new()
	camera.fov = 19.0
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 1.7, 2.2)
	camera.look_at(Vector3(0.0, 1.46, 0.0))
	var options = ItemAssets.cosmetics()
	var jobs: Array = []
	for face in options.choices["face"]:
		if ItemAssets.entry(face["asset_id"]).get("replaces_head", false):
			var head := ItemAssets.appearance({"face": face["id"]})
			jobs.append(["face", face["id"], head])
	for style in options.choices["hair_style"]:
		jobs.append(["hair_style", style["id"], {"hair_style": ItemAssets.path(style["asset_id"])}])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for job in jobs:
		var looks := ItemAssets.appearance({})
		looks.merge(job[2], true)
		model.set_appearance(looks)
		for frame in 6:
			model.apply_pose(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "%s_%s.png" % [job[0], job[1]]))
	print("icons: %d" % jobs.size())
	quit()
