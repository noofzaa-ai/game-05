# Status VFX release — 2026-10-29

Boss authorized deployment of the reviewed body status effects. Release source03dc0f2a6ca16b8fb962a488216336dcbec58a4d is layered on live Gem-touch build3c1917765f64. Final Web build c11ef07e658a.

Only presenter.gd and status_effect.gd plus build metadata change in existing core; engine and all earlier content bytes stay identical. Three new status_vfx common/S3TC/ETC2 packs contain folded effects+imports and128px alpha texture derivatives. Unfinished online migration and Stage/Fighter changes in the dirty workspace are excluded. The presenter measures existing model mesh bounds once and defers final position sync when called through the older two-argument Stage API. No gameplay/server/balance changes.

Actual shipped-pack tests were assembled separately with PC S3TC and mobile ETC2, using only the patched core+existing content+new VFX packs: status_vfx_lifecycle PASS for both. Six actual scenes, simultaneous statuses, expiry, pooled stop/reuse, body despawn, graphics toggle, size/head anchor, rendered-position follow and older two-argument Stage compatibility. Native Compatibility renderer reviewed18images: six effects ×3phases, each on three monster sizes. Images build/status-shipped-*.jpg. New packs pass existing18/18hat export guard. No script/material/texture errors in shipped native render log. Final revision increases bleeding droplet size/forward offset after the first packed render showed body occlusion; corrected packed image reviewed. Existing Gem touch contract rerun against final VFX combined packs PASS.

Added device-specific download: PC+1.000MB, mobile+1.040MB decimal (core delta+common+ONE GPUformat). No FPS/mobile-device/Web-combat acceptance claim. Full project suite remains known failing/timed-out in profile/online/legacy-skill cases from preceding task; no all-green claim.

Runtime README contains earlier trial measurements; this release note supersedes its old not-deployed statement after rollout verification. Rollback saved /tmp/zorx-status-vfx-rollback.json. Release image/digest and public verification to be recorded after push/rollout.

## Rollout verified

Final image `wiyazard:30500/zorx-web:status-vfx-20261029-2@sha256:da33090e93d98ab8f7a72029684a3040a8589f20cab8117d0d4c66afef58b175`; source03dc0f2; Webc11ef07e658a. game-test rollout SUCCESS. Public manifest and core+allthree status packs downloaded via publicHTTPS and byte-compared to tested release. Ready pod immutable digest verified. Existing game.yaml image synced; rollback retains original Gem image in /tmp/zorx-status-vfx-rollback.json and remote game.yaml.before-status-vfx-20261029-2.bak. First VFX revisione4a7a80cc2b6 was briefly deployed during this session; superseded by final corrected bleeding revision above. Workers/account data untouched.
