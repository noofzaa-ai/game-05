extends SceneTree
## Pictures of the walkable camp hub (client/hub.gd) from the game camera: the overview at the spawn,
## near the warp gate, next to an NPC with the talk prompt, an NPC's "coming soon" line, and the menu,
## on a desktop window (1600x900) and a phone in landscape (932x430). Needs a window (no --headless):
##   godot --path . --script res://tools/shots/hub_camp_shot.gd -- <out_dir>

const SIZES := {"desktop": Vector2i(1600, 900), "phone": Vector2i(932, 430)}


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://hub_camp"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var game_state: Node = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.profile.created = true  # (skip the character creator)
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	hub.density_override = 1.0
	root.add_child(hub)
	await _settle(10)
	var world = hub.world
	var gate: Vector3 = world.spot("warp_gate")
	var smith: Vector3 = hub.npc("blacksmith").position
	var merchant: Vector3 = hub.npc("merchant").position
	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _settle(5)
		hub._fit_menu()
		await _shot(hub, out, "overview", size_name, world.spot("spawn"), Vector2(0.0, -1.0))
		await _shot(hub, out, "gate", size_name, gate + Vector3(0.0, 0.0, 2.4), Vector2(0.0, -1.0))
		await _shot(hub, out, "npc_prompt", size_name, smith + Vector3(-1.5, 0.0, 1.4), Vector2(0.8, -0.6))
		hub.place_player(merchant + Vector3(-0.4, 0.0, 1.5))
		await _settle(5)
		hub.interact()
		await _shot(hub, out, "npc_soon", size_name, merchant + Vector3(-0.4, 0.0, 1.5), Vector2(0.2, -1.0), false)
		await _shot(hub, out, "west", size_name, Vector3(-6.0, 0.0, 1.0), Vector2(-1.0, 0.0))
		await _shot(hub, out, "south", size_name, Vector3(1.0, 0.0, 8.0), Vector2(0.0, 1.0))
		hub.open_menu()
		await _save(out.path_join("menu_%s.png" % size_name))
		hub.close_menu()
	print("draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"  objects ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"  primitives ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	quit()


## Puts the player at `at` facing `facing` (by walking a tick that way), lets the camera settle, saves.
func _shot(hub: Node, out: String, name: String, size_name: String, at: Vector3, facing: Vector2, place := true) -> void:
	if place:
		hub.place_player(at)
		hub._facing = facing.normalized()
		hub._rig._x = clampf(at.x, hub._rig.min_x, hub._rig.max_x)
		hub._rig._z = clampf(at.z, hub._rig.min_z, hub._rig.max_z)
	await _settle(40)
	await _save(out.path_join("%s_%s.png" % [name, size_name]))
	print("draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " (", name, " ", size_name, ")")


func _settle(frames: int) -> void:
	for frame in frames:
		await process_frame


func _save(file: String) -> void:
	await _settle(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
