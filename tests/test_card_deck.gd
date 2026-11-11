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
	ctx.check("the starter squad is three cards", deck["squad"] == ["sword_shield", "greatsword", "longbow"])
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var profile = Profile.new_player(rules, camp, rng)
	ctx.check("a new profile has a valid deck", Deck.validate(profile.card_deck, cosmetics) == "")
	var state := {"profile": profile, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}
	var ok: Dictionary = Commands.apply(state, {"type": "card_look", "class": "greatsword", "part": "hair", "choice": "e"}, rng)
	ctx.check("the card_look command changes the card", ok.get("ok", false) and profile.card_deck["cards"]["greatsword"]["hair"] == "e")
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
