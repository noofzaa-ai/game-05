extends RefCounted
## Equipment tab filter (Boss 2026-11-16): the storage list shows only what the selected card can wear,
## using the same rule as the equip command (Profile.card_can_wear / wearable_items).
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var items: Array = []
	for id in rules.catalog.items:
		var e: Dictionary = rules.catalog.entry(id)
		var slot := str(e.get("slot", ""))
		if slot.is_empty():
			continue
		var item = ItemSystem.create_item(rules, "t-" + str(id), slot, 0, rng, "", str(id))
		if item != null:
			items.append(item)
	ctx.check("class filter: catalog yields items", items.size() > 20)
	var weapons: Array = items.filter(func(i): return i.slot == "weapon")
	var shields: Array = items.filter(func(i): return i.slot == "offhand")
	ctx.check("class filter: catalog has weapons and shields", weapons.size() > 3 and not shields.is_empty())
	for card in CLASSES:
		var shown: Array = Profile.wearable_items(card, items, rules)
		var agree := true
		for item in items:
			if shown.has(item) != Profile.slot_problem(card, item, rules).is_empty():
				agree = false
		ctx.check("class filter: %s list agrees with the equip rule" % card, agree)
		ctx.check("class filter: %s sees only its weapon families" % card, shown.all(func(i): return i.slot != "weapon" or Profile.weapon_families(card).has(i.weapon_type)))
		ctx.check("class filter: %s hides weapons of other classes" % card, shown.filter(func(i): return i.slot == "weapon").size() < weapons.size())
		ctx.check("class filter: %s keeps its own weapons" % card, shown.any(func(i): return i.slot == "weapon"))
		ctx.check("class filter: %s shields only for Sword & Shield" % card, shown.any(func(i): return i.slot == "offhand") == (card == "sword_shield"))
		ctx.check("class filter: %s keeps generic gear" % card, shown.any(func(i): return i.slot == "ring" or i.slot == "shirt"))
	ctx.check("class filter: no filter would show every item (old behaviour differs)", Profile.wearable_items("longbow", items, rules).size() < items.size())
