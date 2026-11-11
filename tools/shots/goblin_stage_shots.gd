extends SceneTree
## Pictures of the goblin-forest stages (data/maps/goblin_*.json + art/maps/goblin_forest/*.glb) as the game
## shows them: the real stage scene, the default camera (8: High), desktop 1600x900. The rules are frozen a few
## frames in, so the monsters stay on their spawn spots. For each map:
##   <id>_1_start      the player on the spawn, as the stage opens
##   <id>_2_north      the player walked up to the middle-north: the exit-portal side (portal spots marked
##                     with thin cyan posts, only in these pictures)
##   <id>_3_overview   straight-ish from high above (layout check, not a game view)
##   <id>_4_south_west the darkest corner: does the floor still read?
##   <id>_5_east       the far east edge (2026-10-14: the arenas grew, so the new far corners get a look)
##   <id>_6_*          one close look at the map's landmark
## Saves to art_source/preview/goblin_stages/ (or the folder given after --). Needs a window (no --headless):
##   godot --path . --script res://tools/shots/goblin_stage_shots.gd [-- <out_dir> [<map_id> ...]]

const MAPS := ["goblin_arena_a", "goblin_arena_b", "goblin_arena_c", "goblin_rest_camp"]
## A closer look at what makes each map memorable (map id -> where the player stands).
const LANDMARK := {
	"goblin_arena_a": ["6_watchtower", Vector3(11.5, 0.05, -6.5)],
	"goblin_arena_b": ["6_rootwell", Vector3(-2.6, 0.05, -1.8)],
	"goblin_arena_c": ["6_winch", Vector3(0.0, 0.05, -5.6)],
}
const MapLoader := preload("res://logic/map_loader.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://art_source/preview/goblin_stages")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var ids: Array = args.slice(1) if args.size() > 1 else MAPS
	for id in ids:
		var map = MapLoader.load_by_id(id)
		game_state.start_stage(game_state.Mode.PVE, id)
		await _frames(4)
		var stage: Node = current_scene
		stage.set_physics_process(false)  # freeze: monsters stay on their spots
		await _frames(30)
		await _save(out, id + "_1_start")
		var views: Dictionary = stage.get("_views")
		var player: Node3D = views[1]
		var markers := _portal_markers(stage, map)
		player.global_position = Vector3(0.0, 0.05, -map.half_depth * 0.35)
		await _frames(50)  # (the camera eases after its target)
		await _save(out, id + "_2_north")
		player.global_position = Vector3(-map.half_width + 1.0, 0.05, map.half_depth - 0.8)
		await _frames(50)
		await _save(out, id + "_4_south_west")  # the darkest corner before r2: does the floor still read?
		player.global_position = Vector3(map.half_width - 1.0, 0.05, 0.0)
		await _frames(50)
		await _save(out, id + "_5_east")
		if LANDMARK.has(id):
			var look: Array = LANDMARK[id]
			player.global_position = look[1]
			await _frames(50)
			await _save(out, id + "_" + str(look[0]))
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.fov = 50.0
		var high := maxf(map.half_width, map.half_depth) * 2.9
		camera.look_at_from_position(Vector3(0.0, high, high * 0.52), Vector3(0.0, 0.0, -2.0))
		camera.current = true
		await _frames(5)
		await _save(out, id + "_3_overview")
		for marker in markers:
			marker.queue_free()
	quit()


func _portal_markers(stage: Node, map) -> Array:
	var markers := []
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3, 1.0, 1.0)
	for spot in map.exit_portals:
		var post := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.06
		mesh.height = 2.4
		mesh.material = material
		post.mesh = mesh
		post.position = spot + Vector3(0, 1.2, 0)
		stage.add_child(post)
		markers.append(post)
	return markers


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var image := root.get_texture().get_image()
	if image.get_width() > 1024:  # (review copies: small enough to open in the agents' image viewer)
		image.resize(1024, int(image.get_height() * 1024.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
	image.save_png(out.path_join(name + ".png"))
	print("saved %s %dx%d draw_calls=%d primitives=%d" % [name, image.get_width(), image.get_height(), calls, primitives])
