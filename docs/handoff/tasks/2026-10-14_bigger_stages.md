# Task: bigger goblin arenas + a third arena (level-designer, 2026-10-14)

Boss: the journey arenas are TOO SMALL, and the stages feel too hard partly because there is
no room to kite.

## Read first
`.claude/agents/level-designer.md`, `CLAUDE.md`, the tail of `PROGRESS.md`,
`tools/blender/build_goblin_stages.py`, `data/maps/goblin_*.json`,
`tests/test_goblin_stages.gd`, `tools/shots/goblin_stage_shots.gd`,
and `data/maps/ink_garden.json` + `shrine_wall.json` for size comparison.

## Do
- Enlarge `goblin_arena_a` (now 22x16 m) and `goblin_arena_b` (21x16 m) to roughly 2-2.5 screens
  at camera 8, about 1.6-1.8x the current play area. Still ONE arena: no corridors, no long walks.
- Use the extra room well: space to retreat and circle, a few more cover pieces, a landmark or
  two so the space is interesting rather than empty.
- Keep the north portal spots, the palisade / thorn-root identity, night readability, and the
  3-material, <= ~30k tri budget per map.
- Add a THIRD fight arena `goblin_arena_c` of the same size for variety (goblin quarry/ravine or
  a river ford, your call).
- `goblin_rest_camp` may grow about 1.3x.
- Update the generated map JSONs (spawns spread over the larger area; every monster must still
  reach the player within 90 s) and the tests.
- Shots -> `art_source/preview/goblin_stages/r3/`. LOOK at them and fix what looks bad (max 3 rounds).

## Own / do not touch
You own the Blender stage scripts and art, `data/maps`, the map loader and `client/stage_props.gd`.
Do not edit journeys, combat data, `client/stage_view.gd`, hub or title files: other agents are in
them right now. If you must add a line to `tests/run_all.gd`, re-read it immediately before editing.

## Environment (macOS)
- Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
- Blender: `/Applications/Blender.app/Contents/MacOS/Blender -b -P <script>`
- No `timeout` on macOS: `perl -e 'alarm 1800; exec @ARGV' <cmd>`
- Run `--import` after .glb changes.
- Suite must stay green (1730 passed / 0 failed now), stderr clean:
  `<godot> --headless --path . --script res://tests/run_all.gd`

## Report to the PO (English)
Sizes before/after, triangle counts, the new map id, PNG paths with an honest description, and
what is still weak.
