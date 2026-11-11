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

