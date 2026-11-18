extends SceneTree
var fails := 0
func check(name: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  "), name)
	if not ok: fails += 1
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		print("== ", path)
		load(path).new().run(self)
	print("FAILS ", fails)
	quit(1 if fails else 0)
