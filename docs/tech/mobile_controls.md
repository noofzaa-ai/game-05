# Mobile controls / landscape-only

Touch devices get a stage joystick (left) and eight independent touch regions (right): light, heavy, jump, dodge, guard, run, skill, ultimate. Run/guard are holds; attacks are consumed once per press, even if a tap ends between physics ticks. Existing keyboard/mouse input is merged without synthetic Input action presses, so releasing a touch cannot clear a keyboard hold. The hub retains its original walking stick and tappable NPC/menu prompts.

Stage utility buttons reuse existing key handlers for rest/campfire, back/route/summary and retry, respecting journey restrictions. Existing chest prompt stays tappable. No rules were moved from logic/ and no networking or damage changes.

`GameState` installs `client/mobile_controls.gd`; `InputReader` merges its state. The overlay disables combat while a rest menu is open, and releases state on resize, scene change, cancellation and focus loss. Cooldown icons remain visible above touch buttons; HUD switches to compact on touch devices.

Portrait blocks input with a full-screen rotation message and pauses the tree. Returning landscape resumes only pauses owned by the rotation gate, preserving preexisting pauses. Hub stick is also cleared on rotation. The web shell has an independent portrait gate before the engine starts and attempts fullscreen + Screen Orientation lock from Start; rejection falls back to manual rotation (e.g. iOS). No reliance on lock support. Menus and title are also gated in portrait. Desktop without touch remains unchanged.

## Verification (2026-10-16)

Godot4.7.2 full suite: passed=1844 failed=0, empty stderr. Tests include merge/one-shot/hold, simultaneous screen-touch events, cancelled touches, joystick drag, portrait gate and pause ownership. Native Compatibility screenshots captured at1280x720,720x1280 and restored1280x720 in ignored build/mobile-validation. Hardware phone / Safari / Android browser and release Web export still require device verification; Web export templates and PowerShell are not installed on this Mac. Browser shell code is included in the existing split-build template, no deployment performed.

Build the existing Web preset through tools/web/build_web.ps1 on the configured build machine, then test play.html on HTTPS. Check moving + attack together, held guard/run, attack jump, cancel/focus loss, rest menus, chest, defeat/retry, journey summary, portrait during combat and resume. Test a real iOS Safari and Android Chrome device before public release.

## Radial thumb layout (2026-10-16)

Large circular attack at bottom right; heavy/skill/ultimate arc to the left and above it, guard/dodge/jump/run outside. Colors use existing InkUi surface, brass outline, icon and state tokens, with existing BrassIcons glyphs. Hit tests are circles, not their bounding squares. The old duplicate keyboard skill row is hidden on touch devices; cooldown text/rings, affordability and ultimate charging are read from HUD presentation state on the actual touch buttons. No combat rules changed.

## Approved button mapping (2026-10-16)

Supersedes earlier eight-button placement: MAIN light attack; slot1 dodge/dash, slot2 heavy, slot4 held run, slot5 skill, slot6 held guard (left of1), slot7 ultimate (above5). No on-screen jump button in this approved six-auxiliary layout; desktop Space remains unchanged. Slots1/2/4/5 sit at0/40/80/120 degrees on a170-unit arc, scaled with screen height. Main radius73, other buttons40, outer spacing96; equal bottom inset under1 and right inset after5. Reproduces the user-approved position study. Native landscape/portrait/resume screenshots reviewed; physical mobile verification remains pending.

## Shared joystick/attack centerline

Joystick idle/base centre Y is derived from the same anchor as MAIN, across screen sizes. Touch-down uses the fixed base rather than relocating it to the finger, so off-centre touches cannot move it off that line. Utility buttons sit above the joystick interaction rectangle. Regression checks cover phone/wide sizes, equal centreline and off-centre touch-down.

## Compact rounded player bars

Touch/compact resource bars use `hud_capsule.gd`: HP300x24, stamina up to280x19 (gear still changes length within cap), ultimate230x17 in viewport pixels. Colors retain InkUi palette and low-health outline feedback; remove ornate caps/ticks and scale status chips down. Desktop/boss bars retain their previous layout. Full suite1858 passed,0 failed, empty stderr; native1280x720 screenshot reviewed.

### Character creation and rotation overlay (2026-10-16)
Creator reserves its name/Random/Start footer and lets the preview shrink into the remaining height; choices scroll independently. Empty validation text takes no space; errors keep the footer visible. Compact layouts do not autofocus the name (avoid opening the phone keyboard on entry). Camp Look retains its current sizing. The portrait blocker is a separate CanvasLayer128 above creator25, menus20 and FPS100; combat controls remain layer20. Native captures checked 667x375 with invalid name, 844x390 with valid name, portrait blocking and return preserving input. Full suite: 1865 passed, 0 failed; physical iPhone keyboard behavior still needs device verification.

### Web name keyboard (2026-10-16)
Enabled html/experimental_virtual_keyboard in the Web preset (previously false), which exports experimentalVK=true into the engine configuration retained by both packaging scripts. Creator explicitly enables the default platform keyboard on its LineEdit, while preserving tap-to-focus on compact screens. Rebuild Web and publish a new image for this export setting to reach phones; native screenshots cannot verify Safari keyboard behavior.

### Look categories and preview fit (2026-10-16)
Shared camp/creator LookPanel now has Face, Hair and Colors tabs; Colors groups hair color and skin. Each page scrolls independently and preserves its scroll position. Compact preview no longer forces a 420-unit minimum height, keeping the whole doll inside the available panel. Model tiles are 104 units with an explicit 88-unit icon limit (overrides shared Button theme26); swatches64, category tabs68 tall. Native screenshots reviewed at844x390,667x375 and desktop1280x720; physical mobile verification remains pending.

### Floating movement zone and drag-to-run (2026-10-16)
Supersedes the fixed joystick/base centerline and run button above. Stage movement starts anywhere in the left45% below HUD, excluding visible utility buttons. Origin is the initial finger position; the stick only draws while held. Short drags walk; run engages at85% reach and disengages below70% (hysteresis), deadzone12%. Release/cancel/focus/menu/resize clears movement and run. Run button removed; five auxiliary combat buttons remain and heavy is centered at60degrees on the arc. Utilities (Back, interact/rest, retry) are smaller88x40 screen-pixel buttons, with14px text, placed below bars at viewport y100/x16. Keyboard movement/run unchanged. Native844x390 landscape drag and rotation captures reviewed; physical device verification pending.

### Hide browser keyboard-help button on touch devices (2026-10-16)
The HTML top-right help button is hidden for maxTouchPoints>0 or any-pointer:coarse, both after initial load and resume. Coarse-pointer CSS also suppresses it. Desktop mouse retains keyboard help; game combat buttons and joystick are unchanged. Requires rebuilding/publishing the Web HTML. JS VM checks cover touch/coarse/desktop initial and resume visibility; physical mobile verification remains pending.

### Inventory pane stability and touch scroll (2026-10-16)
Details use horizontal SHOW_NEVER to decouple content minimum width; title/subtitle wrap in a fixed-width pane. Selection no longer moves the bag or changes its columns. Grid reserves a visible vertical scrollbar in all modes; compact lane32 units with large brass thumb, desktop14 units. Native touch drags anywhere over tiles scroll; tap selects on release, drag/cancel never selects. Emulated mouse press/drag-to-equip is suppressed while grid owns touch; use Wear/Take off actions on mobile, desktop mouse drag/drop retained. Verified native844x390 longest catalog item and viewport-pushed touch scrolling (offset90); physical Safari verification pending.

### Larger illustrated combat controls (2026-10-16)
Replaced thin line glyphs with cached256px vector medallions: charcoal face, faceted gold rim and gems, colored silver sword/crossed swords, gold shield/star/crown and cyan dash. Labels/cooldown text stay live Godot text; cooldown and charge rings retained. SVG rasterizes once per action with mipmaps; no extra 3D objects. At phone390px CSS height, auxiliary buttons/hit circles are60px diameter and main104px; wider spacing120px arc/72px secondary separation prevents overlaps. Browser canvas backing/CSS ratio converts Retina pixels to actual CSS-sized touch targets. Native844x390 reviewed; tests cover667/844/932 widths, caching, hit spacing and3x Retina conversion. Physical Safari still pending.

### Approved reference geometry + supplied PNGs (2026-10-16)
Supersedes the generic symmetric arc/medallion art above. REFERENCE_BUTTONS stores measured centers and visible rim widths/heights from the1473x1068 approved reference; all six are scaled together, main rim120 CSSpx on a390px-high phone. Ratios: heavy62.2%, dash54.8%, skill55.7%, guard51.9%, ultimate51.1%; ultimate is left of skill. Centers/rim gaps retain reference offsets, including slight vertical offset of guard/dash. Hit regions are body ellipses, not padded image rectangles. Supplied six PNG originals copied unchanged to art/ui/mobile_combat; BODY_UV compensates differing padding/glow without raster edits. Labels are baked in originals; only dynamic cooldown text overlays. Godot import512px + mipmaps limits memory. Native844x390 screenshot reviewed and all normalized center/size tests pass; suite1890 passed0failed, stderr empty. Physical Safari pending, rebuild image to publish.

### Thin-brass supplied reference skin v2 (2026-10-16)
User chose graphics replacement only. Kept REFERENCE_BUTTONS and all control bounds unchanged; replaced art with transparent v2 atlas derived from the new composite via imagegen. AtlasTexture body bounds compensate different padding, including diamond ornaments. Back, compact HP/stamina/ULT and trip counter use matching frames; HUD sample numbers/fills removed from atlas, existing live values/trails/low-HP indicator retained. Frame caps scale uniformly while centers stretch. Six Thai action labels remain baked; cooldown/gauge live overlays retained. Native844x390 reviewed; 1893 passed0failed stderr empty. Physical Safari/new Web+image publish pending. See art/ui/mobile_combat/v2/README.md.
