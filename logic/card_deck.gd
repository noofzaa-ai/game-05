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
##         "makeup": "none"|"sharp_wing", "skills": []}

const CLASS_FOLDER := "res://data/classes/"
const CLASS_ORDER: Array[String] = ["sword_shield", "greatsword", "longbow", "magic"]
const SQUAD_MAX := 3
const OUTFITS: Array[String] = ["none", "silver"]  ## none = the base body; silver = Silver Silk (test05 Studio)
const MAKEUPS: Array[String] = ["none", "sharp_wing"]
const PARTS: Array[String] = ["hair", "outfit", "eye_color", "skin", "makeup"]
## The card each class starts with (the squad the game had before cards).
const STARTERS := {
	"sword_shield": {"hair": "a", "outfit": "none"},
	"greatsword": {"hair": "c", "outfit": "silver"},
	"longbow": {"hair": "e", "outfit": "silver"},
	"magic": {"hair": "f", "outfit": "silver"},
}
const STARTER_SQUAD: Array[String] = ["sword_shield", "greatsword", "magic"]

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
		"eye_color", "skin":
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
		"skills": [],
	}


## A brand new player's deck: every class's starter card and the starter squad.
static func initial(cosmetics = null) -> Dictionary:
	var cards := {}
	for class_id in classes():
		cards[class_id] = starter_card(class_id, cosmetics)
	var squad: Array = []
	for class_id in STARTER_SQUAD:
		if cards.has(class_id):
			squad.append(class_id)
	return {"v": 1, "cards": cards, "squad": squad}


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
	if squad.is_empty() or squad.size() > SQUAD_MAX:
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
		if not card.get(part) is String:
			return "bad_card"
		if not _part_allowed(class_id, part, card[part], cosmetics):
			return "bad_card"
	if not card.get("skills") is Array or not (card["skills"] as Array).is_empty():
		return "bad_card"  # skills are not part of cards yet
	return ""


static func _part_allowed(class_id: String, part: String, choice: String, cosmetics) -> bool:
	if part in ["eye_color", "skin"] and cosmetics == null:
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
	return true


## Sets the squad (class ids, 1..SQUAD_MAX, no repeats, every one a card the deck has).
static func set_squad(deck: Dictionary, squad: Array) -> bool:
	if squad.is_empty() or squad.size() > SQUAD_MAX:
		return false
	var seen := {}
	var clean: Array = []
	for class_id in squad:
		if not class_id is String or not deck.get("cards", {}).has(class_id) or seen.has(class_id):
			return false
		seen[class_id] = true
		clean.append(class_id)
	deck["squad"] = clean
	return true


## What the card looks like, as plain data the client dresses a model with:
## {"class", "hair", "silver", "eye_color", "skin", "makeup"}.
static func look_of(deck: Dictionary, class_id: String) -> Dictionary:
	var card: Dictionary = deck.get("cards", {}).get(class_id, {})
	return {
		"class": class_id,
		"hair": str(card.get("hair", hair_options(class_id)[0])),
		"silver": str(card.get("outfit", "none")) == "silver",
		"eye_color": str(card.get("eye_color", "")),
		"skin": str(card.get("skin", "")),
		"makeup": str(card.get("makeup", "none")),
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
	if not deck is Dictionary:
		return fresh
	var saved_cards = deck.get("cards", {})
	if saved_cards is Dictionary:
		for class_id in fresh["cards"]:
			if saved_cards.has(class_id) and validate_card(class_id, saved_cards[class_id], cosmetics).is_empty():
				fresh["cards"][class_id] = (saved_cards[class_id] as Dictionary).duplicate(true)
	if deck.get("squad") is Array:
		var squad: Array = fresh["squad"].duplicate()
		if set_squad(fresh, deck["squad"]):
			return fresh
		fresh["squad"] = squad
	return fresh
