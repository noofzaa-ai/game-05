extends RefCounted
const Wire := preload("res://logic/net_wire.gd")
const Delta := preload("res://logic/net_state.gd")
const Manager := preload("res://server/rooms/manager.gd")
const Remote := preload("res://client/session/netfox_session.gd")
const F := preload("res://tests/online_fixture.gd")
const SimInput := preload("res://logic/sim_input.gd")

func run(ctx) -> void:
	var values := [null, true, false, -32768, 32767, 32768, 0xffffffff, -9223372036854775807, 9223372036854775807, 1.23456789, "ไทย 東京", Vector2(1.25, -2.5), Vector3(-3, 4, 5), Vector2i(2, -3), {1: [1, 2], "test": {"value": 12}}]
	for value in values:
		var bytes := Wire.encode(value)
		var decoded := Wire.decode(bytes)
		ctx.check("M4 binary roundtrip type%d" % typeof(value), decoded.has("value") and decoded.value == value)
	var valid := Wire.encode({"test": [Vector3(1, 2, 3), "word"]})
	var all_truncated := true
	for i in range(valid.size()):
		if not Wire.decode(valid.slice(0, i)).is_empty(): all_truncated = false
	ctx.check("M4 all truncated prefixes fail closed", all_truncated)
	ctx.check("M4 trailing payload rejected", Wire.decode(valid + PackedByteArray([0])).is_empty())
	ctx.check("M4 nonfinite encode rejected", Wire.encode(NAN).is_empty() and Wire.encode(Vector3(INF, 0, 0)).is_empty())
	ctx.check("M4 unknown tag rejected", Wire.decode(PackedByteArray([255])).is_empty())
	ctx.check("M4 invalid UTF8 rejected without engine decoder errors", Wire.decode(PackedByteArray([5, 2, 0, 192, 128])).is_empty())
	var deep = 1
	for i in range(14): deep = [deep]
	ctx.check("M4 nested data bounded", Wire.encode(deep).is_empty())
	ctx.check("M4 strings and arrays bounded", Wire.encode("x".repeat(8193)).is_empty() and Wire.encode(range(1025)).is_empty())
	var packet := Wire.packet(Wire.STATE, 1, {"tick": 3})
	ctx.check("M4 packet header roundtrip", Wire.parse(packet).sequence == 1 and Wire.decode(Wire.parse(packet).body).value.tick == 3)
	var broken := packet.duplicate(); broken[0] = 0
	ctx.check("M4 magic/version/length enforced", Wire.parse(broken).is_empty() and Wire.parse(packet + PackedByteArray([0])).is_empty() and Wire.frame(9, 1, PackedByteArray()).is_empty())
	var frame := SimInput.new(); frame.light = true; frame.move = Vector2(1, 0)
	var input := Wire.inputs(2, 1, 3, 10, [frame.encode(), SimInput.new().encode()], 4)
	var decoded_input := Wire.read_inputs(Wire.parse(input).body)
	ctx.check("M4 input binds epoch and newest/history ticks", decoded_input.tick == 10 and decoded_input.epoch == 4 and decoded_input.frames.size() == 2 and decoded_input.state_ack == 1)
	ctx.check("M4 malformed input history rejected", Wire.read_inputs(PackedByteArray([0])).is_empty() and Wire.inputs(1, 0, 0, 2, [PackedByteArray([0, 128, 0, 0, 0])]).is_empty())
	var manager := Manager.new()
	var f := F.make(77)
	manager.create("net-test-room", 77, [{"id": 1, "profile": f.profile.to_dict()}, {"id": 2, "profile": F.make(78).profile.to_dict()}])
	var room = manager.rooms["net-test-room"].room
	var full: Dictionary = room.public_state(1)
	var patch := Delta.difference(full, {}, 0, 0)
	var restored := Delta.apply({}, Wire.decode(Wire.encode(patch)).value)
	ctx.check("M4 full snapshot reconstructs all public state", restored.entities == full.entities and restored.meta == full.meta)
	room.input(1, 1, frame.encode()); manager.advance(1.0 / 60.0)
	var next: Dictionary = room.public_state(1)
	var sparse := Delta.difference(next, full, 1, 1)
	var applied := Delta.apply(restored, Wire.decode(Wire.encode(sparse)).value)
	ctx.check("M4 acknowledged delta reconstructs authoritative state", applied.entities == next.entities and applied.meta == next.meta and applied.tick == next.tick)
	ctx.check("M4 delta smaller than full snapshot", Wire.encode(sparse).size() < Wire.encode(Delta.difference(next, {}, 0, 0)).size())
	ctx.check("M4 recipient filtering excludes peer stash and RNG", next.meta.profiles[2].stash.gold == "0" and next.meta.profiles[2].stash.items.is_empty() and not next.has("rng") and not next.meta.has("seed"))
	ctx.check("M4 stage-only command cannot award client-provided loot", not room.command(1, 1, {"type": "journey_finish", "gold": 999}, room.epoch).ok)
	ctx.check("M4 stale epoch cannot mutate new stage", room.command(1, 2, {"type": "journey_treasure"}, room.epoch + 1).error == "stale_epoch")
	var movement := SimInput.new(); movement.move = Vector2(1, 0)
	ctx.check("M4 bounded 24-tick prediction input admitted", room.input(1, room.clock_tick + 24, movement.encode()) and not room.input(1, room.clock_tick + 25, movement.encode()))
	var journal: Dictionary = room.command(1, 3, {"type": "journey_treasure"}, room.epoch)
	ctx.check("M4 command retry is idempotent and payload reuse denied", room.command(1, 3, {"type": "journey_treasure"}, room.epoch) == journal and room.command(1, 3, {"type": "journey_finish"}, room.epoch).error == "request_id_reused")
	room.journey.stage_cleared(1.0)
	var route: Dictionary = room.public_state(1)
	ctx.check("M4 cleared-stage snapshot retains physical map after Journey clears current", route.meta.state == "choosing" and not route.meta.map.is_empty() and route.meta.current.is_empty())
	var chosen: Dictionary = room.command(1, 4, {"type": "journey_choose", "index": 0}, room.epoch)
	ctx.check("M4 authoritative route choice changes epoch and builds next simulation", chosen.ok and room.epoch == 2 and not room.public_state(1).meta.map.is_empty())
	var request_id := 10
	var camp_seen := false
	var lifecycle_ok := true
	for transition in range(30):
		if room.journey.is_over(): break
		if room.journey.state == "in_stage": room.journey.stage_cleared(1.0)
		elif room.journey.state == "choosing":
			var options: Array = room.journey.upcoming_choices()
			var choice := 0
			for i in options.size():
				if options[i].kind in ["camp", "treasure"]: choice = i; break
			lifecycle_ok = lifecycle_ok and room.command(1, request_id, {"type": "journey_choose", "index": choice}, room.epoch).ok
			request_id += 1
		elif room.journey.state == "at_node":
			if room.journey.is_at_camp():
				camp_seen = true
				lifecycle_ok = lifecycle_ok and room.command(2, request_id, {"type": "bank_bag"}, room.epoch).ok
				request_id += 1
			lifecycle_ok = lifecycle_ok and room.command(1, request_id, {"type": "journey_leave"}, room.epoch).ok
			request_id += 1
		if room.public_state(1).is_empty(): lifecycle_ok = false
	ctx.check("M4 camp banking/leave and full route lifecycle retain valid public snapshots", lifecycle_ok and camp_seen and room.journey.state == "won")
	var settled_profiles: Dictionary = room.finalize()
	ctx.check("M4 terminal settlement is repeatable without duplicate rewards", settled_profiles.size() == 2 and room.finalize() == settled_profiles)
	# A final leave reply can be buffered after the underlying WebSocket is CLOSED.
	var closing := Remote.new()
	var left_count := [0]
	closing.party_left.connect(func(): left_count[0] += 1)
	closing._leave_requested = true
	closing._pending_commands[77] = {"request": {"type": "party_leave"}, "epoch": 1, "sent": 0}
	closing._receive(Wire.packet(Wire.CONTROL, 1, {"id": 77, "result": {"ok": true, "left": true}}), 0)
	ctx.check("final leave reply is drained with a closed socket", left_count[0] == 1 and closing.saved and closing._deliberate_close)
	closing._finish_leave(true)
	ctx.check("leave completion is emitted once", left_count[0] == 1)
	var terminal := Remote.new()
	terminal._handle_reconnect_result({"ok": false, "error": "room_expired"})
	ctx.check("expired room stops reconnect and permits Back without inventing a save", terminal.can_return_to_hub() and terminal._terminal and not terminal.saved)
	var lost_ack := Remote.new()
	var recovered := [0]
	lost_ack.party_left.connect(func(): recovered[0] += 1)
	lost_ack._leave_requested = true
	lost_ack._handle_reconnect_result({"ok": false, "error": "not_invited"})
	ctx.check("lost leave reply plus revoked membership exits safely", recovered[0] == 1 and lost_ack._deliberate_close and not lost_ack.saved)
	var transient := Remote.new()
	transient._handle_reconnect_result({"ok": false, "error": "unavailable"})
	ctx.check("transient outages retain reconnect behavior", not transient._terminal and not transient.can_return_to_hub())

