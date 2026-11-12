extends SceneTree
const Roster := preload("res://logic/companions/roster.gd")
const InputFrame := preload("res://logic/sim_input.gd")
const Fighter := preload("res://logic/fighter.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var manager = preload("res://server/rooms/manager.gd").new()
	var rng := RandomNumberGenerator.new(); rng.seed = 100
	var human = preload("res://logic/profile.gd").new_player(manager.rules, manager.camp, rng)
	var companion = Roster.make_profile("arun", manager.rules, manager.camp)
	assert(companion != null)
	assert(companion.name == "อรุณ" and companion.stash.items.is_empty() and companion.stash.gold == 0)
	var profiles: Array = [{"id":1,"profile":human.to_dict()},{"id":4,"profile":companion.to_dict()}]
	assert(manager.create("companion-room-contract", 100, profiles, true, 4).ok)
	var room = manager.rooms["companion-room-contract"].room
	assert(room.install_companions([{"id":"arun","slot":4}]))
	room.require_scene_ready()
	assert(room._scene_waiting.keys() == [1])
	assert(not room.scene_ready(4, room.epoch) or not room._scene_waiting.has(4))
	assert(room.scene_ready(1, room.epoch) and not room.scene_loading())
	assert(room.party.members[4].ready and room.party.members.size() == 2)
	assert(not room.input(4, 1, InputFrame.new().encode()))
	assert(room.command(1, 1, {"type":"party_ready","ready":true}).ok)
	assert(room.command(1, 2, {"type":"party_depart"}).ok and room.depart())
	assert(room.sim.coop_enabled and room.sim.fighters[4].team == "player")
	assert(room._scene_waiting.keys() == [1])
	room.scene_ready(1, room.epoch)
	# Real shared combat: a fixed nearby target receives damage from companion inputs.
	for id in room.sim.fighters.keys():
		if room.sim.fighters[id].team == "enemy": room.sim.remove_player(id)
	room.sim._waves.clear()
	var at: Vector3 = room.sim.bodies[4].position
	room.sim.add_enemy(100, at + Vector3(1.1,0,0), "goblin")
	room.sim.fighters[100].stats["HP"] = 2000.0
	room.sim.fighters[100].hp = 2000.0
	var start_hp: float = room.sim.fighters[100].hp
	var hurt := false
	for tick in 300:
		room.tick()
		if room.sim.fighters[100].hp < start_hp: hurt = true; break
	assert(hurt, "companion must damage actual enemy through shared skill/combat")
	assert(room.sim.fighters[4].energy >= 0 and room.sim.fighters[4].energy <= room.sim.fighters[4].max_energy())
	# Existing co-op revive, with no extra bot heal path.
	room.sim.remove_player(100)
	room.sim.bodies[1].position = room.sim.bodies[4].position + Vector3(0.3,0,0)
	var downed = room.sim.fighters[1]
	preload("res://logic/coop.gd").down(room.sim, 1, {})
	for tick in int(manager.combat.coop.revive_ticks) + 240:
		# Prevent test fixture clear-victory while evaluating the actual revive rule.
		room.sim.set_input(4, room.companion_slots[4].think(room.sim,4))
		room.sim.set_input(1, InputFrame.new())
		room.sim.tick()
		if downed.is_alive(): break
	assert(downed.is_alive() and downed.hp > 0, "real revive completes")
	var saved: Dictionary = room.finalize()
	assert(saved.keys() == ["1"], "companion profile must never be submitted to account persistence")
	assert(room.human_ids() == [1])
	# Stage/lobby rebuild retains bot identity/readiness and reserves only human scene ACKs.
	var other = preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
	assert(manager.create("companion-rebuild-contract", 100, profiles, true, 4).ok)
	var rebuilt = manager.rooms["companion-rebuild-contract"].room
	assert(rebuilt.install_companions([{"id":"arun","slot":4}]))
	var joined: Array = rebuilt.owned_profiles(); joined.append({"id":2,"profile":other.to_dict()})
	assert(rebuilt.rebuild_lobby(joined))
	assert(rebuilt.companion_slots.has(4) and rebuilt.party.members[4].ready and rebuilt.human_ids().size() == 2)
	rebuilt.presence(1,false); rebuilt.presence(2,false)
	assert(not rebuilt.has_connected_humans())
	manager.advance(30.1)
	assert(not manager.rooms.has("companion-rebuild-contract"), "bots cannot keep an empty human room alive")
	print("COMPANION ROOM PASS: slot/readiness, actual damage/shared stamina, real revive, stage rebuild, human-only saves, empty-room cleanup")
	quit()
