# Refine rates (2026-10-20)

Rates are indexed by the target level. Each attempt costs100Gold, success raises one level; failure lowers one level subject to the bracket floor. Failure never increases an item to an unearned floor. Items are not destroyed. Bonus remains base main stat ×1.3% ×refine level.

| Target | Chance | Failure floor |
| --- | --- | --- |
| +1–3 | 100% | — |
| +4 | 80% | +4 |
| +5 | 70% | +4 |
| +6 | 60% | +4 |
| +7 | 50% | +7 |
| +8 | 40% | +7 |
| +9 | 30% | +7 |
| +10 | 20% | +10 |
| +11 | 10% | +10 |
| +12 | 5% | +10 |

Examples: +3→4 failure stays+3; +4→5 failure stays+4; +5→6 failure becomes+4; +6→7 failure stays+6; +8→9 failure becomes+7; +9→10 failure stays+9; +11→12 failure becomes+10.

Server-owned RNG; failed roll returns a successful paid command with `result.success=false`, so the profile CAS/request receipt commits cost and result together. Existing ownership/location/expected-level validation applies. Table is in `data/items/equipment_tuning.json`: `success_chances`, `failure_floors`, max12; generated ConfigMap in `server/k3s/equipment-tuning.yaml`. Legacy guaranteed config remains readable. New tables require new server code before applying ConfigMap.

User requested local changes only: not built or deployed; no test suite run.

## Equipped appearance (2026-10-20 correction)

Refine aura belongs to actual worn weapon/hat/shirt/armband/pants/shoes meshes; inventory icons stay neutral. +4–6 greens; +7 yellow,+8 amber,+9 orange,+10 red-orange,+11 red,+12 deep red with greatest spread. Client ItemAssets.looks derives slot levels from authoritative loadout data, including other players' run loadouts; appearance comparison triggers mesh update on level/equipment changes. Both daggers share the weapon's level. Unequipping/destroying a piece removes its effect; no effect on basic clothing or bare skin. Shared shader materials, no new lights/particles/network messages or per-frame CPU updates. Existing hit flash temporarily overlays sheen and restores it when finished. GPU cost not profiled. Native landscape UI and equipped-model review performed; live two-client visibility not exercised.
