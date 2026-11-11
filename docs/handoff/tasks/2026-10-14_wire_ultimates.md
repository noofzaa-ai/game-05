# Task: wire the 30 imported ultimates into combat (combat-designer, 2026-10-14)

Boss: put the model team's skills into the game so they can actually be used.
30 ultimate packs are already imported and shrunk; only `blade_inferno_ultimate` is wired today.

## Read first
`.claude/agents/combat-designer.md`, `CLAUDE.md`, the tail of `PROGRESS.md`,
`art/skills/IMPORTED.md`, `art/skills/skill_manifest.json` (field `in_game`), `art/skills/skill.md`,
`art/skills/shared/*` (their WeaponSkillController and `*_presentation.gd`),
`/tmp/gr/README_GODOT.md` (re-extract `~/Downloads/godot_runtime.zip` to /tmp/gr if missing),
and how the inferno is wired now: grep `inferno`, `art/skills`, `ultimate`, `skill_names` in
`client/`, `logic/`, `data/combat/`; `client/vfx/skill_vfx.gd`, `client/fighter_view.gd`,
`data/combat/weapons.json`, `data/combat/vfx.json`.

## Do
1. Data-driven choice: each weapon gets a default ultimate per weapon type (blade / dagger /
   spear / hammer, mapped to our weapon ids), with the others selectable in data. If our items
   have an element field, pick by element; otherwise explain the default you chose.
2. Play their motion clip on our chibi rig and their VFX at the frozen cast origin with locked
   facing. The "caster dashes forward" packs must move the fighter in the SIM (logic/data), not
   only visually. Handle the spear throw-and-recall packs too.
3. Turn each pack's `gameplay_events` (hit time + range_factor, range 2 body lengths) into our
   logic hit frames through data. No client-only damage.
4. Respect the locomotion release / blend-out times from their docs.
5. Web cost: load a skill lazily when the weapon is equipped, and warm its shaders once so the
   first cast does not hitch.
6. Try their `*_presentation.gd` / `inferno_spectacle.gd` looks if they work under GL
   Compatibility at acceptable cost; otherwise GLB materials only, and say which. Their
   cinematic skill cameras: only if cheap and compatible with our CameraRig, else skip and say so.

## Tests
Every manifest skill maps to a weapon type and resolves; each weapon's ultimate resolves to a
present pack; hit events land at the documented times and range in the sim; dash packs move the
fighter; equipping loads the pack.

## Shots
Per weapon type, its default ultimate in 3 frames (windup, hit, fade) ->
`art_source/preview/skills/ultimates/`, plus a contact sheet of all 30 at hit time.
LOOK at them and fix the broken ones (max 3 rounds).

## Own / do not touch
Other agents are working in parallel on `data/journeys/*`, `data/maps`, the goblin Blender
scripts, the hub and the title. Do not touch journeys, data/maps, hub, title, camp_screen or any
Blender file. If you must add a line to `tests/run_all.gd`, re-read it immediately before editing.
`logic/` stays pure: no nodes, visuals, `client/` or `GameState`.

## Environment (macOS)
- Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
- No `timeout` on macOS: `perl -e 'alarm 1800; exec @ARGV' <cmd>`
- Suite must stay green (1730 passed / 0 failed now), stderr clean:
  `<godot> --headless --path . --script res://tests/run_all.gd`

## Report to the PO (English)
The mapping table, what you skipped and why, first-cast hitch / fps notes, PNG paths with an
honest description, and decisions the Boss must make.
