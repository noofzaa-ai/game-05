extends SceneTree
## Renders the chibi's head and body close up with several looks (skin, hair color, face item) to check
## that faces sit on the head and colors read well. Needs a window (no --headless):
##   godot --path . --script res://tools/shots/appearance_shot.gd -- <out.png>

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")

const LOOKS := [
	{},
	{"skin": Color("#e8c4a6"), "hair": Color("#3b2a20"), "hair_natural": true, "face": "res://art/items/faces/face_smile_01.glb", "hair_style": "res://art/items/hair/hair_ref10_10.glb"},
	{"skin": Color("#b98260"), "hair": Color("#8c3b22"), "face": "res://art/items/faces/face_devious_01.glb", "hair_style": "res://art/items/hair/hair_row4_spiky_black_01.glb"},
	{"skin": Color("#f3dccb"), "hair": Color("#d9b56a"), "face": "res://art/items/faces/face_soft_smile_01.glb", "hair_style": "res://art/items/hair/hair_row2_long_center_01.glb"},
	{"skin": Color("#6e4630"), "hair": Color("#2e4a7d"), "face": "res://art/items/faces/face_vampire_01.glb", "hair_style": "res://art/items/hair/hair_row4_cat_ears_01.glb"},
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://appearance.png"
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 640)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
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
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.25, 1.0)
	var models: Array = []
	for index in LOOKS.size():
		var model := CharacterModel.new()
		model.ink_outline = true
		viewport.add_child(model)
		model.load_model()
		model.set_appearance(LOOKS[index])
		model.position = Vector3(-2.4 + 1.2 * index, 0.0, 0.0)
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false)
		models.append(model)
	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 1.2, 5.0)
	camera.look_at(Vector3(0.0, 0.85, 0.0))
	for frame in 40:
		for model in models:
			model.apply_pose(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out)
	quit()
