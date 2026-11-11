extends SceneTree
func _initialize() -> void:
 var runner = preload("res://server/profile/runner.gd").new()
 var rng = RandomNumberGenerator.new()
 var profile = preload("res://logic/profile.gd").new_player(runner.rules, runner.camp, rng)
 var item = profile.loadout._equipped.values()[0].duplicate_item()
 item.id = "treasure-123-1"
 profile.stash.items.append(item)
 var second = item.duplicate_item(); profile.stash.items.append(second)
 var before = second.to_dict()
 runner._repair_wave_chest_ids(profile)
 assert(item.id != second.id)
 var after = second.to_dict(); after.id = before.id
 assert(before == after)
 var snapshot = profile.to_dict()
 runner._repair_wave_chest_ids(profile)
 assert(snapshot == profile.to_dict())
 var price = preload("res://logic/shop.gd").item_sell_price(second, runner.rules)
 var gold = profile.stash.gold
 var result = preload("res://logic/commands.gd").apply({"profile":profile,"rules":runner.rules,"camp":runner.camp,"location":"camp"}, {"type":"shop_sell_batch","entries":[{"kind":"item","id":second.id}],"expected_price":price}, rng)
 assert(result.ok and profile.stash.gold == gold + price)
 print("MIGRATION PASS: distinct IDs; all stats retained; idempotent")
 quit()
