extends "res://server/shared/private_http.gd"
## Private names/profile authority; no database access.
const Rules := preload("res://server/names/name_rules.gd")
var _profiles := preload("res://server/profile/runner.gd").new()

func _configuration_ready() -> bool:
	return _profiles.ready()

func _routes() -> Array:
	return ["/validate-name", "/profile", "/recover", "/equipment-config"]

func _dispatch(path: String, data: Variant) -> Dictionary:
	if path == "/equipment-config": return {"v": 1, "ok": _profiles.ready(), "refine": _profiles.rules.refine, "upgrade": _profiles.rules.upgrade, "mobility": _profiles.rules.mobility, "armor": _profiles.rules.armor}
	if path == "/recover": return _profiles.recover(data)
	return Rules.validate(data) if path == "/validate-name" else _profiles.execute(data)
