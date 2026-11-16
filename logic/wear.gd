extends RefCounted
## Equipment wears out with use: armor when its wearer takes damage, the weapon when it lands hits,
## everything when the wearer dies. A worn item gives lower stats (see ItemRules.durability_factor)
## until it is repaired at camp. Each function returns true when the wearer's stats changed, so the
## simulation knows to recompute them.

const Item := preload("res://logic/item.gd")
const ItemRules := preload("res://logic/item_rules.gd")
const Loadout := preload("res://logic/loadout.gd")


## The wearer took `damage` (of `max_hp`): every worn non-weapon item loses a proportional share.
static func damage_taken(loadout: Loadout, rules: ItemRules, damage: float, max_hp: float) -> bool:
	var before := _factor_sum(loadout, rules)
	var points := rules.armor_wear_per_full_hp * damage / maxf(max_hp, 1.0)
	for item in loadout.items():
		if item.slot != "weapon":
			_lose(item, points, rules)
	return not is_equal_approx(before, _factor_sum(loadout, rules))


## The wearer landed a hit: the weapon loses a little.
static func hit_landed(loadout: Loadout, rules: ItemRules) -> bool:
	var before := _factor_sum(loadout, rules)
	var weapon := loadout.item_at("weapon", 0)
	if weapon != null and not weapon.destroyed:
		_lose(weapon, rules.weapon_wear_per_hit, rules)
	return not is_equal_approx(before, _factor_sum(loadout, rules))


## The wearer died: every worn item loses a fixed amount.
static func death(loadout: Loadout, rules: ItemRules) -> bool:
	var before := _factor_sum(loadout, rules)
	for item in loadout.items():
		_lose(item, rules.death_wear, rules)
	return not is_equal_approx(before, _factor_sum(loadout, rules))


## Hard guarantee (Boss 2026-11-16): per run an item loses at most rules.max_loss_per_run_fraction of its max
## durability, whatever the damage and deaths. Item.run_wear counts what it lost this run (reset by Run.start).
static func _lose(item: Item, points: float, rules: ItemRules) -> void:
	var loss := minf(maxf(points, 0.0), item.durability)
	if rules.max_loss_per_run_fraction >= 0.0:
		loss = minf(loss, maxf(0.0, rules.max_loss_per_run_fraction * item.max_durability - item.run_wear))
	item.durability -= loss
	item.run_wear += loss


## A run starts: every item of the profile begins with a clean wear tracker.
static func reset_run(profile) -> void:
	var lists: Array = [profile.worn_items(), profile.stash.items]
	for list in lists:
		for item in list:
			item.run_wear = 0.0


static func _factor_sum(loadout: Loadout, rules: ItemRules) -> float:
	var total := 0.0
	for item in loadout.items():
		total += rules.durability_factor(item.durability_ratio())
	return total
