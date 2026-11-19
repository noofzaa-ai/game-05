extends RefCounted
## Race gear drops (design/gdd/race-gear-sets.md 3.12; design/gdd/drops-and-rewards.md 3.8; Boss 2026-11-13). Pure rules.
## Boss 2026-11-16: only the WEAPON is a race piece (race x class); armour becomes the CLASS armour of a squad card (any race
## wears it, ItemCatalog.race_piece); the shield stays the race shield. The race share therefore matters for weapons only.
## Race pieces add no rolls: a piece that already dropped (per-kill item, wave chest) keeps its tier and slot, and with
## the share in data/loot/race_drops.json for (source, wave, tier) it BECOMES the race piece of one squad card's race and
## class (uniform pick among the squad that played; an offhand becomes that card's race shield). Boss 2026-11-13 (old item
## system removed): every share is 1.0, so every armour/weapon drop is the piece of a squad card. Gold (legendary) shares
## exist only for the boss; a tier the source has no share for, listed in the file's `downgrade`, drops one tier lower
## (a wave or chest gold becomes purple, PO default 2026-11-13).
## The draw uses its own generator seeded from the item id, so the combat/loot stream is the same with or without it.
## Boss 2026-11-20 ("random everything"): the file's `pick` block says HOW race and class are drawn. "uniform" (now) = uniform
## over every race (data/races) / class (data/classes), independent of the squad; "squad" = the old rule (one squad card,
## uniform). Weapon = random race x random class; offhand = random race shield; armour = class armour of a random class (it
## has no race). See _piece_id for the fixed draw order. A run with no squad card still converts nothing (every mode).

const ItemSystem := preload("res://logic/item_system.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const GearLevels := preload("res://logic/gear_levels.gd")
const UNIFORM := "uniform"
const SQUAD := "squad"
const PATH := "res://data/loot/race_drops.json"

const WAVE := "wave"
const CHEST := "chest"
const BOSS := "boss"

static var _cached: Dictionary = {}


## The parsed data file ({} when missing or broken: then nothing converts).
static func data() -> Dictionary:
	if _cached.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		_cached = parsed if parsed is Dictionary else {"slots": []}
	return _cached


## The share (0..1) that a piece of `tier_id` from `source` at `wave` becomes a race piece.
static func share(source: String, wave: int, tier_id: String, d: Dictionary = {}) -> float:
	if d.is_empty():
		d = data()
	if source == BOSS:
		return float(d.get("boss_shares", {}).get(tier_id, 0.0))
	for bracket in d.get(source + "_shares", []):
		if wave <= int(bracket.get("to_wave", 0)):
			return float(bracket.get("shares", {}).get(tier_id, 0.0))
	return 0.0


## True when `enemy_type` is a boss (data/races/rules.json boss_types).
static func is_boss_type(enemy_type: String) -> bool:
	return RaceData.load_default().rules.get("boss_types", []).has(enemy_type)


## The squad cards a race piece can be made for: [{"race", "class"}], one per squad card of `run` (a SquadMember's
## whole squad, else the run's own card). [] for a run with no card (old single-profile runs): nothing converts.
static func picks_for(run) -> Array:
	if run == null:
		return []
	var members: Array = run.squad if "squad" in run and run.squad is Array and not run.squad.is_empty() else [run]
	var out: Array = []
	for member in members:
		var card := str(member.card_id) if "card_id" in member else ""
		if card.is_empty() or member.profile == null:
			continue
		out.append({"race": CardDeck.gear_race(member.profile.card_deck, card), "class": card})
	return out


## `item` turned into a race piece with the share for (source, wave, its tier), else `item` unchanged.
## The new piece keeps the id, slot and tier (unless downgraded); its stats are rolled again for the race catalog item.
## `cap` = the profile unlocked gear level (logic/gear_levels.gd; default 1 = the safe low value): the result never needs
## more than that level (level 1 = the same piece with a "starter-drop-" instance id).
static func convert_piece(rules, item, picks: Array, source: String, wave: int, cap: int = 1):
	return GearLevels.fit(rules, _convert(rules, item, picks, source, wave), cap)


static func _convert(rules, item, picks: Array, source: String, wave: int):
	if item == null or picks.is_empty() or not data().get("slots", []).has(item.slot):
		return item
	var tier := clampi(int(item.tier), 0, rules.tiers.size() - 1)
	var tier_id := str(rules.tiers[tier]["id"])
	var chance := share(source, wave, tier_id)
	var lower := str(data().get("downgrade", {}).get(tier_id, ""))
	if chance <= 0.0 and not lower.is_empty():  # e.g. a gold piece outside the boss: one tier down, then that tier's share
		for index in rules.tiers.size():
			if str(rules.tiers[index]["id"]) == lower:
				tier = index
		chance = share(source, wave, str(rules.tiers[tier]["id"]))
	if chance <= 0.0:
		return item
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["race_drop", item.id, source, wave])
	if rng.randf() >= chance:
		return item
	var piece_id := _piece_id(rules, rng, picks, str(item.slot))
	if piece_id.is_empty():
		return item
	var piece = ItemSystem.create_item(rules, item.id, item.slot, tier, rng, "", piece_id)
	return piece if piece != null else item


## The mode ("uniform" or "squad") of `which` ("race" / "class") from the file's `pick` block (default uniform).
static func pick_mode(which: String, d: Dictionary = {}) -> String:
	if d.is_empty():
		d = data()
	return str(d.get("pick", {}).get(which, UNIFORM))


## The catalog piece id for a drop of `slot`, race and class drawn per the `pick` modes ("" when the catalog has none).
## Draw order (same rng on client and server): [squad card, only if a mode is "squad"], race (weapon/offhand only), class
## (weapon/armour only). Armour is class armour (race-free), so it draws no race; the shield draws no class.
static func _piece_id(rules, rng: RandomNumberGenerator, picks: Array, slot: String) -> String:
	var squad_pick: Dictionary = {}
	if pick_mode("race") == SQUAD or pick_mode("class") == SQUAD:
		squad_pick = picks[rng.randi_range(0, picks.size() - 1)]
	var race := ""
	if slot == "weapon" or slot == "offhand":
		if pick_mode("race") == SQUAD:
			race = str(squad_pick["race"])
		else:
			var races: Array = RaceData.load_default().ids().filter(func(r): return _has_piece(rules, str(r), slot))
			if races.is_empty():
				return ""
			race = str(races[rng.randi_range(0, races.size() - 1)])
	if slot == "offhand":
		return rules.catalog.race_shield(race)
	var klass := ""
	if pick_mode("class") == SQUAD:
		klass = str(squad_pick["class"])
	else:
		var classes: Array = CardDeck.classes().filter(func(c): return not rules.catalog.race_piece(race if slot == "weapon" else "", str(c), slot).is_empty())
		if classes.is_empty():
			return ""
		klass = str(classes[rng.randi_range(0, classes.size() - 1)])
	return rules.catalog.race_piece(race, klass, slot)


## True when the catalog has a piece of `race` for `slot` (weapon: for some class; offhand: the shield).
static func _has_piece(rules, race: String, slot: String) -> bool:
	if slot == "offhand":
		return not rules.catalog.race_shield(race).is_empty()
	for c in CardDeck.classes():
		if not rules.catalog.race_piece(race, str(c), slot).is_empty():
			return true
	return false


## Every item of `items` through convert_piece() (same order, same count).
static func apply(rules, items: Array, picks: Array, source: String, wave: int, cap: int = 1) -> Array:
	return items.map(func(item): return convert_piece(rules, item, picks, source, wave, cap))
