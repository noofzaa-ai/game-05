"""Race gear sets data (design/gdd/race-gear-sets.md, Boss 2026-11-13). Idempotent: run again after editing the tables.

Writes into data/items/catalog.json, data/items/sets.json and data/items/starter_kits.json:
- 80 race pieces `race_<race>_<class>_<slot>` (slot: weapon, shirt, pants, armband, shoes). The weapon is in the class's
  weapon family; armour has the class's armour weight. Any card can wear any piece; the set option needs the card's race.
- 4 race sets `race_<race>` (kind "race"): steps 2 / 4 / 5 pieces that boost the race passive (cell_mod vocabulary).
- Removes the old game's items (Boss 2026-11-13): blade_01..07, the Ash/Obsidian/Royal armour and their sets, the neutral
  starter pieces and round_shield. Race pieces drop (drop_level 1) and make the starter kits and the shop stock.
- Asset hook: asset_path / icon_path point at the Studio files (art/armor/race_<race>/<class>/<slot>.glb,
  icon-<slot>.png; art/weapons/race_<race>/<class>.glb, icon-<class>.png). Every tier of a piece is the same item id,
  so one file serves white, blue, purple and gold. Until a file exists the client walks the fallback chain
  (client/item_assets.gd chain(): "a|b|c", first existing file wins, no code change when files land):
  armour = the race x class file -> the race's SHARED interim file (OUTFIT_SCOPE below);
  weapon = the race x class file -> the class weapon stand-in (procedural / asset_id).
Also removes the retired hat slot's items (Boss 2026-11-13: armour is shirt, pants, armband, shoes) and moves generic
set bonuses that needed 5 armour pieces to 4.
Keeps each file's line endings (CRLF / LF) and its JSON indent.
Usage: python -X utf8 tools/items/build_race_gear.py
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
RACES = {
    "human": ("Human", "มนุษย์", "Banner Gear", "ชุดธงศึก"),
    "viking": ("Viking", "ไวกิ้ง", "War Gear", "ชุดศึก"),
    "elf": ("Elf", "เอลฟ์", "Grove Gear", "ชุดพนาลัย"),
    "runeborn": ("Runeborn", "รูนบอร์น", "Rune Gear", "ชุดอักขระ"),
}
CLASSES = {
    "sword_shield": ("Sword & Shield", "ดาบโล่", "heavy", "blade", "Sword", "ดาบ"),
    "greatsword": ("Greatsword", "ดาบใหญ่", "heavy", "greatsword", "Greatsword", "ดาบใหญ่"),
    "longbow": ("Longbow", "ธนู", "light", "longbow", "Longbow", "ธนูยาว"),
    "magic": ("Magic", "เวท", "cloth", "magic", "Staff", "คทา"),
}
# Weapon stand-in look per class weapon type (shown when the Studio file does not load). Boss 2026-11-13: the legacy items
# (blade_01..07, Ash/Obsidian/Royal armour, neutral starter pieces, round_shield) are gone, so the race pieces carry these
# fields themselves instead of copying them from the starter items.
WEAPON_LOOK = {
    "blade": {"asset_id": "weapon_blade_01"},
    "greatsword": {"asset_id": "procedural_class_greatsword", "procedural": True},
    "longbow": {"asset_id": "procedural_class_longbow", "procedural": True},
    "magic": {"asset_id": "procedural_class_staff", "procedural": True},
}
ARMOR_MAIN_STAT = {"shirt": "DEF", "pants": "HP", "armband": "DEF", "shoes": "DEF"}
# Every race piece can drop: logic/loot.gd draws a catalog piece of the rolled slot, then logic/race_drops.gd makes it the
# piece of a squad card's race and class.
DROP_LEVEL = 1
LEGACY_SET = r"armor_(ash|obsidian|royal)_"


def is_legacy(item_id):
    """The old game's items (Boss 2026-11-13: remove everything from the old item system)."""
    return (re.fullmatch(r"blade_\d+", item_id) is not None or re.match(LEGACY_SET, item_id) is not None
            or item_id.startswith("starter_") or item_id == "round_shield")
ARMOR = {"shirt": ("Tunic", "เสื้อ"), "pants": ("Trousers", "กางเกง"), "armband": ("Armband", "ปลอกแขน"), "shoes": ("Boots", "รองเท้า")}
SLOTS = ["weapon", "shirt", "pants", "armband", "shoes"]
# Which delivered looks exist besides the final race x class files (Boss 2026-11-13: 16 armour looks + 16 weapons are
# the target; the Studio's race_outfits.glb, one look per race, is the interim look of every class at every tier).
# "class": only the race x class file.  "race": the race's shared file comes next in the chain.
OUTFIT_SCOPE = "race"
SHARED_ARMOR = "res://art/armor/race_shared/%s_%s.glb"  # tools/items/split_race_outfits.py
SHARED_ICON = "res://art/armor/race_shared/icon-%s_%s.png"  # rendered from the mesh (tools/shots/race_outfit_shots.gd)


def T(on, actions, **extra):
    d = {"type": "trigger", "on": on}
    d.update(extra)
    d["actions"] = actions
    return d


def mod(**fields):
    d = {"type": "cell_mod", "cell": "passive"}
    d.update(fields)
    return d


# GDD 3.8 (numbers at blue, m = 1.0). Step 4 "Attuned" and step 5 "Awakened" per race x class: (text, [effects]).
STEPS = {
    "human": {
        "sword_shield": (("Rallying Drill cooldown x0.85.", [mod(icd_mul=0.85)]),
                         ("The drill also trims every ally's skill cooldowns by 0.5 s.", [mod(extra_actions=[{"action": "skill_refresh", "target": "allies_all", "seconds": 0.5}])])),
        "greatsword": (("Skill radius +10%.", [mod(extra_effects=[{"type": "skill_mod", "radius_mul": 1.10}])]),
                       ("A skill that hits 3+ enemies cuts its cooldowns by 0.5 s (2 s cooldown).", [mod(extra_effects=[T("skill_hit", [{"action": "skill_refresh", "target": "self", "seconds": 0.5}], min_targets=3, cooldown_ticks=120)])])),
        "longbow": (("Skill crit rate +10.", [mod(extra_effects=[{"type": "skill_mod", "crit_add": 10.0}])]),
                    ("A kill cuts this card's skill cooldowns by 1 s.", [mod(extra_effects=[T("kill", [{"action": "skill_refresh", "target": "self", "seconds": 1.0}])])])),
        "magic": (("Skill cooldowns x0.95.", [mod(extra_effects=[{"type": "skill_mod", "cooldown_mul": 0.95}])]),
                  ("Every 4th skill cast refreshes 25% of this card's cooldowns.", [mod(extra_effects=[T("skill_cast", [{"action": "skill_refresh", "target": "self", "fraction": 0.25}], every_n=4)])])),
    },
    "viking": {
        "sword_shield": (("Unbroken triggers 5% HP higher.", [mod(hp_threshold_add=0.05)]),
                         ("Unbroken also gives Fortify for 4 s.", [mod(extra_actions=[{"action": "apply_status", "status": "fortify", "target": "self", "duration": 240}])])),
        "greatsword": (("Berserker reaches its full bonus 5% HP higher.", [mod(hp_threshold_add=0.05)]),
                       ("Blood Up: the first time each wave HP drops below 50%, Rage for 6 s.", [mod(extra_effects=[T("self_low_hp", [{"action": "apply_status", "status": "rage", "target": "self", "duration": 360}], hp_below=0.5, once_per_wave=True)])])),
        "longbow": (("Headhunter's Rage and Haste last 25% longer.", [mod(duration_mul=1.25)]),
                    ("A kill also heals 3% max HP.", [mod(extra_actions=[{"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.03}])])),
        "magic": (("A kill heals 3% max HP.", [mod(extra_effects=[T("kill", [{"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.03}])])]),
                  ("Skill damage +15% below 50% HP.", [mod(extra_effects=[{"type": "low_hp_scaling", "stat": "SKILL_DMG", "max_mul": 0.15, "below": 0.5}])])),
    },
    "elf": {
        "sword_shield": (("Warden's Grove cooldown x0.75.", [mod(icd_mul=0.75)]),
                         ("Each block also heals this card 1% max HP.", [mod(extra_actions=[{"action": "heal", "target": "self", "fraction_of": "max_hp", "fraction": 0.01}])])),
        "greatsword": (("Living Bark regen lasts 25% longer.", [mod(duration_mul=1.25)]),
                       ("A kill heals the most-hurt ally 3% max HP.", [mod(extra_effects=[T("kill", [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "max_hp", "fraction": 0.03}])])])),
        "longbow": (("Moonlit Arrow every 4th shot instead of every 5th.", [mod(every_n_add=-1)]),
                    ("Moonlit Arrow also gives the ally Regen for 3 s.", [mod(extra_actions=[{"action": "apply_status", "status": "regen", "target": "ally_most_hurt", "duration": 180}])])),
        "magic": (("Bloomcaster heals x1.15.", [mod(heal_mul=1.15)]),
                  ("Bloomcaster also shields the ally for 10% of the damage (cap 5% max HP).", [mod(extra_actions=[{"action": "shield", "target": "ally_most_hurt", "fraction_of": "damage", "fraction": 0.10, "cap_max_hp": 0.05}])])),
    },
    "runeborn": {
        "sword_shield": (("Rune Aegis needs 1 rune less.", [mod(charges_max_add=-1)]),
                         ("A discharge also shields the most-hurt ally 8% of this card's max HP.", [mod(extra_actions=[{"action": "shield", "target": "ally_most_hurt", "fraction_of": "source_max_hp", "fraction": 0.08}])])),
        "greatsword": (("Runic Edge needs 1 rune less.", [mod(charges_max_add=-1)]),
                       ("A discharge also gives Haste for 3 s.", [mod(extra_actions=[{"action": "apply_status", "status": "haste", "target": "self", "duration": 180}])])),
        "longbow": (("Glyph Shot needs 1 rune less.", [mod(charges_max_add=-1)]),
                    ("A discharge also bursts 60% ATK in 1.5 m around the target.", [mod(extra_actions=[{"action": "burst", "center": "target", "radius": 1.5, "atk_mul": 0.6}])])),
        "magic": (("Runeweaver keeps 1 rune after a discharge.", [mod(charges_reset_to=1)]),
                  ("A discharge also gives every ally Focus for 3 s.", [mod(extra_actions=[{"action": "apply_status", "status": "focus", "target": "allies_all", "duration": 180}])])),
    },
}


def load(rel):
    raw = (ROOT / rel).read_bytes()
    crlf = b"\r\n" in raw
    return json.loads(raw.decode("utf-8")), crlf


def save(rel, data, crlf, indent):
    text = json.dumps(data, indent=indent, ensure_ascii=False) + "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    (ROOT / rel).write_bytes(text.encode("utf-8"))


def main():
    catalog, cat_crlf = load("data/items/catalog.json")
    items = catalog["items"]
    for key in [k for k, v in items.items() if v.get("slot") == "hat" or k.startswith("race_") or is_legacy(k)]:
        del items[key]
    for race, (rname, rname_th, _, _) in RACES.items():
        for cls, (cname, cname_th, weight, wtype, wname, wname_th) in CLASSES.items():
            for slot in SLOTS:
                item_id = "race_%s_%s_%s" % (race, cls, slot)
                if slot == "weapon":
                    entry = {
                        "asset_id": WEAPON_LOOK[wtype]["asset_id"], "name": "%s %s" % (rname, wname), "name_th": "%s%s" % (wname_th, rname_th),
                        "slot": "weapon", "weapon_type": wtype, "set": "race_" + race, "race": race, "class": cls, "drop_level": DROP_LEVEL,
                        "asset_path": "res://art/weapons/race_%s/%s.glb" % (race, cls),
                        "icon_path": "res://art/weapons/race_%s/icon-%s.png" % (race, cls),
                    }
                    if WEAPON_LOOK[wtype].get("procedural"):
                        entry["procedural"] = True
                else:
                    sname, sname_th = ARMOR[slot]
                    entry = {
                        "asset_id": item_id, "name": "%s %s (%s)" % (rname, sname, cname), "name_th": "%s%s · %s" % (sname_th, rname_th, cname_th),
                        "slot": slot, "set": "race_" + race, "race": race, "class": cls, "drop_level": DROP_LEVEL, "armor_class": weight,
                        "main_stat": ARMOR_MAIN_STAT[slot],
                        "asset_path": "res://art/armor/race_%s/%s/%s.glb" % (race, cls, slot),
                        "icon_path": "res://art/armor/race_%s/%s/icon-%s.png" % (race, cls, slot),
                    }
                    if OUTFIT_SCOPE == "race":
                        entry["fallback_asset_path"] = SHARED_ARMOR % (race, slot)
                        entry["fallback_icon_path"] = SHARED_ICON % (race, slot)
                items[item_id] = entry
    # Race off-hand shields (Boss 2026-11-13: the Studio's sword & shield delivery has a shield per race): slot offhand
    # (Sword & Shield only), no set (the race set is weapon + 4 armour), one item for every tier. The procedural round
    # shield (asset_id + procedural) shows if the file fails to load; stats come from the rule book like any offhand.
    for race, (rname, rname_th, _, _) in RACES.items():
        items["race_%s_shield" % race] = {
            "asset_id": "procedural_round_shield", "name": "%s Shield" % rname, "name_th": "โล่%s" % rname_th,
            "slot": "offhand", "race": race, "class": "sword_shield", "drop_level": DROP_LEVEL, "procedural": True,
            "asset_path": "res://art/weapons/race_%s/shield.glb" % race,
            "icon_path": "res://art/weapons/race_%s/icon-shield.png" % race,
        }
    save("data/items/catalog.json", catalog, cat_crlf, 1)

    sets, sets_crlf = load("data/items/sets.json")
    for set_id in [k for k in sets["sets"] if k.startswith("race_") or re.match(LEGACY_SET, k)]:
        del sets["sets"][set_id]
    sets["starter_armor_sets"] = []  # the old wardrobe grant (Profile.ensure_starter_armor) listed only legacy sets
    for info in sets["sets"].values():  # 4 armour slots now: a 5-piece bonus moves to 4 (PO default 2026-11-13)
        for bonus in info.get("bonuses", []):
            bonus["pieces"] = min(int(bonus["pieces"]), 4)
    for race, (rname, rname_th, gear, gear_th) in RACES.items():
        attuned, awakened = {}, {}
        for cls in CLASSES:
            (t4, e4), (t5, e5) = STEPS[race][cls]
            attuned[cls] = {"text": t4, "effects": e4}
            awakened[cls] = {"text": t5, "effects": e5}
        attuned["default_class"] = {"text": "The passive's numbers +5% more.", "effects": [mod(scale_add=0.05)]}
        sets["sets"]["race_" + race] = {
            "name": "%s %s" % (rname, gear), "name_th": "%s%s" % (gear_th, rname_th), "kind": "race", "race": race,
            "tier_mul": {"normal": 0.75, "rare": 1.0, "epic": 1.25, "legendary": 1.5},
            "steps": [
                {"pieces": 2, "name": "Kindled", "all": {"text": "The race passive's numbers +10%.", "effects": [mod(scale_add=0.10)]}},
                {"pieces": 4, "name": "Attuned", "by_class": attuned},
                {"pieces": 5, "name": "Awakened", "by_class": awakened},
            ],
            "bonuses": [],
        }
    sets["_race_sets"] = ("Race gear sets (design/gdd/race-gear-sets.md 3.5-3.10, Boss 2026-11-13; built by tools/items/build_race_gear.py). "
                          "kind race: 5 pieces (the race weapon of the class + shirt, pants, armband, shoes). The set option works only when the card's race "
                          "equals `race`; steps boost the race passive with cell_mod words (logic/race_sets.gd). A step's numbers x tier_mul of the LOWEST "
                          "tier among the N best pieces it counts (white starter 0.75, PO default). bonuses stays empty: ItemCatalog.set_bonus ignores race sets.")
    save("data/items/sets.json", sets, sets_crlf, 2)

    kits, kits_crlf = load("data/items/starter_kits.json")
    kits.pop("race_kit", None)
    kits.pop("_race_kit", None)
    kits["version"] = 4
    kits["kits"] = {cls: {slot: "race_{race}_%s_%s" % (cls, slot) for slot in SLOTS} for cls in CLASSES}
    kits["offhand"] = "race_{race}_shield"
    kits["_comment"] = ("Class starter kits (design/gdd/race-gear-sets.md 3.2-3.3, Boss 2026-11-13; built by tools/items/build_race_gear.py). "
                        "Every class card starts wearing its OWN race's starter outfit at tier `tier` (white): `kits` maps class -> slot -> "
                        "a catalog id, {race} = the card's race. `offhand`: the starter shield of a card whose offhand slot is open (Sword & "
                        "Shield), {race} likewise. logic/profile.gd: new players get the kit; old saves get it once (starter_kit_version) in "
                        "EMPTY slots only. Accessories start empty. The neutral starter pieces and round_shield are gone (Boss 2026-11-13).")
    text = json.dumps(kits, indent=1, ensure_ascii=False) + "\n"
    (ROOT / "data/items/starter_kits.json").write_bytes((text.replace("\n", "\r\n") if kits_crlf else text).encode("utf-8"))

    shop, shop_crlf = load("data/items/shop.json")
    # Boss 2026-11-13 (PO default): the merchant sells the race armour of the Sword & Shield look (any card may wear any
    # armour) plus each race's shield; legacy stock is gone. White like every shop piece (equipment_tier).
    shop["catalog_items"] = (["race_%s_sword_shield_%s" % (race, slot) for race in RACES for slot in ARMOR]
                             + ["race_%s_shield" % race for race in RACES])
    save("data/items/shop.json", shop, shop_crlf, 2)

    tuning, tun_crlf = load("data/items/equipment_tuning.json")
    weights = tuning["mobility"]["slot_weights"] if "mobility" in tuning else None
    if weights is None:
        for value in tuning.values():
            if isinstance(value, dict) and "slot_weights" in value:
                weights = value["slot_weights"]
    if weights is not None and "hat" in weights:
        weights["shirt"] = round(weights["shirt"] + weights.pop("hat"), 4)  # the hat's weight share moves to the shirt
    for value in tuning.values():  # race armour carries armor_class itself; the legacy set ids are gone
        if isinstance(value, dict) and "set_classes" in value:
            value["set_classes"] = {k: v for k, v in value["set_classes"].items() if not re.match(LEGACY_SET, k)}
    save("data/items/equipment_tuning.json", tuning, tun_crlf, 2)

    mig, mig_crlf = load("data/items/armor_migration.json")
    # The old identity remap (scout_vest -> Ash Knight, unknown armour -> plain Ash) pointed at legacy items, which are gone.
    # A save's legacy piece becomes a race piece once (logic/legacy_items.gd); armor_migration.gd now keeps every identity.
    mig["version"] = 3
    mig["aliases"] = {}
    mig["plain_slots"] = {}
    mig["allowed_armor"] = {}
    save("data/items/armor_migration.json", mig, mig_crlf, 2)

if __name__ == "__main__":
    main()
