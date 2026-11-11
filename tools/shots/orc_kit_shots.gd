extends SceneTree
## Close looks at the orc-kit dressing of the goblin stages (Boss 2026-10-15), from the game camera (8: High):
## the player is put next to each kit piece / cover so it fills the view. Saves 1024-px PNGs to
## art_source/preview/orc_kit/ingame/ (or the folder given after --). Needs a window (no --headless):
##   godot --path . --script res://tools/shots/orc_kit_shots.gd [-- <out_dir> [<map_id> ...]]

const LOOKS := {
	"goblin_arena_a": [["k1_picket_fence", Vector3(-10.0, 0.05, -1.4)], ["k2_bone_fence", Vector3(8.6, 0.05, 9.6)],
		["k3_totem", Vector3(-7.0, 0.05, 1.6)], ["k4_west_huts", Vector3(-12.5, 0.05, 2.0)]],
	"goblin_arena_b": [["k1_shrine", Vector3(0.0, 0.05, -5.2)], ["k2_rootwell", Vector3(-2.6, 0.05, -1.4)],
		["k3_east_cage", Vector3(11.5, 0.05, -3.5)]],
	"goblin_arena_c": [["k1_ramp_gates", Vector3(0.0, 0.05, -9.8)], ["k2_blocks", Vector3(-6.0, 0.05, -1.0)],
		["k3_spoil_forge", Vector3(11.5, 0.05, 0.5)], ["k4_west_huts", Vector3(-11.0, 0.05, 8.0)]],
	"goblin_rest_camp": [["k1_huts", Vector3(4.0, 0.05, 1.6)], ["k2_forge", Vector3(-4.6, 0.05, 2.0)],
		["k3_bonfire", Vector3(0.0, 0.05, 2.6)]],
	"brush_ring": [["k1_throne", Vector3(0.0, 0.05, -4.0)], ["k2_west", Vector3(-10.0, 0.05, -2.0)],
		["k3_east_south", Vector3(10.0, 0.05, 7.0)], ["k4_start", Vector3(0.0, 0.05, 6.0)]],
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://art_source/preview/orc_kit/ingame")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	var ids: Array = args.slice(1) if args.size() > 1 else LOOKS.keys()
	for id in ids:
		game_state.start_stage(game_state.Mode.PVE, id)
		await _frames(4)
		var stage: Node = current_scene
		stage.set_physics_process(false)  # freeze: monsters stay on their spots
		await _frames(20)
		var player: Node3D = stage.get("_views")[1]
		for look in LOOKS[id]:
			player.global_position = look[1]
			await _frames(50)  # (the camera eases after its target)
			await _save(out, id + "_" + str(look[0]))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(1024, 576, Image.INTERPOLATE_LANCZOS)
	image.save_png(out.path_join(name + ".png"))
	print("saved ", name)
