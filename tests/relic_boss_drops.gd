extends SceneTree
const Relics := preload("res://logic/relics.gd")
const Run := preload("res://logic/run.gd")
func _initialize() -> void:
	var manager=preload("res://server/rooms/manager.gd").new()
	var rng := RandomNumberGenerator.new();rng.seed=934
	for enemy in manager.combat.enemies:
		if enemy!="goblin_chief":assert(Relics.roll(enemy,rng).is_empty(),"only Goblin boss drops relics")
	var seen := {}
	for n in 100:
		var drops := Relics.roll("goblin_chief",rng)
		assert(drops.size()==1 and Relics.catalog().has(drops[0].relic))
		assert(not seen.has(drops[0].id));seen[drops[0].id]=true
	var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
	var trip=Run.start(p,manager.camp)
	var drop={"gold":0,"materials":{},"items":[],"relics":Relics.roll("goblin_chief",rng)}
	assert(trip.loot_into_bag(drop).relics.size()==1 and p.relics.owned.is_empty())
	trip.loot_into_bag(drop);assert(trip.relic_loot.size()==1)
	var restored=Run.from_dict(trip.to_dict(),manager.rules,manager.camp)
	assert(restored!=null and restored.relic_loot==trip.relic_loot)
	restored.return_to_camp();assert(restored.profile.relics.owned.size()==1 and restored.relic_loot.is_empty())
	restored.return_to_camp();assert(restored.profile.relics.owned.size()==1)
	assert(Relics.equip(restored.profile,restored.profile.relics.owned[0].id,0).ok)
	trip.death();assert(p.relics.owned.size()==1)
	trip.death();assert(p.relics.owned.size()==1)
	var loss=Run.start(p,manager.camp);loss.loot_into_bag({"gold":0,"materials":{},"items":[],"relics":Relics.roll("goblin_chief",rng)})
	assert(loss.discard_loot().relics.size()==1 and loss.relic_loot.is_empty() and p.relics.owned.size()==1)
	# Exercise real multiplayer monster-death fanout, duplicate kill guard, and checkpoint restore.
	var p2=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
	assert(manager.create("relic-boss-contract",934,[{"id":1,"profile":p.to_dict()},{"id":2,"profile":p2.to_dict()}],true,2).ok)
	var room=manager.rooms["relic-boss-contract"].room
	var sim=room.sim
	sim.add_enemy(100,Vector3(2,0,2),"goblin_chief")
	sim._on_killed(100,1)
	assert(sim.runs[1].relic_loot.size()==1 and sim.runs[2].relic_loot.size()==1)
	sim._on_killed(100,1)
	assert(sim.runs[1].relic_loot.size()==1 and sim.runs[2].relic_loot.size()==1)
	sim.add_enemy(101,Vector3(2,0,3),"goblin");sim._on_killed(101,1)
	assert(sim.runs[1].relic_loot.size()==1)
	var saved: Dictionary=sim.snapshot()
	assert(sim.restore(saved,manager.camp))
	assert(sim.runs[1].relic_loot.size()==1)
	print("RELIC BOSS PASS: GoblinChief-only, one of2, unique instances, secure/abandon, owned equip, co-op per-player reward, duplicate kill guard, checkpoint")
	quit()
