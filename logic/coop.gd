extends RefCounted
## Explicit-party rules only. No extra input bit: remain idle near an ally for the configured hold.
const Fighter := preload("res://logic/fighter.gd")
const Effects := preload("res://logic/effects.gd")

static func down(sim, id: int, event: Dictionary) -> void:
	var fighter: Fighter = sim.fighters[id]
	fighter.state = Fighter.State.DOWNED
	fighter.state_ticks = 0
	fighter.downed_at = sim.tick_count
	fighter.bleedout_left = int(sim.combat.coop["downed_ticks"])
	fighter.revive_progress = 0
	fighter.reviver = -1
	fighter.move_id = ""
	fighter.buffered = ""
	fighter.running = false
	fighter.hitstop = 0
	fighter.launched = false
	fighter.dodge_left = 0
	sim.bodies[id].knockback = Vector2.ZERO
	sim.bodies[id].velocity.x = 0
	sim.bodies[id].velocity.z = 0
	Effects.clear(fighter, sim.combat)
	event["type"] = "downed"  # do not show terminal death or lose the bag yet
	event["player"] = id
	event["left"] = fighter.bleedout_left


static func step(sim) -> void:
	if not sim.coop_enabled or sim._coop["wiped"]:
		return
	var ids: Array = sim._coop["players"]
	var active := ids.filter(func(id): return sim.fighters.has(id) and sim.fighters[id].is_alive())
	if active.is_empty():
		sim._coop["wiped"] = true
		for id in ids:
			if sim.fighters.has(id) and not sim.fighters[id].eliminated:
				_eliminate(sim, id, "team_wiped")
		sim.events.append({"type": "team_wiped", "players": ids.duplicate()})
		return
	var claimed := {}
	for id in ids:
		if not sim.fighters.has(id): continue
		var downed: Fighter = sim.fighters[id]
		if downed.state != Fighter.State.DOWNED: continue
		if downed.downed_at == sim.tick_count: continue  # full configured interval starts next tick
		downed.bleedout_left -= 1
		if downed.bleedout_left <= 0:
			_eliminate(sim, id, "bleedout")
			continue
		var helper := -1
		for candidate in active:
			if claimed.has(candidate): continue
			var fighter: Fighter = sim.fighters[candidate]
			var input = sim._inputs[candidate]
			if fighter.state != Fighter.State.IDLE or not sim.bodies[candidate].grounded or input.move.length() > .1 or input.jump or input.light or input.heavy or input.special or input.ultimate or input.dodge:
				continue
			var offset: Vector3 = sim.bodies[candidate].position - sim.bodies[id].position
			if offset.length() <= float(sim.combat.coop["revive_radius"]):
				helper = candidate
				break
		if helper < 0:
			downed.reviver = -1
			downed.revive_progress = 0
			continue
		claimed[helper] = true  # one helper cannot revive multiple allies at once
		if downed.reviver != helper: downed.revive_progress = 0
		downed.reviver = helper
		downed.revive_progress += 1
		if downed.revive_progress >= int(sim.combat.coop["revive_ticks"]):
			downed.state = Fighter.State.IDLE
			downed.state_ticks = 0
			downed.hp = downed.max_hp() * float(sim.combat.coop["revive_hp_fraction"])
			downed.invulnerable_left = int(sim.combat.coop["revive_invulnerable_ticks"])
			downed.bleedout_left = 0
			downed.revive_progress = 0
			downed.reviver = -1
			sim.events.append({"type": "revived", "player": id, "by": helper})


static func _eliminate(sim, id: int, reason: String) -> void:
	var fighter: Fighter = sim.fighters[id]
	fighter.state = Fighter.State.DEAD
	fighter.hp = 0
	fighter.eliminated = true
	fighter.bleedout_left = 0
	fighter.revive_progress = 0
	fighter.reviver = -1
	sim._finalize_player_death(id)
	sim.events.append({"type": "eliminated", "player": id, "reason": reason})
