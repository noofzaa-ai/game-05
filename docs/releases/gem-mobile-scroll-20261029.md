# Gem mobile scroll patch — 2026-10-29

Scope: `client/skill_panel.gd` and new `client/skills/touch_scroll.gd`. Gem choices use a themed scrollable panel; both the page and picker accept swipes starting over buttons. Tap activates only on release, drag/cancel never selects. Disabled Gem compatibility, build authority and PC mouse wheel remain intact. Scroll offset is restored after selection.

Native Godot4.7.2 tests: `tests/gem_touch_scroll.gd` PASS at844x390 using viewport ScreenTouch/ScreenDrag (body, shape/effect list, bottom choice, disabled/cancel protection, retained offset, Save in viewport, PC wheel). `tests/skill_panel_flow.gd` PASS. Native PC1440x810 and mobile844x390 screenshots in ignored build/.

Release baseline is the running Web build75347a059a85, image `zorx-web:gem-ui-20261028-1` digest92a88ad6511ba526ad061b3dce1e91f57c53f038058cb7b7eceaf5a7b3c8ec36. This patch overlays ONLY the two scripts into that core PCK, retaining every other runtime entry and all content/engine bytes. This avoids publishing unrelated unfinished source changes in the shared dirty workspace. VFX experiments and online-prediction migration are NOT part of this release. Published new build/digest will be recorded after rollout.

The repository has an existing large uncommitted integration backlog; this source commit records the complete current SkillPanel plus the focused touch fix, its tests and capture tool, not that entire backlog. Full suite was attempted earlier and failed/timed out on profile/online/legacy-skill cases; no full-suite pass or physical-mobile acceptance is claimed. Release artifact must be separately verified against the deployed baseline dependencies.


## Released

- Source patch96a3504; reproducible scoped builder5eae25c (remote codex/gem-mobile-scroll).
- Web build3c1917765f64, image `wiyazard:30500/zorx-web:gem-touch-20261029-1@sha256:035d38f0bf21794640071af9c316263a1c4bca80b8bbe31428da4b827d618033`.
- Deployed only game-test web in zorx-staging; rollout SUCCESS. Public packs.json confirms build; public core.af01ad5e6bd9.pck.wasm downloaded and compared byte-for-byte with the tested artifact.
- Shipped-only native test: combined the actual patched core + unchanged content/S3TC packs; loaded the original exported project and ran ScreenTouch/ScreenDrag Gem contract against those dependencies. PASS. No dirty-workspace logic, VFX or network changes were used in that verification/release.
- Core gzip8204523→8200076bytes. Engine/content/format packs unchanged. Not a full gameplay performance claim.
- Rollback: local /tmp/zorx-gem-touch-rollback.json, remote game.yaml.before-gem-touch-20261029-1.bak. Existing game.yaml image synchronized. Workers/account balances untouched. Browser without an authenticated session redirected to the landing site; no physical-mobile or authenticated Web Gem interaction claimed.
- Latest run_all attempt timed out60s with profile/online/legacy skill failures; targeted SkillPanel and shipped-native touch tests passed. No full-suite pass claim.
