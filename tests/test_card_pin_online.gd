extends RefCounted
## Card pin online (Boss 2026-11-26): server card_pin / card_unpin commands in squad rooms (owner-only, fight-only,
## 5/s, clamp, relayed events, wave-end clear) and the online session's prediction + reconcile + owner filtering.
const Squads := preload("res://tests/test_online_squads.gd")
const CardPin := preload("res://client/card_pin.gd")

var _rid := 0


func _cmd(room, player: int, request: Dictionary) -> Dictionary:
	_rid += 1
	return room.command(player, _rid, request)


func run(ctx) -> void:
	var mgr = Squads.squad_manager()
	var made: Dictionary = mgr.create("pin-room", 77, Squads.players(2))
	ctx.check("pin online: room created", made.get("ok", false))
	if not made.get("ok", false): return
	var room = mgr.rooms["pin-room"].room
	for i in 30: room.tick()
	ctx.check("pin online: room fights (%s)" % room.status, room.status == "active" and not room.scene_loading())
	var mine: Array = room.fighters_of(1)
	var theirs: Array = room.fighters_of(2)
	ctx.check("pin online: each player owns cards", mine.size() >= 2 and theirs.size() >= 1)
	if mine.size() < 2 or theirs.is_empty(): return
	var card: int = mine[1]
	var seq_before: int = room.event_sequence
	var at: Vector3 = room.sim.bodies[card].position
	var target := Vector2(at.x + 3.0, at.z)
	var res: Dictionary = _cmd(room, 1, {"type": "card_pin", "card": card, "x": target.x, "z": target.y})
	ctx.check("pin online: own card pin accepted (%s)" % res, res.get("ok", false) and room.sim.get_pin(card).size() == 2)
	target = Vector2(float(room.sim.get_pin(card).get("x", 0.0)), float(room.sim.get_pin(card).get("z", 0.0)))
	var relayed: Array = room.events.filter(func(r): return int(r.sequence) > seq_before and r.event.type == "card_pinned" and int(r.event.player) == card)
	ctx.check("pin online: card_pinned relayed as a numbered room event", relayed.size() == 1)
	ctx.check("pin online: foreign card rejected", _cmd(room, 1, {"type": "card_pin", "card": theirs[0], "x": 0.0, "z": 0.0}).get("error", "") == "not_your_card" and room.sim.get_pin(theirs[0]).is_empty())
	ctx.check("pin online: enemy id rejected", _cmd(room, 2, {"type": "card_pin", "card": 100, "x": 0.0, "z": 0.0}).get("ok", true) == false)
	ctx.check("pin online: unknown field rejected", _cmd(room, 2, {"type": "card_pin", "card": theirs[0], "x": 0.0, "z": 0.0, "extra": 1}).get("error", "") == "invalid_command")
	ctx.check("pin online: non-finite rejected", _cmd(room, 2, {"type": "card_pin", "card": theirs[0], "x": INF, "z": 0.0}).get("error", "") == "invalid_command")
	ctx.check("pin online: string card rejected", _cmd(room, 2, {"type": "card_pin", "card": "1", "x": 0.0, "z": 0.0}).get("error", "") == "invalid_command")
	var far: Dictionary = _cmd(room, 2, {"type": "card_pin", "card": theirs[0], "x": 9999.0, "z": -9999.0})
	var margin := float(room.sim.pin_rules().edge_margin)
	ctx.check("pin online: out of bounds clamped (%s)" % far, far.get("ok", false) and is_equal_approx(float(far.pin.x), room.sim.world.half_width - margin) and is_equal_approx(float(far.pin.z), -room.sim.world.half_depth + margin))
	# The card walks to and holds the pin over ticks (the server auto-pilot reads fighter.pin).
	var start := Vector2(at.x, at.z).distance_to(target)
	var best := start
	var held := 0
	for i in 400:
		room.tick()
		if room.sim.get_pin(card).is_empty(): break
		var p: Vector3 = room.sim.bodies[card].position
		var d := Vector2(p.x, p.z).distance_to(target)
		best = minf(best, d)
		if d <= float(room.sim.pin_rules().pin_radius) + 0.1: held += 1
	ctx.check("pin online: the pinned card walks to its pin (%.2f -> %.2f m)" % [start, best], best <= float(room.sim.pin_rules().pin_radius) + 0.1)
	ctx.check("pin online: and holds it (%d ticks inside)" % held, held >= 60 or room.sim.get_pin(card).is_empty())
	# One pin per player: pinning another own card releases the first and tells everyone.
	var seq2: int = room.event_sequence
	room.clock_tick += 120
	_cmd(room, 1, {"type": "card_pin", "card": mine[0], "x": 0.0, "z": 0.0})
	ctx.check("pin online: a second own pin releases the first", room.sim.get_pin(card).is_empty() and not room.sim.get_pin(mine[0]).is_empty())
	ctx.check("pin online: release relayed as card_unpinned", room.events.any(func(r): return int(r.sequence) > seq2 and r.event.type == "card_unpinned" and int(r.event.player) == card))
	# Rate limit: 5 per second per player.
	room.clock_tick += 120
	var oks := 0
	for i in 6:
		if _cmd(room, 1, {"type": "card_pin", "card": mine[0], "x": float(i), "z": 0.0}).get("ok", false): oks += 1
	ctx.check("pin online: 6th command in one second rate limited (%d ok)" % oks, oks == 5)
	room.clock_tick += 120
	var un: Dictionary = _cmd(room, 1, {"type": "card_unpin", "card": mine[0]})
	ctx.check("pin online: unpin clears", un.get("ok", false) and room.sim.get_pin(mine[0]).is_empty())
	_cmd(room, 2, {"type": "card_pin", "card": theirs[0], "x": 0.0, "z": 0.0})
	ctx.check("pin online: foreign unpin rejected", _cmd(room, 1, {"type": "card_unpin", "card": theirs[0]}).get("error", "") == "not_your_card" and not room.sim.get_pin(theirs[0]).is_empty())
	# Wave end clears every pin (sim events), relayed to clients by the room tick.
	var seq3: int = room.event_sequence
	room.sim._clear_all_pins()
	ctx.check("pin online: wave-end clear queued as sim events", room.sim.events.any(func(e): return e.type == "card_unpinned"))
	room.sim.events.clear()
	room.sim.fighters[theirs[0]].pin = {"x": 0.0, "z": 0.0}
	room.sim.fighters[theirs[0]].state = preload("res://logic/fighter.gd").State.DEAD  # a dead card's pin clears inside the tick
	room.tick()
	ctx.check("pin online: an in-tick clear replicates as card_unpinned", room.events.any(func(r): return int(r.sequence) > seq3 and r.event.type == "card_unpinned" and int(r.event.player) == theirs[0]))
	# Non-fight phase refused.
	room.status = "route"
	room.clock_tick += 120
	ctx.check("pin online: refused outside a fight", _cmd(room, 1, {"type": "card_pin", "card": mine[0], "x": 0.0, "z": 0.0}).get("error", "") == "not_available_here")
	room.status = "active"
	_client(ctx, mgr, room)


func _client(ctx, mgr, room) -> void:
	var one = Squads.client_for(mgr, room, 1)
	one.connected = true
	one.fighters = room.sim.fighters
	one._sim = room.sim
	var mine: Array = one.own_cards().filter(func(id): return room.sim.fighters[id].is_alive())
	ctx.check("pin client: own cards are only player 1's (%s)" % [mine], one.own_cards() == room.fighters_of(1))
	ctx.check("pin client: card_pin enabled for the room session", CardPin.enabled_for(one))
	ctx.check("pin client: camp account session stays off", not CardPin.enabled_for(preload("res://client/session/account_session.gd").new()))
	ctx.check("pin client: own_cards helper follows the session", CardPin.own_cards(one) == one.own_cards())
	if mine.size() < 2: return
	var p: Dictionary = one.set_pin(mine[0], 9999.0, 0.0)
	ctx.check("pin client: prediction is clamped and shown at once (%s)" % p, not p.is_empty() and float(p.x) < 9999.0 and one.get_pin(mine[0]) == p)
	ctx.check("pin client: a squad-mate card cannot be pinned", one.set_pin(room.fighters_of(2)[0], 0.0, 0.0).is_empty())
	var sent: int = one._command_id
	one._pin_command_result(one._pending_commands[sent].request, sent, {"ok": true, "pin": {"x": 1.5, "z": 2.0}})
	ctx.check("pin client: server result reconciles the pin", one.get_pin(mine[0]) == {"x": 1.5, "z": 2.0})
	one.set_pin(mine[1], 0.0, 0.0)
	one._pin_command_result(one._pending_commands[one._command_id].request, one._command_id, {"ok": false, "error": "rate_limited"})
	ctx.check("pin client: a refused pin drops the prediction", one.get_pin(mine[1]).is_empty())
	one._pin_event({"type": "card_pinned", "player": mine[1], "x": 3.0, "z": 0.0})
	ctx.check("pin client: event pin replaces my other pin", one.get_pin(mine[1]) == {"x": 3.0, "z": 0.0} and one.get_pin(mine[0]).is_empty())
	one._pin_event({"type": "card_unpinned", "player": mine[1]})
	ctx.check("pin client: card_unpinned clears", one.get_pin(mine[1]).is_empty())
	var ui := CardPin.new()
	ui.session = one
	ui.owner_ids = one.own_cards()
	ui._on_selected(room.fighters_of(2)[0])
	ctx.check("pin client: tapping a squad-mate card does not select it", ui.selected_id() == -1)
	ui._on_selected(mine[0])
	ctx.check("pin client: own card selects", ui.selected_id() == mine[0])
	ui.free()
	one.server_state.meta.party = {"lobby": true}
	ctx.check("pin client: no pin in the lobby", one.set_pin(mine[0], 0.0, 0.0).is_empty())
