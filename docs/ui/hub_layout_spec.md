# Hub layout spec: class-card home screen + card character screen

Status: proposal, 2026-11-11 (ux-ui-designer). Follows the Boss decisions of 2026-11-11 (leather/parchment frames
`art_source/ui/class_cards/v10/boss_6..9.png`, background A `bg_ruins_v10_a.png`, full-body characters, English card text,
per-card gear, service menus drawn along the side of the screen).
Mocks: `art_source/ui/class_cards/v10/hub/_mock_hub_1080.png`, `_mock_hub_phone_2340.png`, `_mock_character_1080.png`
(made by `hub/mock_hub.py`; art cut by `hub/cut_hub.py`; nothing is imported into `art/` yet).

## 1. Home screen regions

Reference canvas 1920x1080. The canvas scales by height (`CardTokens.scale_for`), so 1080 px of height is always the
same layout. Wider screens add width on both sides; the content stays inside the safe area.

| Region | 1920x1080 (x, y, w, h) | Phone landscape 2340x1080 |
|---|---|---|
| Safe area | 40 px each side, 24 px top/bottom | +132 px each side for notch / rounded corners (`DisplayServer.get_display_safe_area()`; use the larger of the two values) |
| Top bar | title "MY CARDS" left (52 px serif); gold counter + Account + Settings right; height 110 | same, inside the safe area |
| Side menu (left) | x 28, y 132, entry 300x~100, step 104, 6 entries (ends y ~760) | x 160, same sizes |
| Card row | the space right of the menu (x 400..1880); 4 cards 300 wide (450 tall), gap 34, top y 150 | x 532..2168; the cards stay 300 wide (extra width goes into the margins) |
| Hint line | centred under the cards, y 640, 22 px | same |
| Squad tray | x 470, bottom 34 px from the edge, 760x210, 3 slots with a number medallion 1-3 | x 602 |
| FIGHT button | right corner, 470x210, the stage name above it (22 px) | 40 px inside the right safe edge |

Rules
- The cards never cover the menu or the tray. Below about 1600x1080 effective width (4:3 tablets), the cards shrink to
  fit the card row (minimum 240 wide); below that they become a horizontal scroller, never two rows.
- A phone held upright (portrait) is not supported for the hub: show a "rotate your device" card (the game is landscape).
- Touch sizes at 1080 px = ~68 mm screen height on a 6.5" phone: menu entries (100 px, ~6.5 mm) and the tray slots pass.
  **The system buttons (80 px, ~5 mm) are too small on a phone: use 96 px with a 112 px hit area** when the screen is under 7".

## 2. Side menu

**Side: left.** Reading starts top-left, the right thumb rests on FIGHT, and the left side of background A is the
vine arch + campfire, the "camp" half of the picture, so the services sit by the fire. The right side is
kept for the FIGHT action and the moon/ruins.

Order (most used first): Blacksmith, Shop, Tailor, Storage, Quests, Relics.

Entry = the leather plate (`hub_menu_plate_v1.png`) + the service medallion (`icon_<service>_v1.png`) over the round
socket + an English label (serif 36 px, ink #3A2414) on the parchment. All labels come from one TEXT table (localizable;
Thai labels must fit the same width: shrink to 28 px before wrapping).

| State | Look (never colour alone) |
|---|---|
| Normal | as drawn |
| Hover / keyboard focus | warm gold glow around the plate, the plate moves 6 px right; focus also gets a 3 px cream outline |
| Pressed | plate moves back 2 px, 8% darker, medallion scale 0.96, click sound |
| Locked | plate and medallion desaturated + darkened; cream label with a dark outline; a second line says how to unlock ("Quest 3 to unlock"). Tapping shows that line as a toast; it never opens the panel |
| Has notification | red disc badge with a white number and dark ring on the medallion's top-right (number = things to claim/collect). Without a number (just "new") use a "!" |
| Disabled because of a missing resource | never: services always open; the panel itself says what is missing (for example "Need 100 gold") |

How each menu opens (all are owned by the hub; Back/Esc closes back to the hub, never further):

| Service | Opens as | Content (logic already present) |
|---|---|---|
| Blacksmith | panel over the scene (leather/parchment panel, 1500x880 centred, the cards dimmed behind) | tabs Refine / Upgrade tier / Repair; picks a card first (the 4 card heads in a strip at the top), then that card's gear (`logic/refine.gd`, item_system enhance/upgrade, camp repair) |
| Shop | panel over the scene | Buy / Sell lists, gold shown at the top (`data/items/shop.json`) |
| Tailor | full screen (needs the big live character) | the card's Outfit tab (same screen as section 4, opened on Outfit) with a card picker |
| Storage | panel over the scene | stash + vault grids (`client/storage_panel.gd`) |
| Quests | panel over the scene | quest list, claim buttons; the Magic card unlock is shown as a quest reward |
| Relics | panel over the scene | relic slots (1 of 3 unlocked, `logic/relics.gd`), catalogue |

## 3. Squad tray and FIGHT

- Tray: 3 slots with the card head; number medallion 1-3 = fight order. Tap a deck card's "SQUAD" plate or drag a card onto a
  slot to place it; drag a tray head off to remove it. Empty slot: dashed outline + "+" and "Add a card".
- FIGHT: big plaque; the stage name above it. With an empty squad FIGHT is greyed and its line reads "Pick at least 1 card".
  Not enough stamina/tickets (if added later): the line says what is missing and the button stays pressable to show it.
- Locked card (Magic): grey, "LOCKED" across the window, tap = toast "Finish Quest 3 to unlock Magic" (reason, not just a lock).

## 4. Card character screen (tap a card)

Full screen, opened from a card. Mock: `_mock_character_1080.png`.

- Top bar: Back medallion (left), card name (52 px serif), card switcher under it ("< prev | Card 1 of 4 | next >", also
  swipe on touch, LB/RB on gamepad, Q/E on keyboard), gold + Account + Settings on the right.
- One leather/parchment panel (`hub_panel_tabs_v1.png`, 1840x930) with 3 bookmark tabs: **Equipment**, **Outfit**, **Skills**.
  The active tab is lighter and underlined (shape cue as well as colour).
- **Equipment tab** (left half): a paper-doll grid of 5 columns x 6 rows of 104 px slots
  (`equip_slot_normal_v1` / `equip_slot_selected_v1`) around the full-body character window (3x4 cells, live 3D).
  Accessories on the top row (Earring, Earring, Necklace, Ring, Ring), armour down the left (Hat, Shirt, Pants, Shoes),
  arm pieces down the right (Armband, Bracelet, Bracelet), Weapon and Back under the character. This is exactly
  `gear_panel.gd` SLOT_PLACES. Each filled slot: the real item icon, tier pips (1-4 diamonds, shape + colour), "+N" refine.
  Empty slot: the slot name in muted text. The card's stats (HP, ATK, DEF, CRIT) sit on a dark strip at the foot of the
  character window.
- Right half: the **item details** (pinned tooltip) of the selected piece: icon, name + refine, slot · tier, main stat
  (with the refine share), substats, durability bar with "82 / 100" as a number, and the actions Unequip / Refine / Repair
  (Refine and Repair jump into the Blacksmith panel for this item). Under it, the **shared Storage grid** with filters.
  Hover on desktop shows the same detail as a floating tooltip next to the cell (compare against the worn piece: green up /
  red down arrows + signed numbers).
- **Outfit tab**: the character larger in the centre; the outfit / hair / eye colour / skin / makeup choices of
  `CardDeck.PARTS` on the right (reuse `look_panel.gd` patterns; the deck editor of `card_deck_screen.gd` state B already does this per card).
- **Skills tab**: the class's skills (icon, name, short text, cooldown), read-only for now.
- Input on the grid (same as today, `item_cell.gd`): tap = select/details, double-tap/right-click/drag = wear or take off,
  hold = details sheet. Every action is also a button in the details, so nothing needs hovering.

## 5. Navigation and back rules

- Hub is the root. One level of panels over it; the character screen is one full-screen level; a Blacksmith panel opened
  from the character screen stacks over it (max depth 2).
- Back medallion, Esc, gamepad B, Android back: close the top-most panel; on the character screen go back to the hub;
  on the hub ask "Back to title?" (no instant exit).
- After a fight the game returns to the hub with the squad unchanged; rewards appear as a badge on the service that has
  something new (Quests, Storage).
- Unsaved state does not exist: every change is a server command at once (`card_deck_screen.gd` wiring); on a refused
  command the panel shows the reason in a status line and redraws from the profile.

## 6. Keyboard / gamepad focus order

Hub: cards (left to right; Left/Right) -> Up from a card goes to the top bar, Left from the first card goes to the side
menu (Up/Down inside it), Down from the cards goes to the tray slots (Left/Right) then FIGHT. Initial focus: the first squad
card. Shortcuts: Enter/A = open, F or Start = FIGHT, 1-3 = tray slots, Esc/B = back, Tab cycles regions.
Character screen: tabs (Q/E or LB/RB switch the card; 1-3 or the bumpers with a modifier switch the tab) -> slot grid
(arrow keys move in the 5x6 grid) -> detail buttons -> storage grid. Focus ring: 3 px cream outline + gold glow.

## 7. Accessibility

Colour is never the only signal (tier pips, badge numbers, lock text, underline on tabs). Text sizes are tokens and follow
the text-scale setting (100-150%); labels shrink then wrap, never clip. Reduced motion: no card bob, no glow pulse.
Every string in one TEXT table per screen (English now, Thai later).

## 8. Code to reuse (all in `client/`)

| File | What it gives | Change needed |
|---|---|---|
| `card_deck_screen.gd` (1571 lines) | the home screen, signals card_selected / squad_changed / fight_pressed / settings_pressed / back_pressed, command wiring, ui_cancel | swap the art via `card_tokens.gd`, add the side menu column and the tray; replace `bag_pressed` with one `service_pressed(id)` signal |
| `card_tokens.gd` | every colour, size, string, art path; `ART_DIR` falls back to placeholders | new tokens for the leather palette, menu, tray, FIGHT |
| `card_portrait.gd` | live 3D class character in a SubViewport (`set_framing`), render modes | add a "full" framing (full body) for the cards and the character window |
| `card_frame.gd` | code-drawn frame | replaced by the Boss frame PNGs (keep the layer order: art window under the frame) |
| `gear_panel.gd` (1124 lines) | paper-doll + 14 slots (SLOT_PLACES), bag grid, details, equip/unequip through LocalSession | needs a `card` argument once the loadout is per card; restyle with the new slot tiles |
| `item_cell.gd` | slot/bag cell: tap/double-tap/hold/drag, tier pips, selection frame | draw the leather slot texture behind it |
| `look_panel.gd` | look choices with icons | patterns for the Outfit tab; the per-card parts come from `logic/card_deck.gd` |
| `storage_panel.gd`, `paper_doll.gd`, `graphics_panel.gd`, `squad_panel.gd` | Storage panel, live doll, Settings, fight squad names | reuse as they are |

## 9. Gaps in logic (report, not UI work)

- **Per-card loadout does not exist yet**: `Profile` has one `loadout`; `card_deck.gd` cards hold only looks. The
  character screen needs `Profile` loadout per class card and equip/refine commands that name the card (Boss decision 2026-11-11, PROGRESS.md).
- Quests have no logic yet (the Quests panel and "Magic unlocks after Quest N" need it).
- The data has **14 equipment slots** (`data/items/rules.json`), not 15. The Sword & Shield shield (`off_hand` in
  `data/classes/sword_shield.json`) is a class part, not a slot.
