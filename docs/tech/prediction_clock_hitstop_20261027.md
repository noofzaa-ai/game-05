# Prediction clock and melee contact pause

Target: movement rubber-banding, particularly after incoming hits. Not an FPS acceptance claim.

The controls accumulator schedules fixed 1/60 simulation steps at 0.95–1.05 rate, using target minus latest authoritative snapshot tick consistently with desired RTT-based lead. No tick ID skips. One-shot actions queue across a zero-step callback and fire once; extra steps use held controls. The first valid RTT seeds the future horizon once; subsequent rebases and matching snapshots do not refill that floor. A world-clock overtake explicitly reanchors, retaining monotonic IDs. B/C diagnostic local simulation bypasses this scheduler.

Confirmed incoming hit events allow presentation-only correction under3m (decay40ms:95%settled120ms). Non-hit correction limit remains1m. Actual body/state/hitstun applies immediately; downed/dead/eliminated still snap. No hitstun gameplay tuning.

Reproduced outgoing melee contact discrepancy: at authority hit tick3 hitstop3 vs prediction0; next tick predicted move_frame4.0879858 vs authority3.06598935 at ATKSPD2.199645. Predict only attacker hitstop/once-per-target IDs using the same hitbox/footprint/invulnerability tests. No target mutation, damage, RNG, VFX, rewards or network side effects. A moving target or hidden skill filter can still invalidate the speculative contact; authority restores it. This is not proof every historical move_frame discrepancy has this cause.

Native correctness contracts: scheduler ±5%/queuededge once; actual Room queue300msRTT+jitter0reverse/0missing/0tickIDregression; RTTdrop300→163 desired21→13,0missing; 2.4m confirmed incominghit blends whiledeathsnaps; outgoingmelee60tick frameparity/targetHPunchanged;5weaponsx240inputparity;history/reuse/A-B-C regression. These are correctness checks, not actual Web gameplay acceptance.

OPEN: browser305msstall cause is not established by server arrival batching alone. Epoch first-input barrier is not changed; world timers must not freeze. App RTT includes scheduling; not pure network RTT. Actual Web movement/monster acceptance pending.
