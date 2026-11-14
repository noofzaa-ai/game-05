extends RefCounted
## The player's class cards (Boss 2026-11-11, auto-battler): one card per class the game has (data/classes/),
## and every card is customised on its own (hair, outfit, eyes, skin, makeup). Skills will live on the card
## too; `skills` is reserved and stays empty until that system exists. The squad is the 1..SQUAD_MAX cards
## that go into the next fight (no class twice).
## Pure rules and plain data: no nodes, no client code. The client turns `look_of()` into a model.
## Saved in Profile.card_deck. The server validates every change (logic/commands.gd: card_look, card_squad).
##
## deck = {"v": 1, "cards": {class_id: card}, "squad": [class_id, ...]}
## card = {"hair": "a", "outfit": "none"|"silver", "eye_color": id or "#rrggbb", "skin": id or "#rrggbb",
##         "makeup": "anime_soft"|"sharp_wing"|"none", "iris_style": id of data/cosmetics/iris_styles.json,
##         "hair_color": "" (the hair's Studio default) or any "#rrggbb" (Studio #hair-color free input), "skills": [],
##         "race": a race id of data/races/ (design/gdd/races-and-classes.md 3.7; changed only by the card_race command),
##         "progress": {"level", "xp"} (design/gdd/skill-tree.md 3.2, logic/card_progress.gd; optional: missing = level 1,
##         changed only by the run-end XP grant),
##         "skill_tree": {"class": [node ids], "race": [...], "combo": [...]} (design/gdd/skill-tree.md 3.3, logic/skill_tree.gd;
##         optional: missing = nothing learned; changed only by the tree_* commands and card_race)}

const CLASS_FOLDER := "res://data/classes/"
const CLASS_ORDER: Array[String] = ["sword_shield", "greatsword", "longbow", "magic"]
const SQUAD_MAX := 3
const OUTFITS: Array[String] = ["none", "silver"]  ## none = the class armor (Studio "ชุดประจำคลาส"); silver = Silver Silk + class weapons
const MAKEUPS: Array[String] = ["anime_soft", "sharp_wing", "none"]  ## Studio eye-makeup.js: Anime Soft, Sharp Wing, Natural (Boss 2026-11-14)
const PARTS: Array[String] = ["hair", "outfit", "eye_color", "skin", "makeup", "iris_style", "hair_color"]
## Parts added after cards shipped: a saved card without them uses this value (the card stays valid).
const LATER_PARTS := {"iris_style": "0", "hair_color": ""}
## Starter flavour palette (Boss 2026-11-13): new cards draw distinct hair colours from it. Not an option list.
## The card's race (Boss 2026-11-13: any card may be any race, switchable any time). Not a look PART: card_look cannot
## change it, only the server-validated `card_race` command. A saved card without it is valid and uses its class's
## starter race (data/races/rules.json starter_races), like LATER_PARTS.
const RACE_PART := "race"
const RaceData := preload("res://logic/race_data.gd")
const CardProgress := preload("res://logic/card_progress.gd")
const STARTER_HAIR_COLORS := "res://data/cosmetics/starter_hair_colors.json"
## The card each class starts with. Every class starts in its class armor (outfit "none", PO default 2026-11-12,
## docs/po_defaults.md); saved cards keep their own choice.
const STARTERS := {
	"sword_shield": {"hair": "a", "outfit": "none"},
	"greatsword": {"hair": "c", "outfit": "none"},
	"longbow": {"hair": "e", "outfit": "none"},
	"magic": {"hair": "f", "outfit": "none"},
}
## The squad an old save falls back to (Boss 2026-11-11): Sword & Shield, Great Sword, Bow. A NEW player starts with an
## empty squad and raceless cards (design/gdd/tutorial.md 2); Magic is locked until wave 12 (logic/unlocks.gd).
const STARTER_SQUAD: Array[String] = ["sword_shield", "greatsword", "longbow"]

static var _class_cache := {}


## Every class id the game has, in card order.
static func classes() -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(CLASS_FOLDER):
		if file.ends_with(".json"):
			found.append(file.get_basename())
	var ordered: Array[String] = []
	for id in CLASS_ORDER:
		if found.has(id):
			ordered.append(id)
	found.sort()
	for id in found:
		if not ordered.has(id):
			ordered.append(id)
	return ordered


## The class file (data/classes/<id>.json), {} when missing or broken.
static func class_data(class_id: String) -> Dictionary:
	if not _class_cache.has(class_id):
		var path := CLASS_FOLDER + class_id + ".json"
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_class_cache[class_id] = parsed if parsed is Dictionary else {}
	return _class_cache[class_id]


## The hairs this class can wear (from its class file).
static func hair_options(class_id: String) -> Array:
	return class_data(class_id).get("hair_options", ["a"]).duplicate()


## What a card of this class can choose for `part`: a list of ids ("custom colour" is any "#rrggbb" for the
## colour parts, flagged in `custom`). `cosmetics` is a CosmeticOptions (eye and skin lists).
static func options(class_id: String, part: String, cosmetics) -> Array:
	match part:
		"hair": return hair_options(class_id)
		"outfit": return OUTFITS.duplicate()
		"makeup": return MAKEUPS.duplicate()
		"eye_color", "skin", "iris_style":
			var ids := []
			if cosmetics != null:
				for entry in cosmetics.choices.get(part, []):
					ids.append(entry["id"])
			return ids
	return []


static func allows_custom_color(part: String, cosmetics) -> bool:
	return cosmetics != null and bool(cosmetics.custom_colors.get(part, false))


static func starter_card(class_id: String, cosmetics) -> Dictionary:
	var start: Dictionary = STARTERS.get(class_id, {})
	var hairs := hair_options(class_id)
	return {
		"hair": str(start.get("hair", hairs[0])),
		"outfit": str(start.get("outfit", "none")),
		"eye_color": str(cosmetics.defaults.get("eye_color", "")) if cosmetics != null else "",
		"skin": str(cosmetics.defaults.get("skin", "")) if cosmetics != null else "",
		"makeup": "none",
		"iris_style": str(cosmetics.defaults.get("iris_style", "0")) if cosmetics != null else "0",
		"hair_color": "",
		"skills": [],
		"race": NO_RACE,  # tutorial.md 2: a new card has no race until the player picks one
	}


## A card's race before the player picks one (tutorial.md 2). Such a card cannot join the squad or fight.
const NO_RACE := ""


## True when the card has a race (old cards without the field use their starter race, so they count).
static func has_race(deck: Dictionary, class_id: String) -> bool:
	return deck.get("cards", {}).has(class_id) and not race_of(deck, class_id).is_empty()


## The race a card of this class starts with (and an old card without a race has).
static func starter_race(class_id: String) -> String:
	return RaceData.load_default().starter_race(class_id)


## The card's race: its own, or its class's starter race (an older card).
static func race_of(deck: Dictionary, class_id: String) -> String:
	var card: Dictionary = deck.get("cards", {}).get(class_id, {})
	return str(card.get(RACE_PART, starter_race(class_id)))


## The squad's races in squad order (for the run-start synergy, logic/race_passives.gd). Raceless cards are left out.
static func squad_races(deck: Dictionary) -> Array:
	return deck.get("squad", []).map(func(class_id): return race_of(deck, str(class_id))).filter(func(race): return not str(race).is_empty())


## Switches one card's race. Returns false (nothing changed) for an unknown class or race; "" is never accepted.
static func set_race(deck: Dictionary, class_id: String, race: String) -> bool:
	if not deck.get("cards", {}).has(class_id) or not RaceData.load_default().has_race(race):
		return false
	deck["cards"][class_id][RACE_PART] = race
	return true


## A brand new player's deck (tutorial.md 2): every class's starter card with no race, and an empty squad.
static func initial(cosmetics = null) -> Dictionary:
	var cards := {}
	for class_id in classes():
		cards[class_id] = starter_card(class_id, cosmetics)
	return {"v": 1, "cards": cards, "squad": []}


## The old-save fallback squad: STARTER_SQUAD cards the deck has that have a race.
static func fallback_squad(deck: Dictionary) -> Array:
	return STARTER_SQUAD.filter(func(class_id): return has_race(deck, class_id))


## Boss 2026-11-13: a NEW player's cards do not all look alike. Each card gets its own iris style (no two
## cards share one), the eye colour that style brings (Studio irisSelect; the Classic style takes a colour of
## data/cosmetics/eye_colors.json instead, so no two cards share an eye colour either) and a makeup set, all
## from the existing Studio-sourced option lists, plus a hair colour (the Studio's free #hair-color input) drawn
## from the curated starter palette (data/cosmetics/starter_hair_colors.json): no two cards share one and at
## most one is near-white. Hair style and class armor stay the class starter's.
## `rng` is a profile-creation RNG (deterministic per seed). Saved decks never pass through here.
static func vary_starter_looks(deck: Dictionary, cosmetics, rng: RandomNumberGenerator) -> void:
	if cosmetics == null:
		return
	var styles: Array = options("", "iris_style", cosmetics)
	var colors: Array = options("", "eye_color", cosmetics)
	_shuffle(styles, rng)
	_shuffle(colors, rng)
	var used_colors := {}
	var index := 0
	for class_id in classes():
		if not deck.get("cards", {}).has(class_id):
			continue
		if not styles.is_empty():
			set_look(deck, class_id, "iris_style", str(styles[index % styles.size()]), cosmetics)
		var card: Dictionary = deck["cards"][class_id]
		if str(card.get("iris_style", "0")) == "0" or used_colors.has(str(card["eye_color"])):
			for id in colors:  # the Classic iris (or a repeat) takes the first unused eye colour of the list
				var tint := str(cosmetics.entry("eye_color", str(id)).get("color", "")).to_lower()
				if not used_colors.has(str(id)) and not used_colors.has(tint):
					card["eye_color"] = str(id)
					break
		used_colors[str(card["eye_color"])] = true
		used_colors[str(cosmetics.entry("eye_color", str(card["eye_color"])).get("color", card["eye_color"])).to_lower()] = true
		card["makeup"] = MAKEUPS[rng.randi_range(0, MAKEUPS.size() - 1)]
		index += 1
	_vary_hair_colors(deck, rng)


## The starter hair palette: [{"id", "color": "#rrggbb", "near_white"?: bool}], only valid colours.
static func starter_hair_palette() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STARTER_HAIR_COLORS)) if FileAccess.file_exists(STARTER_HAIR_COLORS) else null
	var out := []
	if parsed is Dictionary and parsed.get("colors") is Array:
		for entry in parsed["colors"]:
			if entry is Dictionary and is_hex_color(str(entry.get("color", ""))):
				out.append(entry)
	return out


## Each card (class order) takes the next colour of the shuffled palette, skipping repeats and a second
## near-white. A palette too small to go round leaves the remaining cards on the Studio default ("").
static func _vary_hair_colors(deck: Dictionary, rng: RandomNumberGenerator) -> void:
	var palette := starter_hair_palette()
	_shuffle(palette, rng)
	var used := {}
	var white_used := false
	for class_id in classes():
		if not deck.get("cards", {}).has(class_id):
			continue
		for entry in palette:
			var hex := str(entry["color"]).to_lower()
			var white := bool(entry.get("near_white", false))
			if used.has(hex) or (white and white_used):
				continue
			deck["cards"][class_id]["hair_color"] = hex
			used[hex] = true
			white_used = white_used or white
			break


## True for "#rrggbb" (exactly 7 characters, hex digits).
static func is_hex_color(text: String) -> bool:
	return text.length() == 7 and text.begins_with("#") and Color.html_is_valid(text)


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):  # Fisher-Yates with the given RNG (Array.shuffle uses the global one)
		var j := rng.randi_range(0, i)
		var swap = list[i]
		list[i] = list[j]
		list[j] = swap


## "" when the deck is sound, else what is wrong. Unknown classes, hairs the class cannot wear, a
## repeated or oversized squad, or skills before the skill system exists are all rejected.
static func validate(deck: Variant, cosmetics = null) -> String:
	if not deck is Dictionary or int(deck.get("v", 0)) != 1:
		return "bad_deck"
	if not deck.get("cards") is Dictionary or not deck.get("squad") is Array:
		return "bad_deck"
	var known := classes()
	for class_id in deck["cards"]:
		if not known.has(str(class_id)):
			return "unknown_class"
		var problem := validate_card(str(class_id), deck["cards"][class_id], cosmetics)
		if not problem.is_empty():
			return problem
	for class_id in known:
		if not deck["cards"].has(class_id):
			return "missing_card"
	var squad: Array = deck["squad"]
	if squad.size() > SQUAD_MAX:  # empty = a new player before the race steps (tutorial.md 2)
		return "bad_squad"
	var seen := {}
	for class_id in squad:
		if not class_id is String or not deck["cards"].has(class_id) or seen.has(class_id):
			return "bad_squad"
		seen[class_id] = true
	return ""


static func validate_card(class_id: String, card: Variant, cosmetics = null) -> String:
	if not card is Dictionary:
		return "bad_card"
	for part in PARTS:
		if LATER_PARTS.has(part) and not card.has(part):
			continue  # an older card: the default applies
		if not card.get(part) is String:
			return "bad_card"
		if not _part_allowed(class_id, part, card[part], cosmetics):
			return "bad_card"
	if not card.get("skills") is Array or not (card["skills"] as Array).is_empty():
		return "bad_card"  # skills are not part of cards yet
	if card.has(RACE_PART) and (not card[RACE_PART] is String or (card[RACE_PART] != NO_RACE and not RaceData.load_default().has_race(card[RACE_PART]))):
		return "bad_card"
	if card.has(CardProgress.PROGRESS) and not CardProgress.problem(card[CardProgress.PROGRESS]).is_empty():
		return "bad_card"
	if card.has("skill_tree") and not _tree_shape_ok(card["skill_tree"]):
		return "bad_card"  # the node rules themselves are checked by logic/skill_tree.gd (repair on load, commands)
	return ""


static func _tree_shape_ok(tree) -> bool:
	if not tree is Dictionary or tree.size() != 3 or not tree.has_all(["class", "race", "combo"]):
		return false
	for branch in tree:
		if not tree[branch] is Array or not (tree[branch] as Array).all(func(id): return id is String):
			return false
	return true


static func _part_allowed(class_id: String, part: String, choice: String, cosmetics) -> bool:
	if part == "hair_color":  # Studio #hair-color is a free colour input: any #rrggbb, or "" for the default
		return choice.is_empty() or is_hex_color(choice)
	if part in ["eye_color", "skin", "iris_style"] and cosmetics == null:
		return true  # without the cosmetic lists a colour cannot be checked here (the server always has them)
	if options(class_id, part, cosmetics).has(choice):
		return true
	return part in ["eye_color", "skin"] and allows_custom_color(part, cosmetics) and choice.length() == 7 and choice.begins_with("#") and Color.html_is_valid(choice)


## Changes one thing on one card. Returns false (nothing changed) for an unknown class, part or choice.
static func set_look(deck: Dictionary, class_id: String, part: String, choice: String, cosmetics) -> bool:
	if not deck.get("cards", {}).has(class_id) or not part in PARTS:
		return false
	if not _part_allowed(class_id, part, choice, cosmetics):
		return false
	deck["cards"][class_id][part] = choice.to_lower() if choice.begins_with("#") else choice
	if part == "iris_style" and cosmetics != null:
		# index.html irisSelect: a style brings its own colour (data-color) into the eye colour.
		var tint := str(cosmetics.entry("iris_style", choice).get("color", ""))
		if not tint.is_empty():
			deck["cards"][class_id]["eye_color"] = tint.to_lower()
	return true


## Sets the squad (class ids, 1..SQUAD_MAX, no repeats, every one a card the deck has that has a race).
static func set_squad(deck: Dictionary, squad: Array) -> bool:
	if squad.is_empty() or squad.size() > SQUAD_MAX:
		return false
	var seen := {}
	var clean: Array = []
	for class_id in squad:
		if not class_id is String or not deck.get("cards", {}).has(class_id) or seen.has(class_id) or not has_race(deck, class_id):
			return false
		seen[class_id] = true
		clean.append(class_id)
	deck["squad"] = clean
	return true


## What the card looks like, as plain data the client dresses a model with:
## {"class", "hair", "silver", "eye_color", "skin", "makeup", "iris_style", "hair_color", "race"}.
static func look_of(deck: Dictionary, class_id: String) -> Dictionary:
	var card: Dictionary = deck.get("cards", {}).get(class_id, {})
	return {
		"class": class_id,
		"hair": str(card.get("hair", hair_options(class_id)[0])),
		"silver": str(card.get("outfit", "none")) == "silver",
		"eye_color": str(card.get("eye_color", "")),
		"skin": str(card.get("skin", "")),
		"makeup": str(card.get("makeup", "none")),
		"iris_style": str(card.get("iris_style", LATER_PARTS["iris_style"])),
		"hair_color": str(card.get("hair_color", LATER_PARTS["hair_color"])),
		"race": race_of(deck, class_id),
	}


## The looks of the squad in order (the fighters of the next fight: player 1, then the guests).
static func squad_looks(deck: Dictionary) -> Array:
	var looks := []
	for class_id in deck.get("squad", []):
		looks.append(look_of(deck, str(class_id)))
	return looks


## Cleans a deck loaded from storage: anything missing or no longer valid falls back to the starter card.
static func repaired(deck: Variant, cosmetics = null) -> Dictionary:
	var fresh := initial(cosmetics)
	for class_id in fresh["cards"]:  # a card the save lacks is an old-save card: it uses its starter race (no field)
		fresh["cards"][class_id].erase(RACE_PART)
	if not deck is Dictionary:
		fresh["squad"] = fallback_squad(fresh)
		return fresh
	var saved_cards = deck.get("cards", {})
	if saved_cards is Dictionary:
		for class_id in fresh["cards"]:
			if not saved_cards.has(class_id) or not saved_cards[class_id] is Dictionary:
				continue
			var saved_card: Dictionary = (saved_cards[class_id] as Dictionary).duplicate(true)
			if saved_card.has(RACE_PART) and str(saved_card[RACE_PART]) != NO_RACE and not RaceData.load_default().has_race(str(saved_card[RACE_PART])):
				saved_card[RACE_PART] = RaceData.load_default().default_race()  # a removed race file (GDD 5): keep the card, default race
			if saved_card.has(CardProgress.PROGRESS):  # JSON floats or an out-of-range block: keep the card, clean its level
				saved_card[CardProgress.PROGRESS] = CardProgress.clean(saved_card[CardProgress.PROGRESS])
			if saved_card.has("skill_tree"):  # GDD 5: unknown ids dropped, invalid deepest tiers refunded (load(): no preload cycle)
				var level: int = int(CardProgress.clean(saved_card.get(CardProgress.PROGRESS))["level"])
				var race := str(saved_card.get(RACE_PART, starter_race(class_id)))
				saved_card["skill_tree"] = load("res://logic/skill_tree.gd").repaired(saved_card["skill_tree"], class_id, race, CardProgress.points(int(level)))
			if validate_card(class_id, saved_card, cosmetics).is_empty():
				fresh["cards"][class_id] = saved_card
	if deck.get("squad") is Array and (deck["squad"] as Array).is_empty() and STARTER_SQUAD.all(func(c): return not has_race(fresh, c)):
		return fresh  # a new player before the race steps keeps the empty squad
	if deck.get("squad") is Array and set_squad(fresh, deck["squad"]):
		return fresh
	fresh["squad"] = fallback_squad(fresh)
	return fresh
