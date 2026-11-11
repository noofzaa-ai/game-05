# Task: make the journey friendlier (combat-designer, 2026-10-14)

Boss: "the stages really are too hard." The arenas have just been enlarged by the
level-designer and a third one (`goblin_arena_c`) was added, so retune on the new map pool.

## Read first
`.claude/agents/combat-designer.md`, `CLAUDE.md`, `data/journeys/ink_road.json` (stage 9-11 power
was lowered yesterday for the SMALL arenas; see its `_design` note), `logic/journey_data.gd`
(`arena_maps`, `fight_map_pool`), `logic/journey.gd` (power curve, boss), `tests/journey_sweep.gd`,
`tests/test_journey.gd`, and the level-designer's report for the new arena sizes and map id.

## Do
- Add `goblin_arena_c` to `arena_maps` if the map is valid.
- Measure with the bot sweep (skill 0.6, 100 runs) for stages 1, 4, 8, 9, 10 and 11, plain plus
  challenge, on the new map pool; and the boss on `brush_ring` at skill 0.3 / 0.6 / 0.9 (40 runs each).
- Retune so a mid-skill bot has a fair run:
  - early stages near 95%+
  - late plain fights about 75-85%
  - challenges about 55-65% (a real risk, not a wall)
  - the boss about 35-40% at skill 0.6 (roughly 55-65% at 0.9), by adjusting boss `hp_mult` /
    power a little
- Keep the rule that a plain fight never gets easier than the previous stage.
- Document the tuning and the measured numbers in the file's `_design` note, and update any test
  that locks threat ranges.
- Use temporary copies of the sweep script limited to the stages you need, and delete them after.

## Own / do not touch
Only `data/journeys/*`, `tests/test_journey.gd` threat checks, and your temp sweep copies.
Another combat-designer is wiring the ultimates in parallel (weapons, vfx, fighter, client files):
stay out of those.

## Environment (macOS)
- Godot: `/Applications/Godot.app/Contents/MacOS/Godot`
- No `timeout` on macOS: `perl -e 'alarm 3000; exec @ARGV' <cmd>`
- Suite must stay green, stderr clean:
  `<godot> --headless --path . --script res://tests/run_all.gd`

## Report to the PO (English)
A before/after table for every stage you measured, and say plainly where the run is still harsh.
