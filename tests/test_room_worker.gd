extends RefCounted
const Manager := preload("res://server/rooms/manager.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Codec := preload("res://logic/state_codec.gd")
const F := preload("res://tests/online_fixture.gd")

func players(count: int) -> Array:
	var result := []
	for id in range(1, count + 1): result.append({"id": id, "profile": F.make(id).profile.to_dict()})
	return result

func run(ctx) -> void:
	_scene_barrier(ctx)
	var mgr := Manager.new()
	ctx.check("M4-1 server-only production data loads", mgr.ready())
	var raw := players(2)
	var original := raw.duplicate(true)
	ctx.check("M4-1 room allocates separate party sim/journey", mgr.create("room-0001", 77, raw).ok)
	ctx.check("M4-1 second room allocates independently", mgr.create("room-0002", 77, raw).ok)
	ctx.check("M4-1 caller-owned profiles not mutated", raw == original)
	var one = mgr.rooms["room-0001"].room
	var two = mgr.rooms["room-0002"].room
	ctx.check("M4-1 profiles and runs never shared across rooms", one.journey.runs_by_player[1].profile != two.journey.runs_by_player[1].profile and one.sim != two.sim)
	var move := SimInput.new()
	move.move = Vector2(1, 0)
	ctx.check("M4-1 input accepts only bound participant slot", not one.input(99, 1, move.encode()) and one.input(1, 1, move.encode()))
	ctx.check("M4-1 duplicate input idempotent", one.input(1, 1, move.encode()))
	ctx.check("M4-1 queued input cannot be replaced", not one.input(1, 1, SimInput.new().encode()))
	ctx.check("M4-1 malformed/future/played tick rejected", not one.input(1, 1, PackedByteArray([0])) and not one.input(1, 25, move.encode()) and not one.input(1, 0, move.encode()))
	mgr.advance(1.0 / 60.0)
	ctx.check("M4-1 clock advances both rooms exactly one tick", one.sim.tick_count == 1 and two.sim.tick_count == 1)
	ctx.check("M4-1 movement stays in its own room", one.sim.bodies[1].position != two.sim.bodies[1].position)
	ctx.check("M4-1 only played input gets acknowledged", one.acknowledged[1] == 1 and two.acknowledged[1] == 0)
	ctx.check("M4-1 played tick cannot replay attack", not one.input(1, 1, move.encode()))
	one.input(1, 2, move.encode())
	one.presence(1, false)
	ctx.check("M4-1 disconnect clears queued input and denies new input", one.queued[1].is_empty() and not one.input(1, 2, move.encode()))
	mgr.advance(1.0 / 60.0)
	ctx.check("M4-1 disconnect does not advance input acknowledgement", one.acknowledged[1] == 1)
	ctx.check("M4-1 unknown presence cannot create a participant", not one.presence(9, true))
	var previous: int = one.sim.tick_count
	mgr.advance(0.1)
	ctx.check("M4-1 per-frame catch-up bounded to five", one.sim.tick_count == previous + 5)
	mgr.advance(0)
	ctx.check("M4-1 catch-up retains residual fixed ticks", one.sim.tick_count == previous + 6)
	var before := mgr.status("room-0002")
	mgr.advance(-1)
	mgr.advance(NAN)
	ctx.check("M4-1 invalid scheduler delta ignored", mgr.status("room-0002") == before)
	mgr.close("room-0001")
	ctx.check("M4-1 closing one room preserves other", not mgr.rooms.has("room-0001") and mgr.rooms.has("room-0002"))
	two.presence(1, false)
	two.presence(2, false)
	mgr.advance(30)
	ctx.check("M4-1 empty room retires without financial settlement", mgr.rooms.is_empty() and mgr.closed[-1].reason == "empty_timeout" and raw == original)
	mgr.create("room-overload", 77, players(1))
	mgr.advance(0.251)
	ctx.check("M4-1 overload closes instead of stretching dt", mgr.rooms.is_empty() and mgr.closed[-1].reason == "overload")
	mgr.create("room-finished", 77, players(1))
	mgr.rooms["room-finished"].room.status = "finished"
	mgr.advance(60)
	ctx.check("M4-1 completed room has finite lifetime", mgr.rooms.is_empty() and mgr.closed[-1].reason == "inactive_timeout")
	for count in [1, 2, 4]:
		var a := Manager.new()
		var b := Manager.new()
		var profiles := players(count)
		a.create("repeat-room", 88, profiles)
		b.create("repeat-room", 88, profiles)
		for tick in range(1, 61):
			for id in range(1, count + 1):
				a.rooms["repeat-room"].room.input(id, tick, move.encode())
				b.rooms["repeat-room"].room.input(id, tick, move.encode())
			a.advance(1.0 / 60.0)
			b.advance(1.0 / 120.0)
			b.advance(1.0 / 120.0)
		var ar = a.rooms["repeat-room"].room
		var br = b.rooms["repeat-room"].room
		ctx.check("M4-1 fixed ticks independent of render cadence party%d" % count, Codec.digest(ar.sim.snapshot()) == Codec.digest(br.sim.snapshot()) and ar.journey.to_dict() == br.journey.to_dict() and ar.sim.tick_count == 60)
	var cap := Manager.new()
	for i in range(8): cap.create("capacity-%d" % i, i + 1, players(1))
	ctx.check("M4-1 bounded rooms per process", cap.create("capacity-9", 9, players(1)).error == "worker_full")
	ctx.check("M4-1 duplicate room cannot replace active state", cap.create("capacity-0", 9, players(1)).error == "room_exists")
	for request in [null, {}, {"v": true, "op": "status", "room": "room-0001"}, {"v": 1, "op": "status", "room": "room-0001", "player": 1}, {"v": 1, "op": "tick", "room": "room-0001"}]:
		ctx.check("M4-1 private control rejects malformed/client-clock requests", not mgr.control(request).ok)
	var duplicate := players(2)
	duplicate[1].id = 1
	ctx.check("M4-1 duplicate player slot rejected", mgr.create("bad-players", 1, duplicate).error == "invalid_state")

func _scene_barrier(ctx) -> void:
	for count in [1, 2, 4]:
		var mgr := Manager.new()
		mgr.create("loading-room", 91, players(count))
		var room = mgr.rooms["loading-room"].room
		room.require_scene_ready()
		var before: Dictionary = room.sim.snapshot().duplicate(true)
		for frame in range(180): mgr.advance(1.0 / 60.0)
		ctx.check("scene barrier freezes HP, AI, movement and sim clock party%d" % count, room.sim.snapshot() == before and room.clock_tick == 0)
		ctx.check("scene barrier rejects wrong slot and stale epoch party%d" % count, not room.scene_ready(99, room.epoch) and not room.scene_ready(1, room.epoch - 1))
		ctx.check("scene barrier rejects gameplay input while loading party%d" % count, not room.input(1, 1, SimInput.new().encode()))
		for id in range(1, count): room.scene_ready(id, room.epoch)
		ctx.check("scene barrier waits for the slowest party%d" % count, room.scene_loading())
		room.scene_ready(count, room.epoch)
		ctx.check("scene barrier duplicate ACK is idempotent party%d" % count, room.scene_ready(count, room.epoch) and not room.scene_loading())
		mgr.advance(1.0 / 60.0)
		ctx.check("scene barrier starts after all ACKs party%d" % count, room.clock_tick == 1 and room.sim.tick_count == 1)
		room.epoch += 1
		room._start_stage()
		ctx.check("scene barrier resets every stage and rejects prior ACK party%d" % count, room.scene_loading() and not room.scene_ready(1, room.epoch - 1))
		mgr.advance(120.0)
		ctx.check("scene barrier has a bounded loading lifetime party%d" % count, mgr.rooms.is_empty() and mgr.closed[-1].reason == "scene_load_timeout")
