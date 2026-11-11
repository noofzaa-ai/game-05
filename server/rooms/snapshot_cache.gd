extends RefCounted
## Room-local immutable serialization cache. Exact source comparisons, never hash-based freshness.
## Keep item fields aligned with Item.to_dict; callers may only read cached dictionaries.
var _items := {}
var _inventories := {}
var _loadouts := {}
var _profiles := {}
var _used := {}

func begin() -> void:
	_used.clear()

func end() -> void:
	for store in [_items, _inventories, _loadouts, _profiles]:
		for key in store.keys():
			if not _used.has(key): store.erase(key)

static func freeze(value):
	if value is Dictionary:
		if value.is_read_only(): return value
		for child in value.values(): freeze(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only(): return value
		for child in value: freeze(child)
		value.make_read_only()
	return value

func item(value) -> Dictionary:
	var key: int = value.get_instance_id(); _used[key] = true
	var signature := [value.id, value.slot, value.tier, value.level, value.refine_level, value.upgrade_count, value.main_stat, value.weapon_type, value.item_id, value.substats, value.destroyed, value.durability, value.max_durability]
	if _items.has(key) and _items[key].signature == signature: return _items[key].data
	var data: Dictionary = freeze(value.to_dict())
	_items[key] = {"signature": signature.duplicate(true), "data": data}
	return data

func inventory(value) -> Dictionary:
	var key: int = value.get_instance_id(); _used[key] = true
	var entries := []
	for entry in value.items: entries.append(item(entry))
	var old: Dictionary = _inventories.get(key, {})
	var same_items: bool = not old.is_empty() and old.data.items.size() == entries.size()
	if same_items:
		for i in entries.size():
			if not is_same(old.data.items[i], entries[i]): same_items = false; break
	if same_items and old.gold == value.gold and old.data.capacity == value.capacity and old.data.materials == value.materials: return old.data
	var data: Dictionary = freeze({"v": 1, "capacity": value.capacity, "gold": str(value.gold), "materials": value.materials.duplicate(), "items": entries})
	_inventories[key] = {"data": data, "gold": value.gold}
	return data

func loadout(value) -> Dictionary:
	var key: int = value.get_instance_id(); _used[key] = true
	var entries := {}
	for slot in value._equipped: entries[slot] = item(value._equipped[slot])
	var old: Dictionary = _loadouts.get(key, {})
	var same: bool = not old.is_empty() and old.equipped.size() == entries.size()
	if same:
		for slot in entries:
			if not old.equipped.has(slot) or not is_same(old.equipped[slot], entries[slot]): same = false; break
	if same: return old
	var data: Dictionary = freeze({"v": 1, "equipped": entries})
	_loadouts[key] = data
	return data

func profile(value) -> Dictionary:
	var key: int = value.get_instance_id(); _used[key] = true
	var stash := inventory(value.stash); var vault := inventory(value.vault); var worn := loadout(value.loadout)
	var fields := {"v": 1, "diamonds":value.diamonds, "mall_owned":value.mall_owned, "farm":value.farm, "camp_level": value.camp_level, "facility_levels": value.facility_levels, "appearance": value.appearance, "name": value.name, "created": value.created, "beta_kit_version": value.beta_kit_version, "armor_migration_version": value.armor_migration_version, "bonus_stash_slots": value.bonus_stash_slots, "skill_build": value.skill_build, "relics": value.relics}
	var old: Dictionary = _profiles.get(key, {})
	if not old.is_empty() and is_same(old.data.stash, stash) and is_same(old.data.vault, vault) and is_same(old.data.loadout, worn) and old.fields == fields: return old.data
	fields = fields.duplicate(true)
	var data := fields.duplicate()
	data["stash"] = stash; data["vault"] = vault; data["loadout"] = worn
	_profiles[key] = {"fields": fields, "data": freeze(data)}
	return data
