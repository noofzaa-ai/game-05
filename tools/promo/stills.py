"""ZORX social stills (Boss 2026-11-15): landscape 1920x1080 PNGs from the 3840x2160 captures of
tools/promo/promo_capture.gd (--promo=stills_hub / stills_card / stills_battle), plus a ZORX logo ribbon version of
shots 1, 7 and 10. Clean shots: no captions. Landscape only (Boss: no square crops).

    python tools/promo/stills.py

Output: art_source/promo/2026-11-15/stills/NN_name.png and NN_name_logo.png
"""
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FRAMES = Path(os.environ.get("ZORX_PROMO_FRAMES", Path(os.environ["TEMP"]) / "zorx_promo_frames"))
OUT = ROOT / "art_source" / "promo" / "2026-11-15" / "stills"
W, H = 1920, 1080
# the battle runs are captured at 1920x1080 (the battle HUD is pixel-sized) into their own folder
BATTLE_FRAMES = Path(os.environ.get("ZORX_PROMO_BATTLE_FRAMES", Path(os.environ["TEMP"]) / "zorx_promo_frames4"))
BATTLE_RUNS = {"stills_battle", "stills_face"}
TAVIRAJ = str(ROOT / "art/fonts/Taviraj-SemiBold.woff2")
INK = (58, 36, 20)

# name -> (run, captured frame, crop box in 3840x2160 px or None for the full frame; the crop is 16:9)
PICKS = {
    "01_hub": ("stills_hub", "01_hub", None),
    "02_card_closeup": ("stills_card", "02_card_tilt_0", None),
    "03_character_gear": ("stills_hub", "03_character_gear", None),
    "04_skill_tree": ("stills_hub", "04_skill_tree", None),
    "05_tailor": ("stills_hub", "05_tailor", None),
    "06_race_picker": ("stills_hub", "06_race_picker", None),
    "07_battle_overview": ("stills_battle", "07_battle_overview_f240", None),
    "08_battle_closeup": ("stills_face", "08_face_f660", None),
    "09_boss_goblin_chief": ("stills_battle", "09_boss_f240", None),
    "10_unlock_ceremony": ("stills_hub", "10_unlock_ceremony_f084", None),
    "11_fight_loading": ("stills_hub", "11_fight_loading_f11", None),
}
LOGO = ["01_hub", "07_battle_overview", "10_unlock_ceremony"]
# the ribbon corner per shot (kept clear of the shot's own top-left title / top-right buttons)
LOGO_CORNER = {"01_hub": "bottom_left", "07_battle_overview": "top_left", "10_unlock_ceremony": "bottom_right"}


def ribbon(width):
    rib = Image.open(ROOT / "art/ui/hub_carved/title_ribbon.png").convert("RGBA")
    rib = rib.resize((width, int(rib.height * width / rib.width)), Image.LANCZOS)
    d = ImageDraw.Draw(rib)
    zf = ImageFont.truetype(TAVIRAJ, int(width * 0.17), layout_engine=ImageFont.Layout.RAQM)
    d.text((width / 2, rib.height * 0.31), "Z O R X", font=zf, fill=INK, anchor="mm", stroke_width=2, stroke_fill=(255, 246, 224))
    return rib


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    picks = PICKS
    for name, (run, shot, box) in picks.items():
        src = FRAMES / run / "stills" / (shot + ".png")
        if run in BATTLE_RUNS:
            src = BATTLE_FRAMES / run / "stills" / (shot + ".png")
        if not src.exists():
            print("missing", src)
            continue
        img = Image.open(src).convert("RGB")
        if box:
            img = img.crop(box)
        img = img.resize((W, H), Image.LANCZOS)
        img.save(OUT / (name + ".png"), optimize=True)
        print(name, img.size)
        if name in LOGO:
            rib = ribbon(330)
            m = 34
            corner = LOGO_CORNER[name]
            x = m if "left" in corner else W - rib.width - m
            y = m if "top" in corner else H - rib.height - m + 18
            logo = img.convert("RGBA")
            logo.alpha_composite(rib, (x, y))
            logo.convert("RGB").save(OUT / (name + "_logo.png"), optimize=True)


if __name__ == "__main__":
    main()
