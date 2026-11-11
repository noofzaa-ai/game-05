extends RefCounted
## The looks a player picks for their character (not items: free, kept in Profile.appearance):
## face, hair style, hair color and skin tone, read from data/cosmetics/. A mistake in the files never crashes
## the game: `errors` is filled in and a broken part offers nothing (the model keeps its own look).
## EXTENDING: a new part (eye color, hair style...) is one more entry in PARTS and its data file.

## part -> [data file, the key of its list]
const PARTS := {
	"skin": ["res://data/cosmetics/skin_tones.json", "colors"],
	"face": ["res://data/cosmetics/faces.json", "faces"],
	"hair_style": ["res://data/cosmetics/hair_styles.json", "styles"],
	"eye_color": ["res://data/cosmetics/eye_colors.json", "colors"],
	"fashion": ["res://data/cosmetics/fashion.json", "styles"],
	"fashion_display": ["res://data/cosmetics/wear_modes.json", "styles"],
	"fashion_hat": ["res://data/cosmetics/fashion_hats.json", "styles"],
	"fashion_back": ["res://data/cosmetics/fashion_back.json", "styles"],
	"blink_mode": ["res://data/cosmetics/blink_modes.json", "styles"],
	"wear_shirt": ["res://data/cosmetics/wear_modes.json", "styles"],
	"wear_pants": ["res://data/cosmetics/wear_modes.json", "styles"],
	"wear_shoes": ["res://data/cosmetics/wear_modes.json", "styles"],
	"wear_head": ["res://data/cosmetics/wear_modes.json", "styles"],
	"wear_hair": ["res://data/cosmetics/wear_modes.json", "styles"],
	"wear_mask": ["res://data/cosmetics/wear_modes.json", "styles"],

}
const WEAR_PARTS: Array[String] = ["wear_head", "wear_hair", "wear_mask"]
const PART_ORDER: Array[String] = ["face", "eye_color", "hair_style", "skin", "fashion", "fashion_display", "fashion_back", "blink_mode", "wear_head", "wear_hair", "wear_mask"]
const MODEL_PARTS: Array[String] = ["face", "hair_style", "fashion", "fashion_display", "fashion_hat", "fashion_back", "blink_mode", "wear_shirt", "wear_pants", "wear_shoes", "wear_head", "wear_hair", "wear_mask"]  ## parts that are a model (asset_id; "" = the body's own)

var choices: Dictionary = {}  ## part -> Array of entries ({"id", "name", "color" (+ "natural") or "asset_id"})
var defaults: Dictionary = {}  ## part -> id
var errors: Array[String] = []
var custom_colors: Dictionary = {}
var wardrobe_budget: Dictionary = {}


static func load_default() -> RefCounted:
	var texts := {}
	for part in PARTS:
		var file: String = PARTS[part][0]
		texts[part] = FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""
	var options = parse(texts)
	var budget = JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics/reference_budget.json"))
	if budget is Dictionary: options.wardrobe_budget = budget
	return options


## `texts`: part -> the JSON text of its file ("" = missing).
static func parse(texts: Dictionary) -> RefCounted:
	var options = load("res://logic/cosmetic_options.gd").new()
	for part in PARTS:
		options._parse_part(part, str(texts.get(part, "")))
	return options


func is_valid() -> bool:
	return errors.is_empty()


## The entry with this id, or {} if the part has no such choice.
func entry(part: String, id: String) -> Dictionary:
	if custom_colors.get(part, false) and id.length() == 7 and id.begins_with("#") and Color.html_is_valid(id):
		return {"id": id.to_lower(), "name": id, "color": id.to_lower()}
	for candidate in choices.get(part, []):
		if candidate["id"] == id:
			return candidate
	return {}


## What `appearance` (part -> id, as Profile.appearance) means: part -> entry, the default where
## nothing (or something no longer offered) was picked. Parts with no choices are left out.
func resolve(appearance: Dictionary) -> Dictionary:
	var result := {}
	for part in PARTS:
		var picked := entry(part, str(appearance.get(part, "")))
		if picked.is_empty():
			picked = entry(part, str(defaults.get(part, "")))
		if not picked.is_empty():
			result[part] = picked
	return result


func starter() -> Dictionary:
	return defaults.duplicate(true)


## A random pick for every part (the creator's dice button): part -> id.
func random(rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for part in PARTS:
		var list: Array = choices.get(part, [])
		if not list.is_empty():
			result[part] = list[rng.randi_range(0, list.size() - 1)]["id"]
	return result


## Picks `id` for `part` in `appearance`. Returns false (and changes nothing) for an unknown choice.
func choose(appearance: Dictionary, part: String, id: String) -> bool:
	if entry(part, id).is_empty():
		return false
	appearance[part] = id
	if part == "fashion" and id != "none": appearance["fashion_display"] = "on"
	# Hat migration deferred by Boss; outfit selection never equips a cosmetic hat.
	_enforce_wardrobe_budget(appearance)
	return true


func _parse_part(part: String, text: String) -> void:
	choices[part] = []
	if text.is_empty():
		errors.append("%s: file not found" % part)
		return
	var json := JSON.new()
	var root = json.data if json.parse(text) == OK else null
	if typeof(root) != TYPE_DICTIONARY or typeof(root.get(PARTS[part][1])) != TYPE_ARRAY:
		errors.append("%s: must be an object with a '%s' list" % [part, PARTS[part][1]])
		return
	custom_colors[part] = bool(root.get("allow_custom", false)) and part in ["skin", "eye_color"]
	var seen := {}
	for raw in root[PARTS[part][1]]:
		if typeof(raw) != TYPE_DICTIONARY or str(raw.get("id", "")).is_empty():
			errors.append("%s: every choice needs an id" % part)
			continue
		var id := str(raw["id"])
		if seen.has(id):
			errors.append("%s: id '%s' is used twice" % [part, id])
			continue
		seen[id] = true
		var choice := {"id": id, "name": str(raw.get("name", id))}
		if part in MODEL_PARTS:
			choice["asset_id"] = str(raw.get("asset_id", ""))
			if raw.get("archived", false):
				choice["archived"] = true  # a model the model team set aside, offered here on purpose (Boss 2026-10-08)
		else:
			var color := str(raw.get("color", ""))
			if not Color.html_is_valid(color):
				errors.append("%s: '%s' has no valid color" % [part, id])
				continue
			choice["color"] = color
			if raw.get("natural", false):
				choice["natural"] = true  # hair: keep each style's own colors (`color` is for the body's own hair)
		choices[part].append(choice)
	var wanted := str(root.get("default", ""))
	if entry(part, wanted).is_empty():
		errors.append("%s: default '%s' is not one of the choices" % [part, wanted])
		if not choices[part].is_empty():
			wanted = choices[part][0]["id"]
	defaults[part] = wanted

func _enforce_wardrobe_budget(appearance: Dictionary) -> void:
	if wardrobe_budget.is_empty(): return
	var resolved := resolve(appearance)
	var outfit := str(resolved.get("fashion",{}).get("id","red"))
	var hat := str(resolved.get("fashion_hat",{}).get("id","none"))
	var back := str(resolved.get("fashion_back",{}).get("id","none"))
	if back == "none": return
	var total := int(wardrobe_budget.hats.get(hat,0)) # Back accessories have an independent budget; the outfit toggle never removes wings.
	for slot in ["shirt","pants","shoes","mask"]:
		if outfit != "none" and str(resolved.get("fashion_display",{}).get("id","on"))=="on":
			total+=int(wardrobe_budget.outfits.get(outfit,{}).get(slot,0))
	if total>int(wardrobe_budget.cap): appearance["fashion_display"]="off"
