extends RefCounted
## Guards the layering rule: logic/ must not depend on rendering, input devices, scene nodes or client/.
## If this fails, someone let the game rules and the game client get tangled together.

const FORBIDDEN_WORDS := [
	"Node", "Node2D", "Node3D", "Control", "Camera3D", "CanvasLayer", "MeshInstance3D",
	"WebSocketPeer", "MultiplayerPeer", "Nakama", "Input", "InputMap", "InputEvent", "DisplayServer", "SceneTree", "get_tree", "GameState",
]


func run(ctx) -> void:
	var regex := RegEx.new()
	regex.compile("\\b(" + "|".join(FORBIDDEN_WORDS) + ")\\b")

	var files := DirAccess.get_files_at("res://logic")
	ctx.check("logic/ has script files", files.size() > 0)

	for file_name in files:
		if not file_name.ends_with(".gd"):
			continue
		var violations: Array[String] = []
		for raw_line in FileAccess.get_file_as_string("res://logic/" + file_name).split("\n"):
			var line: String = raw_line.split("#")[0]
			if "res://client" in line:
				violations.append("references res://client")
			var found := regex.search(line)
			if found != null:
				violations.append("uses " + found.get_string())
		ctx.check("logic/%s has no client/rendering dependencies %s" % [file_name, violations], violations.is_empty())
