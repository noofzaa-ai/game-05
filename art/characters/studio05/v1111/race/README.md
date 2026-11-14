# Studio race heads (v1111)

- `race_heads.glb`: Boss delivery 2026-11-14 (Studio team; Boss file `Downloads/race_heads.glb`, SHA-1
  `45996bf0e558f44d8b1e81fbafc4c287d0771752`). Copied as delivered, no change. The source copy is also kept in
  `art_source/race_heads/race_heads.glb` (not shipped).
- Scene "Studio race head export", one skin "StudioRaceRig": 102 joints with the same names, order, rest transforms,
  child lists and byte-identical inverse binds as `split/body_<class>.glb` and `hair/hair_i.glb` (checked with
  `tools/characters/split_studio05_hair.py rig_hash`: c992e286541bfd4b3875aced15c3067ed422371e). No clips.
- Meshes (all weighted 100% to `mixamorig:Head`, like the Studio `Head_Anime`):
  | mesh | material | tris | note |
  |---|---|---|---|
  | `Head_Anime_Elf` | Warm skin.001 | 2200 | long ears; no UV (face drawn by the toon shader like Head_Anime) |
  | `Head_Anime_Runeborn` | Warm skin.001 | 2200 | plain head under the rune overlay |
  | `Head_Anime_Viking` | Viking \| Forest War Paint | 2800 | UV + embedded 1536x1024 PNG (war paint + right-temple tattoo) |
  | `Runeborn_Face_Runes_Studio` | Runeborn runes \| Ink, \| Cyan emission | 2636 | separate rune geometry on the face |
- The embedded paint is extracted by Godot to `race_heads_Viking War Paint and Right Temple Tattoo.png`, imported
  lossy 0.85, size limit 1024, mipmaps.
- Used by `data/races/<id>.json` "look" (`head_file`, `head`, `overlay`) and
  `client/characters/studio05_character_model.gd` `set_race_look()`. Human uses the default `Head_Anime`.
