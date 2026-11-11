extends SceneTree
const Brain := preload("res://logic/companions/brain.gd")
const Dialogue := preload("res://server/companions/dialogue.gd")
const Fighter := preload("res://logic/fighter.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var manager = preload("res://server/rooms/manager.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	var profile = preload("res://logic/profile.gd").new_player(manager.rules, manager.camp, rng)
	var result: Dictionary = manager.create("companion-foundation", 81, [{"id":1,"profile":profile.to_dict()},{"id":2,"profile":profile.to_dict()}], false, 2)
	assert(result.ok, str(result))
	var room = manager.rooms["companion-foundation"].room
	var brain := Brain.new()
	var sim = room.sim
	for id in sim.fighters.keys():
		if id > 4: sim.remove_player(id)
	var before: String = JSON.stringify(profile.to_dict())
	sim.bodies[1].position = Vector3.ZERO
	sim.bodies[2].position = Vector3(4.5, 0, 0)
	sim.bodies[2].grounded = true
	sim.world.solids.clear()
	sim.world.add_solid(AABB(Vector3(-30,-1,-30),Vector3(60,1,60)))
	var frame = brain.think(sim, 2)
	assert(frame.move.x < 0 and not frame.light and frame.skill_slot == -1)
	sim.fighters[1].state = Fighter.State.DOWNED
	sim.bodies[2].position = Vector3(0.1, 0, 0)
	frame = brain.think(sim, 2)
	assert(brain.decision == "revive" and frame.move == Vector2.ZERO and not frame.light and not frame.dodge and frame.skill_slot == -1)
	sim.fighters[1].state = Fighter.State.IDLE
	sim.add_enemy(100, Vector3(1, 0, 0), "goblin")
	sim.fighters[100].state = Fighter.State.ATTACK
	frame = brain.think(sim, 2)
	assert(frame.dodge and frame.move.x < 0)
	sim.fighters[100].state = Fighter.State.IDLE
	sim.fighters[2].skill_view = {"slots":[{"skill":"test","left":0.0,"cost":3.0}]}
	sim.fighters[2].energy = 4.0
	frame = brain.think(sim, 2)
	assert(frame.skill_slot == 0)
	# Thinking never changes HP/energy/profile. Existing simulation owns legality.
	assert(sim.fighters[2].energy == 4.0 and JSON.stringify(profile.to_dict()) == before)
	sim.fighters[2].state = Fighter.State.DOWNED
	frame = brain.think(sim, 2)
	assert(frame.move == Vector2.ZERO and not frame.light and frame.skill_slot == -1)
	var payload := Dialogue.make_payload("model", "อรุณ", "ใจเย็น", "ไปกันไหม")
	assert(payload.messages.size() == 2 and not payload.has("tools") and payload.stream == false)
	var reply := Dialogue.parse_reply(200, JSON.stringify({"choices":[{"message":{"content":"ได้เลย\nไปกัน"}}]}).to_utf8_buffer())
	assert(reply.error == "" and reply.text == "ได้เลย ไปกัน")
	assert(Dialogue.parse_reply(500, PackedByteArray()).error == "unavailable")
	assert(Dialogue.parse_reply(200, '{"choices":[0]}'.to_utf8_buffer()).error == "invalid_response")
	var adapter := Dialogue.new()
	root.add_child(adapter)
	assert(adapter.ask("r1", "user", {}, "hello") == "not_configured")
	adapter.free()
	print("COMPANION FOUNDATION PASS: follow, rescue input, dodge, skill selection, no authority mutation; bounded text-only dialogue parser")
	quit()
