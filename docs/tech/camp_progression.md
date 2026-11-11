# Camp progression — active cap3

Approved 2026-10-21. Main level is campfire (`profile.camp_level`). Core secondary bases are Refine=`workbench`, Upgrade=`armory`, Storage=`storage`.

1. All three core bases start at1.
2. Before fireN→N+1, all three bases must be at leastN. This is checked in shared `Camp.upgrade_camp` **before payment**, not merely UI disabling.
3. Every facility's next level is at most the fire level, also checked before payment. Its existing explicit camp requirement still applies.
4. Active new progression stops at3, selected by Boss instead of inventing prices through5.
5. Therefore fire1/core1→fire2→each core2→fire3→each core3.

`progression_facilities` and `progression_max_level` live in camp.json and are parsed into CampData. The loader rejects circular core requirements, missing steps, unknown/duplicate core IDs and a non1 starting core level. Farm is not a fire-upgrade prerequisite.

Prices: existing Refine/Storage steps retained. Upgrade gets baseline1 free, with its two pre-existing paid steps now at2 and3 (1500/6000Gold plus existing materials). No newly invented paid step or bonus. Original future camp4/5 and Storage4 data remain available solely to preserve existing saved benefits; they cannot be newly upgraded while the active cap is3.

Loading an old profile fills missing/unbuilt core bases to1, preserving all earned higher levels, inventory and balances. Legacy higher levels count as satisfying a lower gate so they do not deadlock progression. No bulk DB rewrite or refund is performed.

UI lists each core's current/required level and disables the fire upgrade while any core is behind. Secondary cards state the fire level needed next. All calls still use existing authoritative commands/revisions.

Source changes compile in the profile worker; no automated tests were added/run. **Not yet deployed**: coordinated web, profiles worker and room worker rebuild/rollout is needed so all shared logic/data copies agree. Nakama transport does not need a new RPC or allowlist.
