extends Node
## Server-timed boss presentation; local ultimate always has priority.
var rig
var active := false
var _return_target: Node3D
func update(session, views: Dictionary, own_ultimate: bool) -> void:
	var intro: Dictionary = session.boss_presentation()
	var tick := int(session.server_state.get("tick", 0))
	var boss := int(intro.get("boss", -1))
	var show := not own_ultimate and int(intro.get("epoch", -1)) == int(session.server_state.get("epoch", -2)) and tick >= int(intro.get("tick", 0)) and tick < int(intro.get("tick", 0)) + int(intro.get("duration", 0)) and views.has(boss)
	if show:
		if not active: _return_target = rig.target
		rig.request_override(self, {"offset": Vector3(0, 3, 7), "look_y": 1.1, "fov": 45.0}, false)
		rig.target = views[boss]
	elif active:
		rig.release_override(self)
		if is_instance_valid(_return_target): rig.target = _return_target
		_return_target = null
	active = show

func _exit_tree() -> void:
	if rig != null and is_instance_valid(rig):
		rig.release_override(self)
		if active and is_instance_valid(_return_target): rig.target = _return_target
