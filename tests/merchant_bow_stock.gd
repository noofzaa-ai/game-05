extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
 var rules=preload("res://logic/item_rules_loader.gd").load_default()
 var camp=preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
 var shop=preload("res://logic/shop.gd")
 var offers=shop.stock(rules,camp)
 assert(offers.any(func(offer):return offer.sku=="item:bow_01"))
 var rng=RandomNumberGenerator.new();rng.seed=123
 var profile=preload("res://logic/profile.gd").new_player(rules,camp,rng)
 profile.stash.gold=2000
 var result=shop.buy(profile,rules,camp,"item:bow_01",rng)
 assert(result.get("ok",false))
 assert(profile.stash.gold==1000)
 assert(profile.stash.items.any(func(item):return item.item_id=="bow_01" and item.weapon_type=="bow"))
 assert(load("res://client/merchant_buy_panel.gd")!=null)
 print("MERCHANT BOW PASS: stock, purchase, gold deducted, bow identity, panel compilation")
 quit()
