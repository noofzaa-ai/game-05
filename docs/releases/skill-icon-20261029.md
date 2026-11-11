# Skill menu icon — 2026-10-29

Boss approved a generated Skill menu book icon, then requested its colour mood match existing controls. Final illustration uses muted antique brass, slate navy and chestnut leather. Built-in image_gen edited the first illustration against assets/ui/hub_shortcuts/controls.png; full prompt and source are in art_source/ui/skill_menu/README.md. Runtime asset assets/ui/hub_shortcuts/skill.png is transparent192×192 PNG52,930bytes. Button retains original60×60 CSS hit target and action.

Web build `a1df239402c6`, baseline `c11ef07e658a`. Image `wiyazard:30500/zorx-web:skill-icon-20261029-2@sha256:7f9164ff7828ecef6b78db794e11529b52962d538d034ea08e42af9da8e5aa38`.

Scoped patch uses the exact deployed compiled hub as parent under hub_skill_baseline.gdc/remap and overrides menu construction only to apply client/skill_menu_icon.gd. Engine/content and unrelated core entries verified byte-identical. Uncommitted training/farm/fence/online changes excluded. PNG/import/cache bundled in patched core. Download delta +44,196bytes.

Exact release packs tested with Godot4.7.2 Compatibility at1280×720 and844×390: image/caption,192px texture,60px hit target, viewport containment, original signal, button opens Skill screen PASS. Native screenshots inspected at /tmp/zorx-skill-icon-muted-release/skill-menu-{1280,844}.png. Existing plaza-chat focus warning occurs on teardown. Full workspace suite remains known failing/profile-online fixture cases and times out; no all-green claim. Browser loading page visibly reports new build; account-authenticated browser gameplay not retested.

Deployment game-test in zorx-staging rolled out successfully. Ready pod game-test-5d76c68d57-ckr6k uses the image digest above. Public HTTPS packs.json matches tested manifest; downloaded core.cc61bf872b51.pck.wasm bytes match release exactly (stored SHA2569485695f4b84d8c6ac7cd54a3d53fcec1c649e7e1aa6e38845e97ac17863257d). Previous image retained; deployment snapshot /tmp/zorx-skill-icon-release/rollback-deployment.json and remote game.yaml.before-skill-icon-20261029-2.bak. Bright first icon was never deployed. Worker/account data unchanged.
