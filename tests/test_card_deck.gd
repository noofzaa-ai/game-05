extends RefCounted
## The class cards (logic/card_deck.gd): one card per class, each customised on its own, plus the squad.
const Deck := preload("res://logic/card_deck.gd")
const Cosmetics := preload("res://logic/cosmetic_options.gd")
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")


func run(ctx) -> void:
	var cosmetics = Cosmetics.load_default()
	var classes := Deck.classes()
	ctx.check("the four classes are the four cards, in order", classes == ["sword_shield", "greatsword", "longbow", "magic"])
	var deck := Deck.initial(cosmetics)
	ctx.check("a new deck is valid", Deck.validate(deck, cosmetics) == "")
	ctx.check("every class has its own card", deck["cards"].size() == classes.size())
	ctx.check("a new squad is empty until the race steps (tutorial.md 2)", deck["squad"].is_empty())
	for c in classes:
		Deck.set_race(deck, c, Deck.starter_race(c))
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	ctx.check("the starter cards differ", deck["cards"]["sword_shield"] != deck["cards"]["greatsword"])

	# One card changes, the others stay.
	var other_before: Dictionary = deck["cards"]["magic"].duplicate(true)
	ctx.check("a hair the class can wear is accepted", Deck.set_look(deck, "sword_shield", "hair", "b", cosmetics))
	ctx.check("a hair the class cannot wear is refused", not Deck.set_look(deck, "magic", "hair", "d", cosmetics))  # (hair D was retired in the Studio)
	ctx.check("an unknown class, part or choice is refused", not Deck.set_look(deck, "nope", "hair", "a", cosmetics) and not Deck.set_look(deck, "magic", "wings", "x", cosmetics) and not Deck.set_look(deck, "magic", "outfit", "gold", cosmetics))
	ctx.check("changing one card leaves the others alone", deck["cards"]["magic"] == other_before and deck["cards"]["sword_shield"]["hair"] == "b")
	ctx.check("outfit, makeup, eyes and skin can be set", Deck.set_look(deck, "magic", "outfit", "none", cosmetics) and Deck.set_look(deck, "magic", "makeup", "sharp_wing", cosmetics) and Deck.set_look(deck, "magic", "eye_color", "violet", cosmetics) and Deck.set_look(deck, "magic", "skin", "tan", cosmetics))
	ctx.check("a custom eye colour is a valid #rrggbb only", Deck.set_look(deck, "magic", "eye_color", "#A0B0C0", cosmetics) and deck["cards"]["magic"]["eye_color"] == "#a0b0c0" and not Deck.set_look(deck, "magic", "eye_color", "#zzzzzz", cosmetics))
	var look := Deck.look_of(deck, "magic")
	ctx.check("the look carries the card's choices", look["class"] == "magic" and look["silver"] == false and look["makeup"] == "sharp_wing" and look["skin"] == "tan")
	ctx.check("the deck stays valid after edits", Deck.validate(deck, cosmetics) == "")

	# PO defaults 2026-11-12 (docs/po_defaults.md): class armor starters, Studio iris styles.
	var fresh := Deck.initial(cosmetics)
	ctx.check("every starter card wears its class armor", classes.all(func(c): return fresh["cards"][c]["outfit"] == "none"))
	ctx.check("the iris styles are the Studio's seven", Deck.options("magic", "iris_style", cosmetics) == ["0", "1", "3", "6", "7", "9", "10"])
	ctx.check("a starter card has the Classic iris", fresh["cards"]["longbow"]["iris_style"] == "0" and Deck.look_of(fresh, "longbow")["iris_style"] == "0")
	ctx.check("an iris style brings its own eye colour", Deck.set_look(fresh, "longbow", "iris_style", "3", cosmetics) and fresh["cards"]["longbow"]["eye_color"] == "#ff562c" and Deck.look_of(fresh, "longbow")["iris_style"] == "3")
	ctx.check("an iris style not in the Studio is refused", not Deck.set_look(fresh, "longbow", "iris_style", "2", cosmetics) and fresh["cards"]["longbow"]["iris_style"] == "3")
	var older := Deck.initial(cosmetics)
	older["cards"]["greatsword"]["outfit"] = "silver"
	older["cards"]["greatsword"].erase("iris_style")
	var kept := Deck.repaired(older, cosmetics)
	ctx.check("an older saved card keeps its own outfit and gets the Classic iris", kept["cards"]["greatsword"]["outfit"] == "silver" and not kept["cards"]["greatsword"].has("iris_style") and Deck.look_of(kept, "greatsword")["iris_style"] == "0")

	# Hair colour (Studio #hair-color free input): "" = the hair's Studio default, else a #rrggbb.
	var tinted := Deck.initial(cosmetics)
	ctx.check("hair colour: a starter card has the Studio default", tinted["cards"]["magic"]["hair_color"] == "" and Deck.look_of(tinted, "magic")["hair_color"] == "")
	ctx.check("hair colour: any #rrggbb is accepted and stored lower case", Deck.set_look(tinted, "magic", "hair_color", "#3A5FCD", cosmetics) and tinted["cards"]["magic"]["hair_color"] == "#3a5fcd" and Deck.look_of(tinted, "magic")["hair_color"] == "#3a5fcd")
	ctx.check("hair colour: bad values are refused", not Deck.set_look(tinted, "magic", "hair_color", "#zzzzzz", cosmetics) and not Deck.set_look(tinted, "magic", "hair_color", "3a5fcd", cosmetics) and not Deck.set_look(tinted, "magic", "hair_color", "#3a5", cosmetics) and not Deck.set_look(tinted, "magic", "hair_color", "#3a5fcd00", cosmetics) and not Deck.set_look(tinted, "magic", "hair_color", "blue", cosmetics) and tinted["cards"]["magic"]["hair_color"] == "#3a5fcd")
	ctx.check("hair colour: \"\" resets to the Studio default", Deck.set_look(tinted, "magic", "hair_color", "", cosmetics) and tinted["cards"]["magic"]["hair_color"] == "")
	ctx.check("hair colour: works without the cosmetic lists too", Deck.set_look(tinted, "magic", "hair_color", "#112233", null) and Deck.validate(tinted, cosmetics) == "")
	var broken_tint := Deck.initial(cosmetics)
	broken_tint["cards"]["longbow"]["hair_color"] = "#nothex"
	ctx.check("hair colour: a saved bad value makes the card invalid", Deck.validate(broken_tint, cosmetics) == "bad_card")
	var pre_tint := Deck.initial(cosmetics)
	for c in classes:
		pre_tint["cards"][c].erase("hair_color")
	ctx.check("hair colour: an old save without it stays valid and keeps its cards", Deck.validate(pre_tint, cosmetics) == "" and Deck.repaired(pre_tint, cosmetics)["cards"]["greatsword"] == pre_tint["cards"]["greatsword"] and Deck.look_of(pre_tint, "greatsword")["hair_color"] == "")

	# Squad rules.
	ctx.check("a squad of one to three is allowed", Deck.set_squad(deck, ["longbow"]) and Deck.set_squad(deck, ["magic", "longbow", "sword_shield"]))
	ctx.check("a class twice, an unknown class, an empty or a fourth card are refused", not Deck.set_squad(deck, ["magic", "magic"]) and not Deck.set_squad(deck, ["ghost"]) and not Deck.set_squad(deck, []) and not Deck.set_squad(deck, classes + ["magic"]))
	ctx.check("a refused squad leaves the old squad", deck["squad"] == ["magic", "longbow", "sword_shield"])
	ctx.check("the squad looks come in squad order", Deck.squad_looks(deck).map(func(l): return l["class"]) == ["magic", "longbow", "sword_shield"])

	# Skills are reserved, not usable yet.
	var with_skill := deck.duplicate(true)
	with_skill["cards"]["magic"]["skills"] = ["fireball"]
	ctx.check("a card with skills is refused until skills exist", Deck.validate(with_skill, cosmetics) == "bad_card")
	ctx.check("a broken deck is repaired to valid", Deck.validate(Deck.repaired({"v": 1, "cards": {"magic": {"hair": "a"}}, "squad": ["magic", "magic"]}, cosmetics), cosmetics) == "")

	# The profile keeps it, saves it, and the server command changes it.
	var rules = ItemRulesLoader.load_default()
	var camp = CampDataLoader.load_default(rules.tiers.size())
	_starter_looks(ctx, rules, camp, cosmetics, classes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var profile = Profile.new_player(rules, camp, rng)
	ctx.check("a new profile has a valid deck", Deck.validate(profile.card_deck, cosmetics) == "")
	preload("res://tests/online_fixture.gd").past_tutorial(profile)  # races picked, Magic unlocked (tutorial.md 2)
	var state := {"profile": profile, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}
	var ok: Dictionary = Commands.apply(state, {"type": "card_look", "class": "greatsword", "part": "hair", "choice": "e"}, rng)
	ctx.check("the card_look command changes the card", ok.get("ok", false) and profile.card_deck["cards"]["greatsword"]["hair"] == "e")
	var tint_ok: Dictionary = Commands.apply(state, {"type": "card_look", "class": "greatsword", "part": "hair_color", "choice": "#C04080"}, rng)
	var tint_bad: Dictionary = Commands.apply(state, {"type": "card_look", "class": "greatsword", "part": "hair_color", "choice": "#C0408"}, rng)
	ctx.check("the card_look command sets a hair colour and refuses a bad one", tint_ok.get("ok", false) and not tint_bad.get("ok", true) and profile.card_deck["cards"]["greatsword"]["hair_color"] == "#c04080")
	var bad: Dictionary = Commands.apply(state, {"type": "card_look", "class": "greatsword", "part": "hair", "choice": "d"}, rng)
	ctx.check("a hair the class cannot wear is rejected by the server", not bad.get("ok", true) and bad.get("error") == "invalid_card")
	var squad_ok: Dictionary = Commands.apply(state, {"type": "card_squad", "squad": ["longbow", "magic"]}, rng)
	ctx.check("the card_squad command sets the squad", squad_ok.get("ok", false) and profile.card_deck["squad"] == ["longbow", "magic"])
	var squad_bad: Dictionary = Commands.apply(state, {"type": "card_squad", "squad": ["magic", "magic"]}, rng)
	ctx.check("a repeated class is rejected by the server", not squad_bad.get("ok", true) and profile.card_deck["squad"] == ["longbow", "magic"])
	state["location"] = "stage"
	ctx.check("cards cannot be changed during a fight", not Commands.apply(state, {"type": "card_squad", "squad": ["magic"]}, rng).get("ok", true))
	var copy = Profile.from_dict(profile.to_dict(), rules, camp)
	ctx.check("the deck survives save and load", copy != null and copy.card_deck == profile.card_deck)
	var old_save: Dictionary = profile.to_dict()
	old_save.erase("card_deck")
	var migrated = Profile.from_dict(old_save, rules, camp)
	ctx.check("an old save without cards gets the starter deck", migrated != null and Deck.validate(migrated.card_deck, cosmetics) == "")


## Boss 2026-11-13: a new player's cards each get their own eyes and makeup (Studio options), per seed.
func _starter_looks(ctx, rules, camp, cosmetics, classes: Array) -> void:
	var looks_of := func(seed_value: int) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var p = Profile.new_player(rules, camp, rng)
		var out := {}
		for c in classes:
			out[c] = p.card_deck["cards"][c].duplicate(true)
		return out
	var a: Dictionary = looks_of.call(11)
	var irises := {}
	var eyes := {}
	var sound := true
	for c in classes:
		irises[a[c]["iris_style"]] = true
		var tint := str(cosmetics.entry("eye_color", str(a[c]["eye_color"])).get("color", a[c]["eye_color"])).to_lower()
		eyes[tint] = true
		var starter := Deck.starter_card(c, cosmetics)
		sound = sound and a[c]["hair"] == starter["hair"] and a[c]["outfit"] == starter["outfit"] and a[c]["skin"] == starter["skin"]
		sound = sound and Deck.validate_card(c, a[c], cosmetics) == ""
	ctx.check("starter looks: every card has its own iris style (%s)" % [irises.keys()], irises.size() == classes.size())
	ctx.check("starter looks: every card has its own eye colour (%s)" % [eyes.keys()], eyes.size() == classes.size())
	ctx.check("starter looks: class hair, armor and skin are kept and every card is valid", sound)
	ctx.check("starter looks: same seed, same looks", looks_of.call(11) == a)
	var differs := false
	for s in [12, 13, 14, 15]:
		differs = differs or looks_of.call(s) != a
	ctx.check("starter looks: other seeds give other looks", differs)
	var hair_tints := {}
	for c in classes:
		hair_tints[str(a[c]["hair_color"])] = true
	var palette: Array = Deck.starter_hair_palette()
	var palette_hex := palette.map(func(e): return str(e["color"]).to_lower())
	ctx.check("starter looks: the hair palette is about ten curated colours", palette.size() >= 8 and palette.size() <= 12)
	ctx.check("starter looks: every card has its own palette hair colour (%s)" % [hair_tints.keys()], hair_tints.size() == classes.size() and hair_tints.keys().all(func(h): return palette_hex.has(h)))
	var whites_ok := true
	var hair_seeds_differ := false
	for s in range(30, 50):
		var l: Dictionary = looks_of.call(s)
		var whites := 0
		var seen := {}
		for c in classes:
			var hex := str(l[c]["hair_color"])
			seen[hex] = true
			for e in palette:
				if str(e["color"]).to_lower() == hex and bool(e.get("near_white", false)):
					whites += 1
		whites_ok = whites_ok and whites <= 1 and seen.size() == classes.size()
		hair_seeds_differ = hair_seeds_differ or classes.any(func(c): return l[c]["hair_color"] != a[c]["hair_color"])
	ctx.check("starter looks: 20 seeds give 4 distinct hair colours, at most one near-white", whites_ok)
	ctx.check("starter looks: hair colours change with the seed", hair_seeds_differ)
	var makeups := {}
	for s in range(20, 30):
		var l: Dictionary = looks_of.call(s)
		for c in classes:
			makeups[l[c]["makeup"]] = true
	ctx.check("starter looks: both card makeup sets are used (%s)" % [makeups.keys()], makeups.size() == Deck.MAKEUPS.size())
	var old = Profile.from_dict(JSON.parse_string(JSON.stringify(_old_save(rules, camp, cosmetics))), rules, camp)
	ctx.check("starter looks: a saved deck is not changed on load", old != null and old.card_deck == Deck.initial(cosmetics))


func _old_save(rules, camp, cosmetics) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var d: Dictionary = Profile.new_player(rules, camp, rng).to_dict()
	d["card_deck"] = Deck.initial(cosmetics)
	return d
