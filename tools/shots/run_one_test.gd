extends "res://tests/run_all.gd"
## Runs one test file: godot --headless --path . --script res://tools/shots/run_one_test.gd -- res://tests/test_x.gd
func _initialize() -> void:
	await process_frame
	var path: String = OS.get_cmdline_user_args()[0]
	var test = load(path).new()
	await test.run(self)
	print("passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
