"""English display names of the native armor items and sets (Boss 2026-11-11: game text in English).

Used by tools/items/publish_native_armor_catalog.py when it builds the armor, and run on its own to rename the
pieces already in data/items/catalog.json and data/items/sets.json without rebuilding them (the publish script
is a one-time migration: re-running it would drop items such as the off-hand shields). `name` is English,
`name_th` keeps the Thai name. Safe to re-run. From the project root:

    python tools/items/armor_names.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
# family -> (Thai label, English label)
FAMILIES = {"obsidian": ("อัศวินดำ", "Obsidian Knight"), "royal": ("ราชันสุริยะ", "Sun King"), "ash": ("อัศวินเถ้า", "Ash Knight")}
# game slot -> (Thai, English)
SLOTS = {"hat": ("หมวก", "Helm"), "shirt": ("เสื้อเกราะ", "Cuirass"), "pants": ("กางเกง", "Legguards"),
         "armband": ("ปลอกแขน", "Bracers"), "shoes": ("รองเท้า", "Boots")}
# armor class -> (Thai piece suffix, Thai set suffix, English)
KINDS = {"heavy": ("เกราะหนัก", "หนัก", "Heavy"), "light": ("เกราะเบา", "เบา", "Light"), "cloth": ("เกราะผ้า", "ผ้า", "Cloth")}
# source_style prefix -> family
STYLE_FAMILY = {"obsidian": "obsidian", "royal": "royal", "ash": "ash"}


def piece_names(family, slot, kind):
    """(English, Thai) name of one armor piece."""
    th = FAMILIES[family][0] + " " + SLOTS[slot][0] + " · " + KINDS[kind][0]
    en = FAMILIES[family][1] + " " + SLOTS[slot][1] + " (" + KINDS[kind][2] + ")"  # ASCII only: the web font
    return en, th


def set_names(family, kind):
    """(English, Thai) name of one armor set."""
    return FAMILIES[family][1] + " (" + KINDS[kind][2] + ")", FAMILIES[family][0] + " · " + KINDS[kind][1]


def _family_of(style):
    return STYLE_FAMILY.get(style.split("_", 1)[0], "")


def main():
    catalog_path = ROOT / "data/items/catalog.json"
    sets_path = ROOT / "data/items/sets.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    sets = json.loads(sets_path.read_text(encoding="utf-8"))
    renamed = 0
    set_kind = {}
    for item_id, entry in catalog["items"].items():
        family = _family_of(str(entry.get("source_style", "")))
        kind = entry.get("armor_class")
        if not family or kind not in KINDS or entry.get("slot") not in SLOTS:
            continue
        en, th = piece_names(family, entry["slot"], kind)
        if entry.get("name") != en or entry.get("name_th") != th:
            renamed += 1
        rebuilt = {}
        for key, value in entry.items():  # keep the key order, name_th right after name
            if key == "name_th":
                continue
            rebuilt[key] = en if key == "name" else value
            if key == "name":
                rebuilt["name_th"] = th
        catalog["items"][item_id] = rebuilt
        if entry.get("set"):
            set_kind[entry["set"]] = (family, kind)
    for set_id, (family, kind) in set_kind.items():
        if set_id in sets["sets"]:
            en, th = set_names(family, kind)
            row = sets["sets"][set_id]
            sets["sets"][set_id] = {"name": en, "name_th": th, **{k: v for k, v in row.items() if k not in ("name", "name_th")}}
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    sets_path.write_text(json.dumps(sets, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"renamed {renamed} armor pieces, {len(set_kind)} sets")


if __name__ == "__main__":
    main()
