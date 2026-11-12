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

