# Layout reference mapping — 2026-10-12 (PHASE 1, mockup only)

The Boss showed a screenshot of another MMO-style game and asked for "the overall picture roughly
like this, but in OUR OWN theme". This document records what we take from the reference's
**composition and information layout** and what we deliberately do **not** take, mapped onto zorx's
existing screens (`docs/design/screen_map.md`). Our look stays **D Night Brass** (navy-teal glass
panels, engraved brass lines, gem-cut rarity frames, code-drawn brass icons — `client/ink_ui.gd`,
`client/brass_icons.gd`). None of the reference's colours, art, ornaments or text are copied.

This is a mapping + a mockup. Nothing in the real game changes until the Boss approves (through the
PO).

---

## 1. The reference, in parts

Three large window panels open side by side over the 3D world, all the same height (~75% of
screen), each framed with a crest at top-centre, a big engraved serif title, a resize tag + resize
icon + a square red close button at top-right, and a thin double ornamental border. Around them: a
dense HUD in every corner.

- **Panel 1 STATUS** (narrow ~1/4): class emblem, name+subtitle, level + job level + progress bar,
  "CHARACTER STATS" header, "Reset stats", a table of primary stats (icon + name + value box +
  -/+/+10), then a two-column list of derived stats.
- **Panel 2 ARTIFACT** (middle ~1/4): the character model on a glowing floor circle, equipment
  slots ringed symmetrically around it (3 per side), each slot = framed icon + caption + "CLASS n"
  badge + "+7" enhance tag + corner gem dots; page arrows on the side edges.
- **Panel 3 INVENTORY** (wide ~1/2): category tabs (ALL / Consumable / Equipment / Artifact /
  Socket / Materials / Cosmetic), an 8-column grid of framed cells with "×27" stack counts and
  lock glyphs, a right scrollbar, a footer "Item 1146 · weight …", a search field + sort
  dropdown, then an action row (Use / Dismantle / Discard(disabled) / Favourite) each with a
  two-line hint.
- **HUD**: top-left name+level + long HP (red) and MP (blue) bars with filigree caps + buff icons;
  top strip currencies + a pill button + a row of labelled menu icons; top-right ornate minimap +
  channel button; bottom-centre 9-slot skill bar + two EXP bars; bottom-left chat with tabs;
  bottom-right round menu buttons + an AUTO button.

---

## 2. What we TAKE (composition only)

### 2.1 The three-panels-open-at-once idea → our Camp window
Our camp management today is **one** window with tabs (`client/camp_screen.gd`: Inventory / Look /
Repair / Camp), and the Inventory tab already is a three-column board
(`client/gear_panel.gd`: equipment board | stash grid | details). The reference's STATUS +
ARTIFACT + INVENTORY three-panel row maps cleanly onto a **widened Inventory tab** on desktop:

| Reference panel | Our mapping | Existing script |
|---|---|---|
| STATUS (stats) | New **left column: character stats** (derived stats we already compute: HP, ATK, DEF, crit, …) | `logic/profile.gd` / `logic/stats` exposes stats; a read-only stats panel would live in `client/` (new `stats_panel.gd` or a column inside `gear_panel.gd`) |
| ARTIFACT (paper doll + slot ring) | Our **paper doll with the 14 equipment slots** | `client/gear_panel.gd` (the doll + slots already exist) |
| INVENTORY (tabs + grid + footer + actions) | Our **stash grid + details/actions** | `client/gear_panel.gd` (grid, search, filters, Wear/Discard already exist) |

So on **wide**, instead of hiding the stats, we show all three columns at once (STATUS | DOLL |
STASH), the richness the Boss liked. On **compact/portrait** they collapse back to one-at-a-time
(tabs), which is what the reference's layout cannot do but a phone must.

### 2.2 Panel anatomy (frame)
Take: **crest at top-centre, engraved serif title, close button at the top-right corner, a double
engraved border.** We already have every piece as a token: `InkUi.window_style()` draws a brass
window with a **crest** on its top edge and three engraved lines; `InkUi.brush_title()` in the
"engraved" style is our serif-ish title plate; `BrassIcons.texture("close", …)` is our close icon.
We do **not** take the "drag to resize" tag / resize handle (our windows are fixed-layout and
responsive; resizing is a desktop-only affordance that fights touch).

### 2.3 The slot ring around the doll
Take: **equipment slots arranged symmetrically around the character**, each slot = framed icon +
small caption + an enhancement tag ("+N") + rarity corner pips. We already draw `+N` in `GOLD` top
-left and rarity diamond pips on cells (style guide §5). Our 14 slots
(`data/items/rules.json` "slots": weapon, hat, shirt, pants, armband, shoes, necklace, earring,
bracelet, ring, back, …) already have brass icons in `brass_icons.gd`. We arrange them left/right
of the doll rather than in a loose cluster. We do **not** take the "CLASS n" badge (we have no
class/job system) or the side page-arrows (our slots fit without paging).

### 2.4 Tab + grid + footer + action row (inventory)
Take: **a category tab strip above the grid, a dense square-cell grid, a footer summary line, and a
row of action buttons with short hints.** `gear_panel.gd` already has filters (All/Weapon/Armor/
Trinket), a search field and Wear/Discard. From the reference we adopt:
- the **footer summary** ("Stash 16/40 · Gold 250" styled as a single quiet line, numbers
  right-aligned) — we already show capacity + wallet, just formalise it as a footer;
- the **action row** sitting under the grid/details with a one-line hint under each button
  (Wear / Discard; later Enhance / Favourite when those systems exist).
We keep our **rarity frames + diamond pips** instead of the reference's plain frames (that is the
one place our theme is richer than the reference and we should not lose it).

### 2.5 HUD corners (fight HUD)
Our fight HUD (`client/hud.gd`) is already corner-based and matches the reference's skeleton:
| Reference HUD corner | Ours today | Take |
|---|---|---|
| top-left name + HP/MP bars + buffs | top-left HP + STAMINA + ULT bars + buff/debuff chips | keep; **add the player name + level line above the bars**, and give the bars the reference's long filigree-capped look (we already have `InkUi.bar_decor()` end caps) |
| top strip currencies + menu icons | top-right "Bag 9/20  Gold 340" | take the **currency row with coin icons**, formalised top-left under the name |
| top-right minimap | — | **do not take yet** (maps are small; revisit when maps are big) |
| bottom-centre skill bar + EXP | bottom-right skill icons (F/C/1/2), banner at top | take the **centred, numbered skill bar** idea for the eventual touch layout; EXP bars deferred (no XP bar system) |
| bottom-left chat | — | **do not take** (no chat system) |
| bottom-right menu buttons + AUTO | bottom-right skill/action icons | keep our action icons; **do not take AUTO** (no auto-play) |

The HUD mockup shows the reference's *density and framing* (named bars with caps, a currency row,
a tidy skill row) in our tokens, while keeping the style-guide rule that the **middle 40% stays
free** and the **HUD never takes clicks**.

---

## 3. What we DELIBERATELY DO NOT TAKE

Each of these is a system zorx does not have; copying its UI would be drawing a lie.

| Reference element | Why we drop it |
|---|---|
| **MP (blue) bar** | No mana system. We have HP + STAMINA + ULT gauge; those are our three bars. |
| **Job / class level + "CLASS n" badges** | No classes or jobs; the player has one character and gear. |
| **Allocatable stat points + -/+/+10 buttons + "Reset stats"** | Stats come from gear, not point-buy. Our STATUS panel is **read-only derived stats**. |
| **ARTIFACT page arrows** | 14 slots fit on one board; no paging. |
| **Socket / Cosmetic / "Artifact" category tabs** | We have Weapon / Armor / Trinket (`rules.json`). No sockets. Cosmetics live in the Look tab, not the bag. |
| **Market / shop in the top strip** | Shop is BLOCKED (server). Not shown. |
| **Minimap** | Maps are small; defer until maps are big (screen_map §2.3). |
| **Chat box + chat tabs** | No chat/online yet. |
| **AUTO button / auto-play** | Not a design we have; combat is hands-on. |
| **Two EXP bars + "battle-pass"-style pill** | No XP/level-up bars or battle pass. |
| **"Drag to resize" window handles** | Our windows are responsive, not free-floating; resizing fights touch. |

If the Boss wants any of these later, each is its own system task first, UI second.

---

## 4. Scripts each part would touch (PHASE 2, after approval — NOT now)

- Three-column wide Inventory: `client/gear_panel.gd` (add a stats column; it already owns the
  doll + grid + details), possibly a small new `client/stats_panel.gd` for the read-only stats
  list; `client/camp_screen.gd` only for sizing.
- Footer + action-row formalising: `client/gear_panel.gd`.
- HUD name/level + currency row: `client/hud.gd` (new top-left name line + currency row; the bars
  and chips already exist). Data for name/level/currencies from `logic/profile.gd` /
  `GameState` — if a number is not exposed, report it, do not reach into `logic/` (hard rule).
- No `logic/` changes. No new fonts, no new textures, no raw colours (style guide §1).

The mockup in `tools/shots/layout_ref_mockup.gd` is **self-contained** (it does not modify the real
screens): it composes placeholder panels from `InkUi` tokens so the Boss can judge the composition
before we touch `gear_panel.gd` / `hud.gd`.

---

## 5. Open decisions for the Boss (see the report for recommendations)

1. Show all three columns at once on desktop (STATUS | DOLL | STASH), or keep today's tabbed
   single-view and only enrich each tab?
2. STATUS panel = read-only derived stats (recommended), confirmed? (No stat-point system.)
3. Add player name + level + a currency row to the fight HUD top-left?
4. Minimap / chat / AUTO / MP / job level / market: confirmed **out** until those systems exist?
