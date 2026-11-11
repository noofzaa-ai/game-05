"""English display names of the cosmetic choices (Boss 2026-11-11: game text in English).

The data/cosmetics/*.json choice lists were written by hand (no generator), so this script renames them in place:
`name` becomes English (plain ASCII: the web font), `name_th` keeps the Thai name, the same pattern as
tools/items/armor_names.py. data/cosmetics/reference_controls.json is the Studio's own option inventory (source
parity record) and is left as it is. Safe to re-run. From the project root:

    python tools/items/cosmetic_names.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]

# file -> {choice id -> English name}
NAMES = {
    "fashion.json": {
        "none": "Show equipped armor",
        "red": "Red Jacket + Jeans",
        "purple": "Bunny Top + Purple Skirt",
        "black": "Black Jacket + Striped Pants",
        "mono": "Mono Menswear - Z Tee",
        "fem": "Lavender Dress - Stars + Plaid",
        "black_zip": "Black Set - Zip Jacket",
        "black_bow": "Black Set - Bow Tube Top",
        "white_ribbon": "Mono Set - Ribbon Blouse",
        "white_corset": "Mono Set - Corset Skirt",
        "cocoa_knit": "Cocoa Knit - Pleated Skirt",
        "white_tee_cargo": "Print Tee - Cargo Shorts",
        "white_tee_shorts": "Plain Tee - Rolled Shorts",
        "black_khaki": "Black Shirt - Khaki Pants",
        "leather_hoodie": "Leather + Gray Hoodie - Washed Jeans",
        "bat_club": "Bat Club - Purple Hoodie",
        "pumpkin_night": "Pumpkin Night - Overalls",
        "little_ghost": "Little Ghost - Cape",
        "moon_witch": "Moon Witch",
        "bat_club_male": "Bat Club (Male)",
        "pumpkin_night_male": "Pumpkin Night (Male)",
        "little_ghost_male": "Little Ghost (Male)",
        "moon_witch_male": "Moon Wizard (Male)",
    },
    "fashion_back.json": {
        "none": "No back accessory",
        "angel_wings": "White Feather Wings",
        "angel_wings_black": "Black Feather Wings",
        "panda_backpack": "Panda Backpack",
        "teddy_backpack": "Teddy Bear Backpack",
        "cocoa_knit": "Brown Bear Bag",
        "bat_club": "Black Bat Bag",
        "pumpkin_night": "Pumpkin Bag",
        "little_ghost": "Little Ghost Bag",
        "moon_witch": "Purple Witch Bag",
    },
    "fashion_hats.json": {
        "none": "No hat",
        "black": "Black Leather Hat",
        "cat": "Cat Ears",
        "moon_witch": "Crescent Witch Hat",
        "pumpkin_night": "Pumpkin Hat",
        "little_ghost": "Little Ghost Hat",
        "bat_club": "Bat Ear Headband",
        "fantasy_01": "01 - Orange Crescent Witch",
        "fantasy_02": "02 - Ivory Plumed Top Hat",
        "fantasy_03": "03 - Compass Explorer",
        "fantasy_04": "04 - Pumpkin Beret",
        "fantasy_05": "05 - Blue Gold-Star Wizard",
        "fantasy_06": "06 - Red Bat Bowler",
        "fantasy_07": "07 - Green Leaf Pointed Hat",
        "fantasy_08": "08 - Purple Ghost Bucket",
        "fantasy_09": "09 - Pirate Tricorn",
        "fantasy_10": "10 - Yellow Flower Brim",
        "fantasy_11": "11 - Black Crescent Newsboy",
        "fantasy_12": "12 - Blue Jewel Top Hat",
    },
    "hair_styles.json": {
        "red": "Long Bangs + Black Ponytail",
        "purple": "Pink-Purple Bob",
        "black": "Long Pink-Purple Waves",
        "vintage_swept_quiff": "Vintage Swept Quiff",
        "vintage_pompadour": "Vintage Faded Pompadour",
        "mens_short": "Side-Part Short Cut",
        "two_block": "Two-Block - Long Nape",
        "short_bob": "Short Brown Bob - Side Part",
        "swept_highlight": "Swept Brown - Gold Highlights",
        "medium_layers": "Brown Layers - Curved Bangs",
    },
    "faces.json": {
        "original": "Original",
        "01": "01 - Open, Sharp",
        "02": "02 - Sleepy",
        "03": "03 - Soft Curve",
        "04": "04 - Slanted",
        "05": "05 - Sweet Round",
        "06": "06 - Big Round",
        "07": "07 - Cat Eye, Slit Pupil",
        "08": "08 - Fierce",
    },
    "eye_colors.json": {"turquoise": "Turquoise", "green": "Green", "violet": "Violet", "brown": "Brown"},
    "skin_tones.json": {"fair": "Fair", "natural": "Natural", "tan": "Tan", "deep": "Deep"},
    "blink_modes.json": {"auto": "Auto - Random Timing", "open": "Always Open", "closed": "Always Closed"},
    "wear_modes.json": {"on": "Show", "off": "Hide"},
}


def _is_thai(text):
    return any("฀" <= ch <= "๿" for ch in text)


def main():
    renamed = 0
    for file_name, names in NAMES.items():
        path = ROOT / "data/cosmetics" / file_name
        data = json.loads(path.read_text(encoding="utf-8"))
        list_key = next(k for k, v in data.items() if isinstance(v, list))
        for i, entry in enumerate(data[list_key]):
            en = names.get(str(entry.get("id", "")))
            if en is None:
                continue
            assert en.isascii(), en
            th = entry.get("name_th") or (entry.get("name") if _is_thai(str(entry.get("name", ""))) else "")
            rebuilt = {}
            for key, value in entry.items():  # keep the key order, name_th right after name
                if key == "name_th":
                    continue
                rebuilt[key] = en if key == "name" else value
                if key == "name" and th:
                    rebuilt["name_th"] = th
            if rebuilt != entry:
                renamed += 1
            data[list_key][i] = rebuilt
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("renamed %d cosmetic choices" % renamed)


if __name__ == "__main__":
    main()
