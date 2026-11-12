extends RefCounted
## Trusted state: {profile, rules, camp, location: camp|rest|stage, run?, cosmetics?}.
## The session/server creates this context; a request may never supply its own context/rules.
## Item references are stable instance IDs. No rule mutations happen before validation.
const Camp := preload("res://logic/camp.gd")
const Profile := preload("res://logic/profile.gd")
const Repair := preload("res://logic/repair.gd")


static func apply(state: Dictionary, command: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	if not state.has_all(["profile", "rules", "camp", "location"]) or not state["profile"] is Profile:
		return _error("invalid_state")
	if not command.get("type") is String:
		return _error("invalid_command")
	var kind: String = command["type"]
	var schemas := {
		# "card" (optional, per-card gear, Boss 2026-11-11): the class card whose slots/build change. Missing =
		# the lead card (Profile.lead_card) with the old weapon-led skill rule, so older clients keep working.
		"equip": {"item": TYPE_STRING, "source": TYPE_STRING, "index": TYPE_INT, "card": TYPE_STRING},
		"unequip": {"slot": TYPE_STRING, "destination": TYPE_STRING, "index": TYPE_INT, "card": TYPE_STRING},
		"discard": {"item": TYPE_STRING, "source": TYPE_STRING},
		"discard_material": {"material": TYPE_STRING, "count": TYPE_INT, "source": TYPE_STRING},
		"repair": {"item": TYPE_STRING}, "repair_all": {"card": TYPE_STRING},
		"upgrade_camp": {}, "upgrade_facility": {"facility": TYPE_STRING},
		"appearance": {"part": TYPE_STRING, "choice": TYPE_STRING},
		"mall_buy": {"part": TYPE_STRING, "choice": TYPE_STRING},
		"card_fashion": {"class": TYPE_STRING, "part": TYPE_STRING, "choice": TYPE_STRING},
		"set_name": {"name": TYPE_STRING},
		"card_look": {"class": TYPE_STRING, "part": TYPE_STRING, "choice": TYPE_STRING}, "card_squad": {"squad": TYPE_ARRAY},
		"card_race": {"class": TYPE_STRING, "race": TYPE_STRING},  # design/gdd/races-and-classes.md 3.7: free switch (Boss 2026-11-13)
		"farm_seed": {"plot":TYPE_INT,"crop":TYPE_STRING}, "farm_plant": {"plot":TYPE_INT,"crop":TYPE_STRING}, "farm_harvest": {"plot":TYPE_INT},
		"shop_buy": {"sku": TYPE_STRING},
		"skill_build": {"action": TYPE_STRING, "build": TYPE_DICTIONARY, "card": TYPE_STRING},
		"relic_equip": {"relic":TYPE_STRING,"slot":TYPE_INT},
		"shop_sell": {"item": TYPE_STRING, "expected_price": TYPE_INT},
		"shop_sell_batch": {"entries": TYPE_ARRAY, "expected_price": TYPE_INT},
		"shop_sell_material": {"material": TYPE_STRING, "count": TYPE_INT, "expected_price": TYPE_INT},
		"refine": {"item": TYPE_STRING, "level": TYPE_INT},
		"storage_item": {"item": TYPE_STRING, "source": TYPE_STRING},
		"storage_material": {"material": TYPE_STRING, "count": TYPE_INT, "source": TYPE_STRING},
		"upgrade": {"item": TYPE_STRING, "count": TYPE_INT},
		"enhance": {"item": TYPE_STRING, "protect": TYPE_BOOL},
		"upgrade_tier": {"item": TYPE_STRING},
		"randomize_appearance": {}, "bank_bag": {}, "return_to_camp": {},
		"journey_choose": {"index": TYPE_INT}, "journey_leave": {}, "journey_abandon": {},
		"journey_retreat": {}, "journey_treasure": {}, "journey_finish": {}, "journey_camp_rest": {"point": TYPE_STRING},
	}
	if not schemas.has(kind):
		return _error("unknown_command")
	var schema: Dictionary = schemas[kind]
	for key in command:
		if key == "type":
			continue
		if not schema.has(key):
			return _error("invalid_command")
		# JSON has no integer type: accept integral finite JSON numbers for index/count only.
		var value = command[key]
		if schema[key] == TYPE_INT:
			if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value)) or float(value) != floorf(float(value)) or absf(float(value)) > 2147483647.0:
				return _error("invalid_command")
		elif typeof(value) != schema[key]:
			return _error("invalid_command")
	for key in schema:
		if not command.has(key) and not key in ["index", "protect", "card"]:
			return _error("invalid_command")
	var p: Profile = state["profile"]
	var card: String = command.get("card", "")
	if command.has("card") and not p.has_card(card):
		return _error("invalid_card")
	var location: String = state["location"]
	var trip = state.get("run")
	if not location in ["camp", "rest", "stage"]:
		return _error("invalid_state")
	if trip != null and trip.profile != p:
		return _error("invalid_state")
	var party_navigation: bool = state.get("journey") != null and state["journey"].has_method("player_ids") and kind in ["journey_choose", "journey_leave", "journey_treasure", "journey_camp_rest", "journey_retreat"]
	if not party_navigation and location != "camp" and (trip == null or trip.died) and not kind in ["journey_finish", "journey_abandon", "return_to_camp"]:
		return _error("trip_over")
	if kind.begins_with("journey_") or kind in ["bank_bag", "return_to_camp"]:
		return _journey_command(state, command)
	if kind == "relic_equip":
		if location != "camp": return _error("camp_only")
		return preload("res://logic/relics.gd").equip(p,command.relic,int(command.slot))
	if kind.begins_with("farm_"):
		if location != "camp": return _error("camp_only")
		return preload("res://logic/farm.gd").apply(p,command,int(state.get("now",0)))
	# Reject ambiguous IDs across ALL containers, including destroyed worn entries of EVERY card: an item is
	# in the shared stash/vault/bag or worn by exactly one card.
	var owned := {}
	var containers: Array = [p.stash.items, p.vault.items]
	containers.append_array(p.worn_lists())
	if trip != null:
		containers.append(trip.bag.items)
	for list in containers:
		for item in list:
			if item.id.is_empty() or owned.has(item.id):
				return _error("duplicate_item_id")
			owned[item.id] = item
	var item = owned.get(command.get("item", ""))
	if command.has("item") and item == null:
		return _error("item_not_owned")
	if item != null and p.vault.items.has(item) and kind != "storage_item":
		return _error("item_not_in_container")
	if kind in ["enhance", "upgrade_tier"]:
		# Boss decision 2026-10-17: disabled until server-owned prices/protection config exists.
		return _error("not_configured")
	var before: Dictionary = p.to_dict()
	var bag_before: Dictionary = trip.bag.to_dict() if trip != null else {}
	var result := {}
	match kind:
		"skill_build":
			if location != "camp": return _error("not_available_here")
			result = preload("res://logic/skill_build.gd").apply(p, command, card)
			if not result.get("ok", false): return _error(str(result.get("reason", "invalid_skill_build")))
		"equip", "unequip", "discard", "discard_material":
			var source: String = command.get("source", command.get("destination", ""))
			if not source in ["stash", "bag"]:
				return _error("invalid_container")
			if source == "bag" and trip != null and trip.died:
				return _error("trip_over")
			if (source == "stash" and location != "camp") or (source == "bag" and trip == null):
				return _error("not_available_here")
			if kind in ["equip", "unequip"] and location == "stage":
				return _error("not_available_here")
			var inventory = p.stash if source == "stash" else trip.bag
			var index := int(command.get("index", 0))
			if kind == "equip":
				var at: int = inventory.items.find(item)
				if at < 0:
					return _error("item_not_in_container")
				if item.destroyed:
					return _error("item_destroyed")
				var wear_problem := Profile.slot_problem(p.lead_card() if card.is_empty() else card, item, state["rules"])
				if not wear_problem.is_empty():
					return _error(wear_problem)  # slot_closed (offhand: Sword & Shield only) or wrong_weapon_family
				if item.slot == "weapon" and not preload("res://logic/skill_build.gd").can_equip(p, item.weapon_type, card):
					return _error("reskill_required")
				if source == "bag" and not card.is_empty() and card != p.lead_card():
					return _error("not_available_here")  # run bags dress the fighting character only (plan step 4)
				if not (p.equip_from_stash(at, index, card) if source == "stash" else trip.equip_from_bag(at, index)):
					return _error("invalid_slot")
				if item.slot == "weapon":
					preload("res://logic/skill_build.gd").follow_unspent_weapon(p, item.weapon_type, card)
			elif kind == "unequip":
				if command.slot == "weapon" and preload("res://logic/skill_build.gd").enabled():
					return _error("weapon_required")
				if source == "bag" and not card.is_empty() and card != p.lead_card():
					return _error("not_available_here")
				if p.loadout_of(card).item_at(command["slot"], index) == null:
					return _error("nothing_worn")
				if inventory.free_slots() < 1:
					return _error("bag_full")
				if source == "stash":
					p.unequip_to_stash(command["slot"], index, card)
				else:
					trip.unequip_to_bag(command["slot"], index)
			elif kind == "discard":
				var at: int = inventory.items.find(item)
				if at < 0:
					return _error("item_not_in_container")
				inventory.take_item(at)
			else:
				var count := int(command["count"])
				if count <= 0 or count > inventory.material_count(command["material"]):
					return _error("invalid_count")
				inventory.remove_material(command["material"], count)
		"mall_buy":
			if location != "camp": return _error("not_available_here")
			return preload("res://logic/mall.gd").buy(p,state.get("cosmetics"),command.part,command.choice)
		"card_fashion":
			if location != "camp": return _error("not_available_here")
			var worn_result: Dictionary = preload("res://logic/mall.gd").wear_on_card(p, state.get("cosmetics"), command["class"], command.part, command.choice)
			if not worn_result.get("ok", false): return _error(str(worn_result.get("reason", "invalid_cosmetic")))
		"card_look", "card_squad":
			if location != "camp": return _error("not_available_here")
			var deck_rules := preload("res://logic/card_deck.gd")
			if kind == "card_look":
				if not deck_rules.set_look(p.card_deck, command["class"], command["part"], command["choice"], state.get("cosmetics")):
					return _error("invalid_card")
			elif not deck_rules.set_squad(p.card_deck, command["squad"]):
				return _error("invalid_squad")
		"card_race":
			if location != "camp": return _error("not_available_here")
			if not command.has_all(["class", "race"]): return _error("invalid_command")
			if not preload("res://logic/card_deck.gd").set_race(p.card_deck, command["class"], command["race"]):
				return _error("invalid_race")
		"set_name", "appearance", "randomize_appearance":
			if location != "camp" and not (kind == "appearance" and command.get("part") == "fashion_display"):
				return _error("not_available_here")
			if kind == "set_name":
				var problem := Profile.name_problem(command["name"])
				if not problem.is_empty():
					return _error(problem)
				p.create_character(command["name"])
			elif kind == "randomize_appearance":
				if state.get("cosmetics") == null:
					return _error("invalid_appearance")
				var randomized: Dictionary = state["cosmetics"].random(_rng)
				for part in ["fashion","fashion_hat","fashion_back"]: randomized[part]=p.appearance.get(part,"none")
				randomized["blink_mode"]="auto"
				p.appearance = randomized
			else:
				var cosmetics = state.get("cosmetics")
				if command.part in ["fashion","fashion_hat","fashion_back"] and not preload("res://logic/mall.gd").owns(p,command.part,command.choice):return _error("cosmetic_not_owned")
				if command.part=="blink_mode" and command.choice!="auto":return _error("invalid_appearance")
				if cosmetics == null or not cosmetics.choose(p.appearance, command["part"], command["choice"]):
					return _error("invalid_appearance")
		_:
			if location != "camp":
				return _error("not_available_here")
			match kind:
				"storage_item": result = preload("res://logic/storage.gd").move_item(p, command.item, command.source)
				"storage_material": result = preload("res://logic/storage.gd").move_material(p, state["camp"], command.material, int(command.count), command.source)
				"shop_sell_batch": result = preload("res://logic/shop.gd").sell_batch(p, state["rules"], state["camp"], command.entries, int(command.expected_price))
				"shop_sell": result = preload("res://logic/shop.gd").sell_item(p, state["rules"], command.item, int(command.expected_price))
				"shop_sell_material": result = preload("res://logic/shop.gd").sell_material(p, state["camp"], command.material, int(command.count), int(command.expected_price))
				"shop_buy": result = preload("res://logic/shop.gd").buy(p, state["rules"], state["camp"], command.sku, _rng)
				"upgrade": result = preload("res://logic/upgrade.gd").apply(item, p, state["rules"], state["camp"], int(command.count), _rng)
				"refine": result = preload("res://logic/refine.gd").apply(item, p, state["rules"], state["camp"], int(command.level), _rng)
				"repair": result = Repair.repair(item, p, state["camp"])
				"repair_all": result = Repair.repair_all_worn(p, state["camp"], card)
				"upgrade_camp": result = Camp.upgrade_camp(p, state["camp"])
				"upgrade_facility": result = Camp.upgrade_facility(p, state["camp"], command["facility"])
			if result.has("ok") and not result["ok"]:
				return _error(str(result["reason"]))
	var changes := {}
	var after: Dictionary = p.to_dict()
	for key in after:
		if after[key] != before[key]:
			changes[key] = after[key]
	if trip != null and trip.bag.to_dict() != bag_before:
		changes["bag"] = trip.bag.to_dict()
	return {"ok": true, "changes": changes, "result": result}


static func _error(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}


## Journey economy is part of the same authority boundary as equipment commands.
static func _journey_command(state: Dictionary, request: Dictionary) -> Dictionary:
	var j = state.get("journey")
	var trip = state.get("run")
	var result := {}
	match request["type"]:
		"return_to_camp":
			if trip == null or j != null:
				return _error("not_available_here")
			result = trip.return_to_camp()
		_:
			if j == null or j.run != trip or j.run.profile != state["profile"]:
				return _error("no_journey")
			match request["type"]:
				"bank_bag":
					if not j.can_bank_bag(): return _error("not_available_here")
					result = j.bank_bag()
				"journey_choose":
					result = j.choose_next(int(request["index"]))
					if result.is_empty(): return _error("invalid_choice")
				"journey_leave":
					if j.state != j.AT_NODE: return _error("not_available_here")
					j.leave_node()
				"journey_abandon":
					if j.is_over() or j.state == j.IN_STAGE or j.is_at_camp(): return _error("not_available_here")
					result = j.abandon()
				"journey_retreat":
					if not j.is_at_camp(): return _error("not_available_here")
					result = j.retreat()
				"journey_treasure":
					result = j.open_treasure().duplicate(true)
					for key in ["items", "lost_items"]:
						if result.has(key): result[key] = result[key].map(func(item): return item.to_dict())
				"journey_camp_rest":
					if not j.is_at_camp() or request["point"] != "journey_camp_%d" % j.stage_number(): return _error("not_available_here")
					if not trip.used_rests.has(request["point"]): trip.used_rests.append(request["point"])
				"journey_finish":
					if not j.is_over(): return _error("not_available_here")
					if j.state == j.WON: result = j.finish_rewards() if j.has_method("finish_rewards") else j.run.return_to_camp()
	var changes := {"profile": state["profile"].to_dict()}
	if trip != null: changes["bag"] = trip.bag.to_dict()
	if j != null: changes["journey"] = j.to_dict()
	return {"ok": true, "changes": changes, "result": result}
