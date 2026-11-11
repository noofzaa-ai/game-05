extends SceneTree
## Where the time goes when a stage opens: the main resource loads timed one by one (cold, first in this
## process), then the frame times of the first frames after the scene change (the build frame and the
## frames that compile shaders on first draw). The web build has no shader cache between sessions; to get
## the same here, run it with the user shader_cache folder moved aside. Needs a window (no --headless):
##   godot --path . --script res://tools/perf/stage_entry_profile.gd [-- [--no-loads] [--twice] [map_id]]
## --twice opens the stage a second time in the same process: what is left then is not first-use compiling.
const Options := preload("res://client/graphics_options.gd")
const LOADS := ["res://art/characters/studio05/our_character_lowpoly_toon_hair_a_5k.glb", "res://art/monsters/goblin/goblin.glb",
	"res://art/animations/goblin.glb", "res://art/monsters/goblin_knight/goblin_knight.glb",
	"res://art/animations/goblin_knight.glb", "res://art/monsters/goblin_archer/goblin_archer.glb",
	"res://art/animations/goblin_archer.glb", "res://art/maps/goblin_base/goblin_base_quarry.tscn"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := "goblin_base_quarry"
	for a in args:
		if not a.begins_with("--"): id = a
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 912))
	root.size = Vector2i(1920, 912)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	if not "--no-loads" in args:
		for path in LOADS:
			var t := Time.get_ticks_usec()
			var res = load(path)
			print("load %-62s %7.1f ms" % [path, (Time.get_ticks_usec() - t) / 1000.0])
	var entries := 2 if "--twice" in args else 1
	for entry in entries:
		await _enter(game_state, id)
	quit()


## Opens the stage and prints the frame times of its first 90 frames.
func _enter(game_state, id: String) -> void:
	var t0 := Time.get_ticks_usec()
	game_state.start_stage(game_state.Mode.PVE, id)
	var last := t0
	var total_slow := 0.0
	for i in 90:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		if ms > 30.0 or i < 6:
			print("frame %2d %8.1f ms" % [i, ms])
		if ms > 50.0: total_slow += ms
		last = now
	print("entry %s: %.0f ms to frame 90, %.0f ms in frames over 50 ms" % [id, (last - t0) / 1000.0, total_slow])
