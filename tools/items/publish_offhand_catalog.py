"""Adds the off-hand (shield) items to data/items/catalog.json. Safe to re-run: entries already there are kept.

Boss 2026-11-11: an `offhand` equipment slot usable only by the Sword & Shield class (data/items/rules.json
slots[].classes). Shields carry stats, refine and drop like other gear. The only shield look the game has
today is the class's procedural round shield (client/characters/studio05_character_model.gd _build_shield),
so the catalog entry is marked "procedural": true (no .glb; tools/items/build_catalog.py keeps such entries).
Its inventory icon is a render of the Studio Sword & Shield armor's shield piece (tools/shots/shield_icon.gd);
UPDATE_FIELDS are also written onto entries that already exist (the rest of an existing entry is kept).
Run from the project root:

    python tools/items/publish_offhand_catalog.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data/items/catalog.json"

SHIELDS = {
    "round_shield": {"asset_id": "procedural_round_shield", "name": "Round Shield", "slot": "offhand",
                     "name_th": "โล่กลม", "drop_level": 1, "procedural": True,
                     "icon_path": "res://art/items/icons/offhand_round_shield.png"},
}
UPDATE_FIELDS = ["icon_path"]


def main():
    text = CATALOG.read_text(encoding="utf-8")
    catalog = json.loads(text)
    added = [item_id for item_id in SHIELDS if item_id not in catalog["items"]]
    for item_id in added:
        catalog["items"][item_id] = SHIELDS[item_id]
    updated = []
    for item_id, entry in SHIELDS.items():
        for field in UPDATE_FIELDS:
            if field in entry and catalog["items"][item_id].get(field) != entry[field]:
                catalog["items"][item_id][field] = entry[field]
                updated.append(item_id)
    comment = catalog.pop("_comment", None)  # keep the comment last, as the other tools write it
    if comment is not None:
        catalog["_comment"] = comment
    out = json.dumps(catalog, ensure_ascii=False, indent=1)
    if text.endswith("\n"):
        out += "\n"
    CATALOG.write_text(out, encoding="utf-8")
    print(f"added {len(added)} off-hand items: {added}; updated {sorted(set(updated))}; catalog has {len(catalog['items'])}")


if __name__ == "__main__":
    main()
