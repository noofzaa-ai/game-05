# New-Player Tutorial

Status: Approved plan (Boss 2026-11-15), spec v1. Owner: game-designer.

## 1. Overview
A new account starts with three raceless class cards. A spotlight guide makes the player give each card a race, explains the Alliance bonus, sends them into the first fight, then tours the hub menu. Magic and Runeborn unlock at the first wave-12 clear of the goblin journey, with a short ceremony and one guided step. Steps live in `data/tutorial/steps.json`; progress lives on the server profile.

## 2. Detailed Rules (starting state and unlock rules)

**New account** (`logic/card_deck.gd` `initial()`):
- Cards: `STARTER_SQUAD` = sword_shield, greatsword, longbow. Race = `""` (empty). `starter_races` in `data/races/rules.json` is no longer applied to new cards. Old saves keep using it (see migration).
- Squad tray: empty until a card has a race. A card with no race cannot join the squad, and FIGHT stays disabled until 3 cards have races.
- Races offered: human, viking, elf.

**Unlock rule.** Add a new pure rule `logic/unlocks.gd`. It reads `data/tutorial/unlocks.json`:
```json
{"locked": {"classes": ["magic"], "races": ["runeborn"]},
 "unlock_on": {"journey": "goblin", "wave": 12}}
```
- `is_class_unlocked(profile, id)` and `is_race_unlocked(profile, id)` both return `profile.unlocks.magic_runeborn == true`, or true when the id is not listed.
- The battle-result handler sets `unlocks.magic_runeborn = true` the first time a goblin-journey run reaches `cleared_wave >= 12`. The server does this; the client never decides it.

**Profile fields** (all new, server-side):
| Field | Type | Meaning |
|---|---|---|
| `tutorial.version` | int | steps.json version the player saw (now 1) |
| `tutorial.step` | String | id of the current step, `""` = not started, `"done"` = finished |
| `tutorial.tour_done` | bool | menu tour finished or skipped |
| `tutorial.unlock_seen` | bool | unlock ceremony shown |
| `unlocks.magic_runeborn` | bool | wave-12 gate passed |

**Migration** (on profile load, runs once and is idempotent): a profile with no `tutorial` block counts as an existing account. It gets `tutorial.step = "done"`, `tour_done = true`, `unlock_seen = true` and `unlocks.magic_runeborn = true`. Cards are left as they are: old raceless cards still get `starter_race` the way they do today. A new account is created with `tutorial.step = ""` and `unlocks.magic_runeborn = false`.

**Server enforcement** (`logic/commands.gd`):
- `card_race`: if `not is_race_unlocked` or `not is_class_unlocked(class)`, return `_error("locked")`. Setting the race to `""` is rejected (`invalid_race`), because a race can be changed but not removed.
- Squad change: return `"locked"` if a class is locked, and `"no_race"` if a card has no race.
- Fight start: reject if any squad card has no race or is locked. This is the only guard that matters against modified clients.
- New command `tutorial_step {step: String}`: the server accepts only the next id in steps.json order, or a skip of a skippable group, and saves it. `tutorial_replay` resets the tour fields only (`tour_done = false`, step = the first tour step).

## 3. Guide system
- **Overlay** `client/tutorial_overlay.gd`: a full-screen dim (black, 60%) with a rounded cut-out around the target's global rect plus 8 px padding, a bobbing arrow on the side with the most room, and a 1–2 line text box. It sits above the hub and screens and below toasts.
- **Input:** every tap is eaten except inside the cut-out, which passes through to the real control. A tap outside makes the cut-out pulse once. There is no other feedback.
- **Targets** resolve by node path or a registered key. Controls that have no `name` today must get one (list in §4). If the target is missing or hidden for 2 s, the step falls back to text-only with a "Next" button and the client logs `tutorial_target_missing`.
- **Steps in data** (`data/tutorial/steps.json`, version 1). Each step has: `id`, `group` (race | fight | tour | unlock), `screen`, `target`, `text_th`, `text_en`, `done_on` (event name plus params), `skippable`. Groups run in file order.
- The client sends `tutorial_step` when `done_on` fires. If the server refuses, the client follows the server's step.

## 4. Step list
"Node" is the real control. *(add name)* means the control exists but needs a stable `name` for targeting.

| id | screen | target node | TH | EN | done_on | skip |
|---|---|---|---|---|---|---|
| welcome | hub | none (centre box + Next) | ยินดีต้อนรับสู่ ZORX! มาจัดทีมแรกกันเถอะ | Welcome to ZORX! Let's build your first squad. | tap Next | no |
| race_ss_card | hub | `_cards["sword_shield"]` HubCard *(add name `Card_sword_shield`)* | แตะการ์ดโล่และดาบ เพื่อเลือกเผ่า | Tap the Sword & Shield card to pick its race. | race picker open (sword_shield) | no |
| race_ss_pick | race picker (`client/race_picker.gd`) | Human option *(add name `Race_human`)* | เลือกมนุษย์ แกร่งรอบด้าน | Pick Human: solid all-round. | `card_race` ok (sword_shield, human) | no |
| race_gs_card | hub | `Card_greatsword` | ต่อไป ดาบใหญ่ | Next, the Great Sword. | picker open (greatsword) | no |
| race_gs_pick | race picker | `Race_viking` | ไวกิ้ง ยิ่งเจ็บยิ่งแรง! | Viking: hits harder when hurt! | `card_race` ok (greatsword, viking) | no |
| race_lb_card | hub | `Card_longbow` | สุดท้าย ธนูยาว | Last one, the Longbow. | picker open (longbow) | no |
| race_lb_pick | race picker | `Race_elf` | เอลฟ์ ยิงไว ตาคม | Elf: quick shots, sharp eyes. | `card_race` ok (longbow, elf) | no |
| alliance | hub | squad tray *(add name `SquadTray`)* | 3 เผ่าต่างกัน = พันธมิตร! HP และ ATK +8% | 3 different races = Alliance! HP and ATK +8%. | tap Next | no |
| fight | hub | `_fight` *(add name `FightButton`)* | พร้อมแล้ว กด FIGHT เลย! | All set. Hit FIGHT! | battle scene loaded | no |
| battle_tip | battle | squad name strip *(battle HUD card names)* | ทีมสู้เองนะ แตะชื่อการ์ดให้กล้องตามตัวนั้น | Your squad fights by itself. Tap a card name to follow it. | tap any card name, or 8 s pass | no |
| tour_equip | character screen (open a card) | Equipment tab | อุปกรณ์และเกราะ ใส่ตรงนี้ | Weapons and armor go here. | tab opened | yes |
| tour_skills | character screen | Skills tab | ต้นสกิล อัปการ์ดให้เก่งขึ้น | Skill tree: make the card stronger. | tab opened | yes |
| tour_smith | hub | side menu `blacksmith` entry *(name `Menu_blacksmith`)* | ช่างตีเหล็ก ตีบวกของ | Blacksmith: upgrade your gear. | panel opened | yes |
| tour_shop | hub | `Menu_shop` | ร้านค้า ซื้อขายของ | Shop: buy and sell. | panel opened | yes |
| tour_storage | hub | `Menu_storage` | คลัง เก็บของที่ยังไม่ใช้ | Storage: keep what you aren't using. | panel opened | yes |
| tour_tailor | hub | `Menu_tailor` | ช่างตัดเสื้อ แต่งลุคการ์ด | Tailor: change your cards' look. | panel opened | yes |
| tour_settings | hub | `_settings_button` *(name `SettingsButton`)* | ตั้งค่า ดูทัวร์นี้ซ้ำได้ตรงนี้ | Settings. You can replay this tour here. | settings opened → `done` | yes |
| unlock_ceremony | hub (after wave-12 result) | none (full-screen card reveal) | ปลดล็อกแล้ว! เวทมนตร์ และ เผ่ารูนบอร์น | Unlocked: Magic and the Runeborn race! | tap Next | no |
| unlock_pick | hub → race picker | `Card_magic`, then `Race_runeborn` | ใส่รูนบอร์นให้การ์ดเวทมนตร์ | Give the Magic card the Runeborn race. | `card_race` ok (magic, runeborn) | no |

Notes:
- Each tour step closes the panel it opened before moving on, so the back button stays usable. A visible "Skip tour" button (top right) skips every remaining `tour` step.
- Quests is not in the tour (the approved list leaves it out).
- `unlock_*` runs whenever `unlocks.magic_runeborn` is true and `unlock_seen` is false, even if the tour was skipped.

## 5. Locked class in the hub
The Magic card shows in the card row in its normal slot, greyscaled to 40% saturation, with a padlock medallion over the race badge. It shows the label "ผ่านเวฟ 12 / Clear wave 12" in place of the name ribbon. Tapping it shows a toast with the same text and nothing opens. It cannot be added to the squad. In the race picker, Runeborn shows the same way (padlock, tap → toast).

## 6. Edge cases
- **First fight lost:** the result screen sends the player back to the hub. A one-line tip ("ลองอีกครั้ง ทีมเก่งขึ้นได้ด้วยอุปกรณ์ / Try again. Gear makes the squad stronger.") points at FIGHT. The tour starts only after the player has finished one fight, win or lose. Wave 1 should be near-certain to win (see risk R1).
- **Online squad rooms:** `OnlineButton` stays hidden until `tutorial.step` is past `battle_tip`. Server-side, joining a room is rejected with `tutorial` until then. The battle tip is never shown in online rooms.
- **Refresh or quit mid-step:** the server holds the last confirmed step. On load, the client resumes at that step and reopens the needed screen. If the player quits during a picker step, the step's precondition (picker open) is re-run from the card step. Battle steps resume at `fight`, not inside a battle.
- **Race already set** (a step whose `done_on` is already true, e.g. a second device): the server auto-advances past it.
- **Phone vs desktop:** the cut-out uses the control's live global rect and recomputes on resize and orientation change. The text box goes opposite the arrow and is clamped to the safe area, at least 16 px font scaled with the hub `s`. The battle tip box sits at the top on phones so it does not cover the name strip. Taps and clicks are the same event, and there is no hover-only step.
- **Skip pressed then Settings replay:** replay resets only the tour group. Race, fight and unlock steps never replay.
- **Steps file changes later:** if `tutorial.version` is lower than the file's version, done players stay done. New steps only run when flagged `for_existing: true`.

## 7. Acceptance criteria (tests)
1. `initial()` gives 3 cards (sword_shield, greatsword, longbow), all race `""`, plus a locked magic card. A new profile has `unlocks.magic_runeborn = false` and `tutorial.step = ""`.
2. Migration: a profile without a `tutorial` block comes out with step `done`, tour done and all unlocks set, and its cards are unchanged. Running it twice changes nothing.
3. `card_race(magic, *)` and `card_race(*, runeborn)` return `locked` before unlock and `ok` after.
4. `card_race(x, "")` returns `invalid_race`. A squad or fight that includes a raceless or locked card is rejected.
5. A goblin-journey result with `cleared_wave = 12` sets the unlock. 11 does not, and another journey does not.
6. `tutorial_step` accepts only the next id. An out-of-order id is refused and the step is unchanged. Skipping the tour sets `tour_done`. `tutorial_replay` resets tour fields only.
7. `steps.json` loads and every step has all fields plus a TH and an EN text, each 60 characters or fewer. Every `target` resolves to a node in the hub, character, picker or battle scene (headless scene test).
8. Overlay: a tap outside the cut-out does not reach the button underneath, and a tap inside does.
9. Online rooms are refused before `battle_tip` is done.
10. Visual check (Godot window screenshots) at 1920×1080 and 390×844: each step shows the cut-out on the right control and the text is not clipped.
11. Playtest: a fresh player reaches the first FIGHT in under 90 s, finishes race selection with no help, and can explain the Alliance bonus afterwards.

## 8. Dependencies
- `logic/card_deck.gd`: raceless new cards (`race ""`), empty new squad, `has_race`, `gear_race`, squad rules.
- `logic/race_data.gd`: race ids, starter races (gear of raceless cards, old saves), synergy (raceless cards skipped).
- `logic/profile.gd`: `tutorial` and `unlocks` fields, old-save migration.
- `logic/commands.gd`: `card_race` / `card_squad` guards, `fight_problem`, `tutorial_step`, `tutorial_replay`.
- `logic/unlocks.gd`, `logic/tutorial.gd`, `data/tutorial/unlocks.json`, `data/tutorial/steps.json`.
- `server/profile/runner.gd`: the ALLOWED command list.
- `server/rooms/manager.gd` (fight-start and shared-room guards) and the Nakama room join (`server/names/runtime/src/rooms.ts`).
- Battle results: `logic/journey.gd` `pay_card_xp` calls `Unlocks.on_battle_result` with `cleared_wave()`.
- Client: `client/card_deck_screen.gd` (hub targets, squad tray, FIGHT), `client/race_picker.gd` (race options).

## 9. Open risks
- **R1:** the first fight must be winnable with Human/Viking/Elf at base stats. This is not measured yet; run class_sim on goblin wave 1–3 before release.
- **R2:** moving the Runeborn and Magic gate to wave 12 delays the 4th card. Check that waves 1–12 with 3 cards are not a grind (playtest time-to-wave-12).
- **R3:** the hub nodes need stable names. This is a small client change in `card_deck_screen.gd`, so coordinate it with whoever holds that file (AI_SYNC).
- **R4:** an empty-race card breaks code that assumes `race_of()` is never empty (race badge, alliance count, skill-tree race branch). Every caller needs an audit.
- **R5:** the server profile runner (`server/profile/runner.gd`) needs the new commands and the battle-result hook. Get technical-director sign-off on the profile schema before building.
