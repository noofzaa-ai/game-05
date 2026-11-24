# Class Card screen: visual direction v3 ("War-Camp Ledger")

Status: PROPOSAL for the Boss (2026-11-11). Mock-ups only; nothing is imported into `art/` and no game code changes.
Art and mocks: `art_source/ui/class_cards/v9/` (gitignored; Codex raw outputs + prompts in `v9/raw/`, scripts in `v9/tools/`).
Genre reference only: the hand-drawn, muted dark-fantasy card-game family (Slay the Spire / Darkest Dungeon). We take mood, materials and line quality; we never copy their assets, frames, fonts, layouts or logos, and their images are never sent to any tool.

## Mood in words
A goblin war-camp at night, seen from the commander's table. Torch light at the edges, dark in the middle. Everything is
made by hand from what a war band has: rough planks, black iron straps and rivets, worn leather, scorched parchment, wax
seals, torn war cloth. Ink line art with a slight hand wobble, painterly flat shading in 2-3 tones, grit and chips, no
gloss. The UI is dark and heavy so the bright little 3D chibi in each card is the brightest, cleanest thing on screen:
"a gritty frame around a bright figure", like a lit window in a dark room.

## Palette (dark, muted; saturation of large areas below ~45%)
| Role | Hex | Note |
|---|---|---|
| Ink (outlines, dark text) | `#21170F` | warm near-black, never pure black |
| Night / deep shadow | `#12161E` | background B sky, vignettes |
| Tent shadow | `#1E1A17` | background A centre |
| Dark wood | `#3A2A20` / light `#5C4330` | planks, buttons, squad tray |
| Black iron | `#2B2A2E` / edge light `#6E6A66` | rims, rivets, brackets |
| Worn leather | `#2E231D` / stitch `#8A6A4A` | panels, tray inside, card back |
| Parchment | `#C9B48A` / text-on-dark `#E6D6B0` | name plate; the main light text colour |
| Ember (selection glow, focus) | `#E0913F` | only for "this is chosen / act here" |
| War-cloth red (FIGHT) | `#8E2B22` / shade `#5E1C17` | one red action per screen |
| Ready / OK text | `#9FC18A` | always with words ("พร้อมรบ 3/3") |
| Error / not enough | `#C8584A` | always with words and an icon |
| Disabled / locked | desaturate to 15%, brightness 45% + padlock | never colour alone |
| Sword & Shield accent | `#4F7FA3` (window `#2A3D52`) | steel blue |
| Great Sword accent | `#A8403A` (window `#4A1E1C`) | crimson |
| Longbow accent | `#5E8A4E` (window `#22351F`) | forest green |
| Magic accent | `#7E64A8` (window `#2E2440`) | amethyst |

Class colour lives in three places only: the wax-seal emblem, the dim window backdrop, and the squad number. Each class
also reads in greyscale by emblem silhouette (round shield + sword / single blade down / bow + arrow / staff + crystal).

## Materials and line
- Card frame: black iron outer rim with rivets, inner frame of rough planks bound by stitched leather straps, scorched parchment name plate at the bottom, round iron socket top-left for the emblem.
- Ink line: outer silhouettes about 6 px at 2x (3 px on screen), inner detail 2-3 px, deliberately uneven (hand wobble). No perfectly straight vector edges, no thin-to-thick calligraphic gold lines.
- Shading: 2-3 flat tones plus painted texture (wood grain, scratches, rust). No airbrush gloss, no white highlight blobs, no bevel-and-emboss.
- Shadows: soft dark drop shadow under cards (ink at ~50%), torch-warm rim on the side nearest a torch.

## Type (Thai + English)
- Display (titles, card names, FIGHT): a Thai serif with some weight and character. Tested in the mock: **Taviraj SemiBold** (OFL, already in `art/fonts/`). Strong option to try next: **Charm/Charmonman** (handwritten Thai, too decorative for body) only for the FIGHT word; or **Chonburi** (OFL, chunky Thai display) if Taviraj feels too bookish.
- Body / hints / numbers: **Sarabun SemiBold/Regular** (OFL, in `art/fonts/`), more legible than Mitr at small sizes and less "app-like".
- Mitr is dropped for this direction: its round geometric shapes pull the screen back toward the rejected friendly-app look.
- Light text on dark: `#E6D6B0` with a 2-3 px ink outline; dark text only on parchment. Minimum 22 px on a 720p screen.

## Screen background (one decision, two variants)
- **A, command tent (recommended):** inside a patched canvas tent, two wall torches, crates, a torn banner; a big war table fills the lower third, so the squad tray and FIGHT button "lie on the table". Warm, cosy-grim, centre stays dark for the cards.
- **B, night camp on the island edge:** palisade walls with torches left and right, crates and barrels, a dark starry sky, the rock edge of our floating island dropping into mist, distant camp fires. Cooler; connects to the fight stages.
- Both: detail only at the edges, low contrast behind the cards. Later: torches flicker (a cheap 2-frame light pulse), a few embers drift.

## Components
- **Buttons:** wooden plank with a leather strip and two rivets (secondary: กระเป๋า / ตั้งค่า / กลับ). No pills, no gloss. Pressed = 3 px down + darker; hover = ember edge glow; disabled = desaturated + text says why.
- **FIGHT (ออกรบ!):** heavy plank with iron corner brackets, a torn red war cloth nailed across it, red wax seal with crossed axes on the left. The only red, the only large warm thing in the lower half; soft ember glow when ready. Not ready (squad < 3): cloth turns dull brown-grey, seal cracked, label underneath says "เลือกอีก N ใบ".
- **Card frame:** see materials. The window is a hand-cut opening; the class backdrop sits behind the character inside it.
- **Class emblem:** wax-seal medallion in the class colour with a pressed weapon icon; overlaps the iron socket top-left.
- **Card back:** stitched dark leather in an iron rim, big red wax seal with a goblin tusked skull over crossed spears (our camp's mark; also usable as a loading / summon reveal).
- **Selected (in squad):** card lifts ~16 px, ember glow around the whole card, squad number (1-3) top-right in parchment with an outline in the class colour. Two cues (lift + number) besides colour.
- **Locked (magic):** window desaturated and darkened (character still visible as a silhouette, so the player sees what they will get), padlock hangs from the emblem seal, name plate faded, centre text "ล็อก" + the unlock condition from data.
- **Squad tray:** a long plank tray with leather inside and three iron-clipped slots; filled slots show the bust of the picked character on its class backdrop; the label area reads "ทัพของฉัน" + "พร้อมรบ 3/3".

## What we are NOT doing (from rejected rounds)
1. No brass/gold filigree, gems or engraved "magic" ornament (round "Gilded Tarot").
2. No saturated toy cartoon: candy primaries, round soft blobs, stars, glossy highlights (round 1 "Toon Summon").
3. No pastel sky, clouds or orange pill buttons (the current screen: "a game for 5-year-olds").
4. No flat grey app UI with plain coloured tabs and bar buttons (v8).
5. No horror: no gore, no realistic skulls, no photoreal metal. Grim but warm, never scary.

## Known open points (honest)
- The cards on screen are dark and heavy; at phone size the frame takes about 25% of each card. If it feels too heavy, the frame can be thinned in the next round (one Codex call).
- The lock reason "ผ่านด่าน 5 เพื่อปลด" in the mock is placeholder text: the unlock rule for Magic is not built yet (`logic/card_deck.gd` says magic unlocks "after a few quests"); the real text must come from data.
- The FIGHT not-ready state, button pressed/hover states and the editor screen are not drawn yet (next round, after a yes).
- Raw Codex images still have chroma-key fringes in a few places (squad tray corners); acceptable for review, needs clean-up before import.
- Chibi characters are in their base white outfit (current profile); with real outfits the contrast against the dark windows will be even stronger.
