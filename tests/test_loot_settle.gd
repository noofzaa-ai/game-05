extends RefCounted
## QA 2026-11-19: a won run's gear must reach the stash even when the stash is full (the run bag is never saved).
const F := preload("res://tests/online_fixture.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Run := preload("res://logic/run.gd")
const Profile := preload("res://logic/profile.gd")


func _piece(rules, id: String):
	return ItemSystem.create_item(rules, id, "shirt", 0, F.rng(3), "", "armour_longbow_shirt")


func run(ctx) -> void:
	var f := F.make(77)
	for fill in [0, 20, 38, 40]:
		var profile = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(5)))
		while profile.stash.items.size() > fill: profile.stash.items.pop_back()
		var n := 0
		while profile.stash.items.size() < fill:
			profile.stash.items.append(_piece(f.rules, "starter-filler-%d" % n)); n += 1
		var cap_before: int = profile.stash.capacity
		var before: int = profile.stash.items.size()
		var trip = Run.start(profile, f.camp)
		for i in 9:
			ctx.check("loot settle: drop %d fits the bag (fill %d)" % [i, fill], trip.loot_into_bag({"gold": 3, "materials": {"ore": 2}, "items": [_piece(f.rules, "drop-%d-%d" % [fill, i])]})["lost_items"].is_empty())
		var summary: Dictionary = trip.return_to_camp()
		ctx.check("loot settle: all 9 items reach the stash (fill %d)" % fill, profile.stash.items.size() == before + 9 and trip.bag.items.is_empty() and summary["left_items"] == 0 and summary["items"] == 9)
		ctx.check("loot settle: capacity never below the items held (fill %d)" % fill, profile.stash.capacity >= profile.stash.items.size() and profile.stash.capacity >= cap_before)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.to_dict()))
		var back = Profile.from_dict(saved, f.rules, f.camp)
		ctx.check("loot settle: the saved profile reloads with every item (fill %d)" % fill, back != null and back.stash.items.size() == before + 9)
		ctx.check("loot settle: a second return brings nothing twice (fill %d)" % fill, trip.return_to_camp()["items"] == 0 and profile.stash.items.size() == before + 9)
