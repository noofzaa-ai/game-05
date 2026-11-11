# Imported skill packs

From the model team's `godot_runtime.zip` (2026-10-12), processed by `tools/skills/shrink_skills.py`
(re-run it on a new pack: `python3 tools/skills/shrink_skills.py <unzipped pack>` then Godot `--import`).
Per skill only `<id>.tres`, `skill.json`, `motion.glb`, `vfx.glb` (+ the textures Godot extracts from the GLB).
Which pack a move shows is `in_game` in `skill_manifest.json`; today only `blade_ultimate -> blade_inferno_ultimate`.
The other 29 are in the build but not wired (combat-designer's job).

What the shrink does: motion.glb loses the reference body (28 meshes, 5,585 tris) and keeps the 57-bone skin
+ clip (one 1-triangle carrier mesh so the Skeleton3D is still built); VFX keys that a straight line
already gives are dropped (1 mm / 0.001 quaternion / 0.001 scale); zero scales become 1e-4 (no more
"Basis must be normalized" import errors: 14,900 lines before, 0 now); Godot lossy animation compression
on (page 512 KB for VFX, 16 KB for motion); shared flame texture 1536x1024 -> 768x512, lossy WebP import.
VFX meshes are not decimated: every pack is within its own triangle cap (<= 10,000).

Sizes in MB. "export" = the files Godot puts in the web pck (`.godot/imported`).

| id | type | our weapon id | length s | raw before / after | export before / after | VFX tris | notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| `blade_earth_slam_ultimate` | blade | `blade` (move `blade_ultimate`) | 4.34 | 7.99 / 4.49 | 1.74 / 0.81 | 9,675 | caster dashes forward (Godot moves the actor); look tuned with earth_slam_presentation.gd |
| `blade_earth_split_ultimate` | blade | `blade` (move `blade_ultimate`) | 3.4 | 4.58 / 1.66 | 0.73 / 0.36 | 4,400 | 179 zero-scale nodes -> 1e-4 |
| `blade_inferno_ultimate` | blade | `blade` (move `blade_ultimate`) | 3.2 | 4.29 / 1.63 | 0.74 / 0.35 | 4,732 | IN GAME (blade_ultimate); replaced our v2 (1,268 tris) with the pack v4; look tuned with inferno_spectacle.gd; 108 zero-scale nodes -> 1e-4 |
| `blade_solar_slam_ultimate` | blade | `blade` (move `blade_ultimate`) | 4.34 | 6.66 / 3.68 | 1.96 / 0.73 | 9,951 | caster dashes forward (Godot moves the actor); look tuned with solar_slam_presentation.gd |
| `blade_thunder_slam_ultimate` | blade | `blade` (move `blade_ultimate`) | 4.34 | 6.15 / 3.15 | 1.06 / 0.50 | 9,970 | caster dashes forward (Godot moves the actor); look tuned with thunder_slam_presentation.gd |
| `blade_thunder_slash_ultimate` | blade | `blade` (move `blade_ultimate`) | 3.4 | 4.37 / 1.48 | 0.66 / 0.33 | 4,746 | 105 zero-scale nodes -> 1e-4 |
| `blade_tidal_dash_ultimate` | blade | `blade` (move `blade_ultimate`) | 2.0 | 3.34 / 1.50 | 0.66 / 0.33 | 4,608 | caster dashes forward (Godot moves the actor); 102 zero-scale nodes -> 1e-4 |
| `blade_tidal_slam_ultimate` | blade | `blade` (move `blade_ultimate`) | 4.34 | 7.53 / 4.05 | 2.25 / 0.83 | 9,514 | caster dashes forward (Godot moves the actor); look tuned with tidal_slam_presentation.gd |
| `blade_verdant_wind_ultimate` | blade | `blade` (move `blade_ultimate`) | 3.4 | 4.56 / 1.73 | 0.79 / 0.39 | 4,896 | 114 zero-scale nodes -> 1e-4 |
| `dagger_ember_flip_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 2.0 | 3.73 / 1.90 | 0.93 / 0.41 | 4,552 | caster dashes forward (Godot moves the actor); 225 zero-scale nodes -> 1e-4 |
| `dagger_leaf_spin_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 2.6 | 3.83 / 1.70 | 0.80 / 0.37 | 4,312 | caster dashes forward (Godot moves the actor); 114 zero-scale nodes -> 1e-4 |
| `dagger_shadow_extraction_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 4.0 | 4.90 / 2.02 | 0.90 / 0.39 | 7,168 | look tuned with shadow_extraction_presentation.gd; 926 zero-scale nodes -> 1e-4 |
| `dagger_stone_skid_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 2.8 | 4.07 / 1.67 | 0.78 / 0.36 | 4,072 | caster dashes forward (Godot moves the actor); 127 zero-scale nodes -> 1e-4 |
| `dagger_thunder_rush_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 2.2 | 3.52 / 1.58 | 0.75 / 0.36 | 4,192 | caster dashes forward (Godot moves the actor); 119 zero-scale nodes -> 1e-4 |
| `dagger_tidal_cross_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 2.4 | 3.77 / 1.67 | 0.77 / 0.36 | 4,368 | caster dashes forward (Godot moves the actor); 135 zero-scale nodes -> 1e-4 |
| `dagger_venom_barrage_ultimate` | dagger | `dagger` (move `dagger_ultimate`) | 3.0 | 4.68 / 1.90 | 0.84 / 0.40 | 4,776 | caster dashes forward (Godot moves the actor); 208 zero-scale nodes -> 1e-4 |
| `hammer_inferno_crush_ultimate` | hammer | `hammer` (move `hammer_ultimate`) | 3.8 | 4.71 / 1.58 | 0.78 / 0.35 | 4,188 | 95 zero-scale nodes -> 1e-4 |
| `hammer_quake_leap_ultimate` | hammer | `hammer` (move `hammer_ultimate`) | 3.6 | 4.65 / 1.51 | 0.73 / 0.35 | 4,036 | caster dashes forward (Godot moves the actor); 109 zero-scale nodes -> 1e-4 |
| `hammer_storm_wheel_ultimate` | hammer | `hammer` (move `hammer_ultimate`) | 4.2 | 5.04 / 1.67 | 0.80 / 0.37 | 4,372 | 98 zero-scale nodes -> 1e-4 |
| `hammer_thunder_crush_ultimate` | hammer | `hammer` (move `hammer_ultimate`) | 3.8 | 4.75 / 1.57 | 0.78 / 0.36 | 4,252 | 103 zero-scale nodes -> 1e-4 |
| `hammer_tidal_drop_ultimate` | hammer | `hammer` (move `hammer_ultimate`) | 4.0 | 5.03 / 1.62 | 0.80 / 0.36 | 4,428 | 119 zero-scale nodes -> 1e-4 |
| `spear_earth_sky_throw_ultimate` | spear | `spear` (move `spear_ultimate`) | 4.2 | 7.30 / 3.25 | 1.68 / 0.79 | 9,289 | spear thrown and recalled (spear_throw_recall.gd); look tuned with earth_slam_presentation.gd |
| `spear_fire_sky_throw_ultimate` | spear | `spear` (move `spear_ultimate`) | 4.2 | 6.04 / 2.62 | 1.97 / 0.66 | 9,565 | spear thrown and recalled (spear_throw_recall.gd); look tuned with solar_slam_presentation.gd |
| `spear_inferno_sweep_ultimate` | spear | `spear` (move `spear_ultimate`) | 3.4 | 4.39 / 1.57 | 0.77 / 0.35 | 4,188 | 95 zero-scale nodes -> 1e-4 |
| `spear_leaf_vault_ultimate` | spear | `spear` (move `spear_ultimate`) | 2.8 | 3.93 / 1.66 | 0.77 / 0.36 | 4,372 | caster dashes forward (Godot moves the actor); 98 zero-scale nodes -> 1e-4 |
| `spear_stone_reap_ultimate` | spear | `spear` (move `spear_ultimate`) | 3.4 | 4.48 / 1.60 | 0.76 / 0.35 | 4,036 | 109 zero-scale nodes -> 1e-4 |
| `spear_thunder_sky_throw_ultimate` | spear | `spear` (move `spear_ultimate`) | 4.2 | 5.25 / 2.29 | 0.97 / 0.47 | 9,200 | spear thrown and recalled (spear_throw_recall.gd); look tuned with thunder_slam_presentation.gd |
| `spear_thunder_whip_ultimate` | spear | `spear` (move `spear_ultimate`) | 3.4 | 4.43 / 1.58 | 0.78 / 0.36 | 4,252 | 103 zero-scale nodes -> 1e-4 |
| `spear_tidal_weave_ultimate` | spear | `spear` (move `spear_ultimate`) | 3.4 | 4.54 / 1.64 | 0.79 / 0.36 | 4,428 | 119 zero-scale nodes -> 1e-4 |
| `spear_water_sky_throw_ultimate` | spear | `spear` (move `spear_ultimate`) | 4.2 | 6.83 / 2.78 | 2.26 / 0.76 | 9,128 | spear thrown and recalled (spear_throw_recall.gd); look tuned with tidal_slam_presentation.gd |
| shared/ (scripts, 22 shaders, flame texture) | | | | | 1.55 / 0.17 | | |
| **total** | | | | **149.3 / 62.8** | **32.5 / 13.7** | | |

Skipped (pose studies / previews: no `.tres` or `skill.json`, not in the pack manifest):
`dagger/shadow_extraction_preview`, `hammer/ground_drag_preview`, `spear/fire_sky_throw_preview`.
Not copied: their `project.godot`, `scenes/`, `scripts/` (demo), `art/characters` (same rig as ours), maps, weapons.

Known issues
- The Godot look of 8 packs (notes "look tuned with ...") comes from their `shared/*_presentation.gd` /
  `inferno_spectacle.gd` scripts, which our `client/vfx/skill_vfx.gd` does not run: in game they show
  the GLB materials only (as the Inferno does today). Their presentation was tuned for Forward+ with glow;
  we render GL Compatibility.
- `forward_dash` packs move the caster in their demo; our logic decides movement, so wiring them needs
  move data (combat-designer).
- Character clips reach the game through `tools/blender/chibi_anims.py` (SKILL_CLIPS), which still reads
  the Inferno from `art_source/skills/`; the shrunk `motion.glb` here keeps the full 57-bone clip and can be
  the source for the rest.
- Visual check after shrinking: earth_slam (heaviest raw) and tidal_slam (heaviest export) rendered before/
  after at 6 moments: pixel-identical within 0.01% (`art_source/preview/skills/shrink/cmp_*.png`).
