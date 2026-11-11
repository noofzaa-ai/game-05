# Goblin single-arena wave GPU audit — 2026-11-01

Boss asked for counts/optimization options before planned waves1–11 in one arena, then boss room. Read-only audit; no gameplay or model edits/deploy. Counts from actual runtime art/monsters GLB triangle accessors, including attached weapon meshes. Animation GLBs contain no mesh triangles.

| Model | Actualtri | Proposed complete-item target | Estimated reduction |
|---|---:|---:|---:|
|goblin|8,616|3,500|59.4%|
|goblin_archer|9,407|3,800|59.6%|
|goblin_mage|9,672|3,800|60.7%|
|goblin_knight|10,592|4,500|57.5%|
|goblin_chief|10,526|5,500|47.7%|

One of each actual48,813tri ->proposed21,100tri (-56.8%). This is catalog sum, not simultaneous spawn. Current ordinary/challenge enemies peak6(Stage11challenge):55,519tri ->target22,600tri. With outline enabled the copied skinned silhouette introduces another geometry pass, approximately111,038 ->45,200 submittedmonster triangles before shadows/VFX/culling; not an FPS or drawcall guarantee.

Dominant-head-bone face classification (meantriangleweight>.5) estimates1656normal/2352archer/2178mage/2532knight/2056chieftri. These are weighted regions, not separate anatomically exact headmeshes. Cutting only these regions80% saves only~15–20% per entiremonster, unlike the original player's12k head. Optimize whole skinned body, armour and hidden geometry too. Preserve joints/rest/bind/socket and every retained vertex weight; lock joint/face/hand/foot critical regions, UV+normal/skin-aware error. Inspect idle/run/attack/death front/side/threequarter and skinning seams. Reuse UVs where sound; rebake colour/normal/detail to shared atlas where needed. Toonshader itself does not reduce triangles. Nonmanifold/degenerate/seam/attribute checks required before accepting any new model.

Scenery currently94,516–110,218instanced triangles,11–13base surfaces (source manifest counts; runtime extra passes/culling not captured). Gate100,418. Shared MultiMesh assets already used; keep sharing. Proposed arena target30–45ktri (-55–70% roughly), preserve combatbounds/exits/cover and environment identity. Tall side/rear towers/huts can be reduced more aggressively than near-camera silhouettes. Crate7128tri, drum6070, cauldron8140 are disproportionately dense; prioritize these (only those actually instantiated matter). Huts7580,towers6306,palisades2792/banner2134 are repeated, so per-piece savings multiply. Keep single sharedatlas colour1024/normal512/MR512 or smaller perassets_spec, GPUcompression+mips; avoid per-piece duplicated maps after rebake.

Single-arena plan: spawn one wave at a time; killed bodies/statusFX/projectiles/materialinstances must expire; avoid appending all11wave sets or accumulating disabled nodes. Start with current3–6concurrent enemies before increasing density. Pool warmed actors/VFX with full state reset; scoped shadows/outline quality bydistance; no decorative dynamiclights perprop. Static collision simplify separate fromvisualmesh; avoidconcave trimeshes. Keep existing sharedmeshes/MM; reduce surface/materialvariants where legitimate. Regular skinned enemies are not drop-in MultiMesh candidates. LOD (near/far) onlyafter baseline visualvalidation, not as substitute for wholebody optimization.

Suggested first-stage measurable envelope: target40kscene +6*~3.8kmonsters ~=63kbase geometry (vs~150–165kcurrent dependingmap/composition), excludingplayer/VFX/outline/shadows. Not a promisedFPS uplift: animation/boneCPU, AI,physics,network,particlesoverdraw,shadowpasses can dominate. Measure30s identical prerecorded wave onWeb: framep95/p99,max,drawcalls,primitives,CPU/GPU timing/physics, actor/FX/nodecount aftereachwave. Verify resource counts return tobaseline afterwave11. Compare old/new on sameviewport/settings/device.

Gameplay wave mechanics (camp/treasure/challenge/rewardsettlement/bossentry) remain undecided/outofscope of this audit; preserve authority/idempotent rewards when implemented. No contentoptimized yet; all targetcounts are estimates awaiting actual export and visualacceptance. Details build/goblin-gpu-audit.json.

## Boss direction — 2026-11-01

One arena through wave11; rest after wave11. Chest/boss timing requested at3,6,9; awaiting clarification whether these are miniboss waves or regular wave chest milestones. Preserve boss room as separate final encounter. Work should be delivered as one integrated change, not staged per monster/map. Server authority and repeat-safe reward settlement required. Scope includes all Goblin variants, arena scenery budgets, bounded lifetimes and multi-wave cleanup.
