extends SceneTree
## Renders the Studio Sword & Shield armor's shield piece ("| Shield" mesh of armor_sword_shield.glb) into a
## transparent 192 px inventory icon, framed and lit like the armor icons (tools/shots/native_armor_icons.gd).
## Run windowed (needs a real renderer):
##   godot --path . --script res://tools/shots/shield_icon.gd
## Then set it on the catalog with: python tools/items/publish_offhand_catalog.py
const SOURCE := "res://art/characters/studio05/v1111/outfits/armor_sword_shield.glb"
const OUT := "res://art/items/icons/offhand_round_shield.png"
const SIZE := 192
const PAD := 1.16  ## frame margin, same as the armor icons
const RENDER := 1024  ## rendered big and wide (the skinned pose is not the mesh AABB), then cropped to the shield


func meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	for child in node.get_children():
		meshes(child, result)


func _initialize() -> void:
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(RENDER, RENDER)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	world.environment = environment
	viewport.add_child(world)
	var asset: Node3D = load(SOURCE).instantiate()
	viewport.add_child(asset)
	var pieces: Array = []
	meshes(asset, pieces)
	var shield: MeshInstance3D = null
	for piece in pieces:
		if str(piece.name).ends_with("| Shield"):
			shield = piece
		else:
			piece.visible = false
	if shield == null:
		print("SHIELD ICON: no '| Shield' mesh in ", SOURCE)
		quit(1)
		return
	for frame in 2:
		await process_frame
	var bounds: AABB = pieces[0].global_transform * pieces[0].get_aabb()
	for piece in pieces:
		bounds = bounds.merge(piece.global_transform * piece.get_aabb())
	var centre := bounds.get_center()
	# The shield's face points along +X (it sits on the left forearm); look at it from the outside, a little
	# from the front so the rim reads, and light it from the upper front like the armor icons.
	var view_dir := Vector3(1.0, 0.0, 0.35).normalized()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.size = maxf(bounds.size.y, maxf(bounds.size.z, bounds.size.x)) * 1.6
	camera.position = centre + view_dir * 3.0
	camera.look_at(centre, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.5
	viewport.add_child(light)
	light.look_at_from_position(centre + Vector3(1.0, 0.6, 0.8), centre, Vector3.UP)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var used := image.get_used_rect()
	if used.size.x <= 0:
		print("SHIELD ICON: nothing rendered")
		quit(1)
		return
	var side := int(ceil(maxf(used.size.x, used.size.y) * PAD))
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.blit_rect(image, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	square.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	square.save_png(ProjectSettings.globalize_path(OUT))
	print("SHIELD ICON saved ", OUT)
	quit()
