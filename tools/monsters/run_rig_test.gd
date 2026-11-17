extends SceneTree
## Runs only tests/test_monster_rig.gd: godot --headless --path . --script res://tools/monsters/run_rig_test.gd
var passed := 0
var failed := 0
func check(name: String, condition: bool) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	print(("  PASS  " if condition else "  FAIL  ") + name)
func _init() -> void:
	load("res://tests/test_monster_rig.gd").new().run(self)
	print("passed ", passed, " failed ", failed)
	quit(1 if failed > 0 else 0)
