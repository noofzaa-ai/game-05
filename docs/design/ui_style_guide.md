# zorx UI style guide

How every screen in zorx looks and behaves. **Live look: D "Night Brass"** (director, 2026-10-12):
navy-teal glass panels, engraved brass lines, brass line icons, gem-cut rarity frames. The older
proposals (ink, sumi, journal, pop) stay in `ui_themes.gd` for comparison. The structure here (token names, scales, states and
rules) stays the same whichever theme the director picks. A theme only changes token values.

- Tokens and the menu Theme: `client/ink_ui.gd`
- Theme proposals (token values only): `client/ui_themes.gd`
- Rule check: `tests/test_ui_tokens.gd` fails if a screen sets a raw `Color`, a raw font size, a
  raw style box or a theme override of its own.
- Mockups: `godot --path . --script res://tools/shots/ui_theme_shots.gd -- <out_dir> [theme] [plain]`
  (`plain` gives the same pixels on every run, so you can compare before and after a refactor).

## 1. The one rule

Screens never pick a color, a font size, a gap or a box style. They use a token from `InkUi`
(`InkUi.GOLD`, `InkUi.FONT_TITLE`, `InkUi.GAP_M`, `InkUi.window_style()`) and an `InkUi` helper
to apply it (`style_text`, `text_size`, `label`, `hud_text`, `gap`, `margins`, `panel`,
`make_primary`, `make_swatch`). If a meaning has no token yet, add one to `ink_ui.gd` and give it a
value in every theme in `ui_themes.gd`. Don't reuse a token for a different meaning just because
its color looks right.

Exceptions are rare and need a reason on the line: `# token-ok: <why>`. Colors that come from
data (a material's color, a hair dye) are fine. In the 3D world (lights, materials, telegraphs),
UI tokens are only used for feedback text: damage numbers, loot lines and popups.

## 2. Tokens

Tokens are `static var`s, so a theme can swap them before screens are built
(`InkUi.apply_tokens()`, `InkUi.reset_tokens()`). Unless noted, the default value is the
current ink-and-paper look.

### Surfaces
| Token | Meaning |
|---|---|
| `INK` | Darkest backdrop: the window behind a whole menu, and outlines on drawn text |
| `PANEL` | Panels on the backdrop (details, equipment board) |
| `PANEL_LIGHT` | Cells and buttons |
| `SLOT_BG` | An equipment slot (darker than a bag cell, so "where it goes" differs from "what you have") |
| `FIELD_BG` | Text fields |
| `BORDER` | Default 1-unit edge of panels, cells and buttons |
| `HOVER_BG`, `PRESSED_BG`, `TAB_HOVER_BG` | Button and tab states (`PRESSED_BG` is also the open tab) |
| `DISABLED_BG`, `DISABLED_BORDER` | A control that cannot be used now |
| `SCRIM`, `SCRIM_STRONG` | Dims the game behind a menu / behind the character creator |
| `SCROLL_TRACK`, `CLEAR` | Scroll track; fully transparent |

### Text
| Token | Meaning |
|---|---|
| `PAPER` | Body text (the name is historical: it's the text color in every theme) |
| `MUTED` | Secondary text: hints, labels next to values, subtitles |
| `TEXT_STRONG` | Text on a hovered, pressed or selected control |
| `TEXT_DISABLED` | Text on a disabled control |
| `TEXT_PLAIN`, `TEXT_BRIGHT` | List text with no meaning of its own; a cost you can pay (merge into `PAPER` when a theme is chosen) |
| `TEXT_TAG` | Small "Worn" / "Stash" tags |
| `TEXT_LOCKED`, `TEXT_UNLOCKED` | Not yet unlocked (always with words, e.g. "camp level 3") |
| `HEADING_ACCENT` | List section headings |
| `SUBSTAT` | An item's extra stats |
| `TITLE_TEXT`, `TITLE_OUTLINE`, `TITLE_BG`, `TITLE_STYLE` | Section title: text, its outline, the backing color and the backing shape (`brush`, `ribbon`, `underline`, `engraved`) |

### Meaning (state colors)
| Token | Meaning | Always paired with |
|---|---|---|
| `SEAL` | Selection, the one main action, the brush strokes | A thicker frame plus corner brackets (`SELECT_MARK`) |
| `GOLD` | Money, highlights, keyboard focus, valid drop targets | A double frame on targets; the word "Gold" for money |
| `GOOD` / `GOOD_TEXT` | Gains, "all fine" | A `+` sign and "(up)", or words |
| `BAD` / `CANT_AFFORD` | Losses, errors, things you can't pay for | A `-` sign and "(down)", or words; a disabled button |
| `WARN` | Worn-down item mark | A `!` in a circle |
| `WEAR_OK`, `WEAR_LOW`, `WEAR_BROKEN` | Durability text | "Durability 100%" / "Worn 25% (stats reduced)" / "broken down" |
| `STAGE_*` | Journey stage kinds (combat, challenge, treasure, camp, boss) | The kind's own word on the button |

### Rarity
Metals and gems: Normal = steel, (Uncommon = jade, reserved: no tier uses `green` yet), Rare =
sapphire, Epic = amethyst, Legendary = amber gold. Each tier also has its own frame shape and gem
count: Normal one line and 1 gem, Rare two lines and 2 gems, Epic two lines with corner brackets
and 3 gems, Legendary two lines, studded corners, a halo and 4 gems. A gem-like glow rises from the
cell's bottom in the tier color. Selection is an ember ring outside the cell, white corner brackets
and an ember pointer on the top edge: shapes no tier frame has.
`RARITY` (menus) and `RARITY_WORLD` (over the 3D world: loot beams, loot lines, the HUD loot feed)
are keyed by the tier's `color` key in `data/items/rules.json`: `white`, `blue`, `purple`, `gold`
(Normal, Rare, Epic, Legendary). Use `InkUi.rarity_color(key, world)`. Rarity never relies on
color alone (see section 6).

### HUD (in combat)
`HUD_PANEL` (bar backs, skill icons), `HUD_TEXT`, `HUD_OUTLINE`, `LOOT_OUTLINE`, `HP`, `HP_TRAIL`,
`STAMINA`, `STAMINA_EXHAUSTED`, `STAMINA_BLINK`, `ULT`, `ULT_READY_TEXT`, `ULT_ICON_PULSE_A/B`,
`ULT_ICON_FILL_ALPHA`, `BUFF`, `DEBUFF`, `CHIP_BASE`, `CHIP_TINT`, `CHIP_ALPHA`, `KEY_BADGE`,
`KEY_TEXT`, `ICON_LABEL`, `COOLDOWN_COVER`, `ICON_ACTIVE` (the action is happening),
`ICON_UNAFFORDABLE` (not enough stamina), `ICON_CHARGING` (not ready, nothing wrong),
`ICON_DIM_ALPHA`, `COMBO_COOL`, `COMBO_HOT`, `COMBO_OUTLINE`, `COMBO_LABEL`, `COMBO_TIMER`,
`WARNING_TEXT`, `TRIP_TEXT`, `SKILL_BANNER_BG`, `SKILL_BANNER_TEXT`, `PROMPT_TEXT`, `INFO_TEXT`,
`HELP_TEXT`, `HELP_PLATE`.

### World feedback (`client/stage_view.gd`)
`DAMAGE`, `DAMAGE_BIG` (larger too), `DAMAGE_CRIT` (larger, with `!`), `DAMAGE_BLOCKED` (says
BLOCK), `POPUP_RESIST`, `LOOT_GOLD`, `LOOT_PROBLEM` (BAG FULL), `BAG_LOST`.

### Shapes
| Token | Default | Effect |
|---|---|---|
| `RADIUS_ADD` | 0 | Added to every corner radius |
| `CORNER_SKEW` | 3 | Top-left and bottom-right corners this much rounder (a brushed edge) |
| `BORDER_SCALE` | 1 | Multiplies every border width (bolder outlines) |
| `SHADOW_SIZE`, `SHADOW_OFFSET`, `SHADOW_COLOR` | 0 | Drop shadow under panels and buttons |
| `FONT`, `FONT_EMBOLDEN` | null, 0 | The font (null = engine default) and synthetic bold (FontVariation, 0 KB) |
| `CORNER_DETAIL` | 8 | Segments per rounded corner; 1 gives cut (chamfered) corners |
| `FRAME_STYLE`, `ORNAMENT` | "plain" | "engraved": panels get a second inset `ORNAMENT` line with corner diamonds, the window a medallion on its top edge, HUD bars/icons an `ORNAMENT` line, diamond key badges, a pointed skill-banner plate and a plate under the trip line. Drawn in code (`InkUi.engraved()`, `InkUi.hud_ornament()`), 0 KB |
| `ICON_STYLE`, `ICON_TINT` | "brass" | The line icon set (`client/brass_icons.gd`, SVG text, about 6 KB) on tabs, filters (in cogwheels, with gold count badges), empty slots, the wallet, HUD actions, close/back, campfire menu and journey choices; "plain" = no icons |
| `BAR_STYLE`, `HP_LOW`, `LOW_HP` | "brass", 0.3 | HUD bars: gloss, segment ticks (stamina: one per 10), a hatched dark damage trail (never reads as more HP), brass frame with a gem cap; under `LOW_HP` the HP frame pulses to `HP_LOW` and the cap shows "!" |
| `GLASS_GLOW`, `LINE_PHONE` | | Glassy top highlight on panels; engraved lines are drawn at least `LINE_PHONE` real pixels thick on phones |
| `DISPLAY_FONT` | null | Face for menu titles (`FONT_TITLE`..`FONT_DISPLAY`), section titles and the HUD skill/banner words; null = `FONT`. Body text and numbers keep `FONT` |

## 3. Type scale (menu units)

| Token | Size | Use |
|---|---|---|
| `FONT_DISPLAY` | 28 | Screen name on the campfire menu |
| `FONT_TITLE` | 24 | Window title ("Camp"), journey header |
| `FONT_HEADING` | 20 | Main stat in item details, list headings |
| `FONT_ITEM` | 19 | Item name in details |
| `FONT_SECTION` | 18 | Brush titles, the journey screen body |
| `FONT_BODY` | 17 | Default for every control (Theme default size; tabs are +1) |
| `FONT_LABEL` | 16 | Detail lines |
| `FONT_SMALL` | 15 | Wallet, filters, comparisons |
| `FONT_NOTE` | 14 | Notes, stat table names |
| `FONT_CAPTION` | 13 | Hints, the portrait wallet |
| `FONT_TINY` | 12 | Item detail line in lists |

The HUD has its own sizes in HUD units (`HUD_FONT`: hp 17, bar 13, bar_small 12, chip 13, key 15,
icon 13, cooldown 22, loot 18, combo 80 / combo_compact 64, combo_label 22, combo_damage 20,
banner 42, skill 40, prompt 20, trip 17, info 14, help 13, warning 13). On phones the HUD
draws them x1.8.

Rules:
- Real size = units x the layout scale (`InkUi.layout_for()`). On a typical phone in landscape
  (390 pt tall) the compact scale is about 0.78, so `FONT_TINY` shows at about 9 pt and
  `FONT_CAPTION` at about 10 pt. In compact, essential information must be at `FONT_NOTE` or
  larger. `FONT_TINY` and `FONT_CAPTION` are only for hints you can skip.
- Thai text needs about 10% more line height than Latin, and its tone marks get clipped by tight
  boxes. Don't fix the height of a label that holds words.
- Eleven steps is too many. When the theme is chosen, merge them into 7: 28, 24, 20, 17, 15, 13,
  and 12 for the HUD only. Today's values are kept as they are so the look stays the same.

## 4. Spacing

`GAP_XXS` 2, `GAP_XS` 4, `GAP_S` 6, `GAP_M` 8, `GAP_L` 10, `GAP_XL` 12, `GAP_XXL` 14,
`GAP_HUGE` 16. Window margin per layout: `EDGE_WIDE` 24, `EDGE_COMPACT` 8, `EDGE_PORTRAIT` 4
(`InkUi.edge_for(mode)`); campfire menu `EDGE_HUB` 40.
Use `GAP_XS` inside a group (filters, cells), `GAP_S`/`GAP_M` between lines, and `GAP_XL`/`GAP_HUGE`
between columns. Cell grids use the per-mode `gap` in `gear_panel.gd` `SIZES`, which is layout
rather than style.

## 5. Component states

| Component | normal | hover | pressed / on | disabled | focus (keyboard/pad) |
|---|---|---|---|---|---|
| Button | `PANEL_LIGHT` + `BORDER` 1, `PAPER` | `HOVER_BG` + `GOLD` 1, `TEXT_STRONG` | `PRESSED_BG` + `SEAL` 2 | `DISABLED_BG`, `TEXT_DISABLED` | `GOLD` 2 ring |
| Primary button (one per screen) | `SEAL` + `GOLD` 1 | as Button | as Button | as Button | as Button |
| Tab | `PANEL`, `MUTED` | `TAB_HOVER_BG`, `PAPER` | open: `PRESSED_BG` + `SEAL` 3 underline, `TEXT_STRONG` | - | `GOLD` 2 ring |
| Text field | `FIELD_BG` + `BORDER` | - | - | - | `GOLD` 2, caret `GOLD` |
| Panel | `PANEL` + `BORDER` 1; whole window `window_style()` (`INK`) | | | | |
| Swatch | its own color + `BORDER` 1 | `PAPER` 2 | picked: `SEAL` 4 | | `GOLD` 1 |

Item cells (`client/item_cell.gd`):
| State | Look (color + shape) |
|---|---|
| Empty bag cell | `PANEL_LIGHT`, `BORDER` 1 |
| Empty equipment slot | `SLOT_BG`, the slot's silhouette in `MUTED` at 50% |
| Item | Its picture, frame in its rarity color, thicker per tier, 1-4 diamond pips |
| Enhanced | `+N` in `GOLD`, top left |
| Stack | Count in `PAPER`, bottom right |
| Worn (equipped) | Check mark in `GOOD` with an ink edge, top right |
| Worn down / broken down | `!` in a `WARN` / `BAD` circle, top right |
| Selected | `SEAL` 3-unit frame plus `SELECT_MARK` corner brackets |
| Valid target | Double `GOLD` frame |
| Not allowed now | Whole cell at 35% |

## 6. Icons, rarity and color-blind safety

Never use color alone. Every colored state also has a shape, a sign or a word:
- Rarity: diamond pips (1 Normal, 2 Rare, 3 Epic, 4 Legendary), a thicker frame per tier, and the
  tier name in words in the details and the loot feed ("Ash Spear  Rare").
- Gains and losses: `+` / `-` signs and "(up)" / "(down)". Buff and debuff chips get `+` / `-`
  marks as well as the green or red edge.
- Danger: `!` marks, a blinking bar plus the words "NOT ENOUGH STAMINA", "BAG FULL", "BAG LOST".
- Can't afford: the button is disabled (dimmed). The cost line should also say what's missing
  (currently it only turns red, see the open issues in the report).
- Avoid red/green as the only pair. `GOOD` and `BAD` also differ in lightness. Selection
  (`SEAL`) is red-orange and always carries the brackets.
- Contrast (checked by the test for every theme): body text on panels at least 4.5:1, secondary
  text and gain/loss colors at least 3:1.
- Item icons are the item's picture. Placeholder icons are silhouettes outlined in `ICON_INK`.

## 7. Touch targets

The minimum is 44 pt (Apple) / 48 dp (Android) of real screen. Real size = menu units x scale.
| Mode | Typical scale on a phone | Minimum target in menu units | Today |
|---|---|---|---|
| `wide` (mouse) | 1.0 | 32 | buttons 44, cells 60: OK |
| `compact` (phone landscape, about 390 pt tall) | about 0.78 | 56 | cells, filters, search, detail buttons 56 (44 pt): OK. Tabs and the Close button are still about 31-34 pt |
| `portrait` (phone upright, about 390-430 pt wide) | 0.9-1.0 | 48 | buttons 44, cells 48 (about 44 pt): borderline |

Keep at least `GAP_S` between neighboring targets. A target that destroys something (Discard)
needs a second press (already done: "Sure? Discard").

## 8. HUD rules (steep top-down camera)

- The player is in the middle of the screen. Keep the middle 40% free. The skill banner sits at
  the top (wide) or low and beside the skill icons (compact).
- Every HUD text has an outline (`HUD_OUTLINE`, 3 to 12 units). Small text sits on a plate
  (`HELP_PLATE`, `HUD_PANEL`). The ground in daylight stages is light, so don't use bare thin
  text.
- Bars carry their numbers inside, on the left. The stamina bar grows with max STAMINA.
- The loot feed is in rarity colors with a dark `LOOT_OUTLINE`, including on a light theme.
- The HUD never takes clicks (mouse clicks are attacks).

## 9. Adding a new screen

1. Put it in `client/`. It shows state from `logic/` and sends input. It decides nothing.
2. Build it under a `Control` whose `theme = InkUi.make_theme()`, scaled with `InkUi.layout_for()`
   and `InkUi.margins(..., InkUi.edge_for(mode))` like `camp_screen.gd`. Lay out `wide`, `compact`
   and `portrait` on purpose, not by squeezing.
3. Keep every word in one `TEXT` dictionary at the top of the file, ready for Thai/English.
4. Use tokens and `InkUi` helpers only. If something is missing, add a token (section 1).
5. Cover the empty, error and low-resource states (no items, not enough gold or stamina, a full
   bag, data failed to load).
6. Take screenshots with a `tools/shots/` script at wide, phone landscape and phone portrait, and
   look at them. Add the file to `UI_FILES` in `tests/test_ui_tokens.gd` if it doesn't preload
   `ink_ui.gd`.

## 10. Switching to a chosen theme

Copy the chosen theme's values from `client/ui_themes.gd` into the defaults in `client/ink_ui.gd`,
merge the near-duplicate tokens (`TEXT_PLAIN`, `TEXT_BRIGHT`, `GOOD_TEXT`, `CANT_AFFORD`,
`WEAR_LOW`, `RARITY_WORLD`) and consolidate the type scale (section 3). Then rerun the shot script
and the tests. No screen file should need to change.

## 11. Web size

StyleBoxFlat, FontVariation (bold, spacing) and colors cost 0 KB. Textures (9-patch frames,
paper grain) cost 30-200 KB each and should be avoided while the web data pack is at 14.81 of
15 MB. **Thai needs a font whatever the theme**: the engine default font (Open Sans SemiBold) has
no Thai glyphs. Desktop falls back to system fonts, but the web build can't, so Thai shows as boxes
on the web. Plan for one Thai+Latin font, subset to the characters used, as WOFF2: about 25-60 KB
per weight.
