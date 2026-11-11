extends SceneTree
## Runs every test file and exits non-zero if any check fails.
##   godot --headless --path <project folder> --script res://tests/run_all.gd
## EXTENDING: write tests/test_<name>.gd with `func run(ctx)`, call ctx.check("what", condition),
## then add the file to TEST_FILES.

const TEST_FILES := [
 "res://tests/test_map_data.gd",
 "res://tests/test_goblin_stages.gd",
 "res://tests/test_journey.gd",
 "res://tests/test_exit_portals.gd"
]

var passed := 0
var failed := 0


func check(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  PASS  " + name)
	else:
		failed += 1
		print("  FAIL  " + name)


func _initialize() -> void:
	await process_frame  # let the autoloads and the tree finish starting
	for path in TEST_FILES:
		print("--- ", path.get_file())
		var script = load(path)
		if script == null or not script.can_instantiate():
			check("%s loads (it has a script error; see the messages above)" % path.get_file(), false)
			continue
		var test = script.new()
		await test.run(self)
	print("passed=%d failed=%d" % [passed, failed])
	var audio := root.get_node_or_null("Audio")
	if audio != null:
		audio.release_all()  # (as closing the window does: no sounds left held at exit)
		await create_timer(0.3).timeout  # (the audio thread lets go of stopped playbacks a moment later)
	quit(1 if failed > 0 else 0)
