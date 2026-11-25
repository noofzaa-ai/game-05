extends SceneTree
## Runs one test file: godot --headless --path . --script res://tools/ui/run_one_test.gd -- res://tests/test_x.gd
var fails := 0
func check(name: String, ok: bool) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", name)
func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	load(path).new().run(self)
	print("done, failures: ", fails)
	quit(1 if fails > 0 else 0)
