# Attack moves: animation spec (chibi, all weapons)

Status: SPEC for the animator (2026-10-09). No code/data changed. Numbers are placeholders until the Boss plays.

## 0. Ground rules (apply to every clip)

**Timing contract.** The game runs at 60 ticks/s. `client/animation_set.gd` time-warps each attack clip in
three pieces: `0..windup_end` plays over the move's *startup*, `windup_end..strike_end` over *active*,
`strike_end..end` over *recovery*. So:
- Put the anticipation peak exactly at `windup_end` and the end of the hitting arc at `strike_end`.
- Author each clip at the real frame counts below (stretch ~1.0), so it looks right at base speed.
- The weapon must be **inside the hit box only between the two marks**: the arc crosses the box during active.

Frames below = `startup/active/recovery` in ticks after the weapon's `speed` scale (computed from
`data/combat/weapons.json`; active is not scaled).

| move | fists | blade | dagger | spear | hammer |
|---|---|---|---|---|---|
| light_1 | 4/3/10 | 4/3/11 | 3/3/8 | 5/3/12 | 6/3/15 |
| light_2 | 4/3/10 | 4/3/11 | 3/3/8 | 5/3/12 | 6/3/15 |
| light_3 | 5/3/16 | 6/3/18 | 4/3/12 | 6/3/18 | 8/3/24 |
| heavy | 12/4/22 | 13/4/24 | 9/4/17 | 14/4/25 | 18/4/33 |
| air | 3/4/8 | 3/4/9 | 2/4/6 | 3/4/9 | 4/4/12 |
| air_heavy | 8/10/14 | 9/10/15 | 6/10/10 | 9/10/16 | 12/10/21 |
| run_light | 6/6/18 | 7/6/20 | 4/6/14 | 7/6/21 | 9/6/27 |
| run_heavy | 10/7/28 | 11/7/31 | 8/7/21 | 12/7/32 | 15/7/42 |
| special | 8/4/20 | 9/4/22 | 6/4/15 | 9/4/23 | 12/4/30 |
| ultimate | 14/18/28 | 62/54/76 (Inferno pack, done) | 10/18/21 | 16/18/32 | 21/18/42 |

**Hit box shape (what the arc must cover)**, forward center / length / width in m, height band 0.4-1.4 m:
fists 0.9/1.3/1.4 · blade 1.3/1.9/1.75 · dagger 0.63/0.9/1.26 · spear 1.7/2.5/0.98 (long + narrow =
thrust) · hammer 0.95/1.4/2.1 (short + wide = sweep/slam). `air_heavy` box drops to the floor
(center 0.2 m, 1.9 m tall): a downward move. Ultimate = 2 body lengths straight ahead, never around.

**Look rules (Boss).** Gender-neutral: wide grounded base, knees bent, power from hips and shoulders, elbows
out; no hip sway, no wrist flourishes, no pointed toes, no head tilts. No clipping through outfits: keep
upper arms off the chest/cape during wraps (lift the elbow instead). One pose per beat, big readable
silhouette changes; no micro detail.

**Steep top-down camera.** Horizontal arcs read best. Vertical chops/thrusts read poorly from above, so
every vertical move must add (a) a forward step + torso lean, (b) a clear lateral wind-up (weapon goes
out to the side or behind the head, not straight up), (c) a VFX trail / ground decal at contact.

**Short startups (2-4 ticks).** At 3 ticks the anticipation is ~50 ms: it is a 1-key "set", not a wind-up.
Real anticipation for combo hits lives in the *previous* move's recovery (light_1 recovery ends in
light_2's start pose; see reuse in section 7).

**Each clip ends** back in that weapon's idle stance (low carry), so recovery blends cleanly.

## 1. Blade (one-handed, right hand). Feel: fast, clean, wide arcs; a duelist. PROTOTYPE FIRST

| move | key poses (A anticipation / S strike / F follow-through / R recover) | arc | body |
|---|---|---|---|
| light_1 | A: blade cocked back-right at hip height, torso turned right. S: flat horizontal cut right-to-left. F: blade ends left of the body, wrist rolled over. R: idle. | horizontal R->L, waist height, ~150 deg | hips lead the shoulders by ~2 ticks, small front-foot slide |
| light_2 | A = light_1 F (blade already left). S: rising backhand diagonal left-low to right-high. F: blade high right, elbow up. | diagonal L-low -> R-high | reverse twist, back foot pivots |
| light_3 | A: step in, blade raised high behind right shoulder, chest open. S: big descending diagonal cut right-high -> left-low through the box. F: blade low left, knees deep, torso bent forward. R: rise to idle. | diagonal R-high -> L-low, full 180 deg | lunge step forward (finisher), long recovery to show weight |
| heavy | A: deep crouch, blade drawn back along the right side, tip trailing, left hand forward as guide. S: wide horizontal spin-free cleave R->L at chest height ending in an upward flick (launch 9). F: blade overhead left, body extended up on toes. R: drop to stance. | horizontal sweep turning into an up-hook | full torso twist, step forward, rise on contact (sells the launch) |
| air | A: blade high right. S: quick diagonal downward cut. F: blade low left. | diagonal down R->L | knees tucked |
| air_heavy | A: both knees up, blade reversed over the head (two hands allowed only as a pose cue; left hand on pommel). S: plunge straight down, tip leading, body following (dive). F: blade stuck at the floor, one knee down. R: pull out, stand. | vertical down | whole-body drop; land in a kneel |
| run_light | A: (from run) blade swung back low, shoulder dropped. S: shoulder-led forward slash/shove (big knockback 16): blade horizontal R->L while left shoulder charges. F: slide to a stop, blade left. | horizontal, forward-moving | run momentum, lean forward, sliding stop |
| run_heavy | A: brake with the front foot, blade low behind. S: rising launcher cut low-front -> high (launch 8). F: blade overhead, body up on the toes. | vertical up (rising) | plant + rising whole body |
| special (Ember Slash) | A: sheath-like draw pose, blade low back-right, crouched (invuln 0-8 covers it). S: fast flat iai cut R->L. F: hold the extended pose 4-6 ticks (fire trail), then sheath motion back to carry. | horizontal | lunge step; pause in follow-through is the "cool" beat |
| ultimate | done (model team Inferno clip, 3.2 s). | forward | - |

Hooks: L1/L2 thin white trails; L3 brighter trail + hit-stop 5 + light shake; heavy hit-stop 7 + upward
spark; air_heavy ground crack decal + shake on landing; special ember trail (burn) and a 2-frame flash.

## 2. Fists. Feel: snappy boxer, short fast jabs, a stunning finisher; all body, no weapon

| move | key poses | arc | body |
|---|---|---|---|
| light_1 | A: guard up, fists at the chin. S: straight left jab. F: snap back to guard. | straight forward, left | shoulder turn only, feet still |
| light_2 | A = guard. S: straight right cross. F: right shoulder forward, back heel up. | straight forward, right | hip turn, back foot pivot |
| light_3 | A: dip and load the left hip. S: left hook, elbow horizontal. F: torso wrapped right. | horizontal L->R hook | full hip twist + small step |
| heavy | A: deep crouch, right fist dropped by the hip. S: rising uppercut-palm (launch). F: arm extended up, rising on toes. | vertical up, front | legs drive up |
| air | S: downward hammer-fist / knee. | downward front | knees tucked |
| air_heavy | A: both fists over the head. S: drop and smash both fists on the floor (stun). F: crouched, fists on the floor. | vertical down | body drops with the fists |
| run_light | S: running shoulder charge (long stagger), arms tucked. | forward | lead shoulder, lean |
| run_heavy | A: plant. S: big rising uppercut (pop up). F: overextended upward. | vertical up | same pose family as heavy, bigger |
| special (Raging Fist) | A: arms crossed, pull-in (rage buff). S: double-palm push forward. F: hold. | forward | wide stance, step |
| ultimate (Heaven Palm) | A: long charge, palm drawn back by the hip. S: forward palm strike, energy wave grows 2 body lengths ahead. F: hold the extended palm. | forward | deep front stance |

Hooks: jab/cross tiny shake 0; hook hit-stop 5; uppercuts vertical spark + camera nudge up; slam ring decal.

## 3. Dagger (pair, reverse grip). Feel: fastest, close and twisting; slashing flurries, stabs from the side

| move | key poses | arc | body |
|---|---|---|---|
| light_1 | A: right dagger crossed in front of the chest. S: outward backhand slash right hand L->R. F: right arm open. | horizontal L->R (right hand) | shoulder snap, feet still |
| light_2 | mirror of light_1 with the left hand (R->L). | horizontal R->L (left hand) | mirror |
| light_3 | A: both arms crossed in an X at the chest, crouch. S: both blades scissor outward. F: arms wide, low crouch. | double horizontal, outward | hop forward small |
| heavy | A: spin-load (back turned 90 deg, NOT full turn). S: spinning reverse-grip slash back to front, then rising stab. F: crouched, blade up. | horizontal into up-stab | quick pivot on the front foot |
| air | S: both daggers stab downward. | down front | knees tucked |
| air_heavy | A: tuck, both blades raised behind the head. S: dive with both blades down (big damage, low push). F: land crouched, blades in the floor. | vertical down | whole-body drop |
| run_light | S: low sliding slash through the target (right hand), body passes forward. | horizontal, forward-moving | very low lean |
| run_heavy | A: plant. S: twin upward stab, both blades rising. F: up on toes. | vertical up | rising |
| special (Venom Dance) | 3 fast alternating slashes inside the active window (R, L, R) as one clip; F: low crouch, blades crossed. | alternating horizontal | small steps in place |
| ultimate (Shadow Hunt) | A: low crouch, blades back. S: forward dash-through with a flurry trail 2 body lengths ahead. F: finish pose behind the start point is NOT allowed (stay facing forward, slide to a stop). | forward | lunge |

Hooks: poison-green trail on light_3/special; hit-stop small (3); air_heavy short shake only.

## 4. Spear. Feel: long, straight, precise thrusts; keeps the enemy at bay; one big sweep

Two-hand hold for attacks: right hand rear on the shaft, left hand forward. Arcs are mostly **thrusts**
(the box is long and narrow), so readability comes from the arm/shaft extension and a step, plus a
straight thrust trail.

| move | key poses | arc | body |
|---|---|---|---|
| light_1 | A: shaft pulled back along the right side, tip at chest height forward. S: straight thrust. F: arms fully extended. R: pull back. | straight forward | front-foot step, hips square |
| light_2 | same as light_1, higher thrust (head height) with a slight twist. | straight forward | same, smaller step |
| light_3 | A: shaft back, deep load. S: long lunge thrust, front knee deep. F: hold the extension. | straight forward, max reach | full lunge (finisher) |
| heavy | A: shaft swung back over the right shoulder, body turned right. S: wide horizontal sweep R->L then the tip hooks up (launch). F: shaft high left. | horizontal sweep -> up | big hip twist; the one wide move |
| air | S: downward thrust angled forward. | forward-down | tucked |
| air_heavy | A: shaft vertical, tip down, raised. S: drop and impale the floor in front. F: kneel on the shaft. | vertical down | body drops |
| run_light | S: running charge thrust, shaft locked by the hip (slow effect). | straight forward | lean in, slide stop |
| run_heavy | A: plant, tip low. S: rising hook-lift (launch 14): tip goes from floor-front to over the head. F: shaft vertical overhead. | vertical up | legs drive |
| special (Thunder Thrust) | A: coil low with the shaft far back. S: explosive thrust, 2-tick hold at full extension (shock spark at the tip). | straight forward | lunge |
| ultimate (Lullaby Lance) | A: spin the shaft once in front (not around the body), plant. S: one huge forward thrust; a wave travels 2 body lengths. F: hold. | forward | deep lunge |

Hooks: thrust trail = narrow straight line; light_3/special hit-stop 5-6; run_heavy camera nudge up.

## 5. Hammer. Feel: heavy, slow, committed; big wind-ups, ground impacts, momentum carries the body

Two hands on the haft for every swing. Wind-ups show weight (head lags the hands), contacts are short
and hard, recoveries show the body fighting the momentum. The box is short and very wide: horizontal
sweeps and overhead slams landing just in front.

| move | key poses | arc | body |
|---|---|---|---|
| light_1 | A: head drawn back right at hip height. S: flat horizontal sweep R->L. F: head carries past the left, body twisted with it. | horizontal R->L | heavy hip twist, back heel lifts |
| light_2 | A = light_1 F. S: backswing sweep L->R, slightly rising. F: head right-high. | horizontal L->R | reverse twist, small step |
| light_3 | A: head lifted over the right shoulder, body leaning back. S: overhead slam down in front. F: head on the floor, knees bent, 4-6 tick stuck hold. R: heave it back up. | vertical down, front | step in, full body drop |
| heavy | A: big wind-up, hammer far behind the back, body coiled right (18 ticks: show it!). S: diagonal upward golf-swing from low right to high left (launch). F: hammer overhead left, body pulled around by it. | diagonal up R-low -> L-high | full twist, front foot planted |
| air | S: short downward swing. | down front | tucked |
| air_heavy | A: hammer raised overhead in the air, body arched. S: crash down (long stun), head hits the floor. F: crouched, both hands on the haft, head in the crater. R: slow lift. | vertical down | full drop; biggest impact in the game |
| run_light | S: running sideways sweep R->L (knockback 22). F: body spun ~90 deg by the momentum, feet skid. | horizontal, forward-moving | momentum carries the turn |
| run_heavy | A: plant, head dragged behind on the floor. S: underhand upswing from floor-front to overhead (launch 13). F: overhead, on toes. | vertical up | full body lift |
| special (Earthshaker) | A: hammer lifted high overhead, chest up. S: slam to the floor in front, shockwave. F: hold kneel 6+ ticks. | vertical down | big drop |
| ultimate (Mountain Fall) | A: jump-in-place wind-up, hammer far back. S: falling slam, wave runs 2 body lengths forward. F: crater kneel. | vertical down | jump + drop |

Hooks: keep data hit-stop (already 7-8 on heavy/run moves); ground hits = dust ring decal + medium shake; air_heavy/special/ultimate = heavy shake.

## 6. Shared pose families (save work)

- **Combo pair**: light_1 F = light_2 A for blade, hammer (swing out / swing back); dagger light_2 = mirror
  of light_1 (swap hands); fists light_1/light_2 = jab/cross mirror.
- **Rising launcher** (low-front -> overhead, end on toes): heavy-up and run_heavy for every weapon share
  one body curve; only the weapon arc/hold differs. Build once, parametrize the hand path.
- **Overhead slam / plunge** (raise, drop, kneel): air_heavy for all 5 weapons + hammer light_3/special/
  ultimate + spear air_heavy. One body curve, weapon tip/head changes.
- **Air light**: same tucked-body downward cut for all; only the weapon.
- **Run attacks**: same run-to-slide body (lean, slide stop); only the arm motion differs.
- **Thrust**: spear light_1/2/3/special/ultimate are one thrust with 3 depths (step, half lunge, full lunge).
- **Forward ultimate**: same "load -> forward strike -> hold" structure; each weapon swaps the strike.

So per weapon the unique work is ~4 clips (light_1/2, light_3, heavy, special); the rest are variants.

## 7. Build order

1. **Blade, as the look prototype**: light_1, light_2, light_3, heavy only. Boss approves style
   (speed, arcs, gender-neutral body, top-down readability) before anything else.
2. Blade: air, air_heavy, run_light, run_heavy, special. This creates the shared families (launcher, slam,
   air, run) that every later weapon reuses.
3. Hammer (most different: weight and momentum; proves the families scale to slow moves).
4. Spear (thrust family).
5. Dagger (dual-wield mirrors).
6. Fists (no weapon; mostly body; reuses chibi unarmed).
7. Ultimates for fists/dagger/spear/hammer (or skill packs from the model team, as blade did).

## 8. Proposals (data NOT changed; Boss/PO to decide)

1. **Dagger startups 2-3 ticks** (light, air) leave no visible anticipation. Fine for feel, but if the
   Boss finds dagger hits "pop", raise dagger `speed` to 0.8 (light startup 3, air 2) or accept it.
2. **Hammer light_3 & special stuck-in-floor hold** needs the recovery to stay >= 24/30 ticks; keep
   hammer speed >= 1.4 or the hold must shrink.
3. **Air_heavy active is 10 ticks for every weapon** (the dive). The slam lands at strike_end; if the
   landing is earlier/later in practice, the hit should be timed to contact (needs a code look later).
4. **Non-blade ultimates** use the template 14/18/28; blade's skill pack needed 62/54/76. If the other
   ultimates also come as model-team skill packs, their timings will be overridden the same way.
5. **Blade heavy launch** reads better if the box is a bit taller (hit_size y 1.3 -> 1.5) to match the
   upward finish; optional, test after the clip exists.

## 9. Untested / needs the Boss's eyes

Everything visual: the arcs above are designed against the hit box numbers, but whether vertical moves
read from the steep camera, and whether two-hand spear/hammer swings clip through outfits/capes, can only
be judged on the blade prototype renders (step 1).
