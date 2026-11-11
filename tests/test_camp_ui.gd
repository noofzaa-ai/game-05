extends RefCounted
## Tests the camp and rest-point screens by pressing their real buttons.

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CampScreen := preload("res://client/camp_screen.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")


func _buttons(node: Node, found: Array = []) -> Array:
	if node is Button and node.is_inside_tree():
		found.append(node)
	for child in node.get_children():
		_buttons(child, found)
	return found


func _button_starting(screen: Node, text: String) -> Button:
	for button in _buttons(screen):
		if (button as Button).text.begins_with(text):
			return button
	return null


func _text_anywhere(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for child in node.get_children():
		if _text_anywhere(child, needle):
			return true
	return false


func _frames(ctx, count: int = 2) -> void:
	for i in count:
		await ctx.process_frame


func run(ctx) -> void:
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	if not (rules.is_valid() and camp.is_valid() and combat.is_valid()):
		ctx.check("the data loads for the camp screen test", false)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	profile.stash.capacity = 40

	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat)
	await _frames(ctx)
	var tabs: Array = screen._tabs.get_children().map(func(child: Node) -> String: return str(child.name))
	ctx.check("the camp screen has its tabs: Inventory, Look, Repair, Camp", tabs == ["Inventory", "Look", "Repair", "Camp"])
	ctx.check("it shows the wallet (gold and materials)", screen._wallet_text().contains("Gold %d" % profile.stash.gold) and screen._wallet_text().contains("Ore"))
	ctx.check("the resource bar has an icon and a number per currency (store, gold, %d materials)" % camp.materials.size(), screen._wallet.get_child(0).get_child_count() == 2 + camp.materials.size())
	ctx.check("the inventory shows the weapon's attack speed", _text_anywhere(screen, "Attack speed:") and _text_anywhere(screen, "Fighting style: Sword"))
	# (wearing, taking off and discarding are tested in test_gear_panel.gd)

	# Repair.
	var shirt = profile.loadout.item_at("shirt")
	shirt.durability = 40.0
	profile.stash.gold = 10000
	profile.stash.add_material("ore", 40)
	screen._refresh()
	await _frames(ctx)
	var gold_before: int = profile.stash.gold
	var repair := _button_starting(screen, "Repair")
	ctx.check("a worn piece has a Repair button", repair != null and _text_anywhere(screen, "gold"))
	for button in _buttons(screen):
		if (button as Button).text == "Repair" and not (button as Button).disabled:
			button.pressed.emit()
			break
	await _frames(ctx)
	ctx.check("pressing Repair restores it and costs gold", shirt.durability == shirt.max_durability and profile.stash.gold < gold_before)
	profile.loadout.item_at("weapon").durability = 0.0
	screen._refresh()
	await _frames(ctx)
	ctx.check("a broken-down piece is flagged on the screen", _text_anywhere(screen, "BROKEN DOWN") and _text_anywhere(screen, "(broken down!)"))

	# Camp upgrades.
	profile.stash.gold = 100000
	profile.stash.capacity = 200
	for i in 3:
		profile.stash.add_material("ore", 99)
	screen._refresh()
	await _frames(ctx)
	var up := _button_starting(screen, "Upgrade camp")
	ctx.check("the camp tab offers a camp upgrade", up != null and not up.disabled)
	up.pressed.emit()
	await _frames(ctx)
	ctx.check("pressing it raises the camp level", profile.camp_level == 2 and _text_anywhere(screen, "Camp level 2"))
	ctx.check("the skills the new level unlocked are marked", _text_anywhere(screen, "[x] Hardy Camp"))
	screen.queue_free()
	await _frames(ctx)

	# At a rest point.
	var rest_profile = Profile.new_player(rules, camp, rng)
	var trip = Run.start(rest_profile, camp)
	trip.bag.add_item(ItemSystem.create_item(rules, "found-shirt", "shirt", 3, rng))
	trip.bag.gold = 55
	var rest: CanvasLayer = CampScreen.new()
	ctx.root.add_child(rest)
	rest.setup(rest_profile, camp, rules, combat, trip, "spot")
	var events := {"gear": 0, "rest": 0, "retreat": 0, "closed": 0}
	rest.gear_changed.connect(func() -> void: events["gear"] += 1)
	rest.rest_requested.connect(func() -> void: events["rest"] += 1)
	rest.retreat_requested.connect(func() -> void: events["retreat"] += 1)
	rest.closed.connect(func() -> void: events["closed"] += 1)
	await _frames(ctx)
	ctx.check("the rest screen has Inventory and Rest tabs and shows the bag", rest._pages.keys() == ["Rest"] and rest.gear != null and rest._wallet_text().contains("Bag 1/") and rest._wallet_text().contains("Gold 55"))
	rest._tabs.current_tab = 1
	await _frames(ctx)
	_button_starting(rest, "Rest here").pressed.emit()
	await _frames(ctx)
	ctx.check("the Rest button asks the stage to heal", events["rest"] == 1)
	trip.used_rests.append("spot")
	rest._refresh()
	await _frames(ctx)
	ctx.check("a used rest point cannot heal again", _button_starting(rest, "Rest here").disabled)
	ctx.check("a plain rest point (no journey) has no bank button", _button_starting(rest, "Store the bag") == null)
	_button_starting(rest, "Return to camp").pressed.emit()
	await _frames(ctx)
	ctx.check("Return to camp asks the stage to take the loot home", events["retreat"] == 1)

	await _journey_camp(ctx, rules, camp, combat, rng)


## The journey camp's "Store the bag in the stash" button (Boss 2026-10-13; replaces the stage's B key).
func _journey_camp(ctx, rules, camp, combat, rng: RandomNumberGenerator) -> void:
	var loot = LootDataLoader.load_default(camp.materials.keys(), rules.tiers.size())
	var data = JourneyData.load_by_id("ink_road", combat.enemies.keys())
	var camper = Profile.new_player(rules, camp, rng)
	var journey = Journey.start(data, Run.start(camper, camp), rules, loot, combat.weapon_ids, 7)
	journey.state = Journey.AT_NODE  # (stand at a camp node: the path itself is tested in test_journey.gd)
	journey.current = {"stage": 5, "kind": "camp", "map": ""}
	var trip = journey.run
	trip.bag.add_item(ItemSystem.create_item(rules, "found-shirt", "shirt", 3, rng))
	trip.bag.add_item(ItemSystem.create_item(rules, "found-pants", "pants", 2, rng))
	trip.bag.gold = 40
	trip.bag.add_material("ore", 3)
	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(camper, camp, rules, combat, trip, "journey_camp_5", journey)
	var banked: Array = []
	screen.bag_banked.connect(func(summary: Dictionary) -> void: banked.append(summary))
	screen._tabs.current_tab = 1
	await _frames(ctx)
	var bank := _button_starting(screen, "Store the bag in the stash")
	ctx.check("a journey camp's Rest tab has a 'Store the bag in the stash' button, enabled with loot in the bag",
		bank != null and not bank.disabled and _text_anywhere(screen, "Safe from death; the bag empties."))
	ctx.check("the bank button is a touch-size target (>= 44 units tall)", bank != null and bank.custom_minimum_size.y >= 44.0)
	var stash_items: int = camper.stash.items.size()
	var stash_gold: int = camper.stash.gold
	bank.pressed.emit()
	await _frames(ctx, 3)
	ctx.check("pressing it stores the bag in the stash (items, gold, materials) and empties the bag",
		trip.bag.is_empty() and camper.stash.items.size() == stash_items + 2 and camper.stash.gold == stash_gold + 40 and camper.stash.material_count("ore") >= 3)
	ctx.check("it tells the stage what was stored (bag_banked) and the journey goes on", banked.size() == 1 and int(banked[0]["items"]) == 2 and journey.state == Journey.AT_NODE)
	ctx.check("a short confirmation shows the count stored", _text_anywhere(screen, "Stored in the stash: 2 items, 40 gold, 3 materials."))
	ctx.check("the item list and the wallet refresh (the bag shows empty)", screen._wallet_text().contains("Bag 0/") and screen._wallet_text().contains("Gold 0") and screen.gear.run.bag.items.is_empty())
	bank = _button_starting(screen, "Store the bag in the stash")
	ctx.check("with the bag empty the button is disabled and says why", bank != null and bank.disabled and _text_anywhere(screen, "the bag is empty"))
	bank.pressed.emit()
	await _frames(ctx)
	ctx.check("a disabled bank press does nothing", banked.size() == 1)

	# The camp rules say no: shown, disabled, with the reason.
	data.camp_banks_bag = false
	trip.bag.gold = 12
	screen._refresh()
	await _frames(ctx)
	bank = _button_starting(screen, "Store the bag in the stash")
	ctx.check("when the journey's camps cannot bank, the button is disabled with the reason", bank != null and bank.disabled and _text_anywhere(screen, "This camp cannot store the bag"))
	data.camp_banks_bag = true
	ctx.check("the summary line names what stayed behind when the stash was full",
		CampScreen.bank_summary_text({"items": 1, "gold": 0, "materials": {}, "left_items": 2}) == "Stored in the stash: 1 item. 2 item(s) stayed in the bag: the stash is full.")
	screen.queue_free()
	await _frames(ctx)
