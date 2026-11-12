extends SceneTree
## Texture budget check (tech-artist, 2026-11-12): renders each class close up with the imported (web-size)
## class gear / Hair G textures, then with the full-size source JPGs swapped in, same pose, and saves both.
## Run windowed: godot --path . --script res://tools/shots/texture_size_compare.gd -- <out_dir>
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ProjectSettings.globalize_path("res://build/texcheck")
	DirAccess.make_dir_recursive_absolute(out)
	var size := Vector2i(900, 900)
	DisplayServer.window_set_size(size)
	root.size = size
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	root.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	for cls in ["sword_shield", "greatsword", "longbow", "magic"]:
		for hair in ["a", "g"]:
			var m := CharacterModel.new()
			root.add_child(m)
			m.class_id = cls
			m.load_model()
			var look := {"class": cls, "hair": hair, "silver": false, "eye_color": "", "skin": "", "makeup": "none"}
			m.dress({"class": cls, "appearance": ItemAssets.card_appearance(look, ItemAssets.appearance({})), "weapon": {"path": "", "family": "", "style": ""}})
			m.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", "")
			m.apply_pose(0.0)
			cam.position = Vector3(0, 0.95, 1.55)
			cam.look_at(Vector3(0, 0.82, 0))
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_%s_web.png" % [cls, hair]))
			var swapped := 0
			for mat in _materials(m):
				for param in ["albedo_tex", "normal_tex"]:
					var tex = mat.get_shader_parameter(param)
					if tex is Texture2D and tex.resource_path.contains("/v1111/"):
						var img := Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
						if img != null:
							img.generate_mipmaps()
							mat.set_shader_parameter(param, ImageTexture.create_from_image(img))
							swapped += 1
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_%s_full.png" % [cls, hair]))
			print("TEXCHECK ", cls, " hair ", hair, " swapped ", swapped)
			m.queue_free()
			await process_frame
	quit()

func _materials(node: Node) -> Array:
	var out := []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var mat = mi.get_surface_override_material(s)
			if mat == null: mat = mi.mesh.surface_get_material(s)
			if mat is ShaderMaterial and not out.has(mat): out.append(mat)
		if mi.material_override is ShaderMaterial and not out.has(mi.material_override): out.append(mi.material_override)
	return out
