# Relic Master visual v2 — LOCAL review, 2026-10-31

Boss rejected the earlier rounded-flat implementation because it did not transfer the approved concept's framing, hierarchy and material depth. This revision restores left showcase / right sockets, collection, details. It is a Godot implementation, not a generated concept. No build, registry upload or deployment performed.

## Frame hierarchy

- Main shell:6px broad brass bevel, faceted rounded corners, lit upper edge/darker lower edge. Decorative weight belongs to the shell, rather than every nested panel.
- Showcase:38% of content width, dark inset3px rim; actual runtime Relic mesh in isolated SubViewport on a faceted stone base. Camera never changes gameplay. SubViewport uses UPDATE_ONCE on selection/resize, not UPDATE_ALWAYS. No particles, new textures or gameplay physics.
- Right region: sockets tray, collection tray, description inset use3px darker rims. Item/socket standard bevel4px, selectedgold6px. Vector StyleBox draws bevel facets and interpolated face lighting; thickness does not come from repeated thin outlines.
- Sockets are squares (1:1) and always3; only first active. Locked slots use a drawn padlock icon. Owned cards about1.55:1, not long text rows. Actual128px icons fill card content, selectedborder and equippedbadge are separate states.
- Gold close is truly circular52x52 crossing mainframe corner; custom style marginszero prevent fontminimum making it oval. Action130x48mobile/140x48PC, Back58/72x48; footer stays on screen.
- On mobile, selected name remains under showcase; duplicate title hidden in detail to keep two-line effect summary readable. Summary values derived from catalog tuning; full original description remains on PC. TouchScroll retained for larger collections/details.

## Native measurements

- (1280, 720): main(1208.0, 648.0),showcase(437.0, 502.0),socket(140.0, 140.0),card(294.0, 190.0),detail(713.0, 134.0),action(140.0, 48.0),close(52.0, 52.0).
- (844, 390): main(804.0, 350.0),showcase(291.0, 252.0),socket(70.0, 70.0),card(139.0, 90.0),detail(477.0, 66.0),action(130.0, 48.0),close(52.0, 52.0).
- (667, 375): main(626.0, 334.0),showcase(224.0, 236.0),socket(66.0, 66.0),card(130.0, 84.0),detail(366.0, 60.0),action(130.0, 48.0),close(52.0, 52.0).

## Checks and evidence

Actual Godot1280x720,844x390,667x375: preview-only selection does not equip; authority equip/swap/unequip pass;3slots/1active; frame/card ratios; main6pxrim; circular52pxclose; actions and close viewportbounds;60extra fixture-owned rows swipe and do not accidentally equip. Source fixtures are disposable and never grant live-account items. Rendering code and helperparse checked through native execution. No deviceFPS or authenticatedbrowser claim.

Screenshots build/relic-chibi-v2-{1280,844,667}.png. Exact numeric reports build/relic-frame-metrics-{1280,844,667}.json. UI frames are code-native; old concept has richer painted surface detail and glow, so do not claim pixel parity with that generated image. Actual item art/model retained instead of generating a different Relic. Await Boss visual review; LOCAL ONLY.

## Outer-frame correction after Boss feedback

Main shell now9px chamfered8-edge faceted gold: per-face triangular colour variation and sparse short seam strokes along the metal, rather than uniform rounded stroke. Innerframes still3px. Updatedmetrics in build/relic-frame-metrics-*.json and images build/relic-faceted-gold-*.png. Native PC/mobile3sizes PASS. Local only; earlier6px descriptions are historical.

## Current decision: original shared UI specification

Boss rejected the custom frame direction. Runtime Relic panel now uses original InkUi window/panel/button/close styles; bevel_style experiment is not referenced. Icon cards, large actual-item preview, touch selection and explicit authority equip/unequip remain. Native3landscape checks PASS; build/relic-original-spec-*.png. Local only/no deploy. Earlier customframe descriptions are historical and rejected.

## Deployed 2026-10-31

Approved original-spec Relic UI and posture fix now live build **f8082c6b7f9a**. Exact shipped native/public byte checks passed; see docs/releases/relic-ui-20261031.md for release evidence and limitations. Historical LOCAL-only statements above superseded for this approved scope.
