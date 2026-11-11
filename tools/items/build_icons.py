"""Makes the inventory icons of catalog items from the model team's thumbnails.

Each asset in art/items/<category>/ comes with a 320x320 preview PNG next to its .glb. This crops
it to the picture (transparent edges cut off, a little margin kept), scales it to ICON_SIZE and
writes art/items/icons/<asset_id>.png, which the inventory shows (client/item_assets.gd icon()).
The big previews are left out of the web build; only these small icons ship. Run from the project
root after build_catalog.py (and then `godot --headless --path . --import`):

    python tools/items/build_icons.py
"""
import json
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICON_SIZE = 96
MARGIN = 0.06  # of the icon size, on every side
BACKGROUND_TOLERANCE = 28  # how far (per channel sum) a backdrop pixel may stray from its neighbours


def _cut_background(picture):
    """The previews are rendered on a flat grey backdrop: flood it away from the edges (so grey
    inside the item stays) and make it transparent."""
    marker = (255, 0, 255)
    flat = picture.convert("RGB")
    width, height = flat.size
    for x, y in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (width // 2, 0), (width // 2, height - 1), (0, height // 2), (width - 1, height // 2)]:
        if flat.getpixel((x, y)) != marker:
            ImageDraw.floodfill(flat, (x, y), marker, thresh=BACKGROUND_TOLERANCE)
    mask = Image.new("L", flat.size, 255)
    pixels = flat.load()
    mask_pixels = mask.load()
    for y in range(height):
        for x in range(width):
            if pixels[x, y] == marker:
                mask_pixels[x, y] = 0
    picture.putalpha(mask)
    return picture


def main():
    manifest = json.loads((ROOT / "art/items/item_manifest.json").read_text(encoding="utf-8"))["items"]
    catalog = json.loads((ROOT / "data/items/catalog.json").read_text(encoding="utf-8"))["items"]
    wanted = {entry["asset_id"] for entry in catalog.values()}
    out_dir = ROOT / "art/items/icons"
    out_dir.mkdir(exist_ok=True)
    made, missing = 0, []
    for asset in manifest:
        if asset["id"] not in wanted:
            continue
        glb = ROOT / asset["asset_path"].removeprefix("res://")
        source = glb.with_suffix(".png")
        if not source.exists():
            missing.append(asset["id"])
            continue
        picture = _cut_background(Image.open(source).convert("RGBA"))
        box =picture.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if box:
            picture = picture.crop(box)
        inner = round(ICON_SIZE * (1.0 - 2.0 * MARGIN))
        scale = inner / max(picture.size)
        picture = picture.resize((max(1, round(picture.width * scale)), max(1, round(picture.height * scale))), Image.LANCZOS)
        icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
        icon.paste(picture, ((ICON_SIZE - picture.width) // 2, (ICON_SIZE - picture.height) // 2), picture)
        icon.save(out_dir / f"{asset['id']}.png", optimize=True)
        made += 1
    print(f"made {made} icons; no thumbnail: {missing}")


if __name__ == "__main__":
    main()
