# PO defaults (decided without waiting, Boss 2026-11-12)

Boss rule: when a question comes up, the PO picks the recommended option, notes it here, and the Boss can change it later.
Format: date | topic | choice | why | how to change.

- 2026-11-12 | Shield main stat | DEF | Sword & Shield is the tank class | `data/items/rules.json` slot `offhand` main_stat
- 2026-11-12 | Great Sword balance | keep survivability self-buffs (fortify/regen), not more damage | balance team measured: more power/stun/speed did not help; solo now 77.5% = Sword & Shield | `data/combat/weapons.json` greatsword entry
- 2026-11-12 | Destroyed shield look | show the class's default shield, same as an empty slot | keeps the class silhouette | `client/characters/studio05_character_model.gd`
- 2026-11-12 | Card-less gear commands | default to the Sword & Shield card | keeps old clients/tests working | `logic/commands.gd`
- 2026-11-12 | Shop / Tailor rules | reuse the existing shop and fashion rules; fashion is counted (1 copy = 1 card) | Boss rule for fashion; shop unchanged | `logic/shop.gd`, `logic/mall.gd`
- 2026-11-12 | Quests / Relics menus | keep "Coming soon" | quests have no rules yet; relics kept but not developed (Boss) | hub side menu
- 2026-11-12 | Magic card lock | stays pickable until a quest/unlock rule exists | no unlock rule yet | `client/card_deck_screen.gd` locked_classes
- 2026-11-12 | Drop model in wave mode | keep per-kill drops (GDD says per-wave rewards) | code and tuning already use per-kill | `design/gdd/drops-and-rewards.md` 3.1
- 2026-11-12 | Run bag size | 12 -> 16 slots (`data/camp/camp.json` run_slots) | the squad dropped ~12.3 items/run but a full 12-slot bag lost 3.8 of them; 16 keeps them without other balance changes | `data/camp/camp.json`
- 2026-11-12 | Duo difficulty | wave_power_by_squad[1] 1.26 -> 1.0 (duo was winning only 25% vs squad 80%) | not re-measured yet; tune by sim | `data/journeys/goblin_waves.json`
- 2026-11-12 | Online wave chest | not scaled by squad size yet (server/rooms/room.gd) | online rooms still use the old one-profile model (plan step 7) | `server/rooms/room.gd` _open_goblin_chest -> journey.treasure_drop()
- 2026-11-12 | Double-tap a gear piece | equips/unequips at once (no confirm) | spec section 4, fast on phones | `client/card_character_screen.gd`
- 2026-11-12 | Empty equipment slot look | slot name only (as the mock) | approved mock | `client/card_character_screen.gd`
- 2026-11-12 | Starter outfit of Great Sword / Longbow / Magic cards | class armor (not "silver") | the new Studio class armor is the class look; silver looks bare | `logic/card_deck.gd` STARTERS
- 2026-11-12 | Visible weapon | follows the class armor's weapon, not the equipped item | every catalog weapon is still a blade; showing it would put a sword on the archer/mage | `client/characters/studio05_character_model.gd`
- 2026-11-12 | Iris style option on cards | add it (7 Studio styles) | Studio parity rule: keep source options | `logic/card_deck.gd` + Tailor
- 2026-11-12 | Card makeup "none" | maps to the Studio's natural / no-makeup set | Studio parity | `client/characters/studio05_character_model.gd`
- 2026-11-12 | Trinkets in the shop | none until trinket items exist in the catalog (no art yet) | avoid placeholder items | `data/items/shop.json`
- 2026-11-12 | Shop prices | flat 1000 gold at tier 1 (existing `logic/shop.gd` rule) | unchanged rule; tune later | `data/items/shop.json`, `logic/shop.gd`
- 2026-11-13 | Card scene depth (Boss: make the card scene have depth) | painted 3-layer parallax per class (far / mid / near foreground in front of the feet) + floor shadow and rim light on the character | cheap on web, matches the painted ruins hub; a 3D diorama per card would cost 4 extra scenes on phones | `art/ui/class_cards/`, `client/card_deck_screen.gd`, `client/card_portrait.gd`
- 2026-11-13 | Great Sword / Longbow with hair F animation speed | use the class clip speed (old files played 2.5x slower, likely a 24 fps export mistake) | attack timing marks fit the class speed | `tools/characters/split_studio05_hair.py`, docs/tech/studio_v20261111_inventory.md section 7
- 2026-11-13 | Class armor / Hair G texture size on desktop | 1024 everywhere (Godot import settings are not per-platform) | no visible difference measured (<0.2/255 mean), simpler build | `art/characters/studio05/v1111/**/*.import` size_limit
- 2026-11-13 | Boss answer "start with 3 races" read as: the 3-card starter squad has 3 different races (Alliance on day one); all 4 races exist from the start | matches the recommended default the Boss said yes to | design/gdd/races-and-classes.md
- 2026-11-13 | Who fires race ultimates | fully automatic by the auto-pilot | the game is an auto-battler; the Boss ruled players do not press skills | design/gdd/races-and-classes.md 3.10
- 2026-11-13 | Elf Magic ultimate revives downed allies | yes, 35% HP, once per ally per wave | gives Elf its "squad that will not stay down" identity | design/gdd/races-and-classes.md
- 2026-11-13 | Class branch reset price | 50 gold per refunded point (~950 per full branch); race branch reset stays free | keeps class choices meaningful | design/gdd/skill-tree.md
- 2026-11-13 | Max-level card tree coverage | 26 of 35 points (~74%), both capstones never fit together | forces a build choice | design/gdd/skill-tree.md
- 2026-11-13 | Old saves with the old skill tree | each old tree point becomes a card level on that card; gem choices dropped, gem gold refunded | players keep their progress | design/gdd/skill-tree.md
- 2026-11-13 | Difficulty retune after races | wait: retune `wave_power_by_squad` once after phase 4 features and race ultimates land (squad wins 100% with races in the meantime) | avoids tuning twice | design/gdd/races-and-classes.md 4.5
- 2026-11-13 | 5 extra ultimate data fields not in the GDD (last_status, pick nearest/spread, burst.target, zone first_only, use `and`) | keep them and add to GDD 3.6 | 5 of 16 ultimates cannot be written without them | design/gdd/races-and-classes.md 3.6
- 2026-11-13 | Card XP table vs formula | code follows the formula 100 x L^1.2 (GDD table lv15/24 off by 2) | formula is the source | design/gdd/skill-tree.md 4.2

- 2026-11-13 | Skill tree one-off node rules | `mechanic` ids (one line each in data/skill_tree/rules.json; unknown id = load error); small GDD 3.5 additions (`allies_in_radius`, `discharge_add`, heal `per_target`/`cap_max_hp`, skill_refresh `others`); block key `skill_tree` | keeps the vocabulary small, data honest | design/gdd/skill-tree.md 3.5
- 2026-11-13 | Viking Unbowed Roar order / default ultimate | GDD action order (Unbowed +30% ATK before the burst, 60% HP example = 208% base ATK); default "Battle Fury" placeholder | GDD order is the source | design/gdd/races-and-classes.md
- 2026-11-13 | Skill tree commands | four commands (tree_learn, tree_save, tree_reset_class, tree_reset_race) instead of one skill_tree{action} | simpler per-command field checks, same validation | design/gdd/skill-tree.md 5
- 2026-11-13 | Skill tree chunk 4 leftovers (37 mechanic nodes, reflect/death_save, missing events, pilot_mod, CONTROL_IMMUNE, heal per_target) | wire after the 16 class-skill redesign lands; do chunk 5 (old-save migration) now | many nodes hook the old skills; avoids doing them twice | design/gdd/skill-tree.md, design/gdd/class-skills.md
