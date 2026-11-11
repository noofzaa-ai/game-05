extends SceneTree
## Separate executable, deliberately outside run_all; compare its stdout across platforms.
func _initialize() -> void:
	for boss in [false, true]:
		var hashes = load("res://tests/test_determinism.gd").trace(boss)
		for i in hashes.size():
			print("NETCODE_HASH %s %d %s" % ["boss" if boss else "normal", (i + 1) * 60, hashes[i]])
	for count in [2,4]:
		var hashes = load("res://tests/test_determinism.gd").trace_party(count)
		for i in hashes.size():
			print("NETCODE_HASH party%d %d %s" % [count,(i+1)*60,hashes[i]])
	quit()
