extends RefCounted
## Tests the camera rig and camera triggers: PvE special cameras, PvP off, locking, timers.

const CameraRig := preload("res://client/camera_rig.gd")
const CameraTrigger := preload("res://client/camera_trigger.gd")

const PRESET := {"name": "X", "offset": Vector3(1, 1, 1), "look_y": 1.0, "fov": 40.0}


func run(ctx) -> void:
	var player := Node3D.new()
	ctx.root.add_child(player)
	var rig := CameraRig.new()
	rig.target = player
	ctx.root.add_child(rig)

	var manual := CameraTrigger.new()
	manual.rig = rig
	manual.preset = PRESET
	manual.mode = CameraTrigger.Mode.MANUAL
	manual.lock_choice = true
	ctx.root.add_child(manual)

	ctx.check("starts with no override", not rig.has_override())
	manual.activate()
	ctx.check("PvE: activate gives an override", rig.has_override())
	ctx.check("lock flag is set", rig.is_choice_locked())
	rig.choose(CameraRig.PRESETS[KEY_6])
	ctx.check("player's choice is ignored while locked", rig.chosen["name"] == "8: High")
	manual.deactivate()
	ctx.check("deactivate clears the override", not rig.has_override())
	rig.choose(CameraRig.PRESETS[KEY_6])
	ctx.check("player's choice works when unlocked", rig.chosen["name"] == "6: Side")

	rig.special_enabled = false
	manual.activate()
	ctx.check("PvP: activate does nothing", not rig.has_override())
	manual.deactivate()

	rig.special_enabled = true
	manual.activate()
	ctx.check("back to PvE: works again", rig.has_override())
	rig.special_enabled = false
	ctx.check("switching to PvP drops an active override", not rig.has_override())
	rig.special_enabled = true
	manual.deactivate()

	manual.max_duration = 0.2
	manual.activate()
	ctx.check("timed override is active", rig.has_override())
	await ctx.create_timer(0.5).timeout
	ctx.check("timed override ends by itself", not rig.has_override())

	var zone := CameraTrigger.new()
	zone.rig = rig
	zone.preset = PRESET
	zone.box = AABB(Vector3(10, 0, -3), Vector3(6, 5, 6))
	ctx.root.add_child(zone)
	zone.update(Vector3(0, 0, 0))
	ctx.check("outside the zone: no override", not rig.has_override())
	zone.update(Vector3(12, 1.8, 0))
	ctx.check("inside the zone: override", rig.has_override())
	zone.update(Vector3(0, 0, 0))
	ctx.check("leaving the zone clears the override", not rig.has_override())

	var second := CameraTrigger.new()
	second.rig = rig
	second.preset = {"name": "Y", "offset": Vector3.ZERO, "look_y": 1.0, "fov": 50.0}
	second.mode = CameraTrigger.Mode.MANUAL
	ctx.root.add_child(second)
	zone.update(Vector3(12, 1.8, 0))
	second.activate()
	ctx.check("most recent override wins", rig.override_name() == "Y")
	second.deactivate()
	ctx.check("releasing it falls back to the previous override", rig.override_name() == "X")
	zone.update(Vector3(0, 0, 0))

	# Screen shake and zoom punch: they start strong and fade to nothing on their own.
	rig.shake(0.2, 0.2)
	rig._process(0.016)
	var shaking: bool = absf(rig._camera.h_offset) <= 0.2 and rig._shake_left > 0.0
	ctx.check("a shake moves the camera within its strength", shaking)
	rig._process(0.5)
	ctx.check("and the shake fades out completely", rig._camera.h_offset == 0.0 and rig._camera.v_offset == 0.0)
	rig.punch(5.0)
	rig._process(0.016)
	ctx.check("a zoom punch narrows the field of view", rig._camera.fov < rig._fov)
	rig._process(0.5)
	ctx.check("and eases back out", absf(rig._camera.fov - rig._fov) < 0.001)

	for node in [player, rig, manual, zone, second]:
		node.queue_free()

	# A wide arena: the camera follows the player in depth too.
	var arena_player := Node3D.new()
	ctx.root.add_child(arena_player)
	var arena_rig := CameraRig.new()
	arena_rig.target = arena_player
	arena_rig.follow_depth = true
	arena_rig.min_z = -10.0
	arena_rig.max_z = 10.0
	ctx.root.add_child(arena_rig)
	arena_player.position = Vector3(2.0, 0.0, 6.0)
	for i in 120:
		arena_rig._process(1.0 / 60.0)
	var arena_offset: Vector3 = arena_rig._offset
	ctx.check("in a wide arena the camera follows the player's depth (z %.1f)" % arena_rig._camera.position.z, absf(arena_rig._camera.position.z - (6.0 + arena_offset.z)) < 0.2)
	arena_player.position = Vector3(2.0, 0.0, 40.0)
	for i in 120:
		arena_rig._process(1.0 / 60.0)
	ctx.check("and stops at the arena's edge", absf(arena_rig._camera.position.z - (10.0 + arena_offset.z)) < 0.2)
	ctx.check("a lane stage keeps the camera on its lane", absf(rig._camera.position.z - rig._offset.z) < 0.01)
	ctx.check("the top-down preset looks steeply down", CameraRig.PRESETS[KEY_9]["offset"].y > CameraRig.PRESETS[KEY_9]["offset"].z * 1.5)
