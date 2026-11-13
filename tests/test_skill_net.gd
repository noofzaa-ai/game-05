extends RefCounted
## Online class-skill casts (logic/net/skill_net.gd, wire v3): a 2-player room whose players are squad cards
## (SquadMember fixture; real rooms field plain runs until online squads land). Player 1 casts each movement skill;
## player 2's client receives the 20 Hz public snapshots through the real client apply path
## (client/session/online_session.gd apply_entities) and presents player 1 the way netfox_session does
## (interpolated 20 Hz samples, RemoteState delay, SkillNet.remote_position). The remote view must stay within
## TOLERANCE_M of the authority and never jump more than JUMP_M between frames; the clip must play on the same clock.
## Also: validation (malformed/oversized rows rejected), race_net, cooldown rounding and bytes per snapshot.
const Manager := preload("res://server/rooms/manager.gd")
const F := preload("res://tests/online_fixture.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const SkillNet := preload("res://logic/net/skill_net.gd")
const Skills := preload("res://logic/class_skills/engine.gd")
const Wire := preload("res://logic/net_wire.gd")
const Remote := preload("res://client/session/online_session.gd")
const Blob := preload("res://logic/net/compressed_blob.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Motion := preload("res://client/skills/class_skill_motion.gd")

const SEND_EVERY := 3  ## 20 Hz snapshots (runtime/netfox/remote_state.gd, lease.flush_states 50 ms)
const DELAY_TICKS := 6.0  ## RemoteState's base interpolation delay
const FRAME := 0.25  ## render frames per tick sampled (4 frames per tick ~ 240 Hz, catches every jump)
const TOLERANCE_M := 0.35  ## remote vs authority at the same tick
const JUMP_M := 0.6  ## largest per-frame step allowed (a 6 m rush over 19 ticks moves ~0.08 m per frame)

const MOVERS := [["sword_shield", "shield_rush"], ["sword_shield", "intercept"], ["greatsword", "crater_leap"], ["longbow", "vault_shot"], ["greatsword", "hook_sweep"]]


func run(ctx) -> void:
	for pair in MOVERS:
		_movement(ctx, str(pair[0]), str(pair[1]))
	for pair in MOVERS.slice(0, 4):
		_owner_prediction(ctx, str(pair[0]), str(pair[1]))
	_validation(ctx)
	_race_net(ctx)
	_bandwidth(ctx)


static func _room(classes: Array, room_id: String):
	var manager := Manager.new()
	manager.create(room_id, 77, [{"id": 1, "profile": F.make(77).profile.to_dict()}, {"id": 2, "profile": F.make(78).profile.to_dict()}])
	var room = manager.rooms[room_id].room
	for i in 2:
		var id := i + 1
		var member = SquadMember.make_squad(room.trip_for(id), [classes[i]])[0]
		room.sim.runs.erase(id)
		room.sim.attach_run(id, member, room._rules, room._loot)
		room.sim.fighters[id].energy = 999.0
	return room


## Clears the arena around the players: one goblin target (or an ally for Intercept) at a known spot.
static func _stage(room, skill: String) -> Dictionary:
	for id in room.sim.fighters.keys():
		if room.sim.fighters[id].team == "enemy":
			room.sim.remove_player(id)
	room.sim.add_enemy(500, Vector3(0, 0, 0), "goblin")
	room.sim.fighters[500].hp = 1.0e6
	room.sim.fighters[500].stats["HP"] = 1.0e6
	var p1 := Vector3(-5.5, 0, 0)
	var p2 := Vector3(-5.5, 0, 3.0)
	if skill == "intercept":
		p2 = Vector3(1.5, 0, 0)
	elif skill == "vault_shot" or skill == "hook_sweep":
		p1 = Vector3(-1.5, 0, 0)
	for id in [1, 2]:
		room.sim.bodies[id].position = (p1 if id == 1 else p2) + Vector3(0, room.sim.bodies[id].position.y, 0)
		room.sim.bodies[id].velocity = Vector3.ZERO
	room.sim.bodies[500].position = Vector3(0, room.sim.bodies[500].position.y, 0)
	var choice := {"target": 2 if skill == "intercept" else 500}
	if skill == "crater_leap":
		choice["point"] = Vector3(0, room.sim.bodies[1].position.y, 0)
	return choice


func _movement(ctx, class_id: String, skill: String) -> void:
	var room = _room([class_id, "magic"], "skill-net-" + skill.replace("_", "-"))
	var client := Remote.new()
	room.tick()
	var choice := _stage(room, skill)
	var start_tick: int = room.clock_tick
	var why := Skills.cast(room.sim, 1, skill, choice)
	ctx.check("net %s: cast starts on the authority (%s)" % [skill, why], why == "")
	var truth := {}  ## clock tick -> authority position of player 1 (after that tick)
	var samples := {}  ## clock tick -> position the client received (20 Hz)
	var cast_seen := false
	var travel_sent := false
	var state_tick: int = room.clock_tick
	truth[state_tick] = room.sim.bodies[1].position
	samples[state_tick] = room.sim.bodies[1].position
	var cast_info: Dictionary = room.sim.fighters[1].skill_state["cast"]
	var to_clock: int = room.clock_tick - (room.sim.tick_count - 1)  # sim tick T ran for room clock tick T + to_clock
	var end_tick: int = int(cast_info["end"]) + to_clock + 40
	var view_cast := {}
	var max_err := 0.0
	var max_jump := 0.0
	var last := Vector3.INF
	var clip_ok := true
	var client_sim = null
	while room.clock_tick < end_tick:
		for id in [1, 2]:
			room.input(id, room.clock_tick + 1, SimInput.new().encode())
		room.tick()
		truth[room.clock_tick] = room.sim.bodies[1].position
		if room.clock_tick % SEND_EVERY == 0:
			var state: Dictionary = room.public_state(2)
			var packed := Blob.pack(var_to_bytes(state))
			state = bytes_to_var(Blob.unpack(packed))  # the actual transport round trip (netfox_session._state_bytes)
			if client_sim == null:
				client_sim = Remote.new().make_sim(state, preload("res://logic/map_loader.gd").load_by_id(state.meta.map))
			else:
				client.apply_entities(client_sim, state)
			samples[int(state.tick)] = room.sim.bodies[1].position
			if client_sim.fighters[1].skill_view.has("class_cast"):
				cast_seen = true
				travel_sent = travel_sent or client_sim.fighters[1].skill_view["class_cast"].has("travel")
		# present frames for this tick, drawn DELAY_TICKS behind the newest tick (as RemoteState does)
		if client_sim == null:
			continue
		for f in int(1.0 / FRAME):
			var clock: float = float(room.clock_tick) - 1.0 + (f + 1) * FRAME - DELAY_TICKS
			if clock < start_tick:
				continue
			var sampled = _interpolate(samples, clock)
			if sampled == null:
				continue
			var shown: Vector3 = SkillNet.remote_position(client_sim.fighters[1].skill_view, sampled, clock, client_sim.world.half_width, client_sim.world.half_depth, 0.75)
			var actual: Vector3 = _interpolate(truth, clock)
			max_err = maxf(max_err, Vector2(shown.x - actual.x, shown.z - actual.z).length())
			if last != Vector3.INF:
				max_jump = maxf(max_jump, Vector2(shown.x - last.x, shown.z - last.z).length())
			last = shown
			var c: Dictionary = client_sim.fighters[1].skill_view.get("class_cast", {})
			if not c.is_empty():
				view_cast = c
				# the clip clock is the drawn tick; the pose must be the one the authority's cast plays at that tick
				var want: Dictionary = Motion.frame({"skill": skill, "start": int(cast_info["start"]) + to_clock, "time_mul": float(cast_info.get("cast_time", 1.0))}, clock)
				var got: Dictionary = Motion.frame(c, float(c.get("view_tick", -1.0)))
				if not want.is_empty() and (got.get("clip") != want.get("clip") or absf(float(got.get("time", 0)) - float(want.get("time", 0))) > 0.02):
					clip_ok = false
	var moved: float = Vector2(truth[end_tick].x - truth[start_tick].x, truth[end_tick].z - truth[start_tick].z).length()
	ctx.check("net %s: remote client received the cast with its travel (moved %.2f m)" % [skill, moved], cast_seen and travel_sent and (moved > 0.2 or skill == "hook_sweep"))
	ctx.check("net %s: remote view within %.2f m of the authority (max %.3f m)" % [skill, TOLERANCE_M, max_err], max_err <= TOLERANCE_M)
	ctx.check("net %s: no remote teleport, largest frame step %.3f m <= %.2f m" % [skill, max_jump, JUMP_M], max_jump <= JUMP_M)
	ctx.check("net %s: remote clip plays on the drawn tick (same clip frame as the authority cast)" % skill, clip_ok and not view_cast.is_empty())
	ctx.check("net %s: the ended cast is dropped once the drawn tick passes its end" % skill, not client_sim.fighters[1].skill_view.has("class_cast"))


## Linear interpolation of a {tick: Vector3} table at fractional tick `t` (null before the first entry).
static func _interpolate(table: Dictionary, t: float):
	var keys: Array = table.keys()
	keys.sort()
	if keys.is_empty() or t < float(keys[0]):
		return null
	var a: int = keys[0]
	for k in keys:
		if float(k) <= t:
			a = k
		else:
			var span := float(k - a)
			return Vector3(table[a]).lerp(Vector3(table[k]), clampf((t - a) / span, 0.0, 1.0))
	return table[a]


func _validation(ctx) -> void:
	var room = _room(["sword_shield", "magic"], "skill-net-validate")
	room.tick()
	var choice := _stage(room, "shield_rush")
	Skills.cast(room.sim, 1, "shield_rush", choice)
	var row: Array = SkillNet.pack_skill(room.sim.fighters[1])
	var bytes := Wire.encode(row).size()
	ctx.check("net skill_net row is compact (%d B <= %d B)" % [bytes, SkillNet.SKILL_MAX_BYTES], bytes <= SkillNet.SKILL_MAX_BYTES and bytes > 0)
	ctx.check("net skill_net roundtrips through the wire codec", not SkillNet.read_skill(Wire.decode(Wire.encode(row)).value).is_empty())
	var bad := []
	var r := row.duplicate(); r[0] = 99; bad.append(r)  # unknown version
	r = row.duplicate(); r[1] = "not_a_skill"; bad.append(r)
	r = row.duplicate(); r[2] = 99999999; bad.append(r)  # tick out of range
	r = row.duplicate(); r[8] = Vector3(1e9, 0, 0); bad.append(r)  # coordinate out of range
	r = row.duplicate(); r[11] = range(20); bad.append(r)  # too many counters
	r = row.duplicate(); r[1] = "x".repeat(300); bad.append(r)  # oversized
	r = row.duplicate(); r.append(1); bad.append(r)  # wrong shape
	r = row.duplicate(); r[7] = int(r[6]) - 5; bad.append(r)  # travel ends before it starts
	bad.append("text")
	var all_rejected := true
	var fighter = room.sim.fighters[2]
	fighter.skill_view = {"class_cast": {"skill": "keep"}}
	for value in bad:
		if not SkillNet.read_skill(value).is_empty() or SkillNet.apply_skill(fighter, value, 100):
			all_rejected = false
	ctx.check("net malformed/oversized skill_net rows are rejected and never partially applied", all_rejected and fighter.skill_view["class_cast"]["skill"] == "keep")
	ctx.check("net skill_net rejections are counted (rate-limited log)", SkillNet.rejected >= bad.size())
	# the wire skill_view: no class_cast, slot cooldowns rounded to 0.1 s
	Skills.publish_view(room.sim, 1, room.sim.fighters[1])
	var view: Dictionary = Wire.fighter_value(room.sim.fighters[1], "skill_view")
	var rounded := true
	for slot in view.get("slots", []):
		rounded = rounded and is_equal_approx(float(slot["left"]), snappedf(float(slot["left"]), 0.1))
	ctx.check("net wire skill_view drops class_cast and rounds slot cooldowns to 0.1 s", not view.has("class_cast") and rounded and not view.get("slots", []).is_empty())
	ctx.check("net authority skill_view itself is untouched by the wire copy", room.sim.fighters[1].skill_view.has("class_cast"))


func _race_net(ctx) -> void:
	var room = _room(["sword_shield", "magic"], "skill-net-race")
	var fighter = room.sim.fighters[1]
	fighter.race_state["tree"] = {"gauge": {"fire_at": 60.0, "fire_below_hp": 0.5}}
	fighter.race_state["ult"] = {"move": "%s_%s_ultimate" % [fighter.race_state.get("race", ""), fighter.race_state.get("class", "")], "at": 3, "done": false}
	var row: Array = SkillNet.pack_race(fighter)
	var client = Remote.new().make_sim(room.public_state(2), preload("res://logic/map_loader.gd").load_by_id(room.public_state(2).meta.map))
	var shown = client.fighters[1]
	ctx.check("net race_net: remote client knows the race, the ultimate and the move (%s)" % [row],
		not fighter.race_state.is_empty() and shown.race_state.get("race") == fighter.race_state["race"] and not shown.race_state.get("ultimate", {}).is_empty()
		and shown.race_state.get("ult", {}).get("move") == fighter.race_state["ult"]["move"])
	ctx.check("net race_net: the tree fire threshold reaches the client (squad panel 'full')",
		is_equal_approx(preload("res://logic/skill_tree_effects.gd").fire_threshold(shown, 100.0), preload("res://logic/skill_tree_effects.gd").fire_threshold(fighter, 100.0)))
	ctx.check("net race_net row is compact (%d B)" % Wire.encode(row).size(), Wire.encode(row).size() <= SkillNet.RACE_MAX_BYTES)
	var bad := row.duplicate(); bad[1] = "dragon"
	var bad_move := row.duplicate(); bad_move[6] = "other_move"
	ctx.check("net race_net: unknown race / mismatched move rejected", SkillNet.read_race(bad).is_empty() and SkillNet.read_race(bad_move).is_empty())
	ctx.check("net wire VERSION is 3 and carries skill_net/race_net", Wire.VERSION == 3 and Wire.FIGHTER_FIELDS.has("skill_net") and Wire.FIGHTER_FIELDS.has("race_net"))


## Bytes per 20 Hz snapshot (zstd var_to_bytes, the netfox metadata path) for a 2-card room casting skills.
## Before (wire v2, measured 2026-11-13 with tests/_bw_probe.gd): 3,354 B per snapshot average, ~67 KB/s per player.
func _bandwidth(ctx) -> void:
	var room = _room(["sword_shield", "greatsword"], "skill-net-bandwidth")
	var memory := {1: preload("res://logic/auto_pilot.gd").new_memory(11), 2: preload("res://logic/auto_pilot.gd").new_memory(22)}
	var total := 0
	var count := 0
	for i in 900:
		for id in [1, 2]:
			room.input(id, room.clock_tick + 1, preload("res://logic/auto_pilot.gd").decide(room.sim, room.sim.combat, id, memory[id], room.sim.tick_count).encode())
		room.tick()
		if room.clock_tick % SEND_EVERY == 0:
			total += Blob.pack(var_to_bytes(room.public_state(1))).size()
			count += 1
	var average := total / maxi(1, count)
	print("  skill_net bandwidth: %d B per snapshot, %d B/s per player at 20 Hz" % [average, average * 20])
	ctx.check("net bytes per snapshot stay within the v2 baseline (+5%%): %d B vs 3354 B" % average, average <= 3522)


## B: the caster's OWN client predicts its travel frames (logic/game_sim.gd _predict_class_travel). The owner copy is
## restored from the authority continuation at the cast start (as runtime/netfox/actor.gd does), then advanced with
## prediction ticks only (logic/net/actor_step.gd); its position must follow the authority without a correction.
func _owner_prediction(ctx, class_id: String, skill: String) -> void:
	var room = _room([class_id, "magic"], "skill-net-own-" + skill.replace("_", "-"))
	room.tick()
	var choice := _stage(room, skill)
	Skills.cast(room.sim, 1, skill, choice)
	var bytes: PackedByteArray = preload("res://logic/net/actor_continuation.gd").capture(room.sim, 1)
	var state: Dictionary = room.public_state(1)
	var owner = Remote.new().make_sim(state, preload("res://logic/map_loader.gd").load_by_id(state.meta.map))
	var restored: bool = preload("res://logic/net/actor_continuation.gd").restore(owner, 1, bytes)
	owner.tick_count = room.sim.tick_count
	var worst := 0.0
	var end := int(room.sim.fighters[1].skill_state["cast"]["end"])
	while room.sim.tick_count <= end:
		for id in [1, 2]:
			room.input(id, room.clock_tick + 1, SimInput.new().encode())
		room.tick()
		preload("res://logic/net/actor_step.gd").advance(owner, 1, SimInput.new())
		worst = maxf(worst, Vector2(owner.bodies[1].position.x - room.sim.bodies[1].position.x, owner.bodies[1].position.z - room.sim.bodies[1].position.z).length())
	ctx.check("net %s: owner prediction follows the authority travel (max %.3f m <= 0.03 m, the actor's correction threshold)" % [skill, worst], restored and worst <= 0.03)
