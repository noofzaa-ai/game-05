"""Split the Studio team's race starter outfits (one look per race) into one GLB per race x armour slot.

Source: art_source/race_gear/race_outfits.glb (Boss delivery 2026-11-13, copied from the shared drive; 102-joint Studio
rig, 16 skinned meshes Outfit_<Race>_<Shirt|Pants|Gloves|Boots>.001, one material, one 2048 JPEG atlas, no clips).
Outputs (art/armor/race_shared/):
  <race>_<slot>.glb           one mesh + the full rig; slot: shirt, pants, armband (= Gloves), shoes (= Boots)
  race_wardrobe_atlas.jpg     the atlas bytes as delivered, referenced by every GLB as an external image (one copy
                              on disk and in the web pack instead of 16 embedded copies)
These are the INTERIM look of every class's race piece (docs/art/race_gear_handoff.md): the client shows
art/armor/race_<race>/<class>/<slot>.glb when the Studio sends it, else this shared race file, else the class armour.

Pure glTF JSON/binary surgery (helpers from tools/characters/split_studio05_hair.py): every kept accessor is copied
byte for byte, so joints, inverse binds, rest transforms, weights, UVs and the material stay identical. The script
re-reads each output and checks the rig against the class bodies (art/characters/studio05/split/body_*.glb) and each
mesh against the source, and fails loudly on a difference.
Also splits the Studio's race weapons (art_source/race_gear/sword_shield_weapons.glb, 2026-11-13, MID tier, same rig,
meshes Weapon_<Race>_<Sword|Shield> weighted 100% to RightHand / LeftForeArm exactly like the class gear's
"| Sword" / "| Shield"): art/weapons/race_<race>/sword_shield.glb (the sword) and art/weapons/race_<race>/shield.glb
(the race off-hand shield), node renamed "Weapon_<Race> | Sword" / "| Shield" (the class-gear label the client reads;
mesh bytes unchanged), textures once in art/weapons/race_shared/.
Run: python -I tools/items/split_race_outfits.py   (from the repo root; re-run after a new Studio drop)
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_studio05_hair as glb  # noqa: E402  (read_glb, write_glb, subset, mesh_hash, rig_hash, meshed)

SOURCE = os.path.join(ROOT, "art_source", "race_gear", "race_outfits.glb")
OUT = os.path.join(ROOT, "art", "armor", "race_shared")
ATLAS = "race_wardrobe_atlas.jpg"
RACES = {"human": "Human", "viking": "Viking", "elf": "Elf", "runeborn": "Runeborn"}
SLOTS = {"shirt": "Shirt", "pants": "Pants", "armband": "Gloves", "shoes": "Boots"}


def source_mesh_name(race, slot):
    return "Outfit_%s_%s.001" % (RACES[race], SLOTS[slot])


WEAPONS_SOURCE = os.path.join(ROOT, "art_source", "race_gear", "sword_shield_weapons.glb")
WEAPON_TEXTURES = os.path.join(ROOT, "art", "weapons", "race_shared")
WEAPON_PIECES = {"Sword": "sword_shield.glb", "Shield": "shield.glb"}  # mesh kind -> file in art/weapons/race_<race>/


def split_weapons(rig):
    if not os.path.exists(WEAPONS_SOURCE):
        return 0
    js, binary = glb.read_glb(WEAPONS_SOURCE)
    assert glb.rig_hash(js, binary) == rig, "weapon delivery rig differs from the Studio body rig: stop"
    os.makedirs(WEAPON_TEXTURES, exist_ok=True)
    uris = []
    for index, image in enumerate(js["images"]):
        view = js["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        name = "ss_weapons_%d.jpg" % index
        with open(os.path.join(WEAPON_TEXTURES, name), "wb") as f:
            f.write(binary[start: start + view["byteLength"]])
        uris.append({"name": image.get("name", name), "uri": "../race_shared/" + name, "mimeType": image.get("mimeType", "image/jpeg")})
        print("  %-22s %8d bytes" % (name, view["byteLength"]))
    bare = json.loads(json.dumps(js))
    textures, samplers = bare.pop("textures"), bare.pop("samplers", None)
    bare.pop("images")
    total = 0
    for race in RACES:
        for kind, file in WEAPON_PIECES.items():
            keep = "Weapon_%s_%s" % (RACES[race], kind)
            assert keep in glb.meshed(js), keep
            part, part_bin = glb.subset(bare, binary, lambda n, keep=keep: "mesh" in n and n["name"] != keep, False)
            used = sorted({m.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1) for m in part["materials"]} |
                          {m.get("normalTexture", {}).get("index", -1) for m in part["materials"]} |
                          {m.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture", {}).get("index", -1) for m in part["materials"]})
            part["images"] = uris
            part["textures"] = textures
            if samplers is not None:
                part["samplers"] = samplers
            for node in part["nodes"]:
                if node.get("name") == keep:
                    node["name"] = "Weapon_%s | %s" % (RACES[race], kind)
            part.setdefault("extras", {})["zorx_source"] = "sword_shield_weapons.glb " + keep
            folder = os.path.join(ROOT, "art", "weapons", "race_" + race)
            os.makedirs(folder, exist_ok=True)
            out = os.path.join(folder, file)
            glb.write_glb(out, part, part_bin)
            nj, nb = glb.read_glb(out)
            assert glb.rig_hash(nj, nb) == rig
            label = "Weapon_%s | %s" % (RACES[race], kind)
            assert list(glb.meshed(nj)) == [label]
            assert glb.mesh_hash(nj, nb, glb.meshed(nj)[label]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
            total += os.path.getsize(out)
            print("  %-34s %8d bytes  <- %s (textures %s)" % (os.path.relpath(out, ROOT), os.path.getsize(out), keep, used))
    return total


def main():
    js, binary = glb.read_glb(SOURCE)
    assert len(js["images"]) == 1 and len(js["materials"]) == 1 and not js.get("animations"), "unexpected source layout"
    body_js, body_bin = glb.read_glb(os.path.join(ROOT, "art", "characters", "studio05", "split", "body_greatsword.glb"))
    rig = glb.rig_hash(body_js, body_bin)
    assert glb.rig_hash(js, binary) == rig, "the delivery's rig differs from the Studio body rig: stop, do not adapt"
    os.makedirs(OUT, exist_ok=True)
    view = js["bufferViews"][js["images"][0]["bufferView"]]
    start = view.get("byteOffset", 0)
    with open(os.path.join(OUT, ATLAS), "wb") as f:
        f.write(binary[start: start + view["byteLength"]])
    # the texture goes out as an external file: strip it before the subset, add the URI back after
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
            part.setdefault("extras", {})["zorx_source"] = "race_outfits.glb " + keep
            out = os.path.join(OUT, "%s_%s.glb" % (race, slot))
            glb.write_glb(out, part, part_bin)
            nj, nb = glb.read_glb(out)
            assert glb.rig_hash(nj, nb) == rig
            assert list(glb.meshed(nj)) == [keep]
            assert glb.mesh_hash(nj, nb, glb.meshed(nj)[keep]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
            size = os.path.getsize(out)
            total += size
            print("  %-22s %8d bytes  <- %s" % (os.path.basename(out), size, keep))
    atlas_size = os.path.getsize(os.path.join(OUT, ATLAS))
    print("  %-22s %8d bytes" % (ATLAS, atlas_size))
    print("rig identical to the Studio class bodies; meshes byte-identical; total %d bytes" % (total + atlas_size))
    print("weapons: %d bytes of GLB" % split_weapons(rig))


if __name__ == "__main__":
    main()
