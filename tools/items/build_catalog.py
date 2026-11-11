"""Adds the model team's new assets to the game's item catalog.

Reads art/items/item_manifest.json (the model Studio's register of asset ids) and writes
data/items/catalog.json (game items: item_id -> asset_id, slot, weapon type, set) and
data/items/sets.json (set bonuses). Entries already in those files are KEPT as they are, so
hand edits survive: only assets that no item uses yet get a new entry. Run from the project root:

    python tools/items/build_catalog.py

Boss 2026-10-15: only items WITH A MODEL are items. A catalog entry whose asset is not in the
manifest, is not "ready", or whose .glb is not on disk is removed (and reported), and a set left
with no pieces loses its bonus table. Remaining ids never change.

Names are English because the web build's default font has no Thai glyphs (name_th keeps the
Studio's Thai name). A new item gets a rough name from its id: translate name_th by hand after a run. Every number written for a new set is a PLACEHOLDER to tune in sets.json.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "art/items/item_manifest.json"
CATALOG = ROOT / "data/items/catalog.json"
SETS = ROOT / "data/items/sets.json"

# Studio clothing slot -> the game's equipment slot.
SLOT_FROM_STUDIO = {"head": "hat", "shirt": "shirt", "arms": "armband", "pants": "pants", "shoes": "shoes"}
# Assets that are not items: shown on an empty slot (see GDD) instead.
NOT_ITEMS = {"clothing_shirt_basic_01", "clothing_shorts_basic_01"}
WEAPON_NAMES = {
    "weapon_blade_01": "Steel Blade",
    "weapon_blade_02": "Ivory Hilt Katana",
    "weapon_blade_03": "Night Katana",
    "weapon_blade_04": "Silver Katana",
    "weapon_blade_05": "Golden Bloom Katana",
    "weapon_blade_06": "White Bloom Katana",
    "weapon_blade_07": "Crescent Katana",
    "weapon_dagger_01": "Twin Daggers",
    "weapon_dagger_02": "Ashen Daggers",
    "weapon_dagger_03": "Jade Fangs",
    "weapon_dagger_04": "Golden Talons",
    "weapon_dagger_05": "Silver Shades",
    "weapon_dagger_06": "Blood Fangs",
    "weapon_spear_01": "Iron Spear",
}
# Set bonus stats are picked by the set's kind; a 5-piece set uses all four, a 4-piece set three.
BONUS_STATS = {
    "armor": [["DEF", "HP", "EFFECT_RES", "ATK"], ["HP", "DEF", "CRIDMG", "STAMINA"], ["DEF", "ATK", "HP", "EFFECT_RES"]],
    "outfit": [["MOVESPD", "CRIRATE", "ATK", "STAREGEN"], ["ATKSPD", "EFFECT_ACC", "CRIRATE", "HP"], ["CRIRATE", "MOVESPD", "CRIDMG", "ATKSPD"]],
    "cloth": [["EFFECT_ACC", "ULTREGEN", "ATK", "HPREGEN"]],
}
BONUS_VALUE = {"HP": 120, "ATK": 12, "DEF": 9, "ATKSPD": 4, "MOVESPD": 4, "CRIRATE": 4, "CRIDMG": 8,
               "EFFECT_ACC": 6, "EFFECT_RES": 6, "HPREGEN": 1.5, "STAREGEN": 3, "ULTREGEN": 0.3, "STAMINA": 15}


def words(text):
    return " ".join(part.capitalize() for part in text.split("_") if part)


def item_id_for(asset_id):
    # clothing_aegis_helmet_01 -> aegis_helmet; weapon_blade_02 -> blade_02
    core = asset_id.removeprefix("clothing_").removeprefix("weapon_")
    return core.removesuffix("_01") if asset_id.startswith("clothing_") else core


def set_name(set_id):
    core = set_id.split("_", 1)[1] if set_id.split("_", 1)[0] in BONUS_STATS else set_id
    return words(core.removesuffix("_01"))


def load(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def has_model(asset):
    """The asset is "ready" in the manifest and its file is on disk."""
    path = str(asset.get("asset_path", "")).removeprefix("res://")
    return asset.get("status") == "ready" and bool(path) and (ROOT / path).is_file()


def main():
    manifest = load(MANIFEST, {"items": []})["items"]
    catalog = load(CATALOG, {"version": 1, "items": {}})
    sets = load(SETS, {"version": 1, "sets": {}})
    by_id = {asset["id"]: asset for asset in manifest}
    # "procedural": the client builds the look in code (off-hand shields, tools/items/publish_offhand_catalog.py).
    removed = [item_id for item_id, entry in catalog["items"].items() if not entry.get("procedural") and not has_model(by_id.get(entry["asset_id"], {}))]
    for item_id in removed:
        print(f"removed {item_id} (asset {catalog['items'][item_id]['asset_id']} has no model)")
        del catalog["items"][item_id]
    used = {entry["asset_id"] for entry in catalog["items"].values()}
    added = 0
    for asset in manifest:
        if not has_model(asset) or asset["id"] in used or asset["id"] in NOT_ITEMS:
            continue
        entry = None
        if asset["category"] == "weapons":
            entry = {"name": WEAPON_NAMES.get(asset["id"], words(item_id_for(asset["id"]))), "slot": "weapon",
                     "weapon_type": asset.get("family", "")}
        elif asset["category"] == "clothing" and asset.get("slot") in SLOT_FROM_STUDIO:
            piece = item_id_for(asset["id"])
            entry = {"name": words(piece), "slot": SLOT_FROM_STUDIO[asset["slot"]]}
            if asset.get("set_id"):
                entry["set"] = asset["set_id"]
        if entry is None:
            continue  # hair and faces are cosmetics, not equipment
        entry = {"asset_id": asset["id"], **entry, "name_th": asset.get("name", ""), "drop_level": 1}
        item_id = item_id_for(asset["id"])
        while item_id in catalog["items"]:
            item_id += "_b"
        catalog["items"][item_id] = entry
        added += 1
    # Every set that has pieces gets a bonus table (kept if it is already there).
    pieces = {}
    for entry in catalog["items"].values():
        if entry.get("set"):
            pieces[entry["set"]] = pieces.get(entry["set"], 0) + 1
    for set_id in [set_id for set_id in sets["sets"] if set_id not in pieces]:
        print(f"removed set {set_id} (no pieces left)")
        del sets["sets"][set_id]
    for index, set_id in enumerate(sorted(pieces)):
        if set_id in sets["sets"]:
            continue
        kind = set_id.split("_", 1)[0]
        options = BONUS_STATS.get(kind, BONUS_STATS["outfit"])
        stats = options[index % len(options)]
        bonuses = [{"pieces": count, "stat": stat, "value": BONUS_VALUE[stat]}
                   for count, stat in zip(range(2, pieces[set_id] + 1), stats)]
        sets["sets"][set_id] = {"name": set_name(set_id), "bonuses": bonuses}
    catalog["_comment"] = ("Game items made from the model team's assets (art/items/item_manifest.json). The key is the "
                           "item_id the game and saves use; asset_id finds the model. slot is the game's slot, weapon_type "
                           "the combat style, set a set id in sets.json, drop_level the lowest monster level that drops it. "
                           "tools/items/build_catalog.py adds new assets and never changes entries already here.")
    sets["_comment"] = ("Set bonuses. Wearing `pieces` or more items of the same set adds `value` to `stat` (each step "
                        "adds on top of the ones before). All numbers are PLACEHOLDERS to tune by feel.")
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    SETS.write_text(json.dumps(sets, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"added {added}, removed {len(removed)} items; catalog has {len(catalog['items'])}, sets {len(sets['sets'])}")


if __name__ == "__main__":
    main()
