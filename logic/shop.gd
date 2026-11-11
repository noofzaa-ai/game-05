extends RefCounted
## Fixed-price camp merchant. Catalog and costs come only from server-owned data.
const ItemSystem := preload("res://logic/item_system.gd")
const PATH := "res://data/items/shop.json"
static var _config := {}

static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
			var price := float(parsed.get("price", -1))
			if is_finite(price) and price >= 1 and price <= 2147483647 and price == floorf(price): _config = parsed
	return _config

static func stock(rules, camp) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cfg := config()
	if cfg.is_empty(): return result
	if cfg.get("include_catalog", false) or not cfg.get("catalog_items", []).is_empty():
		var ids: Array = rules.catalog.items.keys(); ids.sort()
		for id in ids:
			if not cfg.get("include_catalog", false) and id not in cfg.get("catalog_items", []): continue
			var entry: Dictionary = rules.catalog.items[id]
			result.append({"sku": "item:" + str(id), "id": str(id), "kind": "item", "name": entry.name, "slot": entry.slot, "price": int(cfg.price)})
	if cfg.get("include_materials", false):
		var ids: Array = camp.materials.keys(); ids.sort()
		for id in ids:
			result.append({"sku": "material:" + str(id), "id": str(id), "kind": "material", "name": camp.materials[id].name, "price": int(cfg.price)})
	return result

static func buy(profile, rules, camp, sku: String, rng: RandomNumberGenerator) -> Dictionary:
	var product := {}
	for offer in stock(rules, camp):
		if offer.sku == sku: product = offer; break
	if product.is_empty(): return {"ok": false, "reason": "invalid_product"}
	var price := int(product.price)
	if profile.stash.gold < price: return {"ok": false, "reason": "cannot_afford"}
	if product.kind == "material":
		if profile.stash.room_for(product.id) < 1: return {"ok": false, "reason": "stash_full"}
		if profile.stash.add_material(product.id, 1) != 1: return {"ok": false, "reason": "stash_full"}
	else:
		if profile.stash.free_slots() < 1: return {"ok": false, "reason": "stash_full"}
		var tier := int(config().get("equipment_tier", -1))
		if tier < 0 or tier >= rules.tiers.size(): return {"ok": false, "reason": "not_configured"}
		var used := {}
		for item in profile.stash.items + profile.vault.items: used[item.id] = true
		for list in profile.worn_lists():
			for item in list: used[item.id] = true
		var instance_id := ""
		for attempt in 16:
			var candidate := "shop-%d-%d" % [rng.seed, rng.state]
			rng.randi()
			if not used.has(candidate): instance_id = candidate; break
		if instance_id.is_empty(): return {"ok": false, "reason": "conflict"}
		var entry: Dictionary = rules.catalog.entry(product.id)
		var piece = ItemSystem.create_item(rules, instance_id, entry.slot, tier, rng, entry.weapon_type, product.id)
		if piece == null: return {"ok": false, "reason": "invalid_product"}
		if not profile.stash.add_item(piece): return {"ok": false, "reason": "stash_full"}
	# All capacity/config checks have passed; one unit and its price commit together.
	profile.stash.gold -= price
	return {"ok": true, "sku": sku, "price": price, "count": 1}


## Sale quotes and proceeds are authority-owned. Client expected_price only prevents stale quotes.
static func _sell_price(value: Variant) -> int:
	if not (value is int or value is float): return 0
	var number := float(value)
	return int(number) if is_finite(number) and number >= 1 and number <= 2147483647 and number == floorf(number) else 0

static func item_sell_price(item, rules) -> int:
	if item == null or item.tier < 0 or item.tier >= rules.tiers.size(): return 0
	var tuning = config().get("sell", {})
	if not tuning is Dictionary: return 0
	var prices = tuning.get("equipment_by_tier", [])
	if not prices is Array or item.tier >= prices.size(): return 0
	return _sell_price(prices[item.tier])

static func material_sell_price(camp, material: String, count: int) -> int:
	if not camp.materials.has(material) or count < 1 or count > int(camp.materials[material].get("stack", 99)): return 0
	var tuning = config().get("sell", {})
	if not tuning is Dictionary: return 0
	var price := _sell_price(tuning.get("material_per_unit", 0))
	if price < 1 or price > floori(2147483647.0 / float(count)): return 0
	return price * count

static func sell_item(profile, rules, id: String, expected_price: int) -> Dictionary:
	var at := -1
	for index in profile.stash.items.size():
		if profile.stash.items[index].id == id: at = index; break
	if at < 0: return {"ok": false, "reason": "item_not_in_container"}
	var price := item_sell_price(profile.stash.items[at], rules)
	if price < 1: return {"ok": false, "reason": "not_sellable"}
	if expected_price != price: return {"ok": false, "reason": "price_changed"}
	if profile.stash.gold < 0 or profile.stash.gold > 2147483647 - price: return {"ok": false, "reason": "gold_limit"}
	# No yield: remove one existing owned instance and credit its server-computed price together.
	profile.stash.take_item(at)
	profile.stash.gold += price
	return {"ok": true, "item": id, "price": price, "count": 1}

static func sell_material(profile, camp, id: String, count: int, expected_price: int) -> Dictionary:
	if not camp.materials.has(id): return {"ok": false, "reason": "invalid_material"}
	if count < 1 or count > profile.stash.stack_size(id) or count > profile.stash.material_count(id): return {"ok": false, "reason": "invalid_count"}
	var price := material_sell_price(camp, id, count)
	if price < 1: return {"ok": false, "reason": "not_sellable"}
	if expected_price != price: return {"ok": false, "reason": "price_changed"}
	if profile.stash.gold < 0 or profile.stash.gold > 2147483647 - price: return {"ok": false, "reason": "gold_limit"}
	profile.stash.remove_material(id, count)
	profile.stash.gold += price
	return {"ok": true, "material": id, "count": count, "price": price}


## Validate the entire batch before changing any item, material or Gold.
static func sell_batch(profile, rules, camp, entries: Array, expected_price: int) -> Dictionary:
	if entries.is_empty() or entries.size() > 64: return {"ok": false, "reason": "invalid_command"}
	var seen := {}
	var take_indices: Array[int] = []
	var materials := {}
	var total := 0
	for entry in entries:
		if not entry is Dictionary or not entry.get("kind") is String or not entry.get("id") is String:
			return {"ok": false, "reason": "invalid_command"}
		if entry.id.is_empty() or entry.id.length() > 256: return {"ok": false, "reason": "invalid_command"}
		var key: String = entry.kind + ":" + entry.id
		if seen.has(key): return {"ok": false, "reason": "invalid_command"}
		seen[key] = true
		var price := 0
		if entry.kind == "item":
			if entry.size() != 2: return {"ok": false, "reason": "invalid_command"}
			var at := -1
			for index in profile.stash.items.size():
				if profile.stash.items[index].id == entry.id: at = index; break
			if at < 0:
				for owned in profile.vault.items + profile.worn_items():
					if owned.id == entry.id: return {"ok": false, "reason": "item_not_in_container"}
				return {"ok": false, "reason": "item_not_owned"}
			price = item_sell_price(profile.stash.items[at], rules)
			take_indices.append(at)
		elif entry.kind == "material":
			if entry.size() != 3 or not (entry.get("count") is int or entry.get("count") is float): return {"ok": false, "reason": "invalid_command"}
			var number := float(entry.count)
			if not is_finite(number) or number < 1 or number > 2147483647 or number != floorf(number): return {"ok": false, "reason": "invalid_count"}
			var count := int(number)
			if count > profile.stash.material_count(entry.id): return {"ok": false, "reason": "invalid_count"}
			var unit := material_sell_price(camp, entry.id, 1)
			if unit < 1: return {"ok": false, "reason": "not_sellable"}
			if count > floori(2147483647.0 / float(unit)): return {"ok": false, "reason": "gold_limit"}
			price = unit * count
			materials[entry.id] = count
		else: return {"ok": false, "reason": "invalid_command"}
		if price < 1: return {"ok": false, "reason": "not_sellable"}
		if total > 2147483647 - price: return {"ok": false, "reason": "gold_limit"}
		total += price
	if total != expected_price: return {"ok": false, "reason": "price_changed"}
	if profile.stash.gold < 0 or profile.stash.gold > 2147483647 - total: return {"ok": false, "reason": "gold_limit"}
	take_indices.sort()
	take_indices.reverse()
	for index in take_indices: profile.stash.take_item(index)
	for id in materials: profile.stash.remove_material(id, int(materials[id]))
	profile.stash.gold += total
	return {"ok": true, "price": total, "items": take_indices.size(), "materials": materials}
