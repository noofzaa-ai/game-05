# Campaign spine: combat side (regions, pressures, counters)

Canon level: **Provisional** (only the goblin base and the soul/form rule are Established by Boss).
Combat Designer, 2026-11-16. Draft for the PO to merge with the narrative director's and the game designer's input. Region names are working labels; narrative owns the real names and order.
Base: `story-refinement-review.md` (Boss locks: the card holds the hero's soul and skill, race is a summoned form the player can change; chapter 1 = goblin base, 12 waves, Chief at wave 12; about 10 more regions).
Sources read: `data/races/*.json`, `data/races/rules.json`, `data/journeys/goblin_waves.json`, `data/combat/combat.json` (enemies, moves), `data/combat/effects.json`, `logic/race_passives.gd`, `logic/enemy_ai.gd`, `design/gdd/races-and-classes.md`, `design/gdd/skill-tree.md`.
**Nothing here is measured yet.** Only the goblin base exists as playable content. Every "answer" below is read from data text, not from simulation (see section 6).

## 0. Facts that shape every region

| Fact (source) | Consequence for region design |
|---|---|
| Squad max 3, one card per class, 4 classes (`SQUAD_MAX = 3`) | Every fight already has a choice: **which class sits out**. A pressure can be answered by the bench choice as well as by races. |
| Race switch is free in the hub and refunds race/combo tree points (`skill-tree.md` 3.11) | Rethinking forms per region costs nothing, so pressures can be sharp without punishing players. The class branch stays, so the soul/skill lock matches the rules: switching the form keeps the hero's skill. |
| Enemies always target the **nearest** fighter unless taunted (`enemy_ai.gd::_decide`) | Today there is no backline pressure. A "hunts the weak" region needs a new targeting rule. |
| Enemy moves can only apply statuses to `enemy` or `self` (`effects.json` comment) | Enemies **can** self-regen or self-buff in data alone (as `brute_roar` gives itself `rage`). Enemies **cannot** heal or shield allies or project auras without new logic. |
| Enemy debuffs already in data: `wound` (healing -60%), `sunder` (DEF -40%), `weaken` (ATK -30%), `slow`, `poison` (3 stacks, ignores DEF), `burn`, `exhaust` (stamina regen -60%), `stun`, `sleep`, `shock` | Most debuff regions need only data: new enemy moves using existing statuses. |
| Shields are not healing; `wound` scales only `HEALING` (`effects.json`) | Runeborn shields are the natural answer to anti-heal. This makes Runeborn a counter, and also a dominance risk (section 5). |
| Control immunity 120 ticks after any stun, shock or sleep (`effects.json` rules) | A stun-lock answer to a boss cannot exist. Burst and interrupt answers stay fair. |
| Boss reinforcements on an HP threshold exist (`goblin_waves.json` wave 12, `waves` block) | Phased bosses for later regions are data, not code. |
| `boss_types` / `elite_types` in `rules.json` list only goblins | Every new boss/elite must be added there, or the pilot rules (longbow boss-first, `boss_near`, execute, Called Shot target) ignore it. |

## 1. Region pressures and valid answers

"Answers" cite race x class cells from `data/races/<race>.json` (P = passive, U = ultimate) and class signatures from `races-and-classes.md` 3.2. Each region lists at least two squads that should work, and they use different races and benches.

| # | Region (working label) | Enemy theme | Main pressure | Answer A | Answer B (different races/bench) | Weak choice (still not dead) |
|---|---|---|---|---|---|---|
| 1 | **Goblin Base** (exists) | goblins, archer w3, mage w5, knight w6, Chief w12 | Teaching mix: light swarm, first ranged, first `wound`/`slow`, first armor, first boss | Starter Alliance (Human S&S, Viking GS, Elf LB) | Any 3; the tuning target is the starter squad at 72-75% | None by design |
| 2 | **Tomb of the Wrapped** (mummy, preview exists) | mummies: 1.5x goblin stats, MOVESPD 32, ATKSPD 50, no retreat | **Attrition melee**: fast, steady front-line damage, no breathing room | Sustain: Elf S&S *Warden's Grove* P + *Heartwood Bastion* U (taunt + 2.5%/s grove heal), Elf Pair healing +20% | Mitigation: Runeborn S&S *Rune Aegis* P (more hits taken = faster shields), Runeborn Pair 8% shield at wave start, Human S&S *Rallying Drill* fortify | Glass back line without a tank (bench S&S) |
| 3 | **Brood Warrens** | many small, low-HP biters (8-12 per wave) | **Swarm** | Kill-fed melee: Greatsword *Cleave* signature, Viking GS *Ragnarok Whirl* U (each kill extends), Viking Trio kill-heals 4% | Area casters: Runeborn Magic *Arcane Singularity* U (4 m vortex, shields squad from damage), Human GS *Wide Arcs* P (+25% radius), Runeborn LB *Glyph Barrage* (6 spread targets) | Single-target Human LB *Called Shot* wasted on a 30-HP target |
| 4 | **Watchtower Pass** | archers and casters behind a melee screen | **Ranged chip and focus** (volleys, homing bolts, ground marks) | Outrange: Viking LB *Executioner's Volley* (12 m, chains on kill), Runeborn LB *Glyph Barrage* (12 m spread), Magic zones at 9 m cast range | Outlast: Runeborn Pair/Trio wave-start shields + Runeborn S&S *Bastion Glyph* (15% to all), Elf LB *Moonlit Arrow* heals | Two melee + tank: the screen holds them while the archers shoot |
| 5 | **Iron Warcamp** | knights and brutes: high DEF (80-90), poise 100-140, EFFECT_RES 30-40 | **Armor** | Shred: Longbow *Hunter's Mark* (sunder on first hit, any race), Human LB *Trained Eye* (skill hits sunder, +20 skill crit) and *Called Shot* (450% crit + sunder 7 s) | Skill power: Human Magic *Archmage* (+30% skill dmg, x0.85 cooldowns), Human Pair/Trio skill dmg; or Viking fury bursts (Blood Moon `fury: 2.0`) | Basic-attack builds (Runeborn LB rune shots) do too little against armor |
| 6 | **Frost Hollows** | trolls with self-`regen`, plus a shaman that heals allies | **Enemy healing** | Burst: Viking ultimates (fury x up to 2.5 at low HP), Viking LB execute (x2 below 30% HP, chain up to 3) | Focus plus interrupt: Human LB *Called Shot* on the toughest, Human GS *Masterstroke* (third arc stuns the healer's cast), Hunter's Mark focus-fire | Slow attrition (Elf Trio) cannot out-damage the regen |
| 7 | **Rot Marsh** | bog creatures with `poison` (3 stacks) and `wound` on hit | **Debuffs: DoT plus anti-heal** | Wards, not heals: Runeborn Magic *Runeweaver* (squad shield every 3 casts), Runeborn Pair/Trio wave-start shields (unaffected by wound) | Race the clock: Viking GS / Viking Magic burst; Human Magic kills before the stacks build (DoT ignores DEF, so fortify does not help) | Elf heal stack is cut 60% (weaker, still viable with Elf Trio +30%) |
| 8 | **Shade Woods** | stalkers that leap to the weakest or furthest fighter, `sleep` / `stun` on hit | **Back-line divers plus control** | Peel: S&S *peel* targeting + taunt ultimates (Human *Commander's Call*, Elf *Heartwood Bastion*, Runeborn *Bastion Glyph*), Viking S&S *Unbroken* aggro pulse | Bench a back-liner: S&S + GS + one ranged; Longbow kites. Or shield the back line: Runeborn Pair | Two fragile back-liners without a tank |
| 9 | **Giant Steps** | 1-3 giants per wave, telegraphed slams (`sunder`), war roar (`weaken`) | **Alpha strikes from few elites** | Absorb: Runeborn S&S *Bastion Glyph* (fires on `boss_telegraph`), Viking S&S *Unbroken* (25% shield below 35% HP), Elf Magic *Rebirth Bloom* (revive once per ally per wave) | Kill first: Longbow boss-first + Human *Called Shot*, Viking Magic *Blood Moon*, Human Trio cooldowns to burst between slams | Swarm builds (Whirl, Singularity need 3+ targets and often hold) |
| 10 | **Mandate Line** (antagonist's border legion) | multi-race soldiers, one **banner officer** per wave whose aura buffs all of them | **Priority target + mixed roles** | Cut the banner: Longbow boss/elite-first + Viking LB execute chain; Human *Called Shot* targets "boss or toughest" | Spread and break: Runeborn LB *Glyph Barrage* (spread + sunder), Magic area ultimates kill the escort and expose the officer | Pure sustain; the buffed legion out-trades it |
| 11 | **The Crossing** (final) | the Commander boss: phases call back the earlier pressures (swarm call, armor stance, healer guard), escorts from regions 3-10 | **Exam of all** | Alliance generalist (any 3 races, +8% HP/ATK) | Any Trio built for the phase mix (for example Runeborn Trio for shields + area, or Viking Trio for burst); the boss must be beatable by at least 3 of the 4 Trios plus Alliance | None should be dead; the target spread is the tightest here |

Order logic: 1-3 teach "one pressure at a time" with forgiving answers; 4-7 make the bench choice matter; 8-9 attack the squad's structure (back line, single big hits); 10 tests target priority as a story beat; 11 combines them.

## 2. Story reason behind each pressure (true to the mechanics)

| # | Pressure | One-line story reason the narrative can use | Mechanic it stays true to |
|---|---|---|---|
| 1 | Mixed | "The goblins raid with whatever they have: spears, bows, a hedge-mage, one armored brute." | Waves 3/5/6/12 add archer, mage, knight, Chief |
| 2 | Attrition | "The wrapped dead never tire. Outlast them: a grove that heals or runes that harden under blows." | Elf heals scale with time; Rune Aegis fills from hits taken |
| 3 | Swarm | "The brood is endless, and a Viking form only grows hungrier with every kill." | Whirl extends on kill, Berserker / Viking Trio heal on kill, Greatsword cleave bonus |
| 4 | Ranged | "The pass is watched from above. Strike from further away, or raise wards before the first arrow." | 12 m volleys and 9 m zones; wave-start shields |
| 5 | Armor | "Steel turns a blind blow. A drilled form finds the gap first, then the rest follow." | Sunder (DEF -40%) from Hunter's Mark and Trained Eye; Human skill damage |
| 6 | Healing | "Frost trolls close their wounds while you watch. End it in one breath." | Fury bursts, x2 execute below 30%, stun on Masterstroke's third arc |
| 7 | Anti-heal | "The marsh rot keeps flesh from mending. Runes do not mend flesh; they stand in front of it." | `wound` scales only HEALING; shields are not healing |
| 8 | Divers | "The shades hunt the one standing alone. Guard each other, or stand closer together." | Taunts, peel targeting; benching a back-liner |
| 9 | Alpha strikes | "A giant swings rarely but once is enough. A ward raised at the right moment, or a fallen friend brought back." | Bastion Glyph fires on `boss_telegraph`; Rebirth Bloom revives once per ally per wave |
| 10 | Priority target | "The legion fights for its banner, not for each other. Cut the banner and the line breaks." | Officer aura ends on death (new feature, section 4) |
| 11 | All | "Everything we learned on the road, and everyone we met on it." | Phases reuse earlier enemies |

Wording guard (from the story draft): a form's ability is a property of the **summoned form in battle**, not of the people of that race. "The Viking form grows stronger near death" is true. "Vikings are reckless" is lore and belongs to narrative. Story lines must not claim an effect the fight did not show (for example "the Elf saved us" after a fight with no heal event); claims about one hero's deeds need the fight's event log.

## 3. Synergy as story, checked against the antagonist

| Bonus | Rule (`rules.json`, race files) | In-world meaning (proposal) | Why it fits the soul/form lock |
|---|---|---|---|
| **Pair** (2 of one form) | Themed and moderate (e.g. Elf healing +20%, Runeborn 8% wave-start shield) | **Shared drill**: two heroes who took the same form fight in the same rhythm, so the form's technique carries across both | It is about the **form's discipline**, not blood or kinship; the player switches forms freely |
| **Trio** (3 of one form) | Strongest themed bonus (design target ~+10%), but narrow | **One tradition, fully practised**: all three chose to train one way, deep and inflexible | A choice the squad makes together; it is not imposed |
| **Alliance** (3 different forms) | Flat +8% max HP and ATK for all, no theme | **Covering each other**: different strengths that close each other's gaps | Generic on purpose: it rewards mixing, not a specific mix |

Check against the antagonist (forced unity vs voluntary alliance):
- **Risk:** if the story says "many races = good, one race = the Commander's way", it contradicts the mechanics (Trio is the strongest themed bonus) and the story draft ("not diverse good, mono-race bad"). **Do not** make Trio villainous.
- **The contrast is in how the bond behaves, not in what the squad is made of.** Ours is computed at run start and holds for the whole fight, even when a member falls. The Commander's legion (region 10) gets its bonus from an **imposed** source, the banner officer's aura: kill the officer and the bonus is gone. That is "forced unity" expressed in rules: strong, but it depends on one master.
- Corollary for the final boss: the Commander's phases should *take* bonuses from his escorts (or lose them when escorts fall), never *share* them. Our side never loses its synergy mid-fight. Mechanically true today; keep it that way.
- Engine detail to verify by test, not assumed: a downed card's allies keep the squad synergy (synergy is computed at run start per `races-and-classes.md` phase 8).

## 4. New content per region (minimal)

Code feature = new rule in `logic/` (data-driven, scheduled through PO/technical-director; none of these change the logic/client structure).

| # | New enemies (data) | Boss | New engine feature needed | New race/card |
|---|---|---|---|---|
| 1 | none | Goblin Chief (exists) | none | none |
| 2 | mummy exists; +1 "tomb warden" elite (slow, `weaken` slam) | Wrapped King: summons a mummy wave at 50% (existing `waves` block) | none (move needs a model/animation set, art cost) | none |
| 3 | brood biter (tiny, 10-15 HP), brood mother (spawns) | Brood Mother: reinforcement waves on HP thresholds | none, if "spawns" are boss `waves`; a true mid-fight summon move would be new | none |
| 4 | tower archer (longer range than goblin_archer), rune-caster (ground mark + `slow`) | Watch Captain (archer, volley + retreat) | none (reuse projectile/area moves) | none |
| 5 | iron knight, brute variant (both exist as styles: `goblin_knight`, `brute`) | Warlord: stance with DEF up that `sunder` breaks | none (`fortify` on self is data) | none |
| 6 | troll (self-`regen` move), frost shaman | Troll Matriarch: regen phase | **enemy heal/regen on allies** (action targets beyond `enemy`/`self`) | none |
| 7 | bog lurker (`poison`), rot spitter (`wound`, ranged) | Marsh Hag: `exhaust` + `wound` | none | none |
| 8 | shade stalker | Shade Huntress | **enemy targeting rule** (`lowest_hp` / `back_line`), a leap move | none |
| 9 | giant (1-3 per wave) | Old Giant (telegraphed slam, roar) | none (`brute` moves are the template); add to `boss_types` | none |
| 10 | legion soldiers (reuse styles of earlier regions in legion colours), banner officer | Legion Marshal | **enemy aura** (stat_mod on allies while alive, ends on death) | none |
| 11 | escorts reused from 3-10 | The Commander: 3 phases on HP thresholds | **phase switch** (boss swaps move set or stance at an HP threshold; extends the existing `waves` trigger) | none |

Totals: about 18 new enemy types (several are variants or re-skins), 10 new bosses, 4 small engine features (ally heal for enemies, enemy targeting rule, enemy aura, boss phase switch). **No new race or card is needed**: the 16 race x class cells already cover every pressure above with at least two answers. A 5th race or class would add test and balance load (64 race mixes become 125) without solving a pressure the current set cannot. Revisit only as post-campaign content.

Every region also needs: its own journey file (`data/journeys/<region>.json`, with its own `wave_power_by_squad`), maps, bosses and elites added to `rules.json` `boss_types` / `elite_types`, and a scripted balance test like `tests/test_auto_pilot.gd`.

## 5. Balance risks

| Risk | Where | Why | Mitigation / test to lock |
|---|---|---|---|
| **Runeborn becomes the universal answer** | 2, 4, 7, 9 | Shields answer attrition, ranged, anti-heal and alpha strikes, and `wound` does not touch them | Shield caps (30% / ultimates 50% max HP) hold; across all regions flag any race present in >50% of top-10 mixes (existing class_sim flag line) |
| **Longbow is always fielded** | 4, 5, 9, 10 | Hunter's Mark sunder, boss-first targeting and 12 m reach all live in the class | Each of these regions must have a no-Longbow answer at >= target-8 pts (Magic zones, Human skill damage, Viking fury) |
| **S&S is never benched** | all | It is the only tank; taunt ultimates fix most pressures | Accept for most regions, but region 3 (swarm) and region 6 (burst) should be winnable with S&S benched |
| **Elf Trio near-unkillable** | 2, 8 | Heal stacking + Rebirth Bloom (GDD 3.8 risk 1) | Heal cap 6% max HP/s, revive once per ally per wave, `wound` enemies appear from region 1 on |
| **Viking a trap with an Elf healer** | 3, 6 | Fury needs low HP; heals keep HP high | Region 6 answer B is Human-based, so Viking is not forced; measure Viking+Elf pairs separately |
| **Status answers blocked by resist** | 5, 6 | Armored enemies have EFFECT_RES 30-40; unverified whether race-trigger `apply_status` (Hunter's Mark, Trained Eye) rolls against it | Test before building region 5; if sunder can be resisted, armor must not stack resist this high |
| **Swarm region needs 3+ target ultimates; boss regions starve them** | 3 vs 9 | Whirl, Singularity, Blood Moon hold until 3+ enemies; on giants they may never fire | Expected and fine as a pressure, but check that no ultimate is held past `max_hold_ticks` in >20% of full-gauge moments for an *intended* answer |
| **Taunt on bosses** | 9, 11 | All 4 S&S ultimates taunt; GDD caps boss-taunted time at ~60% | Keep the GDD check per boss |
| **One "solved" squad per region** | any | Free switching makes a net-guide answer trivial to copy | Per-region test lock: >= 2 squads differing in bench **and** race mix within the 72-80% band; no mix > mean + 8 pts; off-answer squads >= 55% (pressure felt, not a wall) |
| **Final boss favours generalists only** | 11 | Phases that rotate every pressure punish Trios | Lock: Alliance and at least 3 of 4 Trios within ±5 pts |
| **Solo/duo players** | all | `wave_power_by_squad` was tuned per squad size for goblins only | Each region keeps its own per-size curve; regions 8/9 (back line, alpha strikes) will be harshest for solos |

## 6. Measurement status and what to measure

- **Unmeasured:** every answer and risk above is read from data text. No race-mix simulation was run for any region, because only the goblin journey exists.
- **Goblin base today:** the squad of 3 was re-measured at 73% (`goblin_waves.json` `_tuning_waves_2026_11_13c`). No per-race-mix numbers exist yet (class_sim `only=races` is specified in GDD 3.8 but no results are recorded).
- **Before region 2 ships:** run class_sim `only=races` (64 mixes x 4 benches) on that region's journey and confirm the two listed answers sit in the band. Use the same procedure for each later region.

## 7. Decisions for the Boss (via PO)

1. **Region count and order:** A. Use the 11-region spine above as the working order (recommended; it escalates one pressure at a time). B. Narrative picks the order, and combat re-fits the pressures to it. C. Fewer regions (6-7), each with two pressures.
2. **New races/cards for the campaign:** A. None; the campaign uses the 16 existing cells (recommended). B. Plan one new race as a mid-campaign reward. C. Plan a 5th class card.
3. **The antagonist's legion mechanic:** A. The banner officer's aura ends when he dies ("forced unity is fragile"; recommended, 1 engine feature). B. A plain mixed army with no special mechanic (no code; the theme lives only in text).
4. **How strict a region's pressure is:** A. Off-answer squads still win >= 55% (recommended). B. Harder walls (off-answer < 40%): stronger "rethink" pull, but players stall.
