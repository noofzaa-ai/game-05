# Goblin grass/dirt ground — local, 2026-10-31

Boss requested ground grass/dirt, then explicitly deferred deployment. No registry push or rollout performed.

`tools/maps/goblin_terrain.gd` builds offline vertex-painted open terrain and sparse merged opaque grass blades. `tools/maps/build_goblin_base.gd -- --terrain-only` patches only generated terrain in five existing scenes without re-exporting the source kit. Both normal and terrain-only builders count actual triangles and draw surfaces in manifest.json. No new texture, shader, physics, lights or transparent grass. Ground/grass do not cast shadows, preventing closed-floor self-shadow artifacts.

`client/goblin_ground.gd` hides only the generated visible BoxMesh matching the map floor atY0; simulation collision remains unchanged. `client/stage_view.gd` invokes it after building solids. A future scoped Web wrapper calls the same helper on the exact deployed StageView; no entire dirty source replacement. Existing runtime geometry still owns movement/ground detection.

Native actual StageView fixture PASS all5maps: one duplicate floor hidden, terrain visible with vertex colours, PC1440x810 and mobile844x390. Final source scene brightness corrected and inspected after first overly dark trial. Evidence build/goblin-ground-local-844.png. No physical-mobile FPS or authenticated browser claim. No final release build; prototype c8b6e9263f62 has older brightness and must not deploy. Rebuild approved source after explicit deployment approval.
