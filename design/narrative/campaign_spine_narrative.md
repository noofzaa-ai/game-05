# ZORX Campaign Spine (narrative proposal)

Status: DRAFT proposal from narrative-director, 2026-11-16. Canon level: Locked rules are Established. Everything else is Provisional. For PO to merge with the game-designer and combat-designer answers. None of this is approved, and no code or data has changed.
Built on: `story-refinement-review.md` (Boss decisions 2026-11-15/16), `design/gdd/tutorial.md`, `design/gdd/races-and-classes.md`, `data/journeys/goblin_waves.json`, `data/journeys/ink_road.json`, `data/maps/`, `docs/ui/world_map.md`.
Names in quotes ("the Marshal", "the Far Gate", "the Road Compact") are placeholders.

Locked rules this spine keeps (not reopened):
- A card holds the warrior's soul and class craft: identity, memories, skill. Race and body are the summoned form. The player picks it and can change it, and it is always the same person. This applies only to summoned heroes. NPCs and communities have real races and cultures.
- The player is an apprentice summoner who inherited 4 cards and a route journal from the previous summoner.
- The first 3 cards answer the summons when the player picks their race in the tutorial. The first race pick also places the card in the squad when there is a free slot (logic/commands.gd).
- Magic is sealed. The Goblin Chief (wave 12) holds the journal. Winning it back breaks the seal. Magic first appears as Runeborn (Boss 2026-11-16).
- The goblin base is chapter 1, and about 10 more regions follow.

---

## A. Premise

The roads between the peoples of the world were cut years ago. Gates were barred, passes were abandoned, and towns were left to fend for themselves. A summoner once walked those roads with four warriors sealed in cards. They kept a journal of the route to "the Far Gate", the last crossing into a land no one has heard from since. That summoner is gone. You, their apprentice, now hold the four cards and the journal, but the journal has been stolen from you by goblins. Meanwhile "the Marshal" is sweeping across the land, offering every town the same deal: kneel under one banner and be protected, or be left outside it. You set out to finish the route, keep the promises you make along the way, and prove that peoples can stand together because they choose to, not because someone forces them.

**Player role, in one line they could repeat:**
> "I'm the apprentice summoner who finishes the road. My warriors walk with me because they chose to."

---

## B. Spine questions and the goal

The goal the player is always working toward: **follow the journal's route to the Far Gate and open it, so that the cut-off peoples can reach each other again.**

Every region moves the player one step along the route on the world map. The world map is the visible progress bar of the story.

Three questions the whole campaign answers, each one revealed a little in every region:

| # | Question | Who owns it | Answered in |
|---|---|---|---|
| Q1 | **Why were the roads closed, and should they be opened?** | The world | Partial in R2-R5, twist in R6, full in R11 |
| Q2 | **Who was my predecessor, and who are the souls in my cards?** | The player and the squad | Hints in R1, R3 and R8, reveal in R6 and R10 |
| Q3 | **Can people be kept safe together without one ruler?** | The Marshal and the player | Asked in R1, tested in R6-R7, answered in R10-R11 |

How the four Boss questions map onto the structure:

1. **Why do I play?** Someone is waiting at the end of every chapter, and the road on the map gets longer each time you win. Small promises (medicine, a bridge, a letter) add up to the big one, the Far Gate.
2. **What is the mission?** Finish the journal's route. Each region is one page of the journal with one local promise.
3. **What is my role?** You are a summoner, not a soldier and not a ruler. You build the squad, keep the promises, and choose who walks with you. The fight is automatic because the warriors are real people acting on their own. Your job is the decisions you make before the fight.
4. **How do the cards and races connect?** Cards are people (soul and craft). Race is the form they take for you. The communities you meet are real races with real histories. Wearing an Elf form does not win Elf trust. Earning that trust is the story of a region. A mixed squad mirrors the alliance you build on the map. The Marshal's cards are forced to serve, so the difference between hero and villain is consent, not diversity.

---

## C. Region arc (11 regions)

Why this order differs from the earlier pharaoh, forest, snow, capital draft: that order is driven by biome. This order is driven by **what the player learns**. The early regions are small promises, the middle turns the mission on its head, and the late regions answer the questions. The biomes are placed so that existing content comes early (goblin, mummy, ink_road maps) and new art comes later.

Reuse key: **[READY]** playable now. **[PREVIEW]** exists for the test account only. **[DATA]** journey or map data exists but is not opened in the hub. **[NEW]** needs new maps and enemies.

| # | Region | Local promise | Conflict | Gain toward the goal | How the stakes rise / what the "why" becomes |
|---|---|---|---|---|---|
| 1 | **Goblin Base** (the raided depot) [READY: goblin_waves, goblin_base_* maps] | Bring back the stolen medicine for the waystation. | Goblins raided the depot, and the Chief took your predecessor's journal too. The Marshal's patrol refused to help because the waystation is not sworn to him. | **Card:** Magic answers once the seal breaks, in Runeborn form. **Route:** the journal is back, and its first page points down the old road. **Truth:** a fresh letter in the loot says that people on the other side are still alive. | The why goes from "get our stuff back" to "people beyond the closed road are alive, so why is it still closed?" |
| 2 | **Sunward Valley** (Human farm towns) [DATA: sunward_valley map, ink_road journey structure] | Clear the bandits off the harvest road so the towns can trade. | The Marshal's envoy offers protection in exchange for oaths and grain. Half the town wants to sign. The bandits are hungry deserters, not monsters. | **Ally:** the market town lends a supply line. **Route:** the valley road is open. **Truth:** the journal's notes show the roads were closed on purpose, by people. | The Marshal is now a visible choice the towns face, not a rumour. Q3 is asked out loud. |
| 3 | **The Orange Canyon** (tomb of the Road Compact) [PREVIEW: mummy_arena_a/b/c, mummy_ascent] | Let the awakened tomb guardians rest again so the canyon pass is safe. | The guardians were set to protect the graves of the old "Road Compact", the alliance that once kept the roads. Something disturbed them: the Marshal's diggers looking for old cards. | **Truth:** the Compact used summoners, and your predecessor came through here and had the Magic card sealed in rune-script. That is why Magic first appeared as Runeborn. **Route:** the canyon pass is open. | Q2 opens: your predecessor was hiding something, and the Marshal is hunting cards. |
| 4 | **Ink Garden** (Elf forest holds) [DATA: ink_garden map] | Escort the Elf healers' wounded back through the forest. | The Elves closed their borders after the Compact failed. They distrust summoners because "cards are people kept in paper". Changing your squad's form to Elf earns nothing here, only actions do. | **Ally:** the Elf healers will treat travellers on the road. **Truth:** the cards were made by consent, a warrior's pact, but the Elves say not all of them were. | The theme of consent is set up. The player's squad talking and choosing contrasts with the forced cards they will meet later. |
| 5 | **Shrine Wall** (the first barred gate) [DATA: shrine_wall map] | Open the first barred waygate, which the journal's route goes through. | The gate keepers, monks of mixed races, swore to keep it shut until the summoner returned. You are the summoner now. Opening it is the player's first big, irreversible act. | **Route:** the first gate is open, and caravans start moving again. **Truth:** the journal's handwriting changes here. Your predecessor barred this gate. | The player is proud of the result, the road on the map visibly grows, and it sets up the fall. |
| 6 | **Orc Heartland** (centre of the world map) [DATA: central Orc region in world_map.md, ink_road content IDs] | Defend the Orc clan camps from the army marching through. | **Midpoint twist:** the Marshal's army came through the gate you opened. Your predecessor barred the gates to stop the Marshal, who was their partner in the Compact. Your mission helped the enemy. | **Truth (big):** your predecessor and the Marshal built the Road Compact together and split over force versus consent. **Ally:** an Orc clan that fights beside you, because you came back to take responsibility. | The why flips. It is no longer "open the road". It becomes "open it **and** make it safe without one ruler". Q1 and Q3 merge. |
| 7 | **The Fjords** (Viking holds, snow) [NEW: snow maps] | Hold the fjord crossing so refugees from the Marshal's march can get through. | The Vikings will take the refugees in only if the summoner's squad holds the crossing for the night. The Marshal sends a letter offering you a commission: "join, and your road will be guarded forever". | **Ally:** the Viking holds will guard the northern road themselves. **Choice beat:** you refuse the commission (as text in the pre-fight brief, no branching needed). | The Marshal now treats you as a person, and as a rival. The cost of the voluntary route is real: refugees, a night siege. |
| 8 | **The Rune Archive** (Runeborn scribe city) [NEW] | Recover the archive records before the Marshal's scribes burn them. | Runeborn scribes argue about whether to give the Marshal the sealing craft. The Marshal wants it to bind cards without consent. | **Truth:** how seals work. A seal shuts a card so that no other summoner can call it. Your Magic hero was sealed so the Marshal could never bind them. **Form:** if a 5th race form is ever added as data, it could unlock here (scope flag, see notes). | Q2 deepens. Your Magic hero is the one soul the Marshal wanted most. The why gets personal for the squad. |
| 9 | **Brush Ring** (the Marshal's proving ground) [DATA: brush_ring map] | Free the prisoners held at the Marshal's training ring. | First fight against the Marshal's **bound cards**: summoned heroes in forms the Marshal picked, silent and obeying. Same classes as yours, no voice. | **Ally:** freed prisoners from every region carry word that the summoner keeps promises. **Truth:** bound heroes are not evil. They cannot refuse. | Ludonarrative peak: your squad speaks before the fight, theirs does not. The difference between hero and villain is consent, shown through play. |
| 10 | **The Marshal's Citadel** (the capital) [NEW] | Break the Marshal's hold on the capital's gate. | The Marshal faces you. His motive is laid out in full (section D). The allies from R2-R9 each hold one road so his army cannot surround you. | **Truth:** the reveal about your predecessor (section D). **Route:** the last road to the Far Gate. | Q3 is answered: the alliance you built is doing what the Marshal said only force could do. |
| 11 | **The Far Gate** (the final crossing) [NEW] | Open the Far Gate and carry the first letter across. | The Marshal's last stand at the gate, or his bound cards turned loose (combat team decides the format). The final beat is opening, not conquering. | **Goal complete:** the route journal is finished. **Truth:** who wrote the letter from the other side (section D). | The first promise (R1's letter) and the last one meet. |

Content reuse summary: R1 is ready now. R3 is in preview. R2, R4, R5, R6 and R9 can reuse ink_road data and maps (sunward_valley, ink_garden, shrine_wall, brush_ring, Orc central region). R7, R8, R10 and R11 need new environment content. The mode for each region (12 waves, node journey, or other) is the game and combat designers' call. The 12-wave format is not a rule of the world.

**Delivery per region (text only, existing screens):**

| Screen | What it carries | Length |
|---|---|---|
| Before FIGHT (`card_deck_screen.gd`, label above FIGHT) | Region name, the local promise, and one squad line spoken by a card actually in the squad (a fallback line for solo or pair squads) | 1 brief line + 1 voice line |
| Results summary (`journey_screen.gd::_build_wave_summary`) | Win: what changed for the people, the truth learned, the next page of the journal. Loss: retreat line, no success claimed. Replay: road patrol context, no repeat of the main reward. | 3 lines max |
| Unlock ceremony (`tutorial_ceremony.gd`) | Only when a card or form really unlocks (R1 Magic; any later form is scope-dependent) | 1-2 lines |
| Hub | The journal page for the current region, plus the next destination on the world map (needs the world map or journal UI, which is new UI work) | 1 line per region |

---

## D. Antagonist: "the Marshal"

**Who:** a summoner and co-founder of the old Road Compact. His race is real and fixed (he is an NPC, not a card). Recommended: Human, so that "one rule" does not read as one race's conquest, but the art and culture owners decide.

**Motive:** when the Compact's roads were open, a plague or famine struck (exact event open). The Compact's members argued for weeks over who would send aid, and a town he loved died waiting. He concluded that a voluntary alliance is too slow to save lives, and that one command is mercy. He is not wrong about the cost. He is wrong about the cure. He does not hate any race. His army is mixed. What he cannot accept is a "no".

**How he appears across the arc:**

| Region | Appearance (text only) |
|---|---|
| R1 | Mentioned: his patrol refused to escort a waystation that is not sworn to him. |
| R2 | His envoy and banner, and the protection contract the towns debate. |
| R3 | His diggers in the tombs, hunting old cards. |
| R5 | The keepers name him as the reason the gate was barred. |
| R6 | His army comes through your gate. The midpoint twist. |
| R7 | A personal letter offering you a commission. |
| R8 | He wants the sealing craft to bind cards without consent. |
| R9 | His bound cards, a mirror of your squad with no voice. |
| R10 | Face to face, with his full motive. |
| R11 | The last stand, or his surrender at the gate. |

**The reveal about the previous summoner (recommended):** your predecessor and the Marshal built the Compact together. When the Marshal began binding towns and cards by force, your predecessor **barred the gates themselves** to stop his army. Then they sealed the Magic hero, whom the Marshal wanted most, wrote the route journal for whoever came next, and crossed the Far Gate before it was closed behind them. They are alive on the other side. **The letter in R1 was theirs.** The player has been walking toward their teacher the whole game without knowing it.

Why this reveal: it pays off the R1 letter, explains why the roads were closed (Q1), turns the midpoint twist into a moral choice instead of a trick, and gives the ending a reunion without needing a cinematic.

Alternatives for PO and Boss (section G).

---

## E. Where the seal and the cards' souls come from

Kept consistent with the locked rules. Deliberately left partly open.

**Established (can be stated in text):**
- **A card is a pact.** A warrior binds their soul and craft into a card so that they can keep walking with a summoner. Identity, memories and class skill live in the card.
- **Form is lent by the summons.** When a card is called, the summoner shapes the body. The race of that form gives its race powers in the field, but no childhood, nationality or local trust.
- **Answering is consent.** A card answers the summoner it chooses. The first 3 cards answer the apprentice at the race pick. After that, every summons is the same agreement, not a new oath.
- **A seal shuts a card** so that no other summoner can call it. The previous summoner sealed the Magic card in rune-script, learned at the canyon tombs (R3) and the archive (R8). The Chief took the journal, which holds the key. When the seal breaks, the hero first steps out in the form the seal's rune-script gives them: Runeborn. This applies to **this seal only**, not to every seal. Afterward the player can change the form freely.
- **Bound cards** (the Marshal's) are cards forced to serve without consent. They fight, but they do not speak.

**Left open (mystery for later chapters or post-game):**
- Whether a warrior in a card has died, sleeps, or lives somewhere else.
- Who first invented the pact (the Elves, the Runeborn and the Compact records disagree).
- Who the four inherited heroes were before their cards. Personal histories stay unwritten until card voice testing shows whether players want them.
- Why the Magic hero mattered so much to the Marshal. Hinted at in R8, not answered.

**True answers (for writers only, Provisional, never shown as-is):**
- The warriors in the cards are not dead. The pact takes them out of time. The ending of each pact (release) is possible but is never forced on the player's squad.
- The pact was first made by Runeborn scribes and Elf healers together, which is why each people claims it.
- The Magic hero was the Compact's own seal-scribe. With their craft, the Marshal could bind cards without consent at scale, and that is why the predecessor hid them.

---

## F. Ending

- **The world changes:** the Far Gate opens. The route journal's road is lit end to end on the world map, and the fog lifts on every region the player has visited.
- **The roads are not ruled, they are kept.** Each ally from R2-R9 holds and guards its own stretch of road. This is the new Road Compact, built by consent. That is the answer to Q3.
- **The Marshal** is defeated, not executed. He is held to answer to the communities he forced. His bound cards are released, and each chooses whether to answer another summoner or rest. (The game does not need to add those cards. The results text says they are free.)
- **The previous summoner** is met in text on the other side of the gate. They read the finished journal. The player writes the first page of a new one, which leads into post-game and future content.
- **Post-game:** replays become road patrols and keeping the Compact's roads. No first-time rescue is repeated. New regions can be added as pages of the new journal.

---

## G. Open questions for PO and Boss

1. **The reveal about the previous summoner**
   - **Alive beyond the Far Gate, and wrote the R1 letter (Recommended):** pays off chapter 1, gives a warm reunion ending, and needs no extra boss.
   - **Captured by the Marshal:** a strong personal drive from early on, but it reuses the "rescue the captured mentor" cliche that the draft avoided.
   - **The previous summoner is the Marshal:** the biggest twist, but it clashes with a predecessor who left cards to an apprentice by choice, and it muddies the consent theme.
2. **Region order:** accept this learning-driven order (R1-R11), or keep biome-driven groupings? Recommended: this order, because it fronts reusable content and puts the midpoint twist in R6.
3. **Scope flag (producer):** new card or form rewards after Magic, such as a 5th race form in R8, are **new scope**. Recommended default: no new cards. Regions reward route, allies and truths. Forms only arrive if race data is added separately.
4. **Bound-card enemies in R9-R11** need enemy squads that use player-class models. That needs feasibility checks from the combat and technical teams before it is locked.

## Contradictions check
- Locked card rule (soul in the card, form chosen by the player, NPC races real): kept. Section E adds no new rule that changes past or race on a form change.
- First 3 cards answer at the race pick, and auto-join if a slot is free: kept.
- Magic sealed, Chief holds the journal, seal breaks at the first wave-12 clear, Runeborn first: kept. The Runeborn first form is explained by this specific seal, not by a universal rule.
- No world-controlling seal system: the roads were barred physically by people (gates), not by magic.
- Not every enemy works for the Marshal: goblins (R1), bandits (R2) and tomb guardians (R3) have their own reasons.
- Online and progress: story progress per account, a loss never shows success, and replays never repeat the main reward. This matches the draft's criteria. The completion flag stays server-confirmed (PO and technical-director own this).
