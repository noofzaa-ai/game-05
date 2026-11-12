extends RefCounted
## Races (design/gdd/races-and-classes.md 3.3-3.7, phase 1): race files load with strict validation, every card
## carries a race (old saves get their class's starter race), and only the server command `card_race` changes it.
const RaceData := preload("res://logic/race_data.gd")
const Deck := preload("res://logic/card_deck.gd")
const Cosmetics := preload("res://logic/cosmetic_options.gd")
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const Runner := preload("res://server/profile/runner.gd")

const FIXTURE := "user://test_races_fixture/"


func run(ctx) -> void:
	_game_races_load(ctx)
	_bad_files_fail(ctx)
	_card_race(ctx)
	_synergy_pick(ctx)


func _game_races_load(ctx) -> void:
	var races = RaceData.load_default()
	ctx.check("race data loads without errors %s" % [races.errors], races.errors.is_empty())
	ctx.check("the four races, in order", races.ids() == ["human", "viking", "elf", "runeborn"])
	ctx.check("every race has all four class cells (no warnings) %s" % [races.warnings], races.warnings.is_empty())
	var complete := true
	for race in races.ids():
		var data: Dictionary = races.races[race]
		complete = complete and data.get("default_class", {}).get("passive") is Dictionary
		complete = complete and data["synergy"].get("2") is Dictionary and data["synergy"].get("3") is Dictionary
		for class_id in Deck.classes():
			complete = complete and not races.passive_for(race, class_id).get("effects", []).is_empty()
	ctx.check("each race: 4 class passives, a default passive, synergy 2 and 3", complete)
	ctx.check("starter races (Boss 2026-11-13): S&S Human, GS Viking, Bow Elf, Magic Runeborn",
		races.starter_race("sword_shield") == "human" and races.starter_race("greatsword") == "viking"
		and races.starter_race("longbow") == "elf" and races.starter_race("magic") == "runeborn")
	ctx.check("a class without a cell gets the race's default passive", races.passive_for("elf", "no_such_class")["name"] == "Lifebloom")


## Writes rules.json + one race file into a fresh fixture folder and loads it.
func _load_with(race: Dictionary, rules_patch: Dictionary = {}):
	DirAccess.make_dir_recursive_absolute(FIXTURE)
	for file in DirAccess.get_files_at(FIXTURE):
		DirAccess.remove_absolute(FIXTURE + file)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/rules.json"))
	rules["starter_races"] = {}
	rules["default_race"] = str(race.get("id", "x"))
	rules.merge(rules_patch, true)
	FileAccess.open(FIXTURE + "rules.json", FileAccess.WRITE).store_string(JSON.stringify(rules))
	FileAccess.open(FIXTURE + str(race.get("id", "x")) + ".json", FileAccess.WRITE).store_string(JSON.stringify(race))
	return RaceData.load_from(FIXTURE)


func _race_with(effects: Array) -> Dictionary:
	var race: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/elf.json"))
	race["id"] = "testrace"
	race["classes"]["longbow"]["passive"]["effects"] = effects
	return race


func _bad_files_fail(ctx) -> void:
	var good = _load_with(_race_with([{"type": "trigger", "on": "kill", "actions": [{"action": "apply_status", "status": "rage", "target": "self"}]}]))
	ctx.check("a sound fixture race loads %s" % [good.errors], good.errors.is_empty() and good.has_race("testrace"))
	var cases := {
		"unknown effect type": [{"type": "explode", "power": 9.0}],
		"unknown event": [{"type": "trigger", "on": "sneeze", "actions": [{"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.1}]}],
		"unknown action": [{"type": "trigger", "on": "kill", "actions": [{"action": "teleport", "target": "self"}]}],
		"unknown status": [{"type": "trigger", "on": "kill", "actions": [{"action": "apply_status", "status": "petrify", "target": "self"}]}],
		"unknown target": [{"type": "trigger", "on": "kill", "actions": [{"action": "apply_status", "status": "rage", "target": "everyone"}]}],
		"unknown stat": [{"type": "stat_mod", "stat": "LUCK", "mul": 0.1}],
		"unknown charges event": [{"type": "charges", "gain_on": ["hit", "nap"], "max": 3.0, "actions": [{"action": "apply_status", "status": "focus", "target": "self"}]}],
		"empty actions": [{"type": "trigger", "on": "kill", "actions": []}],
	}
	for name in cases:
		var bad = _load_with(_race_with(cases[name]))
		ctx.check("a race file with an %s fails the load" % name, not bad.errors.is_empty())
	var no_synergy := _race_with([{"type": "stat_mod", "stat": "HEALING", "mul": 0.1}])
	no_synergy["synergy"].erase("3")
	ctx.check("a race without synergy.3 fails the load", not _load_with(no_synergy).errors.is_empty())
	var bad_starter = _load_with(_race_with([{"type": "stat_mod", "stat": "ATK", "mul": 0.1}]), {"starter_races": {"longbow": "dwarf"}})
	ctx.check("a starter race that does not exist fails the load", not bad_starter.errors.is_empty())
	var missing_cell := _race_with([{"type": "stat_mod", "stat": "ATK", "mul": 0.1}])
	missing_cell["classes"].erase("magic")
	var warned = _load_with(missing_cell)
	ctx.check("a missing class cell only warns", warned.errors.is_empty() and not warned.warnings.is_empty())


func _card_race(ctx) -> void:
	var cosmetics = Cosmetics.load_default()
	var deck := Deck.initial(cosmetics)
	ctx.check("new cards carry their starter race", deck["cards"]["sword_shield"]["race"] == "human" and deck["cards"]["greatsword"]["race"] == "viking" and deck["cards"]["longbow"]["race"] == "elf" and deck["cards"]["magic"]["race"] == "runeborn")
	ctx.check("the look carries the race", Deck.look_of(deck, "longbow")["race"] == "elf")
	ctx.check("set_race accepts a known race", Deck.set_race(deck, "sword_shield", "elf") and Deck.race_of(deck, "sword_shield") == "elf" and Deck.validate(deck, cosmetics) == "")
	ctx.check("set_race refuses an unknown race or class", not Deck.set_race(deck, "sword_shield", "dwarf") and not Deck.set_race(deck, "nope", "elf") and Deck.race_of(deck, "sword_shield") == "elf")
	ctx.check("card_look cannot change the race", not Deck.set_look(deck, "sword_shield", "race", "viking", cosmetics))
	var bad_saved := Deck.initial(cosmetics)
	bad_saved["cards"]["magic"]["race"] = "dwarf"
	ctx.check("a saved unknown race makes the card invalid", Deck.validate(bad_saved, cosmetics) == "bad_card")
	var repaired := Deck.repaired(bad_saved, cosmetics)
	ctx.check("repair: a removed race falls back to the default race and keeps the card", repaired["cards"]["magic"]["race"] == "human" and repaired["cards"]["magic"]["hair"] == bad_saved["cards"]["magic"]["hair"])

	# Old save: cards without a race stay valid and read as their class's starter race.
	var rules = ItemRulesLoader.load_default()
	var camp = CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	var old_save: Dictionary = profile.to_dict()
	for class_id in old_save["card_deck"]["cards"]:
		old_save["card_deck"]["cards"][class_id].erase("race")
	old_save["card_deck"]["cards"]["greatsword"]["hair"] = "e"  # an own choice that must survive
	var migrated = Profile.from_dict(old_save, rules, camp)
	ctx.check("old save: the deck is valid without races", migrated != null and Deck.validate(migrated.card_deck, cosmetics) == "")
	ctx.check("old save: each card reads its starter race", migrated != null and Deck.squad_races(migrated.card_deck) == ["human", "viking", "elf"] and Deck.race_of(migrated.card_deck, "magic") == "runeborn")
	ctx.check("old save: the cards keep their own choices", migrated != null and migrated.card_deck["cards"]["greatsword"]["hair"] == "e")

	# The server command.
	var state := {"profile": profile, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}
	var ok: Dictionary = Commands.apply(state, {"type": "card_race", "class": "longbow", "race": "viking"}, rng)
	ctx.check("card_race switches a card's race", ok.get("ok", false) and Deck.race_of(profile.card_deck, "longbow") == "viking")
	var bad: Dictionary = Commands.apply(state, {"type": "card_race", "class": "longbow", "race": "dwarf"}, rng)
	ctx.check("card_race rejects an unknown race", not bad.get("ok", true) and bad.get("error") == "invalid_race" and Deck.race_of(profile.card_deck, "longbow") == "viking")
	ctx.check("card_race rejects an unknown class", Commands.apply(state, {"type": "card_race", "class": "bard", "race": "elf"}, rng).get("error") == "invalid_race")
	ctx.check("card_race rejects a missing field or wrong type", not Commands.apply(state, {"type": "card_race", "class": "longbow"}, rng).get("ok", true) and not Commands.apply(state, {"type": "card_race", "class": "longbow", "race": 3}, rng).get("ok", true))
	state["location"] = "stage"
	ctx.check("card_race is refused during a fight", not Commands.apply(state, {"type": "card_race", "class": "longbow", "race": "elf"}, rng).get("ok", true) and Deck.race_of(profile.card_deck, "longbow") == "viking")
	var copy = Profile.from_dict(profile.to_dict(), rules, camp)
	ctx.check("the race survives save and load", copy != null and Deck.race_of(copy.card_deck, "longbow") == "viking")
	ctx.check("the online server allows card_race", Runner.ALLOWED.has("card_race"))


func _synergy_pick(ctx) -> void:
	var races = RaceData.load_default()
	ctx.check("synergy AAA -> Trio", races.synergy_for(["elf", "elf", "elf"])["kind"] == "trio" and races.synergy_for(["elf", "elf", "elf"])["race"] == "elf")
	ctx.check("synergy AAB -> Pair(A)", races.synergy_for(["viking", "elf", "viking"])["kind"] == "pair" and races.synergy_for(["viking", "elf", "viking"])["race"] == "viking")
	ctx.check("synergy ABC -> Alliance", races.synergy_for(["human", "viking", "elf"])["kind"] == "alliance" and races.synergy_for(["human", "viking", "elf"])["effects"].size() == 2)
	ctx.check("synergy solo -> none", races.synergy_for(["human"])["kind"] == "none")
	ctx.check("synergy duo AA -> Pair", races.synergy_for(["runeborn", "runeborn"])["kind"] == "pair")
	ctx.check("synergy duo AB -> none", races.synergy_for(["human", "elf"])["kind"] == "none")
