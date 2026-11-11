extends RefCounted
## Runs unchanged game name rules inside the server's Godot process.
## The Nakama bridge validates authentication and owns the uniqueness transaction.
const Profile := preload("res://logic/profile.gd")
const VERSION := 1


static func validate(request: Variant) -> Dictionary:
	if not (request is Dictionary) or request.size() != 2 or not (request.get("v") is int or request.get("v") is float) or request.get("v") != VERSION or not request.has("name") or not (request.name is String):
		return {"v": VERSION, "ok": false, "error": "invalid_payload"}
	var problem := Profile.name_problem(request.name)
	if not problem.is_empty():
		return {"v": VERSION, "ok": false, "error": problem}
	return {"v": VERSION, "ok": true, "name": request.name.strip_edges(), "canonical": request.name.strip_edges().to_lower()}
