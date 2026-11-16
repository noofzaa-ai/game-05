"""Split the Boss's LEVEL 15 race outfits (one look per race) into one GLB per race x armour slot.

Source: art_source/race_gear/race_outfits_lv15.glb (Boss delivery 2026-11-16; same layout as race_outfits.glb: 102-joint Studio
rig, 16 skinned meshes Outfit_Lv15_<Race>_<Boots|Gloves|Pants|Shirt>, ONE material "Level 15 | Original Armor.001", one 2048
JPEG atlas, no clips). Not shipped (art_source/).
Outputs (art/armor/race_shared/), next to the starter pieces they replace for the level-15 class armour:
  <race>_<slot>_lv15.glb           one mesh + the full rig; slot: shirt, pants, armband (= Gloves), shoes (= Boots)
  race_wardrobe_atlas_lv15.jpg     the atlas bytes as delivered, referenced by every GLB as an external image
The client (client/item_assets.gd) shows these for armour_<class>_<slot> items by the wearing card's race, and the starter
files (split_race_outfits.py) for the starter white kit and as the fallback.
Same pure glTF surgery as split_race_outfits.py: every kept accessor is copied byte for byte, the script re-reads each output
and checks the rig against the class bodies and each mesh against the source, and fails loudly on a difference.
Run: python -I tools/items/split_race_outfits_lv15.py   (from the repo root)
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_studio05_hair as glb  # noqa: E402

SOURCE = os.path.join(ROOT, "art_source", "race_gear", "race_outfits_lv15.glb")
OUT = os.path.join(ROOT, "art", "armor", "race_shared")
ATLAS = "race_wardrobe_atlas_lv15.jpg"
RACES = {"human": "Human", "viking": "Viking", "elf": "Elf", "runeborn": "Runeborn"}
SLOTS = {"shirt": "Shirt", "pants": "Pants", "armband": "Gloves", "shoes": "Boots"}


def source_mesh_name(race, slot):
    return "Outfit_Lv15_%s_%s" % (RACES[race], SLOTS[slot])


def main():
    js, binary = glb.read_glb(SOURCE)
    assert len(js["images"]) == 1 and len(js["materials"]) == 1 and not js.get("animations"), "unexpected source layout"
    assert js["materials"][0]["name"].startswith("Level 15 | Original Armor"), js["materials"][0]["name"]
    body_js, body_bin = glb.read_glb(os.path.join(ROOT, "art", "characters", "studio05", "split", "body_greatsword.glb"))
    rig = glb.rig_hash(body_js, body_bin)
    assert glb.rig_hash(js, binary) == rig, "the delivery's rig differs from the Studio body rig: stop, do not adapt"
    os.makedirs(OUT, exist_ok=True)
    view = js["bufferViews"][js["images"][0]["bufferView"]]
    start = view.get("byteOffset", 0)
    with open(os.path.join(OUT, ATLAS), "wb") as f:
        f.write(binary[start: start + view["byteLength"]])
    bare = json.loads(json.dumps(js))
    images, textures, samplers = bare.pop("images"), bare.pop("textures"), bare.pop("samplers", None)
    names = set(glb.meshed(js))
    expected = {source_mesh_name(r, s) for r in RACES for s in SLOTS}
    assert names == expected, sorted(names ^ expected)
    total = 0
    for race in RACES:
        for slot in SLOTS:
            keep = source_mesh_name(race, slot)
            part, part_bin = glb.subset(bare, binary, lambda n, keep=keep: "mesh" in n and n["name"] != keep, False)
            part["images"] = [{"name": images[0].get("name", "atlas"), "uri": ATLAS, "mimeType": "image/jpeg"}]
            part["textures"] = textures
            if samplers is not None:
                part["samplers"] = samplers
            part.setdefault("extras", {})["zorx_source"] = "race_outfits_lv15.glb " + keep
            out = os.path.join(OUT, "%s_%s_lv15.glb" % (race, slot))
            glb.write_glb(out, part, part_bin)
            nj, nb = glb.read_glb(out)
            assert glb.rig_hash(nj, nb) == rig
            assert list(glb.meshed(nj)) == [keep]
            assert glb.mesh_hash(nj, nb, glb.meshed(nj)[keep]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
            assert nj["materials"][0]["name"] == js["materials"][0]["name"]
            size = os.path.getsize(out)
            total += size
            tris = sum(js["accessors"][p["indices"]]["count"] for p in js["meshes"][glb.meshed(js)[keep]["mesh"]]["primitives"]) // 3 if "mesh" in glb.meshed(js)[keep] else -1
            print("  %-26s %8d bytes  %6d tris  <- %s" % (os.path.basename(out), size, tris, keep))
    atlas_size = os.path.getsize(os.path.join(OUT, ATLAS))
    print("  %-26s %8d bytes" % (ATLAS, atlas_size))
    print("rig identical to the Studio class bodies; meshes byte-identical; total %d bytes" % (total + atlas_size))


if __name__ == "__main__":
    main()
