extends RefCounted
## Finds the models of items: the model team's register (art/items/item_manifest.json) maps an
## asset_id to its .glb, and the item catalog (logic/item_catalog.gd) maps an item to its asset_id.
## looks() turns what a character wears into what CharacterModel.dress() shows.
## An asset that is missing or not "ready" gives "" (the caller shows its stand-in instead).

const MANIFEST_PATH := "res://art/items/item_manifest.json"
## Shown on an empty shirt / pants slot (Boss 2026-10-06: the basic clothes are not items).
const EMPTY_LOOKS := {} # The Studio body supplies the base; old garments use an incompatible rig.
## The equipment slots that show a model on the body.
const BODY_SLOTS: Array[String] = ["shirt", "armband", "pants", "shoes"]  ## no hat slot (Boss 2026-11-13)

const CosmeticOptions := preload("res://logic/cosmetic_options.gd")

static var _by_id: Dictionary = {}
static var _cosmetics: RefCounted
static var _loaded := false


static func entry(asset_id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(MANIFEST_PATH):
			var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if typeof(data) == TYPE_DICTIONARY:
				for asset in data.get("items", []):
					_by_id[str(asset.get("id", ""))] = asset
	return _by_id.get(asset_id, {})


## The resource path of a ready asset (or of an archived one too, with `archived_ok`), or "".
static func path(asset_id: String, archived_ok: bool = false) -> String:
	if asset_id.begins_with("res://art/armor/"):
		return asset_id if ResourceLoader.exists(asset_id) else ""
	var asset := entry(asset_id)
	var file := str(asset.get("asset_path", ""))
	var usable: bool = asset.get("status", "") == "ready" or (archived_ok and asset.get("status", "") == "archived")
	if not usable or file.is_empty() or not ResourceLoader.exists(file):
		return ""
	return file


## A catalog fallback field as an ordered list of paths: race gear writes "first|second|..." (tools/items/build_race_gear.py:
## the race x class file, then the race's shared interim file, then the class armour); the first file that exists wins.
static func chain(field: String) -> PackedStringArray:
	var result := PackedStringArray()
	for part in field.split("|", false):
		if not part.strip_edges().is_empty():
			result.append(part.strip_edges())
	return result


## The model file a catalog armour piece shows: its own asset_path, else the first existing fallback, else "".
static func armor_file(info: Dictionary) -> String:
	var file := str(info.get("asset_path", ""))
	if not file.is_empty() and ResourceLoader.exists(file):
		return file
	for fallback in chain(str(info.get("fallback_asset_path", ""))):
		if ResourceLoader.exists(fallback):
			return fallback
	return path(str(info.get("asset_id", "")))


## The inventory icon of a catalog item (`catalog`: ItemCatalog), or null (draw the slot's shape).
static func icon(item, catalog) -> Texture2D:
	return null if item == null else icon_for_id(item.item_id, catalog)


## The same for a catalog item id ("" or unknown: null).
static func icon_for_id(item_id: String, catalog) -> Texture2D:
	if catalog == null or item_id.is_empty():
		return null
	var info: Dictionary = catalog.entry(item_id)
	var native_icon := str(info.get("icon_path",""))
	if not native_icon.is_empty() and ResourceLoader.exists(native_icon): return load(native_icon) as Texture2D
	for fallback_icon in chain(str(info.get("fallback_icon_path", ""))):  # race gear before the Studio icon lands (docs/art/race_gear_handoff.md)
		if ResourceLoader.exists(fallback_icon): return load(fallback_icon) as Texture2D
	return null  # the old art/items/icons folder is gone with the legacy items (Boss 2026-11-13)


## The choices of looks the game offers (data/cosmetics), read once.
static func cosmetics() -> RefCounted:
	if _cosmetics == null:
		_cosmetics = CosmeticOptions.load_default()
		if not _cosmetics.is_valid():
			push_warning("cosmetics data: %s" % [_cosmetics.errors])
	return _cosmetics


## What the player's chosen looks (Profile.appearance: part -> id) mean for CharacterModel.set_appearance():
## {"skin": Color, "hair": Color, "hair_natural": bool (styles keep their own colors), "face" and
## "hair_style": path ("" = the body's own), "face_replaces_head" / "face_hides_hair": bool (whole
## replacement heads, from the model team's register)}.
## The model's appearance for one class card's look (card_deck.look_of): the card's own hair, hair colour, outfit,
## eyes, skin, makeup and iris style on top of `base` (the account's appearance).
static func card_appearance(look: Dictionary, base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var picks: Dictionary = result.get("choices", {}).duplicate()
	result["studio_hair"] = str(look.get("hair", "a"))
	result["studio_silver"] = bool(look.get("silver", false))
	result["race"] = str(look.get("race", ""))  # the race head (data/races/<id>.json "look"), "" = the Studio head
	var parts: Dictionary = cosmetics().resolve({"eye_color": look.get("eye_color", ""), "skin": look.get("skin", "")})
	if parts.has("eye_color"):
		result["eye_color"] = Color(parts["eye_color"]["color"])
		result["eye_color_id"] = str(parts["eye_color"]["id"])
	if parts.has("skin"):
		result["skin"] = Color(parts["skin"]["color"])
		picks["skin"] = str(parts["skin"]["id"])
	picks["makeup"] = str(look.get("makeup", "none"))
	result["iris_style"] = int(str(look.get("iris_style", "0")))
	# Studio #hair-color: a card colour replaces the hair material colour (index.html updateColors); "" keeps
	# the hair's Studio default (#6f657f for A/B, white for C-G whose colour is in the file).
	var hair_hex := str(look.get("hair_color", ""))
	if hair_hex.length() == 7 and hair_hex.begins_with("#") and Color.html_is_valid(hair_hex):
		result["hair"] = Color(hair_hex)
		result["hair_natural"] = false
	else:
		result.erase("hair")
		result["hair_natural"] = true
	result["choices"] = picks
	return result


static func appearance(chosen: Dictionary) -> Dictionary:
	var parts: Dictionary = cosmetics().resolve(chosen)
	var resolved_choices := chosen.duplicate(true)
	for part in parts:
		if parts[part] is Dictionary and parts[part].has("id"):
			resolved_choices[part] = parts[part]["id"]
	var result := {"choices": resolved_choices}
	if parts.has("skin"):
		result["skin"] = Color(parts["skin"]["color"])
	if parts.has("hair_color"):
		result["hair"] = Color(parts["hair_color"]["color"])
		result["hair_natural"] = parts["hair_color"].get("natural", false)
	if parts.has("eye_color"):
		result["eye_color"] = Color(parts["eye_color"]["color"])
		result["eye_color_id"] = str(parts["eye_color"]["id"])
	result["blink_mode"] = "auto"
	return result


## What a character wearing `loadout` looks like:
## {"weapon": {"path", "family", "style"}, "hat"/"shirt"/...: path or "", "hide_hair": bool}.
## `catalog` is the ItemCatalog; `style` the combat style of the weapon (its stand-in model's name).
static func looks(loadout, catalog, style: String) -> Dictionary:
	var result := {"weapon": {"path": "", "family": style, "style": style}, "hide_hair": false, "refine": {}, "armor_styles": {}}
	for slot_id in BODY_SLOTS:
		result[slot_id] = path(EMPTY_LOOKS.get(slot_id, ""))
	if loadout == null:
		return result
	var weapon = loadout.item_at("weapon", 0)
	if weapon != null and not weapon.destroyed and weapon.weapon_type == style:
		var asset_id: String = catalog.entry(weapon.item_id).get("asset_id", "")
		var own := str(catalog.entry(weapon.item_id).get("asset_path", ""))  # a race weapon's Studio file, when it exists
		result["weapon"]["path"] = own if own.begins_with("res://art/weapons/") and ResourceLoader.exists(own) else path(asset_id)
		result["refine"]["weapon"] = weapon.refine_level
	for slot_id in BODY_SLOTS:
		var item = loadout.item_at(slot_id, 0)
		if item == null or item.destroyed:
			continue
		var asset_id: String = catalog.entry(item.item_id).get("asset_id", "")
		result["refine"][slot_id] = item.refine_level
		var file := armor_file(catalog.entry(item.item_id))  # race gear: race x class file, else the race's shared file, else the class look
		if file.is_empty():
			continue  # a plain piece (no catalog look) keeps the empty-slot look
		result["armor_styles"][slot_id] = str(catalog.entry(item.item_id).get("source_style",""))
		result[slot_id] = file
		result["refine"][slot_id] = item.refine_level
		if slot_id == "hat" and entry(asset_id).get("hide_hair", false):
			result["hide_hair"] = true
	# The off-hand shield (Sword & Shield only, Boss 2026-11-11): {} = empty slot (the model shows the class's own).
	var shield = loadout.item_at("offhand", 0) if loadout.has_method("item_at") else null
	if shield != null and not shield.destroyed:
		var info: Dictionary = catalog.entry(shield.item_id)
		var shield_file := str(info.get("asset_path", ""))
		if shield_file.is_empty():
			shield_file = path(str(info.get("asset_id", "")))
		if not shield_file.is_empty() and not ResourceLoader.exists(shield_file):
			shield_file = ""
		result["offhand"] = {"item_id": shield.item_id, "asset_id": str(info.get("asset_id", "")), "procedural": bool(info.get("procedural", false)), "path": shield_file, "refine_level": shield.refine_level}
		result["refine"]["offhand"] = shield.refine_level
	else:
		result["offhand"] = {}
	return result
