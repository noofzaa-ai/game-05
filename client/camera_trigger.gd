extends Node
## Asks the camera rig for a special camera angle.
## ENTER_EXIT: active while the position passed to update() is inside `box` (call update every frame).
## MANUAL: ignores `box`; a script or event calls activate() / deactivate().
## max_duration > 0 ends the override automatically after that many seconds.
## Set the properties below before adding this node to the scene.

enum Mode { ENTER_EXIT, MANUAL }

var rig: Node
var preset: Dictionary
var box := AABB()
var mode := Mode.ENTER_EXIT
var lock_choice := false
var max_duration := 0.0

var _active := false
var _token := 0


func update(position: Vector3) -> void:
	if mode != Mode.ENTER_EXIT:
		return
	if box.has_point(position):
		activate()
	else:
		deactivate()


func activate() -> void:
	if _active:
		return
	_active = true
	_token += 1
	rig.request_override(self, preset, lock_choice)
	if max_duration > 0.0:
		var token := _token
		get_tree().create_timer(max_duration).timeout.connect(func() -> void:
			if _active and _token == token:
				deactivate()
		)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	rig.release_override(self)
