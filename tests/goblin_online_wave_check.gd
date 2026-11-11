extends SceneTree

func _initialize() -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var loot = preload("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(), rules.tiers.size())
	var combat = preload("res://logic/combat_data_loader.gd").load_default()
	var data = preload("res://logic/journey_data.gd").load_by_id("ink_road", combat.enemies.keys())
	var rng := RandomNumberGenerator.new()
	var profile = preload("res://logic/profile.gd").new_player(rules, camp, rng)
	var room = preload("res://server/rooms/room.gd").create([{ "id": 1, "profile": profile.to_dict() }], 123, {"rules": rules, "camp": camp, "loot": loot, "combat": combat, "journey": data, "enable_goblin_wave_lab": true})
	assert(room != null and room.goblin_waves != null)
	for wave in range(1, 12):
		assert(room.goblin_waves.wave == wave and room.sim.living_enemy_count() > 0)
		for id in room.sim.fighters:
			if room.sim.fighters[id].team == "enemy":
				room.sim.fighters[id].hp = 0
				room.sim.fighters[id].state = preload("res://logic/fighter.gd").State.DEAD
		room._tick_goblin_waves()
		room.clock_tick += 150
		room._tick_goblin_waves()
		if wave in [3, 6, 9]:
			assert(room.goblin_waves.phase == "chest" and room.journey.treasure_pending)
			assert(room._open_goblin_chest(1))
			assert(not room._open_goblin_chest(1))
	assert(room.journey.is_at_camp() and room.status == "camp")
	var chest_ids := {}
	for earned in room.trip_for(1).bag.items:
		assert(not chest_ids.has(earned.id))
		chest_ids[earned.id] = true
	assert(chest_ids.size() == 3)
	var enter_boss: Dictionary = room.command(1, 1, {"type": "journey_choose", "index": 0})
	assert(enter_boss.get("ok", false) and room.journey.current.kind == "boss")
	assert(room.goblin_waves == null and room.sim.living_enemy_count() > 0)
	var second = preload("res://logic/profile.gd").new_player(rules, camp, rng)
	var party = preload("res://server/rooms/room.gd").create([{ "id": 1, "profile": profile.to_dict() }, { "id": 2, "profile": second.to_dict() }], 456, {"rules": rules, "camp": camp, "loot": loot, "combat": combat, "journey": data, "enable_goblin_wave_lab": true})
	assert(party != null and party.sim.coop_enabled)
	for wave in range(1, 4):
		for id in party.sim.fighters:
			if party.sim.fighters[id].team == "enemy":
				party.sim.fighters[id].hp = 0
				party.sim.fighters[id].state = preload("res://logic/fighter.gd").State.DEAD
		party._tick_goblin_waves()
		party.clock_tick += 150
		party._tick_goblin_waves()
	assert(party.goblin_waves.phase == "chest")
	var original_position: Vector3 = party.sim.bodies[1].position
	party.sim.bodies[1].position += Vector3(10, 0, 0)
	assert(not party._open_goblin_chest(1))
	party.sim.bodies[1].position = original_position
	assert(party._open_goblin_chest(1))
	assert(party.trip_for(1).bag.items.size() == 1 and party.trip_for(2).bag.items.size() == 1)
	assert(not party._open_goblin_chest(1))
	print("Goblin online room flow passed")
	quit()
