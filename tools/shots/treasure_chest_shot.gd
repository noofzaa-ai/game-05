extends SceneTree
## Pictures of the treasure chest (art/props/treasure_chest/treasure_chest.glb): closed (left) and open (right,
## lid rotation.x = -105 deg about its hinge) on a dark forest floor under a night light, with a small cyan
## marker on `loot_point`.
##   chest_1_game    seen from about the game camera's height and angle
##   chest_2_close   a close three-quarter view
## Needs a window (no --headless):
##   godot --path . --script res://tools/shots/treasure_chest_shot.gd [-- <out_dir>]

const StageProps := preload("res://client/stage_props.gd")
const CHEST := "res://art/props/treasure_chest/treasure_chest.glb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://art_source/preview/goblin_stages/r2")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.80)
	env.ambient_light_energy = 1.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.70, 0.78, 1.0)
	moon.light_energy = 1.15
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.28, 0.19)
	plane.material = gm
	ground.mesh = plane
	world.add_child(ground)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(0.3, 1.0, 1.0)
	for i in 2:
		var chest := (load(CHEST) as PackedScene).instantiate() as Node3D
		StageProps.use_vertex_colors(chest)
		chest.position = Vector3(-0.85 if i == 0 else 0.85, 0, 0)
		world.add_child(chest)
		var lid := chest.find_child("lid", true, false) as Node3D
		var loot := chest.find_child("loot_point", true, false) as Node3D
		print("chest %d: lid at %s (hinge), loot_point at %s" % [i, lid.position, loot.position])
		if i == 1:
			lid.rotation.x = -deg_to_rad(105.0)
			var glow := OmniLight3D.new()  # (what the game might add: warm light from the gold)
			glow.light_color = Color(1.0, 0.75, 0.35)
			glow.light_energy = 1.2
			glow.omni_range = 2.5
			glow.position = Vector3(0, 0.6, 0)
			chest.add_child(glow)
			var dot := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.035
			sphere.height = 0.07
			sphere.material = marker_mat
			dot.mesh = sphere
			loot.add_child(dot)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 40.0
	camera.current = true
	camera.look_at_from_position(Vector3(0, 4.6, 4.0), Vector3(0, 0.35, 0))
	await _frames(8)
	await _save(out, "chest_1_game")
	camera.look_at_from_position(Vector3(1.6, 1.5, 2.6), Vector3(0.1, 0.4, 0))
	await _frames(4)
	await _save(out, "chest_2_close")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	print("saved %s" % name)
