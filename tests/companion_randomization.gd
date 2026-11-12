extends SceneTree
func _initialize() -> void:
	var manager = preload("res://server/rooms/manager.gd").new()
	var roster = preload("res://logic/companions/roster.gd")
	var builds := {};var names := {};var weapons := {};var looks := {}
	for seed_value in range(100,132):
		var a = roster.make_profile("arun",manager.rules,manager.camp,seed_value)
		var b = roster.make_profile("arun",manager.rules,manager.camp,seed_value)
		assert(a.to_dict()==b.to_dict(),"reconnect must recreate same seeded identity")
		assert(a.stash.gold==0 and a.stash.items.is_empty() and a.vault.items.is_empty())
		assert(a.loadout.items().size()==6,str(a.loadout.to_dict()))
		for item in a.loadout.items():
			assert(not manager.rules.catalog.entry(item.item_id).is_empty() and item.tier<=2 and item.durability==item.max_durability)
		names[a.name]=true
		weapons[a.loadout.item_at("weapon",0).weapon_type]=true
		looks[JSON.stringify(a.appearance)]=true
	assert(names.size()>24 and builds.size()>24 and weapons.size()==5 and looks.size()>24)
	print("COMPANION RANDOMIZATION PASS:32seed deterministic rebuild, unique name/look/build, all5weapon families,6legal gear, no ownership grants")
	quit()
