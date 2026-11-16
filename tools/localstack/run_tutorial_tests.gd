extends SceneTree
var passed := 0
var failed := 0
func check(name: String, condition: bool) -> void:
	if condition: passed += 1
	else:
		failed += 1
		print("  FAIL  " + name)
func _initialize() -> void:
	await process_frame
	for path in ["res://tests/test_tutorial_unlocks.gd", "res://tests/test_tutorial_ui.gd", "res://tests/test_event_stream.gd", "res://tests/test_world_zones.gd", "res://tests/test_localstack_fixtures.gd"]:
		var t = load(path).new()
		await t.run(self)
	print("passed=%d failed=%d" % [passed, failed])
	quit(1 if failed else 0)
