extends RefCounted
## Finds the models of items: the model team's register (art/items/item_manifest.json) maps an
## asset_id to its .glb, and the item catalog (logic/item_catalog.gd) maps an item to its asset_id.
## looks() turns what a character wears into what CharacterModel.dress() shows.
## An asset that is missing or not "ready" gives "" (the caller shows its stand-in instead).

const MANIFEST_PATH := "res://art/items/item_manifest.json"
## Inventory icons made from the model team's previews (tools/items/build_icons.py).
const ICON_FOLDER := "res://art/items/icons/"
## Shown on an empty shirt / pants slot (Boss 2026-10-06: the basic clothes are not items).
const EMPTY_LOOKS := {} # Native body/fashion supplies the base; old garments use an incompatible rig.
## The equipment slots that show a model on the body.
const BODY_SLOTS: Array[String] = ["hat", "shirt", "armband", "pants", "shoes"]

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
	if (asset_id.begins_with("res://art/fashion/") or asset_id.begins_with("res://art/armor/")):
		return asset_id if ResourceLoader.exists(asset_id) else ""
	var asset := entry(asset_id)
	var file := str(asset.get("asset_path", ""))
	var usable: bool = asset.get("status", "") == "ready" or (archived_ok and asset.get("status", "") == "archived")
	if not usable or file.is_empty() or not ResourceLoader.exists(file):
		return ""
	return file


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
	var file := ICON_FOLDER + str(info.get("asset_id", "")) + ".png"
	return load(file) as Texture2D if ResourceLoader.exists(file) else null


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
## The model's appearance for one class card's look (card_deck.look_of): the card's own hair, outfit, eyes,
## skin, makeup and iris style on top of `base` (the account's appearance).
static func card_appearance(look: Dictionary, base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var picks: Dictionary = result.get("choices", {}).duplicate()
	result["studio_hair"] = str(look.get("hair", "a"))
	result["studio_silver"] = bool(look.get("silver", false))
	var parts: Dictionary = cosmetics().resolve({"eye_color": look.get("eye_color", ""), "skin": look.get("skin", "")})
	if parts.has("eye_color"):
		result["eye_color"] = Color(parts["eye_color"]["color"])
		result["eye_color_id"] = str(parts["eye_color"]["id"])
	if parts.has("skin"):
		result["skin"] = Color(parts["skin"]["color"])
		picks["skin"] = str(parts["skin"]["id"])
	picks["makeup"] = str(look.get("makeup", "none"))
	result["iris_style"] = int(str(look.get("iris_style", "0")))
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
	if parts.has("face"):
		var face_id := str(parts["face"].get("asset_id", ""))
		result["face"] = path(face_id, parts["face"].get("archived", false))
		result["face_replaces_head"] = entry(face_id).get("replaces_head", false)
		result["face_hides_hair"] = entry(face_id).get("hide_hair", false)
	if parts.has("hair_style"):
		result["hair_style"] = path(str(parts["hair_style"].get("asset_id", "")), parts["hair_style"].get("archived", false))
	result["eye_style"] = str(parts.get("face", {}).get("id", "original"))
	result["eye_texture"] = str(parts.get("face", {}).get("asset_id", ""))
	if parts.has("eye_color"):
		result["eye_color"] = Color(parts["eye_color"]["color"])
		result["eye_color_id"] = str(parts["eye_color"]["id"])
	var manifest_path := "res://art/fashion/manifest.json"
	if FileAccess.file_exists(manifest_path):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest is Dictionary:
			result["fashion"] = manifest.get("outfits", {}).get(str(parts.get("fashion", {}).get("id", "red")), {})
			var hair_id := str(parts.get("hair_style", {}).get("id", "mens_short"))
			result["head_accessory"] = str(manifest.get("head", {}).get(hair_id, ""))
			result["mask"] = str(manifest.get("mask", {}).get(hair_id, ""))
	for part in ["fashion_hat", "fashion_back"]:
		result[part] = str(parts.get(part, {}).get("asset_id", ""))
	result["wear"] = {}
	for slot in ["shirt", "pants", "shoes", "head", "hair", "mask"]:
		result["wear"][slot] = str(parts.get("wear_"+slot, {}).get("id", "on")) == "on"
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
		result["weapon"]["path"] = path(asset_id)
		result["refine"]["weapon"] = weapon.refine_level
	for slot_id in BODY_SLOTS:
		var item = loadout.item_at(slot_id, 0)
		if item == null or item.destroyed:
			continue
		var asset_id: String = catalog.entry(item.item_id).get("asset_id", "")
		result["refine"][slot_id] = item.refine_level
		var file := str(catalog.entry(item.item_id).get("asset_path",""))
		if file.is_empty(): file=path(asset_id)
		if not file.is_empty() and not ResourceLoader.exists(file): file=""
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
