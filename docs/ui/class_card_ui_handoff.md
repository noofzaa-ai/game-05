# Class Card screen: complete UI handoff

**Status: approved to build (Boss 2026-11-11).** **Update 2026-11-11 (Boss): there is no outside UI team. Our own agents build this: `art-director` (visual assets via Codex), `ui-programmer` (Godot screen + portrait), `ux-ui-designer` (review against §17). The PO coordinates; the old hub is cut later, hidden for now.** This is the single source for the UI team: what the screen
does, how it looks, every string, every asset, the Godot contract and the acceptance checklist. It replaces the
earlier `class_card_screen_spec.md` and `class_card_art_direction.md`. If something here is unclear or impossible,
ask the PO; do not guess.

Contents: 1 Context · 2 Decisions · 3 Flow and states · 4 Rules · 5 Visual style · 6 Card anatomy · 7 Layouts
with measurements · 8 Components · 9 Motion · 10 Summon · 11 Strings · 12 Assets · 13 Godot contract ·
14 Data and commands · 15 Edge cases · 16 Accessibility · 17 Deliverables and acceptance · 18 Out of scope

---

## 1. Context

zorx is now an **auto-battler**. The player never controls a fighter. They prepare a squad, press Fight, and
the squad fights 12 waves of monsters on its own on a small floating-island board.

The player owns **one class card per class**. Today there are 4: Sword & Shield, Great Sword, Longbow and Magic.
Every player has the same 4 cards. What differs is how each player customises each card (hair, eyes, outfit and
body; skills come later). The squad for a fight is **1 to 3 cards**.

A card is **not a printed illustration**. It is a frame around a window, and the game renders the real 3D
character inside that window, playing its class's idle animation. The card should feel alive, like a hero waiting
to be summoned. Pressing Fight "summons" the squad cards onto the board.

This screen **replaces the old campfire hub**, the walkable camp with NPCs. The old NPC features (shop, forge,
farm, relics, storage) are hidden for now, not deleted.

## 2. Decisions already made

| Topic | Decision |
|---|---|
| Look | **Cartoon** ("Toon Summon"): thick ink outlines, flat cel colour, rounded chunky shapes, bouncy motion. No realistic metal, engraving or dark gothic style. |
| Orientation | Landscape only (16:9 desktop and landscape phones up to 19.5:9). |
| Fonts | **Mitr** (Google Fonts, SIL OFL) for titles, class names, tabs and buttons; **Sarabun** (already in the game) for small body text. Add Mitr as `art/fonts/Mitr-SemiBold.woff2` and `Mitr-Medium.woff2`. |
| Languages | Thai is the main language and English the second. Every label is in §11. |
| Card count | Built for 4 cards, and must still work with 5–6 later (see §15). |
| Skills | The tab and the sockets are visible but **locked** ("Coming soon"). |
| Old hub | Hidden. The Bag and Settings buttons stay reachable from this screen. |

## 3. Flow and states

```
Title / login ──► DECK (A) ──tap card──► EDITOR (B) ──back──► DECK (A)
                    │
                    └──FIGHT──► SUMMON (C, ≤1.5 s) ──► battle board ──► results ──► DECK (A)
```

- **A. Deck**: the home screen. It shows all cards and the squad bar, and holds the Fight button.
- **B. Editor**: one card enlarged, with customisation tabs. Every change applies immediately (there is no
  Save or Cancel).
- **C. Summon**: the transition into the fight. It cannot be cancelled but can be skipped by a tap.
- Bag opens the existing bag/inventory screen as an overlay. Settings opens the existing graphics/settings panel.
  Both return to A.

## 4. Rules the UI must show (the game enforces them; the UI must explain them)

- Squad: at least 1 and at most 3 cards, and the same class at most once.
  - A 4th card cannot be added: show "Squad full (3)" and shake the squad bar.
  - Removing the last card is not allowed: show "Need at least 1 card".
- The order matters. Slot 1 is the player's own fighter and slots 2–3 are allies. Dragging between slots
  reorders them.
- Fight is enabled when the squad has 1 or more cards. With 3 cards, show a small "Full squad" tick.
- Hair choices differ by class. Sword & Shield can wear A, B, C, E and F; Great Sword, Longbow and Magic can wear
  C, E and F. The editor shows **only** the allowed hairs (never a greyed-out hair).
- Eye colour and skin tone allow a custom colour (a colour picker), as well as the presets.
- If the server refuses a change (rare), revert the visual to the previous choice and show a small toast:
  "Couldn't change that, try again".

## 5. Visual style

### 5.1 Style rules
| Rule | Value |
|---|---|
| Outline | Every shape has a dark ink outline `#1B1530`. At 1080p: card frame 7 px, buttons 4–5 px, icons 3 px. Slightly thicker bottom/right, like hand inking. |
| Shading | Flat cel: base, one shadow tone (bottom/right), one hard highlight streak (top/left). No airbrush. |
| Shapes | Rounded. Card corner radius = 18% of the card width; buttons are pills. A slightly hand-drawn edge is welcome. |
| Depth | A solid offset "sticker" shadow under raised things: 6 px straight down, `#1B1530` at 35%. |
| Gradients | Only the screen sky and the card window sky. |
| Effects | Cartoon stars, sparkles, speed lines and comic bursts. No lens flares or photoreal particles. |
| Never | Realistic metal or wood, filigree, hairlines under 2 px, glassmorphism, neon, grimdark colours, text baked into images, anything over the character's face. |

### 5.2 Palette
| Role | Hex | Use |
|---|---|---|
| Ink | `#1B1530` | Outlines, dark text, the text outline on colour |
| Sky top / bottom | `#7FC8FF` / `#FFE1B8` | Screen background gradient |
| Cloud / cloud shadow | `#FFFFFF` / `#CFE4FF` | Background clouds |
| Paper panel / shadow | `#FFF6E6` / `#F0D9B5` | Panels, the editor sheet, cream buttons, squad slots |
| Night panel | `#3B3266` | A dark panel only where contrast is needed (behind swatches) |
| Card frame base / shadow / light | `#FFD35C` / `#E8A93A` / `#FFF2B0` | The card frame, the same for every class |
| Action base / shadow / light | `#FF7A2F` / `#D9531A` / `#FFC08A` | FIGHT button and the selected ring **only** |
| Disabled base / shadow | `#B9B3C9` / `#8F88A6` | Disabled controls, locked sockets |
| Error | `#FF5A6E` | Error toast and the shake flash (always with words) |
| Text on light | `#1B1530` | |
| Text on colour | `#FFFFFF` + 3–4 px `#1B1530` outline | |

### 5.3 Class identity
| Class (id) | Base / shadow / light | Emblem | Window pattern |
|---|---|---|---|
| Sword & Shield (`sword_shield`) | `#3FB8E8` / `#1F7FB8` / `#A8E4FA` | Round shield with a sword behind | Shield-shaped soft rays |
| Great Sword (`greatsword`) | `#FF5A4E` / `#C2352E` / `#FFB1A8` | Big blade pointing down | Jagged speed lines |
| Longbow (`longbow`) | `#6CCF5A` / `#3E9A3A` / `#C2F0B5` | Bow with an arrow | Floating leaves |
| Magic (`magic`) | `#A27BFF` / `#6E4CD1` / `#D8C8FF` | Star in a circle | Twinkling stars |

The class colour is used on the window sky, the emblem badge, the name ribbon, the foot glow, the open tab and
the squad slot rim. The frame stays yellow on every class. Do not use hue for anything else (such as rarity)
later.

### 5.4 Typography (sizes at 1080p; we map them to tokens)
| Role | Font | Size | Notes |
|---|---|---|---|
| Screen title | Mitr SemiBold | 40 | White, ink outline 4 |
| Class name (deck card) | Mitr SemiBold | 22 | On the ribbon, white, outline 3 |
| Class name (editor header) | Mitr SemiBold | 34 | |
| FIGHT button | Mitr SemiBold | 36 | White, outline 4 |
| Tabs, secondary buttons | Mitr Medium | 22 | |
| Option labels, slot labels | Mitr Medium | 18 | |
| Hints, toasts, "Coming soon" | Sarabun | 18 | |
| Squad number sticker | Mitr SemiBold | 22 | |
Allow 20% extra width for Thai. Text never shrinks below 16 px. Long text wraps or uses an ellipsis; it never
overflows its container.

## 6. Card anatomy

Ratio **5 : 7**. Deck card 220 × 308 px; enlarged card in the editor 420 × 588 px (1080p).

```
 ╭──────────────────────────────╮  frame (yellow, ink outline 7, sticker shadow)
 │ (emblem)            (  2  )  │  top band 15%: emblem badge 52 px left, squad sticker 44 px right
 │ ╭──────────────────────────╮ │
 │ │  sky + pattern           │ │  window: inset 14 px from the frame, radius 14%
 │ │      FACE ZONE           │ │  upper 45% of the window: nothing drawn over it, ever
 │ │      (character)         │ │  the 3D character is rendered by the game here
 │ │       (foot glow)        │ │  glow ellipse at 85% window height
 │ ╰──────────────────────────╯ │
 │   ╭─  SWORD & SHIELD  ─╮     │  ribbon: overlaps the window bottom edge by 10 px
 │    ( ) ( ) ( ) ( )    🔒     │  4 skill sockets 28 px, gap 8, a padlock sticker 24 px
 ╰──────────────────────────────╯
```

Layers, bottom to top (each is its own image so we can animate it):
1. `sky_<class>`: the window gradient and its pattern (opaque, the window shape).
2. **(game)** the live 3D character.
3. `glow_<class>`: the foot glow (additive; pulses).
4. `frame`: the yellow frame with a transparent window.
5. `emblem_<class>`: the round badge.
6. `ribbon_<class>`: the name ribbon (the text is drawn by the game).
7. `sockets`: 4 sockets, in the states `locked` and `empty`.
8. `shine`: two white diagonal streaks (greyscale, additive; moves across the card).
9. `select_ring`: a fat orange outline with "pop" tick marks around the card.
10. `squad_sticker`: a round sticker (the number is drawn by the game).

Card back (for the summon): yellow frame, a class-colour back with a big emblem and a swirl. One per class plus one
generic.

## 7. Layouts with measurements (1920 × 1080 reference)

Safe area: 48 px left/right, 32 px top/bottom (phones: also respect the notch insets). Spacing scale: 8 / 16 / 24 /
32 / 48 px.

### 7.1 A. Deck
```
y=32   ┌ top bar (h 72) ────────────────────────────────────────────────┐
       │ ZORX logo (h 56)                          (Bag)(Settings)(Back) │  icon buttons 64 px, gap 16
       └────────────────────────────────────────────────────────────────┘
y=180  ╭────╮   ╭────╮   ╭────╮   ╭────╮      cards 220×308, gap 48, the row is centred;
       │ S&S│   │ GS │   │ LB │   │ MG │      slight fan: rotation -6°,-2°,+2°,+6°, outer cards 12 px lower
       ╰────╯   ╰────╯   ╰────╯   ╰────╯      each card has a "+"/"−" sticker button 48 px at its bottom-right
y=560    hint line (Sarabun 18): "Tap a card to customise · Tap + to add to squad"
y=820  ╭ squad bar (w 900, h 180), left-aligned at x=48 ─╮   ╭ FIGHT (w 400, h 120) ╮
       │ "Squad" label · slot 1 · slot 2 · slot 3         │   │      FIGHT!         │ right-aligned at x=1872
       ╰──────────────────────────────────────────────────╯   ╰─────────────────────╯
```
- Squad slot: 140 × 150 px, gap 24. Empty = a cream socket with a dashed ink outline and a "+". Filled = a mini card
  face (the top 55% of the card: sky, character head and shoulders, emblem) with the number sticker. Long-press or
  drag to reorder; a small "×" (40 px) removes.
- Background: the sky gradient, 3–4 large slow-drifting clouds, and an optional tiny floating island far away at
  25% opacity.

### 7.2 B. Editor
```
y=32   (Back 64)  "SWORD & SHIELD" (Mitr 34)                       (Reset card)
y=140  ╭ enlarged card 420×588 at x=120 ╮   ╭ sheet (w 1180, h 760) at x=620 ─────────────╮
       │                                │   │ tabs: Hair · Eyes · Outfit · Body · Skills🔒 │  pills h 64
       │      live character            │   ├──────────────────────────────────────────────┤
       │                                │   │ section title (Mitr 22)                      │
       ╰────────────────────────────────╯   │ options grid: bubbles 96 px, gap 24          │
y=760    card strip: 4 mini cards 88×124, gap 16, centred under the card; the current one is lifted
         and outlined orange; tapping one switches the editor to that card
```
Tab contents:
- **Hair**: one bubble per allowed hair (3 or 5). The bubble shows a small rendered head thumbnail (we render
  these; you design the bubble frame). Label under it: "Hair A" etc.
- **Eyes**: section "Eye colour" with 4 preset paint blobs plus a "Custom" rainbow blob (opens a colour picker
  sheet); section "Eye makeup" with 2 bubbles: None and Sharp Wing.
- **Outfit**: 2 large tiles 220 × 280 with a body thumbnail: "Basic" and "Silver Silk".
- **Body**: section "Skin tone" with 4 preset blobs plus a "Custom" blob.
- **Skills**: 4 big grey sockets 140 px with padlock stickers, and the centred text "Coming soon". No interaction.

The colour picker is a small paper panel (480 × 420) with a hue ring or square, a preview blob, and Done and
Cancel buttons. The preview applies live and Cancel restores the previous colour.

### 7.3 Phones (19.5:9, about 2340 × 1080, physical about 6.5")
- Cards 190 × 266 with a gap of 32, still in one row; the hint line is hidden.
- Squad bar w 760. FIGHT w 340 × 110.
- Editor: card 340 × 476 and the sheet fills the rest. Option bubbles 84 px.
- Every touch target stays at least 56 px.

## 8. Components

Every interactive control needs these states: **normal, pressed, disabled, focused** (and **hover** on desktop).
Focus = a 4 px white outer outline outside the ink outline (keyboard and controller).

| Component | Size | Normal | Pressed | Disabled |
|---|---|---|---|---|
| Primary pill (FIGHT!) | 400 × 120 | Orange, ink 5, highlight streak, sticker shadow | Moves down 6 px onto its shadow and darkens 8% | Grey palette, no shadow, text 60% opacity |
| Secondary pill | h 64 | Cream with ink 4 | Moves down 4 px | Grey |
| Icon button | 64 round | Cream sticker with an icon | Squashes to 92% | Grey |
| Tab pill | h 64 | Cream | — | Grey + padlock (Skills) |
| Tab pill, open | h 64 | Class colour fill, white outlined text | — | — |
| Option bubble | 96 round | Cream with a thumbnail | Squash 92% | — |
| Option, selected | 96 | Orange 6 px ring + bounce | — | — |
| Paint blob | 56 | The colour, with ink 3 | Squash | — |
| "+ / −" card sticker | 48 round | Green-white "+" when not in the squad, orange "−" when in it | Squash | Grey when the squad is full |
| Squad slot | 140 × 150 | Empty (dashed) / filled (mini card) | — | — |
| Squad slot, drop target | | Glowing white outline | | |
| Toast | auto, h 56 | Paper panel with ink 3, at the top centre, 2.5 s | | |

Icons needed (chunky, ink 3, flat fill): bag, settings, back, reset, plus, minus, close (×), padlock, custom colour
(prism), hair, eye, outfit, body, skill, tick, plus 4 class emblems.

## 9. Motion

The motion is bouncy, quick and cartoon. Use ease-out-back for pop-ins and a spring for releases.

| What | Motion |
|---|---|
| Card idle | Bob ±4 px over 2.5 s (each card offset by 0.4 s), with a 3% squash at the bottom of each bob. A shine sweep every 5 s (0.6 s long). |
| Card hover / touch | Jump up 10 px with overshoot (180 ms), tilt toward the pointer up to 8°, the shadow stretches |
| Card select | Scale 1.0 → 1.15 → 1.1 (220 ms) and the orange ring pops in |
| Open the editor | The card flies from the deck to the editor position and grows (300 ms); the sheet slides in from the right (250 ms) |
| Change an option | The card wiggles (±3°, 200 ms) and 3 sparkles appear |
| Add to the squad | The mini card flies from the card to the slot (250 ms); the sticker slaps on (0 → 1.25 → 1) with 3 stars |
| Blocked action | Shake ±8 px × 3 (250 ms), a red flash on the outline, and the toast |
| Button press / release | Squash onto the shadow, then spring back |
| Background | Clouds drift 6–10 px/s |
| Reduced motion (setting) | No bob, shine, tilt or wiggle; transitions become 150 ms fades |

## 10. Summon (Fight → board), at most 1.5 s, tap to skip
| t (s) | Beat |
|---|---|
| 0.00–0.30 | The squad cards hop out of the deck (squash and stretch) and stack at the screen centre; the rest of the UI fades out |
| 0.30–0.70 | The cards flip to their backs; each emblem spins and glows in its class colour |
| 0.70–1.00 | A comic burst (a star-shaped "POW" shape with **no letters**), stars and speed lines fly out |
| 1.00–1.20 | A white flash fills the screen |
| 1.20–1.50 | The game loads the board; the characters pop onto their spawn spots (we do this part) |
Deliver a 6-frame storyboard plus the overlay sprites: burst (greyscale), stars ×3 variants, speed lines, flash.

## 11. Strings (Thai / English)

| Key | Thai | English |
|---|---|---|
| `deck_title` | การ์ดของฉัน | My Cards |
| `deck_hint` | แตะการ์ดเพื่อแต่ง · แตะ + เพื่อลงทัพ | Tap a card to customise · Tap + to add to squad |
| `squad` | ทัพ | Squad |
| `squad_full` | ทัพเต็มแล้ว (3) | Squad full (3) |
| `squad_need_one` | ต้องมีอย่างน้อย 1 ใบ | Need at least 1 card |
| `squad_ready` | ทัพครบ | Full squad |
| `fight` | ออกรบ! | FIGHT! |
| `bag` | กระเป๋า | Bag |
| `settings` | ตั้งค่า | Settings |
| `back` | กลับ | Back |
| `reset_card` | รีเซ็ตการ์ด | Reset card |
| `reset_confirm` | คืนการ์ดใบนี้เป็นแบบเริ่มต้น? | Reset this card to its starting look? |
| `yes` / `no` | ใช่ / ไม่ | Yes / No |
| `tab_hair` | ผม | Hair |
| `tab_eyes` | ตา | Eyes |
| `tab_outfit` | ชุด | Outfit |
| `tab_body` | ตัว | Body |
| `tab_skills` | สกิล | Skills |
| `coming_soon` | เร็วๆ นี้ | Coming soon |
| `eye_color` | สีตา | Eye colour |
| `eye_makeup` | แต่งตา | Eye makeup |
| `skin_tone` | สีผิว | Skin tone |
| `custom` | กำหนดเอง | Custom |
| `done` / `cancel` | เสร็จ / ยกเลิก | Done / Cancel |
| `change_failed` | เปลี่ยนไม่สำเร็จ ลองใหม่อีกครั้ง | Couldn't change that, try again |
| `class_sword_shield` | ดาบและโล่ | Sword & Shield |
| `class_greatsword` | ดาบใหญ่ | Great Sword |
| `class_longbow` | ธนูยาว | Longbow |
| `class_magic` | เวทมนตร์ | Magic |
| `hair_<id>` | ผม A / B / C / E / F | Hair A / B / C / E / F |
| `outfit_none` | ชุดพื้นฐาน | Basic |
| `outfit_silver` | Silver Silk | Silver Silk |
| `makeup_none` | ไม่แต่ง | None |
| `makeup_sharp_wing` | Sharp Wing | Sharp Wing |
| eye colours (from data) | ฟ้า, เขียว, ม่วง, น้ำตาล | Turquoise, Green, Violet, Brown |
| skin tones (from data) | ขาว, ธรรมชาติ, แทน, เข้ม | Fair, Natural, Tan, Deep |

Option names for eyes and skin come from `data/cosmetics/*.json`. Show the data's name, never a hard-coded copy.

## 12. Asset list (deliver to `art/ui/class_cards/`)

PNG with alpha, drawn at **2x** of the sizes above (we downscale). Frames and panels must be **9-slice**, so give the
patch margins for each. Icons: SVG, or PNG at 96 px. Keep sources (PSD, Figma, etc.) in `art_source/ui/class_cards/`
or outside the repo. Total PNG budget for this screen: **≤ 3 MB**.

| File | 2x size | 9-slice margins (L/T/R/B @2x) | Notes |
|---|---|---|---|
| `card_frame.png` | 440 × 616 | 80/96/80/150 | Transparent window |
| `card_sky_<class>.png` ×4 | 384 × 440 | — | Window shape, opaque |
| `card_glow_<class>.png` ×4 | 300 × 90 | — | Greyscale OK (we tint) |
| `card_emblem_<class>.png` ×4 | 104 × 104 | — | |
| `card_ribbon_<class>.png` ×4 | 360 × 72 | 40/0/40/0 | |
| `card_socket_locked.png`, `card_socket_empty.png` | 56 × 56 | — | |
| `card_shine.png` | 440 × 616 | — | Greyscale, additive |
| `card_select_ring.png` | 480 × 656 | 96/96/96/96 | |
| `card_back_<class>.png` ×4 + `card_back.png` | 440 × 616 | — | |
| `squad_sticker.png` | 88 × 88 | — | Number added by the game |
| `squad_slot_empty.png`, `squad_slot_filled.png` | 280 × 300 | 40/40/40/40 | |
| `btn_primary_<state>.png` ×4 | 800 × 240 | 120/0/120/0 | normal, pressed, disabled, focused |
| `btn_secondary_<state>.png` ×4 | 320 × 128 | 64/0/64/0 | |
| `btn_icon_<state>.png` ×4 | 128 × 128 | — | Round base; the icon is a separate file |
| `tab_<state>.png` ×4 | 240 × 128 | 64/0/64/0 | normal, open (tinted by class), disabled, focused |
| `option_bubble_<state>.png` ×3 | 192 × 192 | — | normal, selected, pressed |
| `paint_blob.png` + `paint_blob_custom.png` | 112 × 112 | — | Plain blob greyscale (we tint) |
| `panel_paper.png` | 256 × 256 | 64/64/64/64 | Sheet, toast, colour picker |
| `bg_sky.png` | 1920 × 1080 | — | Gradient only; can be generated in code instead |
| `bg_cloud_<n>.png` ×3 | ~600 × 300 | — | |
| `fx_burst.png`, `fx_star_<n>.png` ×3, `fx_speedlines.png`, `fx_sparkle.png` | as needed | — | Greyscale, additive |
| `icon_<name>.svg` | 48 @1x | — | See the icon list in §8 |

## 13. Godot contract (if you build the scene)

The engine is Godot 4.7 (Compatibility renderer, web export).

**Files you own:**
- `client/card_deck_screen.gd` + `scenes/card_deck_screen.tscn` (root `Control`, full rect).
- `client/card_tokens.gd`: the colours and sizes in §5 and §7 as named constants. The project has a style test
  (`tests/test_ui_tokens.gd`) that fails a screen that writes a raw `Color(...)`, a raw font size or its own
  `StyleBoxFlat`. Put every value in `card_tokens.gd` (add it to `TOKEN_FILES` in that test) or in `client/ink_ui.gd`,
  and use `InkUi` helpers where they fit.

**Files we own (do not edit them; ask us):** `logic/*` (rules), `client/game_state.gd`, and `client/card_portrait.gd`
(the live 3D window).

**Your screen exposes:**
```gdscript
signal card_selected(class_id: String)
signal look_changed(class_id: String, part: String, choice: String)  # part: hair|outfit|eye_color|skin|makeup
signal squad_changed(squad: Array)        # the full new order, 1..3 class ids
signal reset_card(class_id: String)
signal fight_pressed()
signal bag_pressed()
signal settings_pressed()
signal back_pressed()

func show_deck(deck: Dictionary, cosmetics) -> void   # draw everything from this; called again after each change
func refuse(message_key: String) -> void              # revert the last visual change and toast (key from §11)
func play_summon(squad: Array) -> void                 # run §10; emit summon_finished at 1.2 s
signal summon_finished()
func portrait_slot(class_id: String, size: String) -> Control  # "deck" | "editor" | "mini": an empty Control where we add the 3D view
```
- **Never** modify `Profile` or call commands yourself. Emit the signal, and we send the server command and call
  `show_deck()` with the new deck (or `refuse()`).
- Until `CardPortrait` lands, fill `portrait_slot` with a rectangle in the class colour and the class emblem.
- Read option lists through `CardDeck` helpers (see §14). Never hard-code the hair, colour or outfit lists.
- 4 live 3D portraits are expensive on the web. Only the focused card renders every frame (we handle this); your
  layout just must not need more than 4 deck portraits + 1 editor portrait + 4 mini portraits at the same time.

## 14. Data and commands (already implemented)

`Profile.card_deck` (rules in `res://logic/card_deck.gd`):
```
{ "v": 1,
  "cards": { "<class_id>": { "hair": "a|b|c|e|f", "outfit": "none|silver",
                             "eye_color": "<id>|#rrggbb", "skin": "<id>|#rrggbb",
                             "makeup": "none|sharp_wing", "skills": [] } },
  "squad": ["<class_id>", ...] }          # 1..3, no repeats, slot order
```
Helpers (static, on `preload("res://logic/card_deck.gd")`):
- `classes()`: the card ids in display order.
- `options(class_id, part, cosmetics)`: allowed ids for `hair | outfit | makeup | eye_color | skin`.
- `allows_custom_color(part, cosmetics)`: show the Custom blob or not.
- `look_of(deck, class_id)`, `starter_card(class_id, cosmetics)` (used for Reset).
- `cosmetics` = `ItemAssets.cosmetics()`. Its `choices["eye_color"]` and `choices["skin"]` entries have `{id, name, color}`.

Server commands (sent by us from your signals): `card_look {class, part, choice}` → `invalid_card` on refusal;
`card_squad {squad}` → `invalid_squad`.

## 15. Edge cases
- **5 or 6 cards later:** the deck row scales the cards down to a minimum of 170 px wide, then scrolls
  horizontally with snap. Design the row so this works without a redesign.
- **The squad has 1 card:** its "−" sticker and the slot's "×" are disabled, with the tooltip `squad_need_one`.
- **The squad is full:** the "+" on the other cards is grey, and tapping it toasts `squad_full`.
- **Thai text 20% longer:** check the class names on the ribbon at the deck size.
- **The server is slow:** apply the choice visually at once. If `refuse()` arrives, revert.
- **Coming back from a fight:** the screen opens in state A with the same squad and no intro animation, except the
  cards bob in (300 ms).

## 16. Accessibility
- Classes are told apart by emblem and pattern as well as by colour.
- Contrast: text ≥ 4.5:1 on its background. White text on colour always has the ink outline.
- Touch targets ≥ 56 px on phones and ≥ 44 px on desktop.
- Full keyboard and controller navigation: arrows move between cards, slots and options; Enter selects; Esc goes
  back; the focus ring is always visible.
- The reduced-motion setting is in §9.

## 17. Deliverables and acceptance

**Round 1 (images, for the Boss to approve):**
1. Deck (A) at 1920 × 1080: 2 variations (a straight row vs a fan).
2. A close-up of each of the 4 cards.
3. The editor (B): one image per tab (5) and the colour picker.
4. The summon storyboard (6 frames).
5. One phone frame (2340 × 1080) of A and of B.

**Round 2 (production):** the assets in §12, and the scene in §13 if you build it.

**Acceptance checklist:**
- [ ] Matches the cartoon rules in §5.1, with no realistic metal or engraving.
- [ ] Nothing covers the face zone of any card at any size.
- [ ] Every string from §11 fits in Thai and English at the phone size.
- [ ] Every control has all its states (§8) and a visible focus ring.
- [ ] The 4 classes are distinguishable in greyscale.
- [ ] The motion follows §9, and reduced motion works.
- [ ] The assets follow the names, sizes and 9-slice margins in §12, and the total is ≤ 3 MB.
- [ ] The scene (if built) passes `godot --headless --path . --script res://tests/run_all.gd` with no new failures,
      including `test_ui_tokens.gd`.

## 18. Out of scope (now)
Skills on cards (only the locked visuals), card rarity, levels, collecting new cards, the old NPC menus (shop,
forge, farm, relics, storage), online lobby and party screens, and the results screen after a fight.

---

### Prompt starter (for exploration images only)
> Cartoon mobile game UI mockup, landscape 16:9, bright day-sky background with big puffy clouds, four tall rounded
> portrait cards in a slight fan, chunky yellow card frames with thick dark-purple ink outlines and flat cel shading,
> each card window filled with a different bright colour (sky blue, red, leaf green, violet) with a cel-shaded anime
> hero standing inside, round class badge stickers, ribbon name plates, a squad bar with three cream rounded slots
> bottom left, a big glossy orange pill fight button bottom right, bold rounded typography, playful, clean, readable,
> no text artifacts

Generated images are for exploration only. Final assets must be clean, original, editable, and follow §12.
