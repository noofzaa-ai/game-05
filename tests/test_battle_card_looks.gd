extends RefCounted
## Boss 2026-11-17 (staging battle): a hero fought with no shoes / no shirt while the hub card showed all four pieces.
## The room snapshot's own profile (server/rooms/snapshot_cache.gd) has no card_deck / card_gear, so the client's
## netfox_session decoded a profile whose cards were rebuilt: starter race/looks/level and a starter kit that skips every
## starter id the stash still holds (the player's old starter shirt and shoes) -> those body slots were EMPTY.
## online_session.adopt_cards gives the decoded profile the signed-in account's cards (GameState.attach_online_room).
const F := preload("res://tests/online_fixture.gd")
const Profile := preload("res://logic/profile.gd")
const Deck := preload("res://logic/card_deck.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const OnlineSession := preload("res://client/session/online_session.gd")
const Cache := preload("res://server/rooms/snapshot_cache.gd")
const SLOTS := ["shirt", "armband", "pants", "shoes"]


func _battle_looks(profile, card: String, rules) -> Dictionary:  # stage_view._player_looks, squad-room branch
	var loadout = profile.loadout_of(card)
	return ItemAssets.looks(loadout, rules.catalog, card, Deck.gear_race(profile.card_deck, card))


func _empty_slots(looks: Dictionary) -> Array:
	return SLOTS.filter(func(slot): return str(looks.get(slot, "")).is_empty())


func run(ctx) -> void:
	var f := F.make()
	var rules = f.rules
	var account = f.profile
	Deck.set_race(account.card_deck, "longbow", "runeborn")  # a race the player picked (not the starter elf)
	Deck.set_squad(account.card_deck, ["longbow", "magic", "greatsword"])
	# The player wore level-15 class pieces on the Longbow; its starter shirt and shoes went to the stash.
	var worn = account.loadout_of("longbow")
	for slot in ["shirt", "shoes"]:
		var old = worn.unequip(slot, 0)
		ctx.check("fixture: longbow starts with its starter %s" % slot, old != null and str(old.id).begins_with("starter-"))
		account.stash.items.append(old)
		var better = ItemSystem.create_item(rules, "tier-up-test-" + slot, slot, 1, F.rng(), "", "armour_longbow_" + slot)
		ctx.check("fixture: level-15 %s equips" % slot, better != null and worn.equip(better))
	for card in ["longbow", "magic", "greatsword"]:
		ctx.check("hub card %s wears all four body pieces" % card, _empty_slots(_battle_looks(account, card, rules)).is_empty())

	# What the room sends us about ourselves.
	var cache := Cache.new()
	cache.begin()
	var raw: Dictionary = cache.profile(account).duplicate(true)
	cache.end()
	var bare = Profile.from_dict(raw, rules, f.camp)
	ctx.check("room snapshot profile decodes", bare != null)
	if raw.has("card_gear") or raw.has("card_deck"):
		ctx.check("snapshot now carries the cards itself (adopt_cards stays a no-op)", true)
	else:
		ctx.check("cause: without the account's cards the battle Longbow lost body pieces", not _empty_slots(_battle_looks(bare, "longbow", rules)).is_empty())
	var fixed = Profile.from_dict(raw, rules, f.camp)
	OnlineSession.adopt_cards(fixed, account, raw, rules)
	for card in ["longbow", "magic", "greatsword"]:
		var looks := _battle_looks(fixed, card, rules)
		ctx.check("battle %s wears all four body pieces" % card, _empty_slots(looks).is_empty())
		ctx.check("battle %s wears the same pieces as the hub card" % card, looks == _battle_looks(account, card, rules))
	ctx.check("battle keeps the card's race", Deck.race_of(fixed.card_deck, "longbow") == "runeborn")
	ctx.check("battle keeps the card look", Deck.look_of(fixed.card_deck, "longbow") == Deck.look_of(account.card_deck, "longbow"))
	# A copy, not an alias: the room session never edits the account's own loadouts.
	ctx.check("adopted loadouts are copies", not is_same(fixed.loadout_of("longbow"), account.loadout_of("longbow")))
	fixed.loadout_of("longbow").unequip("shoes", 0)
	ctx.check("account loadout untouched by the session copy", account.loadout_of("longbow").item_at("shoes", 0) != null)
	# A snapshot that brings its own cards wins.
	var with_cards: Dictionary = account.to_dict()
	var own = Profile.from_dict(with_cards, rules, f.camp)
	var other = F.make(5).profile
	OnlineSession.adopt_cards(own, other, with_cards, rules)
	ctx.check("snapshot with cards is left alone", Deck.race_of(own.card_deck, "longbow") == "runeborn")
	OnlineSession.adopt_cards(own, null, raw, rules)
	ctx.check("no account profile: nothing changes", Deck.race_of(own.card_deck, "longbow") == "runeborn")
