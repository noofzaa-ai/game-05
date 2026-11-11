# zorx screen map

Every screen that the GDD implies: how the screens connect, plus a rough wireframe of each. This
covers wireframes only. New screens are not built yet. Style rules: `docs/design/ui_style_guide.md`.

Status: **EXISTS** (in `client/` today), **PLANNED** (follows from the GDD, can be designed
now), **BLOCKED** (needs a director decision first; the question is named).

Layout modes (`InkUi.layout_for()`): **wide** = desktop/tablet (1240x680 units), **compact** =
phone landscape (500 units tall), **portrait** = phone upright (430 units wide).

## 1. Flow

```
[Boot] -> [Title / account] -> (new player) -> [Character creator] --+
                 |                                                   |
                 +-------------------> [CAMP HUB: walkable village] <+
                                              |
     +-----------+-----------+----------------+------------+------------+-----------+
     |           |           |                |            |            |           |
 [Camp window] [Facility  ] [Journey board]  [Co-op room] [PvP gate]  [Guild]    [Settings]
  Inventory     Workbench    choose journey   invite into  LOCKED      phase 5    (from any
  Look          Armory       -> [Loadout]     my camp                              screen)
  Repair        Farm/Kitchen     |
  Camp          Storage          v
  Shop?                       [Journey route] <------------------------------+
                                 | pick 1 of 3: combat / challenge / treasure |
                                 v                                            |
                              [IN-RUN HUD] --(Q at a rest point / camp stage)-> [Rest / mid camp]
                                 |  (Esc) -> [Pause]                         |
                                 |  stage cleared --------------------------+
                                 |  died ----------------> [Run result: LOST bag]  --> CAMP HUB
                                 |  boss beaten / went home -> [Run result: brought home] -> CAMP HUB
                                 |  Leave the journey -> [Confirm: lose this run's loot] -> CAMP HUB
```

Rules the flow must make obvious (GDD extraction core):
- What's in the run bag is **not yours yet**. It counts only once you're back at camp. Death loses
  the bag, and worn gear stays (it only loses durability).
- Leaving the journey before a camp stage loses the run's loot. The confirm dialog must say so in
  words, and the confirm button can't be the default.
- Before every run comes the loadout.

## 2. Screens

### 2.1 Character creator (EXISTS: `client/character_creator.gd`)
```
+------------------------------------------------------------+
| Make your character                                         |
| +--------------+  Face   [o][o][o]                          |
| |  paper doll  |  Hair   [o][o][o]   Hair color [#][#][#]   |
| |  (drag=turn) |  Skin   [#][#][#][#]  Eyes [#][#]          |
| +--------------+                                            |
| Name [________________]  [Random]  [ START ]  (primary)     |
| problem line in BAD, only when the name is not allowed     |
+------------------------------------------------------------+
```
- wide: doll left, choices right. portrait: doll on top (smaller), choices scroll under it, and
  the name row is pinned at the bottom.

### 2.2 Title / account (PLANNED, BLOCKED on server and login: the account system isn't designed)
```
            ZORX (logo)
      [ Play ]  [ Settings ]
      account: guest / signed in      v0.x
```
- Today the game starts straight at the campfire (`scenes/hub.tscn`). Keep this screen to one tap.

### 2.3 Camp hub: walkable village (EXISTS as a placeholder: campfire plus text menu in `client/hub.gd`; PLANNED as a village)
```
 3D village, the player walks; a building's prompt floats over it:
        [Workbench]   [Storage]   [Farm]    [Armory]   [Journey board]
 HUD top-left: Camp Lv.2   Gold 250   Ore 10 ...          top-right: [Settings]
 bottom: "E / tap = open Workbench"  (prompt, like the rest-point prompt)
```
- GDD: walk into buildings, then press to open their screen. Until then the text menu (PvE Farm,
  Journey, PvP, Camp, Customize) stays, in a brass window with an icon per entry (D theme).
- portrait: the campfire menu becomes a bottom sheet of big buttons.

### 2.4 Camp window: Inventory tab (EXISTS: `camp_screen.gd` + `gear_panel.gd`)
```
wide
+ Camp ---------------------------------- Stash 16/40 Gold 250 Ore 10 ... [Close (Esc)] +
| [Inventory] [Look] [Repair] [Camp]                                                    |
| +-Equipment--------+ +-Stash---------- Gold 250 16/40-+ +-Details-------------------+ |
| | o  o  v  O  O    | | [Search.........]              | | [icon] Legendary Daggers  | |
| | H  [ paper ]  A  | | [All][Weapon][Armor][Trinket]  | | Weapon  Tier 4 of 4 [Back] | |
| | S  [  doll ]  B  | | [#][#][#][#][#][#]             | | ATK 80                    | |
| | P  [       ]  B  | | [#][#][#][#][#][#]             | | + substats ...            | |
| | F                | | [#][#][ ][ ][ ][ ]             | | Compared with your Weapon:| |
| |    W        Bk   | |                                | | ATK +57.8 (up) ...        | |
| +------------------+ +--------------------------------+ | [Wear] [Discard]          | |
+---------------------------------------------------------------------------------------+
portrait: board (slots around the doll) / details as a short sheet / stash grid, one column.
```
- Empty: "Nothing here yet: hunt monsters on a journey." Full: the capacity shows `FULL` in `BAD`.

### 2.5 Camp window: Look, Repair, Camp tabs (EXISTS)
```
Look:   [doll] | Face / Hair / Hair color / Skin / Eyes choice rows
Repair: Workbench Lv.1, discount ... | Worn  <item>  <cost>  [Repair]   ...  [Repair all worn gear]
Camp:   Camp level 2 / 5   Next level: 1200 gold, 40 ore [Upgrade camp]
        Facilities: Workbench (Lv.1)  <cost -> effect>  [Upgrade]
        Camp skills: [x] Hardy Camp ...  [ ] Iron Resolve - camp level 4
```
- These are long lists. In portrait each row wraps (cost under the name, button full width).
  Can't-afford rows must say what's missing ("need 15 more ore"), not only turn red.

### 2.6 Loadout before a run (PLANNED; partly BLOCKED: what can be carried besides worn gear? potions/food slots, how many)
```
+ Prepare for the journey: Ink Road ----------------------------------------+
| Worn gear (from camp)        | Carry (run bag 12 slots)   | Summary        |
| [H][S][P][F][W] ...          | potions  [#][#][ ][ ]      | HP 1142  ATK.. |
| durability warnings: (!) x1  | food     [#][ ][ ]         | Repair first? |
|                              | free bag slots: 7 / 12     |  [Repair (40g)]|
|          [Back to camp]                       [ SET OUT ] (primary)        |
+---------------------------------------------------------------------------+
```
- Must warn about gear that will lose stats (worn below the full-stats line) and offer the
  repair right there.
- portrait: three stacked sections, with SET OUT pinned at the bottom.

### 2.7 Journey board / journey select (PLANNED)
```
 Journey board:   [Ink Road  - 12 stages - recommended GS 300]  [locked: Ash Marsh - camp Lv.3]
                  best result, last loot, difficulty tier
```

### 2.8 Journey route (EXISTS: `client/journey_screen.gd`)
```
 ~~ Ink Road  -  Stage 4 / 12 ~~
 HP 820/1142   Bag 6/12   Gold 120
 1 - 2 - 3 - (4) - ? - ? - C - ? - ? - ? - C - BOSS       (path so far)
 Choose the next stage:
 +-COMBAT--------+ +-CHALLENGE-----+ +-TREASURE------+
 | Stage 5       | | Stage 5       | | Stage 5       |
 | Sunward Valley| | harder, better| | rare+ gear    |
 +---------------+ +---------------+ +---------------+
 [Camp window]   [Leave the journey]  (BAD, confirm)
```
- portrait: the three choices stack vertically as full-width cards. The path line becomes a
  vertical strip.

### 2.9 In-run HUD (EXISTS: `client/hud.gd`)
```
 [HP 380/1000 =====-----]                         Enemies 3  Bag 9/20  Gold 340
 [STAMINA 22/100 ==-----]           ~Crescent Cut~                    7
 [ULT 60% ======---]                                           HIT COMBO
 [+ Rage 7.0] [- Poison x2 3.5]                                1,234 DMG
                                (player, centre 40% kept free)
                                                    + Golden Blossom Katana  Epic
           Q = rest point (sort the bag, heal, go home)       + 25 gold
 Sword  Camera 8 High                                 [F Guard][C Dodge][1 Skill][2 Ult]
 [help lines (F1)]
```
- compact: HUD drawn x1.8, help hidden, skill banner low. Touch buttons will replace the bottom
  right icons: **BLOCKED on the mobile-controls decision** (stick + buttons layout, where skills
  3-5 go).
- portrait combat: **BLOCKED / open issue.** Today the HUD is not laid out for an upright phone
  (it's tiny and the prompt overlaps the banner). Decide whether combat is landscape-only.

### 2.10 Pause (PLANNED)
```
 Paused:  [Resume]  [Settings]  [Controls]  [Leave the journey (lose the bag)]
```

### 2.11 Rest point / mid-journey camp (EXISTS as the rest point: `camp_screen.gd` rest mode; mid camp BLOCKED on `camp_banks_bag`)
```
+ Rest point ------------------------------------------- Bag 9/12 Gold 340 [Close] +
| [Inventory]  [Rest]                                                             |
| Inventory = the same window over the run bag (+ "the bag is lost if you die")   |
| Rest: [Heal once (50% HP)]  [Go back to camp with the loot]  [Keep going]       |
+---------------------------------------------------------------------------------+
```
- Mid-journey camp (stages 5-7 and 11): whether "store" means **send to the stash (safe)** or
  **only sort the bag** changes this screen. If it banks, it needs a "Send to camp" action and a
  clear safe/unsafe marker on every item.

### 2.12 Run result (PLANNED; today it's a text banner "STAGE CLEAR / DEFEATED" in the HUD)
```
 BROUGHT HOME (GOOD, + check)            or   BAG LOST (BAD, + broken-bag mark)
 Kept:  [#][#][#][#]  +340 gold  +12 ore         Lost: [#][#][#] 120 gold
 Gear wear: Sword -12%  (!) Helmet worn          Gear kept (worn): durability -25% each
 [Back to camp]  [Repair now]                    [Back to camp]
```
- Must show "lost" items in the same cells, dimmed and crossed, so the loss reads without color.

### 2.13 Armory: enhancement (PLANNED, BLOCKED on enhancement rules: cost, success chance, failure result)
```
 [item cell +3] -> [item cell +4]     ATK 80 -> 92 (up)
 Cost: 300 gold, 5 essence   Chance 70%   On failure: ??? (rule needed)
 [Enhance]  (disabled + "need 2 more essence" when short)
```

### 2.14 Farm / kitchen: cooking and potions (PLANNED, BLOCKED: no recipes or rules yet)
```
 Recipes list | selected recipe: ingredients have/need, result, effect (+HP regen 60 s)
 Farm plots: [herb 2/3 grown 4:10] [empty: plant]                 [Cook x1] [x5]
```

### 2.15 Workbench crafting gear (PLANNED; repair EXISTS in the Repair tab)
```
 Blueprints | materials have/need | preview stats range | [Craft]
```

### 2.16 Shop (PLANNED, BLOCKED: the server decides purchases; currency and price design not started)
```
 Tabs: Hair | Hair color | Eyes | ...      [doll preview wearing the item]   price  [Buy]
```

### 2.17 Co-op room: invite into my camp (PLANNED for phase 3, BLOCKED on online/server design)
```
 My camp - party 2/4:  [me (host)] [Mira ready] [+ invite] [+ invite]
 Invite: friend list / room code [ABCD]      [Set out together]  (host only)
```

### 2.18 PvP (LOCKED by the director 2026-10-03; the hub button stays, there's no arena)
### 2.19 Guild and Guild War (phase 5, not designed)

### 2.20 Settings (PLANNED)
```
 [Controls] [Camera] [Display] [Audio] [Language]
 Controls: action | key | [rebind]   (keyboard only today; touch layout BLOCKED)
 Camera: default angle 6/7/8/9 (default 8 High)   HUD size: auto / 1.0 / 1.4 / 1.8
 Display: quality preset, resolution scale   Audio: master/music/sfx sliders
 Language: English / Thai  (needs the Thai font, see the style guide section 11)
```

## 3. Status summary

| Screen | Status | Blocked on |
|---|---|---|
| Character creator | EXISTS | - |
| Title / account | PLANNED | server/login design |
| Camp hub (village) | EXISTS (placeholder menu) | - |
| Camp window: Inventory, Look, Repair, Camp | EXISTS | - |
| Loadout | PLANNED | what can be carried (potions/food slots) |
| Journey board | PLANNED | - |
| Journey route | EXISTS | - |
| In-run HUD | EXISTS | touch layout: mobile-controls decision; portrait combat yes/no |
| Pause | PLANNED | - |
| Rest point | EXISTS | - |
| Mid-journey camp | PLANNED | `camp_banks_bag` (bank or only sort) |
| Run result (death / extract) | PLANNED (text banner today) | - |
| Armory enhancement | PLANNED | enhancement rules |
| Cooking / potions | PLANNED | recipes and rules |
| Crafting gear | PLANNED | crafting rules |
| Shop | PLANNED | server shop design |
| Co-op room | PLANNED (phase 3) | online design |
| PvP | LOCKED | director |
| Guild / Guild War | phase 5 | - |
| Settings | PLANNED | touch controls part only |
