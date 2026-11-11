"""Clip definitions for tools/blender/goblin_family_anims.py (one function per variant; `ns` = that script's
helpers: keyed, run_pose, bump, wave, snap, periodic, smooth, lerp, add, lying, Vector, SCALE, RUN_REF, FPS...).
Channels: see goblin_family_anims.py. Positions are goblin units (armature space: faces -y, its left is +x).
Hands are 9-tuples H(wrist or grip, prop axis, prop up) so keys interpolate every part.
Attack marks come from the moves in data/combat/combat.json (startup / active / recovery at 60 Hz): the clip
is authored 1:1 with the move, windup_end = startup, strike_end = startup + active, length = the whole move.
Personalities (the director: goblins do not move like the player, each is always moving a little):
  archer  jumpy and wary, light on its feet, radar ears, fidgets with the arrow
  mage    aloof and theatrical, sways as if muttering a spell, the hat tip has a life of its own
  knight  heavy, slow, deliberate, the greatsword's tip rests on the floor, breathes like a bellows
  chief   swaggering, chest out, twirls his cleavers, growls; big and slow to turn
"""
import math


def ticks(*t):
    """Move frames (60 Hz) -> clip marks (windup_end, strike_end) and length: the clip plays 1:1 in the game."""
    s, a, r = t
    return (s / 60.0, (s + a) / 60.0), (s + a + r) / 60.0


def run_cycle(sweep=0.215, duty=0.3, v=2.44):
    """Stride T (s) so the planted feet match the game: the client plays a run at speed / (2.44 x fit), the
    model is in goblin units, so every variant's run is authored at 2.44 goblin units/s at rate 1."""
    return sweep / (v * duty), v


def H(p, d, z=(0.0, 0.0, 1.0)):
    return tuple(p) + tuple(d) + tuple(z)


def lift_step(f0, f1, h=0.03, pitch=18):
    """The foot halfway between two planted spots, lifted (a step key between two plants)."""
    return tuple((a + b) / 2 for a, b in zip(f0[:2], f1[:2])) + (h, pitch, (f0[4] + f1[4]) / 2)


# =================================================================== ARCHER
def archer(ns):
    keyed, run_pose, bump, wave, snap, periodic, smooth, lerp, add, lying, Vector = (ns[k] for k in (
        "keyed", "run_pose", "bump", "wave", "snap", "periodic", "smooth", "lerp", "add", "lying", "Vector"))
    Quaternion = ns["Quaternion"]
    CARRY_L = H((0.27, -0.03, 0.36), (0.15, -0.62, 0.77), (0.0, 0.77, 0.62))   # bow upright at its left side
    ARROW_R = H((-0.25, -0.03, 0.31), (-0.1, -0.97, 0.12))
    BASE = dict(hips=(0.0, 0.0, -0.03), hipsr=(4, 0, 0), spine=(2, 0, 0), chest=(0, 0, 0), neck=(0, 0, 0), head=(-3, 0, 0),
                jaw=3.0, earL=(0, -4), earR=(0, -4), tipL=0.0, tipR=0.0,
                footL=(0.12, -0.03, 0.0, 4.0, 12.0), footR=(-0.12, 0.03, 0.0, 4.0, -12.0),
                handL=CARRY_L, handR=ARROW_R, twL=0.0, twR=0.0, draw=0.0, slideR=0.0, nock=0.0, nockTw=0.0,
                wsL=0.0, wsR=0.0, gripL=0.0, gripR=0.0, elbowR=(-0.7, 0.6, -0.2))
    FL, FR = BASE["footL"], BASE["footR"]

    # ---- idle: light on the balls of its feet, ears swivelling like radar, quick wary checks
    IL = 4.8
    def idle(t):
        P = dict(BASE)
        x = periodic([(0, 0.0), (0.7, 0.012), (1.7, 0.013), (2.3, -0.006), (2.8, -0.014), (3.9, -0.010), (4.4, 0.004), (IL, 0.0)], t, IL)
        crouch = bump(t, 3.35, 0.9, 0.35)
        P["hips"] = (x, 0.0, -0.03 + 0.004 * wave(t, IL, 8) - 0.025 * crouch)
        P["hipsr"] = (4 + 1.2 * wave(t, IL, 3) + 6 * crouch, -x * 280, 2 * wave(t, IL, 2, 0.4))
        P["chest"] = (1.5 * wave(t, IL, 8, 0.6) + 3 * crouch, x * 300, 0)
        yaw = snap([(0, 0), (0.55, 0), (0.66, -32), (1.35, -28), (1.47, 6), (2.3, 18), (2.9, 22), (3.0, 0), (3.5, 0), (3.6, 12),
                    (4.05, 10), (4.16, 0), (IL, 0)], t)
        P["neck"] = (4 * crouch, 0, 0.3 * yaw)
        P["head"] = (-3 + 6 * crouch + 3 * bump(t, 2.0, 0.5), -x * 120 + 0.15 * yaw, 0.55 * yaw)
        P["chest"] = add(P["chest"], (0, 0, 0.15 * yaw))
        P["jaw"] = 3 + 2 * bump(t, 2.0, 0.5) + 1.2 * wave(t, IL, 8)
        fl = lambda t0, a, d=0.22: a * bump(t, t0, d)
        P["earL"] = (0.2 * max(0, yaw) - 0.21 * min(0, yaw) + fl(0.4, 22) + fl(2.55, 18) - 10 * crouch + 0.3 * yaw, -4 - 6 * crouch)
        P["earR"] = (0.21 * max(0, yaw) + fl(1.2, 24) + fl(3.0, 14) + fl(4.3, 20) - 10 * crouch - 0.3 * yaw, -4 - 6 * crouch)
        P["tipL"] = 5 * bump(t, 0.45, 0.3); P["tipR"] = 5 * bump(t, 1.25, 0.3)
        pL = 4 + 8 * max(0.0, -x) / 0.013; pR = 4 + 8 * max(0.0, x) / 0.013
        P["footL"] = (0.12, -0.03, 0.0, pL, 12.0); P["footR"] = (-0.12, 0.03, 0.0, pR, -12.0)
        tap = sum(bump(t, t0, 0.16) for t0 in (1.75, 1.95, 2.15))      # taps the arrow on its knee, three beats
        twirl = smooth((t - 4.25) / 0.4)
        hr = list(ARROW_R)
        hr[2] += 0.012 * tap + 0.06 * bump(t, 4.15, 0.6, 0.3); hr[0] -= 0.04 * bump(t, 4.15, 0.6, 0.3); hr[5] += 0.35 * tap
        P["handR"] = tuple(hr); P["twR"] = 360 * twirl
        lift = bump(t, 3.3, 1.0, 0.3)        # brings the bow up a little while it peers
        hl = list(CARRY_L)
        hl[1] -= 0.04 * lift; hl[2] += 0.03 * lift
        P["handL"] = tuple(hl)
        return P

    # ---- run: light, fast, bow carried upright along the left side, arrow hand pumping
    T, v = run_cycle()
    def arms(P, ph, c):
        pump = 0.035 * math.cos(2 * math.pi * ph)
        P["handL"] = H((0.27, 0.02 - pump, 0.33), (0.15, -0.7, 0.7), (0.0, 0.7, 0.7))
        P["handR"] = H((-0.24, 0.05 + pump, 0.31), (-0.1, -0.95, 0.3))
    RP = dict(T=T, duty=0.3, sweep=(-0.115, 0.10), x=0.10, lift=0.06, drop=-0.05, bob=0.022, lean=16, roll=4, yaw=8,
              chest_yaw=10, head=-6, neck=(-6, 0, 0), ears=(22, 6), arms=arms)
    def run(t): return run_pose(t, BASE, RP)

    # ---- shoot / volley: a hop into a side-on stance, nock, draw under the chin, release, hop back.
    # The bow is canted (top limb away from the big head); its grip is placed directly (gripL), in armature space.
    # Side-on, the chest's front faces the archer's right (-x): the only place both short arms reach. So it
    # nocks right at its chest and PUSHES the bow out toward the target while the string hand stays (push-pull
    # draw): bow grip y = string y - 0.075 - draw. The arrow runs along -y at x AX, z AZ, under the chin.
    SIDE = dict(hipsr=(2, 0, -55), spine=(0, 0, -10), chest=(-2, -4, -15), neck=(0, 2, 28), head=(-2, 4, 38))
    FEET = dict(footL=(0.08, -0.07, 0, 0, -25), footR=(-0.06, 0.12, 0, 0, -70))
    AX, AZ, SY = -0.18, 0.40, 0.035
    def bow(draw=0.0, cant=30, aim=0.0, roll=0.0, bx=0.0, bz=0.0):
        """The bow grip and frame for a string at (AX, SY, AZ): X (string -> grip) points at the target, pitched
        up by `aim` degrees; the limbs (Y) tilt `cant` degrees away from the head."""
        c, s = math.cos(math.radians(cant)), math.sin(math.radians(cant))
        ca, sa = math.cos(math.radians(aim)), math.sin(math.radians(aim))
        X = Vector((0.0, -ca, sa)); Y = Vector((s, 0.0, -c)); Y = (Y - X * Y.dot(X)).normalized(); Z = X.cross(Y)
        g = Vector((AX + bx, SY, AZ + bz)) + X * (0.075 + draw)
        if roll:    # the bow turned in the fist about the fist axis Z: at 180 it matches the carried bow
            q = Quaternion(Z, math.radians(roll)); Y = q @ Y
        return H(tuple(g), tuple(Y), tuple(Z))
    BOWG = bow(0.20)
    NOCK = H((AX, SY + 0.015, AZ), (0.0, -1.0, 0.0))
    NOCK2 = H((AX, SY + 0.015, AZ - 0.03), (0.0, -1.0, 0.0))
    ARROW_UP = H((-0.24, -0.04, 0.35), (-0.1, -0.9, 0.42))   # side-on, the arrow tipped up, clear of the thighs
    def hop(t0, f0, f1, h=0.035):
        return [(t0, dict(footL=lift_step(f0[0], f1[0], h), footR=lift_step(f0[1], f1[1], h * 0.8)))]

    # side (0..1): blend of the hands into the side-on bow pose; push = how far the bow is out (= draw until the
    # release, then it stays out while the string snaps back); cant = the bow's tilt (top limb away from the head).
    def bowpose(t, keys, base_cant, bz=0.0):
        P = keyed(dict(BASE, side=0.0, push=0.0, cant=base_cant, aim=0.0, roll=180.0, rws=0.0, bx=0.0, bz=bz), keys, t)
        sd = P.pop("side"); bw = bow(P.pop("push"), P.pop("cant"), P.pop("aim"), P.pop("roll"), P.pop("bx"), P.pop("bz"))
        P["handL"] = lerp(P["handL"], bw, sd)
        P["wsL"] = P["gripL"] = sd                  # the side-on bow is placed by its grip, in armature space
        P["wsR"] = P["gripR"] = P.pop("rws")        # likewise the string hand once it comes to the string
        return P

    (we, se), SL = ticks(34, 2, 22)
    SHOOT = [
        (0.07, dict(hips=(0, 0.01, -0.05), hipsr=(6, 0, -10), chest=(2, 0, -6), head=(-8, 0, 14), earL=(14, -2), earR=(14, -2), jaw=2.0,
                    footL=FL, footR=FR, handL=H((0.27, -0.05, 0.38), (0.2, -0.7, 0.68), (0.0, 0.68, 0.7)),
                    handR=H((-0.24, -0.06, 0.34), (-0.1, -0.95, 0.25)))),
    ] + hop(0.12, (FL, FR), (FEET["footL"], FEET["footR"])) + [
        (0.15, dict(FEET, **SIDE, hips=(0, 0.01, -0.045), side=0.0, handR=ARROW_UP, nock=0.0)),
        (0.215, dict(side=1.0, push=0.17, bx=0.0)),
        (0.22, dict(nock=0.0, draw=0.0, handR=ARROW_UP)),
        (14 / 60, dict(roll=180.0)),       # the bow flips in the fist in one frame (same limb line; only its
        (15 / 60, dict(roll=0.0)),         # 2 cm curve and the string swap sides), out in front, clear of the body
        (0.27, dict(rws=0.0)),
        (0.31, dict(side=1.0, push=0.17, rws=1.0, handR=NOCK, bx=0.0, elbowR=(-0.3, 0.8, 0.5),
                    earL=(10, 0), earR=(10, 0))),
        (0.33, dict(nock=1.0, draw=0.17, push=0.17)),
        (0.48, dict(draw=0.19, push=0.19, hipsr=(0, 0, -57), chest=(-5, -6, -17), head=(-5, 6, 40), earL=(26, 6), earR=(26, 6), jaw=1.0)),
        (we - 0.03, dict(draw=0.195, push=0.195)),
        (we, dict(draw=0.19, push=0.19, nock=1.0)),
        (we + 0.035, dict(draw=0.0, nock=0.0, push=0.205, cant=63, handR=H((-0.18, 0.08, 0.41), (-0.3, 0.9, -0.3)), earL=(-8, -8), earR=(-8, -8),
                          jaw=10.0, hipsr=(2, 0, -59), head=(-7, 6, 40))),
        (0.66, dict(bx=0.0)),
        (0.70, dict(SIDE, handR=ARROW_R, rws=0.0, bx=0.0, elbowR=(-0.7, 0.6, -0.2), earL=(6, -4), earR=(6, -4), jaw=5.0, push=0.17, cant=58, side=1.0, roll=0.0)),
        (46 / 60, dict(roll=0.0, side=1.0)),
        (47 / 60, dict(roll=180.0)),
        (0.80, dict(FEET, side=0.0, push=0.10, bx=0.0, handR=ARROW_R, hipsr=(4, 0, -40), head=(-3, 2, 38), nock=0.0)),
    ] + hop(0.85, (FEET["footL"], FEET["footR"]), (FL, FR), 0.03) + [
        (0.91, dict(BASE, hips=(0, 0.0, -0.04), hipsr=(5, 0, -4), chest=(0, 0, -2), head=(-3, 0, 4), footL=FL, footR=FR,
                    earL=(4, -4), earR=(4, -4), side=0.0, push=0.0)),
        (SL, dict(BASE)),
    ]
    def shoot(t): return bowpose(t, SHOOT, 58)

    (vwe, vse), VL = ticks(44, 2, 30)
    FEET2 = dict(footL=(0.10, -0.06, 0, 0, -28), footR=(-0.07, 0.14, 0, 0, -72))
    SIDE2 = dict(hipsr=(-1, 0, -56), spine=(-1, 0, -10), chest=(-3, -4, -15), neck=(-2, 2, 30), head=(-4, 6, 40))
    VOLLEY = [
        (0.08, dict(hips=(0, 0.02, -0.07), hipsr=(12, 0, -6), chest=(6, 0, -4), head=(4, 0, 8), earL=(30, 20), earR=(30, 20), jaw=12.0,
                    footL=FL, footR=FR, handL=H((0.27, -0.06, 0.38), (0.2, -0.7, 0.68), (0.0, 0.68, 0.7)),
                    handR=H((-0.24, -0.06, 0.34), (-0.1, -0.95, 0.25)))),
    ] + hop(0.15, (FL, FR), (FEET2["footL"], FEET2["footR"]), 0.05) + [
        (0.15, dict(hips=(0, 0.04, 0.0), hipsr=(0, 0, -30))),
        (0.22, dict(FEET2, **SIDE2, hips=(0, 0.02, -0.075), side=0.0, handR=ARROW_UP, nock=0.0)),
        (0.29, dict(side=1.0, push=0.17, bx=0.0)),
        (0.30, dict(nock=0.0, draw=0.0, handR=ARROW_UP)),
        (19 / 60, dict(roll=180.0)),
        (20 / 60, dict(roll=0.0)),
        (0.35, dict(rws=0.0)),
        (0.38, dict(side=1.0, push=0.17, rws=1.0, handR=NOCK2, bx=0.0, elbowR=(-0.3, 0.8, 0.5),
                    earL=(4, 6), earR=(4, 6), jaw=4.0)),
        (0.40, dict(nock=1.0, draw=0.17, push=0.17, hips=(0, 0.02, -0.065))),
        (0.62, dict(draw=0.175, push=0.175, cant=60, aim=12, hipsr=(-2, 0, -58), chest=(-4, -5, -17), head=(-6, 8, 47), earL=(30, 10), earR=(30, 10), jaw=1.0)),
        (vwe - 0.03, dict(draw=0.18, push=0.18)),
        (vwe, dict(draw=0.175, push=0.175, nock=1.0)),
        (vwe + 0.04, dict(draw=0.0, nock=0.0, push=0.185, cant=62, aim=10, handR=H((-0.13, 0.10, 0.37), (-0.3, 0.9, -0.3)), earL=(-10, -10), earR=(-10, -10),
                          jaw=16.0, hips=(0, 0.03, -0.06), hipsr=(-4, 0, -60), head=(-8, 6, 42))),
        (0.86, dict(bx=0.0)),
        (0.90, dict(SIDE2, handR=ARROW_R, rws=0.0, bx=0.0, elbowR=(-0.7, 0.6, -0.2), earL=(10, -2), earR=(10, -2), jaw=8.0,
                    push=0.14, cant=62, aim=4, side=1.0, roll=0.0, hips=(0, 0.02, -0.05))),
        (57 / 60, dict(roll=0.0, side=1.0, aim=0.0, cant=58, push=0.14)),
        (58 / 60, dict(roll=180.0)),
        (1.00, dict(FEET2, side=0.0, push=0.10, bx=0.0, handR=ARROW_R, hipsr=(4, 0, -38), head=(-3, 2, 36), nock=0.0)),
    ] + hop(1.08, (FEET2["footL"], FEET2["footR"]), (FL, FR), 0.035) + [
        (1.15, dict(BASE, hips=(0, 0.0, -0.045), hipsr=(6, 0, -4), chest=(0, 0, -2), head=(-3, 0, 4), footL=FL, footR=FR,
                    earL=(6, -4), earR=(6, -4), side=0.0, push=0.0)),
        (VL, dict(BASE)),
    ]
    def volley(t):
        P = bowpose(t, VOLLEY, 50, -0.03)
        sh = smooth((t - 0.5) / 0.15) * (1 - smooth((t - vwe) / 0.02))     # the strain of the full draw
        P["head"] = add(P["head"], (0, 1.5 * sh * math.sin(2 * math.pi * 11 * t), 0))
        P["chest"] = add(P["chest"], (0.8 * sh * math.sin(2 * math.pi * 9 * t + 1), 0, 0))
        return P

    # ---- hit: a turtle flinch (head ducks, never back into the quiver), bow up as a shield, ears flat
    HIT = [
        (0.05, dict(hips=(0, 0.025, -0.05), hipsr=(-4, 0, 0), spine=(4, 0, 0), chest=(6, 0, 0), neck=(6, 0, 0), head=(10, 0, 0),
                    jaw=16.0, earL=(-12, 32), earR=(-12, 32), tipL=24.0, tipR=24.0,
                    handL=H((0.24, -0.09, 0.40), (0.4, -0.45, 0.8), (0.0, 0.86, 0.5)), handR=H((-0.22, -0.09, 0.39), (0.1, -0.85, 0.5)))),
        (0.13, dict(hipsr=(-1, 0, 0), head=(5, 5, -8), jaw=10.0)),
        (0.27, dict(hips=(0, 0.0, -0.025), hipsr=(6, 0, 0), spine=(2, 0, 0), chest=(-1, 0, 0), neck=(0, 0, 0), head=(-5, 0, 4),
                    earL=(22, -2), earR=(22, -2), tipL=-4.0, tipR=-4.0, jaw=5.0, handL=CARRY_L, handR=ARROW_R)),
        (0.38, dict(hipsr=(3, 0, 0), head=(-2, 0, 0), earL=(6, -4), earR=(6, -4), tipL=0.0, tipR=0.0)),
        (0.50, dict(BASE)),
    ]

    # ---- death: jolt, drops the arrow and the bow, stumbles back, sits down hard and topples onto its back
    DT0, DT1 = 0.30, 0.52
    DEATH = [
        (0.06, dict(hips=(0, 0.03, -0.03), hipsr=(-8, 4, 0), chest=(-6, 0, 0), head=(4, 0, 10), jaw=22.0, earL=(38, 30), earR=(38, 30),
                    tipL=20.0, tipR=20.0, footL=FL, footR=FR,
                    handL=H((0.30, -0.01, 0.45), (0.2, -0.5, 0.85), (0.0, 0.85, 0.5)), handR=H((-0.30, 0.02, 0.38), (-0.6, -0.4, 0.6)))),
        (0.20, dict(hips=(0, 0.06, -0.03), hipsr=(-12, -6, -10), footR=(-0.12, 0.08, 0.04, 15, -12))),
        (0.32, dict(footR=(-0.12, 0.13, 0, 0, -20), footL=FL)),
        (0.44, dict(hips=(0.0, 0.11, -0.035), hipsr=(-8, 8, 12), head=(8, -6, 14), footL=(0.10, 0.10, 0.04, 15, 10))),
        (0.55, dict(hips=(-0.01, 0.13, -0.04), hipsr=(-6, -10, 20), footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0, 0, -20))),
        (0.75, dict(hipsr=(-10, 10, -5), head=(2, -15, 10), handL=H((0.30, 0.0, 0.40), (0.9, 0.0, 0.4)), handR=H((-0.30, 0.05, 0.33), (-0.9, 0.2, -0.2)),
                    footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0, 15, -20))),
        (0.90, dict(hips=(0, 0.16, -0.05), hipsr=(-25, 0, 0), head=(-2, 0, 0), footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0.0, 20, -20))),
        (1.15, dict(hips=(0, 0.26, -0.10), hipsr=(-82, 0, 0), spine=(-10, 0, 0), chest=(-8, 0, 0), neck=(4, 0, 0), head=(6, 0, 0),
                    handL=H((0.33, 0.02, 0.38), (0.6, -0.6, 0.0)), handR=H((-0.33, 0.02, 0.38), (-0.6, -0.6, 0.0)), jaw=10.0,
                    earL=(10, -10), earR=(10, -10),
                    footL=(0.10, 0.18, 0.20, -40, 10), footR=(-0.10, 0.16, 0.22, -40, -10))),
        (1.27, dict(hips=(0, 0.26, -0.07), earL=(20, 20), earR=(20, 20), footL=(0.13, 0.14, 0.10, -60, 15), footR=(-0.13, 0.13, 0.12, -60, -15))),
        (1.40, dict(hips=(0, 0.26, -0.10), footL=(0.14, 0.12, 0.04, -80, 20), footR=(-0.14, 0.12, 0.04, -80, -20), jaw=22.0,
                    earL=(30, 35), earR=(30, 35), head=(0, 10, 18))),
        (1.70, dict(footR=(-0.14, 0.12, 0.04, -80, -20))),
        (1.78, dict(footR=(-0.15, 0.10, 0.08, -70, -25), earL=(20, 25))),
        (1.88, dict(footR=(-0.14, 0.12, 0.04, -80, -20), earL=(30, 35))),
        (2.20, dict(footR=(-0.14, 0.12, 0.04, -80, -20))),
    ]
    death_drop = dict(t0=DT0, t1=DT1, final={"L": lying((0.40, -0.10, 0.026), (0.25, -1, 0)),
                                              "R": lying((-0.28, -0.18, 0.016), (-0.5, -1, 0))})

    def arrow_point(S):
        """The arrow's middle at release (goblin units: forward, up, side +left) and its tip."""
        M = S.M["attach_weapon.R"]
        mid = M @ Vector((0, (0.345 - 0.13) / 2, 0)); tip = M @ Vector((0, 0.345, 0))
        return "mid [%.2f, %.2f, %.2f] tip [%.2f, %.2f, %.2f]" % (-mid.y, mid.z, mid.x, -tip.y, tip.z, tip.x)

    clips = {
        "idle": dict(fn=idle, length=IL, loop=True, shots=[0.0, 0.7, 1.0, 1.95, 2.6, 3.7]),
        "run": dict(fn=run, length=2 * T, loop=True, ground_v=v, shots=[2 * T * k / 6 for k in range(6)]),
        "shoot": dict(fn=shoot, length=SL, marks=(we, se), shots=[0.0, 0.07, 0.15, 0.25, 0.4, we, we + 0.035, 0.72, 0.85],
                      show={"arrow": (0.0, we)}, probe={"arrow": arrow_point}, probe_t={"arrow": we}),
        "volley": dict(fn=volley, length=VL, marks=(vwe, vse), shots=[0.0, 0.08, 0.15, 0.3, 0.5, vwe, vwe + 0.04, 0.95, 1.1],
                       show={"arrow": (0.0, vwe)}, probe={"arrow": arrow_point}, probe_t={"arrow": vwe}),
        "hit": dict(fn=lambda t: keyed(BASE, HIT, t), length=0.5, shots=[0.0, 0.05, 0.13, 0.27, 0.38]),
        "death": dict(fn=lambda t: keyed(BASE, DEATH, t), length=2.2, drop=death_drop, ground_from=0.85, ground_lock=1.15, feet_follow=1.0,
                      shots=[0.06, 0.2, 0.44, 0.75, 0.95, 1.15, 1.4, 2.2]),
    }
    # the drawing fist holds the string, the arrow rests on the bow hand: contacts, not intersections
    return {"clips": clips, "view": 1.7, "nock": "arrow", "qa_skip": {"bow": ["hand.R", "forearm.R"], "arrow": ["hand.L"]}}


# =================================================================== KNIGHT
def knight(ns):
    keyed, run_pose, bump, wave, snap, periodic, smooth, lerp, add, lying, Vector = (ns[k] for k in (
        "keyed", "run_pose", "bump", "wave", "snap", "periodic", "smooth", "lerp", "add", "lying", "Vector"))
    # The goblin's arms reach 0.20 from shoulders 0.30 apart past a torso 0.30 deep: both fists can never meet on
    # one hilt, so the greatsword is swung one-handed (grip_offhand stays unused, see the report).
    SLIDE = 0.22                    # held one-handed at the very end of the hilt, the fist over the pommel
    BLADE = 1.05 + SLIDE            # tip distance from the fist
    REST_SW = H((-0.27, -0.08, 0.33), (0.3, -0.9, -0.33))      # grip at its right, the blade angled across, tip on the floor
    FIST_L = H((0.25, -0.05, 0.31), (0.15, -1.0, -0.2))
    ON_FLOOR = (0.015, BLADE, 1.0)
    BASE = dict(hips=(0.0, 0.0, -0.045), hipsr=(8, 0, -6), spine=(3, 0, -2), chest=(2, 0, 0), neck=(-2, 0, 4), head=(-4, 0, 4),
                jaw=1.0, earL=(-6, 10), earR=(-6, 10), tipL=0.0, tipR=0.0,
                footL=(0.14, -0.05, 0.0, 0.0, 14.0), footR=(-0.13, 0.05, 0.0, 0.0, -18.0),
                handL=FIST_L, handR=REST_SW, twL=0.0, twR=0.0, slideR=SLIDE, offL=0.0, wsL=0.0, wsR=0.0, gripL=0.0, gripR=1.0,
                tipzR=ON_FLOOR, elbowL=(1.0, -0.1, -0.3), elbowR=(-1.0, -0.1, -0.3))
    FL, FR = BASE["footL"], BASE["footR"]

    # ---- idle: a slow bellows breath, weight rolling foot to foot, slow head turns; it tips the blade up and
    #      lets it drop back on the floor (thunk), snorts
    IL = 5.0
    def idle(t):
        P = dict(BASE)
        br = wave(t, IL, 3)                         # three deep breaths per loop
        x = periodic([(0, 0.0), (1.2, 0.012), (2.5, 0.010), (3.4, -0.010), (4.4, -0.008), (IL, 0.0)], t, IL)
        heave = bump(t, 2.9, 0.62, 0.55)
        thunk = bump(t, 3.5, 0.16, 0.3)
        snort = bump(t, 3.75, 0.35, 0.25)
        P["hips"] = (x, 0.0, -0.045 + 0.004 * br - 0.012 * snort - 0.006 * thunk)
        P["hipsr"] = (8 + 1.0 * br, -x * 220, -6 + 3 * wave(t, IL, 1, 0.6))
        P["chest"] = (2 - 2.5 * br - 3 * heave + 2 * thunk, x * 250, 0)
        P["spine"] = (3 - 1.2 * br, 0, -2)
        yaw = periodic([(0, 4), (1.0, 4), (1.9, 16), (2.6, 14), (3.3, -6), (4.3, -5), (IL, 4)], t, IL)
        P["neck"] = (-2 + 1.5 * br + 4 * snort, 0, 0.35 * yaw)
        P["head"] = (-4 + 1.5 * br - 8 * snort, -x * 80 + 3 * snort * math.sin(2 * math.pi * 7 * t), 0.5 * yaw)
        P["jaw"] = 1 + 2.5 * (0.5 + 0.5 * br) + 9 * snort
        P["earL"] = (-6 + 14 * bump(t, 1.95, 0.3), 10 + 6 * snort + 8 * thunk); P["earR"] = (-6 + 12 * bump(t, 4.4, 0.3), 10 + 6 * snort + 8 * thunk)
        P["tipL"] = 6 * bump(t, 2.0, 0.35); P["tipR"] = 6 * bump(t, 4.45, 0.35)
        pL = 6 * max(0.0, -x) / 0.012; pR = 6 * max(0.0, x) / 0.012
        P["footL"] = (FL[0], FL[1], 0.0, pL, FL[4]); P["footR"] = (FR[0], FR[1], 0.0, pR, FR[4])
        g = list(REST_SW); g[0] += 0.01 * wave(t, IL, 2, 0.3)
        P["handR"] = tuple(g); P["tipzR"] = (0.015 + 0.10 * heave, BLADE, 1.0)
        P["twR"] = 5 * wave(t, IL, 2)
        P["handL"] = add(FIST_L, (0, 0.01 * br, -0.008 * br, 0, 0, 0, 0, 0, 0))
        return P

    # ---- run: a heavy armoured jog, low and stomping, the greatsword dragged behind, tip scraping the floor
    T, v = run_cycle(sweep=0.22, duty=0.34)
    DRAG = H((-0.29, -0.01, 0.34), (-0.05, 0.95, -0.3), (1.0, 0.0, 0.0))   # edge down: the guard stands upright, clear of the leg
    def arms(P, ph, c):
        pump = 0.03 * math.cos(2 * math.pi * ph)
        P["handL"] = H((0.25, -0.02 - pump, 0.32), (0.15, -1.0, -0.1))
        P["handR"] = add(DRAG, (0, 0.006 * c, 0.004 * c, 0, 0, 0, 0, 0, 0))
        P["tipzR"] = (0.04, BLADE, 1.0, 1)
    RP = dict(T=T, duty=0.34, sweep=(-0.11, 0.11), x=0.125, lift=0.045, drop=-0.06, bob=0.026, lean=12, roll=5, yaw=7,
              chest_yaw=-6, head=-4, neck=(-4, 0, 0), ears=(-4, 14), toe=12.0, peel=22, arms=arms)
    def run(t):
        P = run_pose(t, BASE, RP)
        P["jaw"] = 3 + 2 * math.sin(4 * math.pi * t / T)
        return P

    # ---- slash_heavy (goblin_knight_cleave 26/6/32): a long cock to its right ('!'), one flat sweep right to left
    #      with a step of the left foot, the blade's weight carries the body round, then it hauls the tip back.
    (we, se), SL = ticks(26, 6, 32)
    FLs = (0.17, -0.13, 0.0, 0.0, 30.0)
    LEVEL = lambda h: (h, BLADE, 1.0)
    SLASH = [
        (0.10, dict(hips=(0, 0.01, -0.05), hipsr=(8, 0, -14), chest=(2, 0, -10), head=(-4, 0, 12), jaw=2.0,
                    handR=H((-0.29, -0.04, 0.36), (-0.3, -0.9, 0.0)), tipzR=LEVEL(0.10), footL=FL, footR=FR)),
        (0.19, dict(handR=H((-0.32, -0.06, 0.38), (-0.72, -0.2, 0.66)), tipzR=LEVEL(0.0), elbowR=(-1.0, 0.0, -0.7))),
        (0.30, dict(hips=(-0.01, 0.025, -0.065), hipsr=(4, -4, -32), spine=(0, 0, -10), chest=(-4, -4, -22), neck=(0, 0, 18), head=(-4, 7, 30),
                    handR=H((-0.31, 0.02, 0.37), (-0.6, 0.72, 0.3)), tipzR=(0.0, BLADE, 0.0), handL=H((0.25, -0.10, 0.35), (0.4, -0.9, 0.0)),
                    earL=(20, 4), earR=(20, 4), jaw=0.0, elbowR=(-1.0, 0.0, -0.7))),
        (we - 0.04, dict(hips=(-0.015, 0.03, -0.07), hipsr=(4, -5, -36), chest=(-5, -4, -25), handR=H((-0.31, 0.03, 0.37), (-0.62, 0.70, 0.32)),
                         tipzR=(0.0, BLADE, 0.0))),
        (we - 0.01, dict(footL=lift_step(FL, FLs, 0.025))),
        (we + 0.03, dict(hips=(0.0, -0.015, -0.065), hipsr=(5, 0, -6), spine=(5, 0, 0), chest=(2, 0, -2), neck=(0, 0, 4), head=(-4, 0, 4),
                         handR=H((-0.26, -0.11, 0.37), (-0.25, -0.97, 0.0)), tipzR=LEVEL(0.30), handL=H((0.27, -0.02, 0.35), (0.5, -0.8, 0.0)),
                         jaw=14.0, earL=(-6, 0), earR=(-6, 0))),
        (se, dict(hips=(0.01, -0.035, -0.07), hipsr=(4, 3, 24), spine=(8, 0, 8), chest=(4, 2, 20), elbowR=(-1.0, -0.1, -0.3), neck=(0, 0, -12), head=(-4, 0, -20),
                  handR=H((-0.21, -0.13, 0.36), (0.6, -0.8, 0.0)), tipzR=LEVEL(0.24), handL=H((0.28, 0.04, 0.36), (0.7, 0.3, 0.0)), footL=FLs, jaw=18.0)),
        (se + 0.10, dict(hips=(0.015, -0.04, -0.08), hipsr=(5, 4, 34), spine=(9, 0, 8), chest=(5, 3, 26), head=(-2, 0, -26),
                         handR=H((-0.20, -0.12, 0.35), (0.85, -0.5, 0.0)), tipzR=LEVEL(0.18), jaw=10.0, earL=(10, 14), earR=(10, 14))),
        (se + 0.26, dict(hips=(0.01, -0.035, -0.065), hipsr=(5, 2, 24), spine=(6, 0, 4), chest=(3, 0, 16), head=(-4, 0, -14), jaw=6.0,
                         handR=H((-0.22, -0.11, 0.34), (0.6, -0.78, 0.0)), tipzR=LEVEL(0.05))),
        (SL - 0.24, dict(hips=(0, -0.02, -0.05), hipsr=(8, 0, 4), chest=(2, 0, 2), head=(-4, 0, 2), footL=FLs,
                         handR=REST_SW, tipzR=ON_FLOOR, handL=FIST_L, earL=(-6, 10), earR=(-6, 10))),
        (SL - 0.15, dict(footL=lift_step(FLs, FL, 0.025))),
        (SL - 0.07, dict(footL=FL, hips=(0, 0.0, -0.05))),
        (SL, dict(BASE)),
    ]

    # ---- overhead (goblin_knight_overhead 42/5/46): steps back and cocks the blade up and out over its right
    #      shoulder (beside the head, so the top camera sees it), holds ('!'), then a big step in and the blade
    #      comes over and down onto the floor; it heaves it free and plods back into its stance.
    (owe, ose), OL = ticks(42, 5, 46)
    FRb = (-0.13, 0.10, 0.0, 0.0, -24.0)
    FLf = (0.15, -0.16, 0.0, 0.0, 10.0)
    OVER = [
        (0.12, dict(hips=(0, 0.02, -0.06), hipsr=(9, 0, -8), chest=(4, 0, -4), head=(-2, 0, 6), jaw=2.0, footL=FL, footR=FR,
                    handR=H((-0.28, -0.05, 0.37), (-0.2, -0.9, 0.2)), tipzR=LEVEL(0.10))),
        (0.21, dict(handR=H((-0.32, -0.07, 0.39), (-0.72, -0.25, 0.64)), tipzR=(0.0, BLADE, 0.0))),   # up and out: past the ear, pommel clear
        (0.22, dict(footR=lift_step(FR, FRb, 0.03))),
        (0.32, dict(footR=FRb, hips=(0, 0.04, -0.05), hipsr=(2, -3, -16), spine=(-2, 0, -4), chest=(-8, -3, -10), neck=(-2, 4, 6), head=(-5, 8, 12),
                    handR=H((-0.31, 0.0, 0.39), (-0.52, 0.45, 0.72)), tipzR=(0.0, BLADE, 0.0), handL=H((0.26, -0.10, 0.35), (0.3, -0.95, 0.1)),
                    earL=(24, 0), earR=(24, 0), jaw=0.0)),
        (owe - 0.06, dict(hips=(0, 0.05, -0.06), hipsr=(-1, -4, -18), chest=(-10, -4, -12), head=(-6, 9, 14),
                          handR=H((-0.31, 0.02, 0.40), (-0.5, 0.4, 0.77)), tipzR=(0.0, BLADE, 0.0))),
        (owe - 0.01, dict(footL=lift_step(FL, FLf, 0.035))),
        (owe + 0.035, dict(hips=(0, 0.0, -0.04), hipsr=(3, 0, -8), spine=(3, 0, 0), chest=(0, 0, -6), head=(-5, 8, 8), jaw=10.0,
                           handR=H((-0.31, -0.06, 0.40), (-0.6, -0.3, 0.74)), tipzR=(0.0, BLADE, 0.0))),
        (ose, dict(hips=(0, -0.05, -0.08), hipsr=(4, 0, 6), spine=(12, 0, 2), chest=(8, 0, 2), neck=(-6, 0, 0), head=(-10, 0, -2), jaw=22.0,
                   handR=H((-0.25, -0.13, 0.31), (0.05, -1.0, -0.3)), tipzR=ON_FLOOR, handL=H((0.28, 0.04, 0.35), (0.6, 0.4, 0.0)),
                   footL=FLf, earL=(-8, 20), earR=(-8, 20))),
        (ose + 0.06, dict(hips=(0, -0.055, -0.095), hipsr=(5, 0, 6), spine=(14, 0, 2), chest=(9, 0, 2), head=(-8, 0, 0), jaw=12.0)),
        (ose + 0.30, dict(hips=(0, -0.05, -0.085), hipsr=(4, 0, 4), spine=(11, 0, 0), chest=(6, 0, 0), head=(-4, 0, 0), jaw=4.0,
                          earL=(-10, 26), earR=(-10, 26), handR=H((-0.26, -0.12, 0.31), (0.05, -1.0, -0.3)))),
        (ose + 0.48, dict(hips=(0, -0.035, -0.06), hipsr=(9, 0, 0), spine=(3, 0, 0), chest=(0, 0, 0), head=(-6, 0, 2), jaw=8.0,
                          handR=H((-0.27, -0.10, 0.34), (0.15, -0.95, -0.3)), tipzR=(0.10, BLADE, 1.0))),
        (OL - 0.28, dict(handR=REST_SW, tipzR=ON_FLOOR, handL=FIST_L, hipsr=(8, 0, -2), earL=(-6, 10), earR=(-6, 10))),
        (OL - 0.22, dict(footR=FRb, footL=FLf)),
        (OL - 0.16, dict(footR=lift_step(FRb, FR, 0.025))),
        (OL - 0.10, dict(footR=FR, footL=FLf, hips=(0, -0.02, -0.05))),
        (OL - 0.06, dict(footL=lift_step(FLf, FL, 0.025))),
        (OL, dict(BASE)),
    ]

    # ---- hit: it barely gives (poise): a jolt, the head knocked down, a grunt, the tip stays on the floor
    HIT = [
        (0.05, dict(hips=(0, 0.02, -0.055), hipsr=(4, 0, -6), chest=(-4, 0, 0), neck=(2, 0, 4), head=(3, 4, 0), jaw=12.0,
                    earL=(20, 24), earR=(20, 24), tipL=14.0, tipR=14.0, handL=H((0.27, -0.02, 0.33), (0.3, -1.0, 0.0)))),
        (0.15, dict(hips=(0, 0.01, -0.05), chest=(4, 0, 0), head=(-7, -2, 6), jaw=4.0)),
        (0.30, dict(hips=(0, 0.0, -0.045), hipsr=(9, 0, -6), chest=(1, 0, 0), head=(-5, 0, 4), earL=(-6, 8), earR=(-6, 8), tipL=0.0, tipR=0.0,
                    handL=FIST_L)),
        (0.50, dict(BASE)),
    ]

    # ---- death: lets go of the sword, sinks onto its heels, sways, and topples onto its back with a crash
    DEATH = [
        (0.07, dict(hips=(0, 0.02, -0.05), hipsr=(-4, 0, -4), chest=(-6, 0, 0), head=(-4, 0, 0), jaw=20.0, earL=(30, 26), earR=(30, 26),
                    footL=FL, footR=FR, handL=H((0.29, 0.0, 0.36), (0.6, -0.5, 0.4)))),
        (0.30, dict(hips=(0, 0.0, -0.07), hipsr=(6, 0, 0), chest=(6, 0, 0), head=(4, 0, 0), jaw=4.0,
                    handR=H((-0.28, -0.02, 0.32), (0.05, -0.9, -0.4)), tipzR=(0.03, BLADE, 1.0))),
        (0.62, dict(hips=(0, 0.03, -0.085), hipsr=(-2, -6, 6), chest=(2, 0, 0), head=(0, -6, 4), footL=(0.14, -0.05, 0.0, 22, 14),
                    footR=(-0.13, 0.05, 0.0, 22, -18), handR=H((-0.30, 0.02, 0.31), (-0.6, -0.6, -0.3)), handL=H((0.30, 0.02, 0.31), (0.6, -0.6, -0.3)))),
        (0.90, dict(hipsr=(-4, 6, -4), head=(-2, 6, -4))),
        (1.10, dict(hips=(0, 0.06, -0.09), hipsr=(-20, 0, 0), chest=(-4, 0, 0), head=(-2, 0, 0))),
        (1.38, dict(hips=(0, 0.20, -0.11), hipsr=(-82, 0, 0), spine=(-8, 0, 0), chest=(-6, 0, 0), neck=(2, 0, 0), head=(4, 0, 0),
                    handL=H((0.33, 0.02, 0.38), (0.6, -0.6, 0.0)), handR=H((-0.33, 0.02, 0.38), (-0.6, -0.6, 0.0)), jaw=14.0,
                    earL=(10, -6), earR=(10, -6),
                    footL=(0.11, 0.12, 0.10, -50, 14), footR=(-0.11, 0.12, 0.10, -50, -16))),
        (1.50, dict(hips=(0, 0.21, -0.09), footL=(0.13, 0.09, 0.05, -70, 16), footR=(-0.13, 0.09, 0.06, -70, -18), earL=(26, 26), earR=(26, 26))),
        (1.62, dict(hips=(0, 0.21, -0.11), footL=(0.14, 0.08, 0.02, -80, 18), footR=(-0.14, 0.08, 0.02, -80, -18), jaw=20.0,
                    earL=(30, 34), earR=(30, 34), head=(0, 3, 6))),
        (2.20, dict(footR=(-0.14, 0.08, 0.02, -80, -18))),
    ]
    death_drop = dict(t0=0.34, t1=0.62, final={"R": lying((-0.40, -0.20, 0.036), (0.25, -1, 0))})

    clips = {
        "idle": dict(fn=idle, length=IL, loop=True, shots=[0.0, 1.0, 2.0, 3.2, 3.55, 3.85]),
        "run": dict(fn=run, length=2 * T, loop=True, ground_v=v, shots=[2 * T * k / 6 for k in range(6)]),
        "slash_heavy": dict(fn=lambda t: keyed(BASE, SLASH, t), length=SL, marks=(we, se),
                            shots=[0.0, 0.10, 0.30, we, we + 0.03, se, se + 0.1, se + 0.26, SL - 0.15]),
        "overhead": dict(fn=lambda t: keyed(BASE, OVER, t), length=OL, marks=(owe, ose),
                         shots=[0.0, 0.12, 0.32, owe - 0.06, owe + 0.035, ose, ose + 0.06, ose + 0.48, OL - 0.2]),
        "hit": dict(fn=lambda t: keyed(BASE, HIT, t), length=0.5, shots=[0.0, 0.05, 0.15, 0.3]),
        "death": dict(fn=lambda t: keyed(BASE, DEATH, t), length=2.2, drop=death_drop, ground_from=1.0, ground_lock=1.38, feet_follow=1.2,
                      shots=[0.07, 0.3, 0.62, 0.9, 1.1, 1.38, 1.62, 2.2]),
    }
    return {"clips": clips, "view": 2.2}


# =================================================================== MAGE
def mage(ns):
    keyed, run_pose, bump, wave, snap, periodic, smooth, lerp, add, lying, Vector = (ns[k] for k in (
        "keyed", "run_pose", "bump", "wave", "snap", "periodic", "smooth", "lerp", "add", "lying", "Vector"))
    # The staff (1.04: 0.44 below the fist, the crystal 0.60 above) is longer than the fist is high, and the hat
    # brim (radius 0.43) is in the way of an upright staff: it is carried hovering, tilted out past the brim,
    # slid up through the fist (slideR) so its foot clears the boots. It slides further for the bolt thrust.
    STAFF = H((-0.33, -0.08, 0.42), (-0.38, -0.15, 0.91), (0.9, 0.0, 0.38))
    UP = 0.12
    PALM = H((0.22, -0.11, 0.37), (0.35, -0.9, 0.25))            # the free hand, half raised, conjuring
    BASE = dict(hips=(0.0, 0.0, -0.03), hipsr=(2, 0, 0), spine=(0, 0, 0), chest=(-3, 0, 0), neck=(-2, 0, 0), head=(-5, 0, 0),
                jaw=2.0, earL=(10, 8), earR=(10, 8), tipL=0.0, tipR=0.0, hat=(0.0, 0.0),
                footL=(0.11, -0.02, 0.0, 0.0, 8.0), footR=(-0.11, 0.03, 0.0, 0.0, -8.0),
                handL=PALM, handR=STAFF, twL=0.0, twR=0.0, slideR=UP, wsL=0.0, wsR=0.0, gripL=0.0, gripR=1.0,
                elbowL=(0.8, 0.4, -0.4), elbowR=(-1.0, 0.1, -0.3), tipzR=(0.0, -0.44, 0.0, 1))
    FL, FR = BASE["footL"], BASE["footR"]

    # ---- idle: an aloof sway, as if humming a spell; the free hand stirs slow circles, the hat tip lags
    #      behind every move; now and then a nod to itself and a quick suspicious glance
    IL = 5.4
    def idle(t):
        P = dict(BASE)
        sw = wave(t, IL, 2); sw2 = wave(t, IL, 3, 1.1)
        x = 0.012 * sw
        nod = bump(t, 2.3, 0.7, 0.35)
        P["hips"] = (x, 0.003 * sw2, -0.03 + 0.004 * wave(t, IL, 6) - 0.008 * nod)
        P["hipsr"] = (2 + 1.5 * sw2, -x * 250, 4 * wave(t, IL, 1, 0.7))
        P["chest"] = (-3 + 1.5 * wave(t, IL, 6, 0.8), x * 280, 3 * wave(t, IL, 2, 0.3))
        yaw = snap([(0, 0), (3.6, 0), (3.7, -26), (4.3, -22), (4.42, 0), (IL, 0)], t)
        P["neck"] = (-2 + 6 * nod, -x * 60, 0.3 * yaw)
        P["head"] = (-5 + 8 * nod, -x * 160 + 3 * sw2, 0.5 * yaw)
        P["jaw"] = 2 + 3 * abs(wave(t, IL, 11)) * (1 - nod)          # muttering
        P["earL"] = (10 + 16 * bump(t, 3.65, 0.3), 8 + 6 * nod); P["earR"] = (10 + 10 * bump(t, 1.1, 0.3), 8 + 6 * nod)
        P["tipL"] = 4 * wave(t, IL, 4); P["tipR"] = 4 * wave(t, IL, 4, 1.0)
        # the hat tip trails the head: its pitch / roll follow the body's sway a beat late
        P["hat"] = (6 * wave(t, IL, 2, -0.9) - 10 * bump(t, 2.45, 0.8, 0.3) + 4 * wave(t, IL, 6, 0.2), -9 * wave(t, IL, 2, -1.2))
        pL = 5 * max(0.0, -sw); pR = 5 * max(0.0, sw)
        P["footL"] = (FL[0], FL[1], 0.0, pL, FL[4]); P["footR"] = (FR[0], FR[1], 0.0, pR, FR[4])
        a = 2 * math.pi * 3 * t / IL                                  # three slow circles of the free hand
        P["handL"] = add(PALM, (0.025 * math.cos(a), 0.02 * math.sin(a), 0.02 * math.sin(a) + 0.01 * nod, 0, 0, 0.2 * math.sin(a), 0, 0, 0))
        P["handR"] = add(STAFF, (0.006 * sw, 0, 0.006 * sw2, 0.05 * sw, 0, 0, 0, 0, 0))
        P["slideR"] = UP + 0.02 * nod
        return P

    # ---- run: a hurried, toes-first scurry, the staff carried forward like a lance, the hat tip streaming back
    T, v = run_cycle(sweep=0.2, duty=0.3)
    LANCE = H((-0.30, -0.05, 0.40), (-0.2, -0.75, 0.62), (0.9, 0.0, 0.3))
    def arms(P, ph, c):
        pump = 0.03 * math.cos(2 * math.pi * ph)
        P["handL"] = H((0.24, 0.03 - pump, 0.33), (0.3, -0.6, -0.6))
        P["handR"] = add(LANCE, (0, 0.008 * c, 0.006 * c, 0, 0, 0, 0, 0, 0))
        P["slideR"] = 0.22
        P["hat"] = (-14 + 6 * math.cos(2 * math.pi * (2 * ph - 0.3)), 6 * c)
    RP = dict(T=T, duty=0.3, sweep=(-0.10, 0.10), x=0.09, lift=0.05, drop=-0.045, bob=0.02, lean=12, roll=4, yaw=6,
              chest_yaw=8, head=-4, neck=(-4, 0, 0), ears=(24, 10), arms=arms)
    def run(t): return run_pose(t, BASE, RP)

    # ---- cast (goblin_mage_bolt 28/2/26): draws the staff back and up, coils, then jabs it at the target, the
    #      staff sliding forward through its fist, crystal first (the bolt leaves the crystal), and holds a beat
    (we, se), CL = ticks(28, 2, 26)
    CAST = [
        (0.10, dict(hips=(0, 0.01, -0.04), hipsr=(0, 0, -8), chest=(-6, 0, -10), head=(-8, 0, 10), jaw=4.0, earL=(18, 4), earR=(18, 4),
                    handR=H((-0.32, -0.06, 0.44), (-0.42, -0.25, 0.87), (0.9, 0.0, 0.38)), slideR=0.12, hat=(8, 0),
                    handL=H((0.24, -0.08, 0.40), (0.3, -0.9, 0.4)), footL=FL, footR=FR)),
        (0.30, dict(hips=(0, 0.025, -0.05), hipsr=(-2, 0, -22), spine=(-2, 0, -6), chest=(-9, 0, -14), neck=(0, 0, 10), head=(-8, 0, 22),
                    handR=H((-0.31, -0.04, 0.45), (-0.48, -0.2, 0.85), (0.9, 0.0, 0.4)), hat=(14, -6), jaw=1.0,
                    handL=H((0.26, -0.13, 0.41), (0.4, -0.9, 0.3)), earL=(34, 8), earR=(40, 8))),
        (we - 0.04, dict(hips=(0, 0.03, -0.055), hipsr=(-3, 0, -25), chest=(-10, 0, -16), head=(-9, 0, 25),
                         handR=H((-0.31, -0.03, 0.45), (-0.5, -0.18, 0.85), (0.9, 0.0, 0.4)))),
        (we, dict(hips=(0, -0.01, -0.04), hipsr=(4, 0, -6), chest=(0, 0, -4), head=(-6, 0, 6), jaw=12.0,
                  handR=H((-0.26, -0.10, 0.44), (-0.15, -0.6, 0.78), (0.9, 0.0, 0.3)), slideR=0.25, hat=(-6, 4))),
        (se, dict(hips=(0, -0.035, -0.045), hipsr=(8, 0, 10), spine=(3, 0, 4), chest=(4, 0, 8), neck=(0, 0, -6), head=(-4, 0, -10), jaw=18.0,
                  handR=H((-0.23, -0.13, 0.45), (-0.02, -0.92, 0.4), (0.6, 0.0, 0.8)), slideR=0.38,
                  handL=H((0.27, 0.0, 0.36), (0.6, 0.2, -0.3)), hat=(-22, 8), earL=(-8, 2), earR=(-8, 2))),
        (se + 0.14, dict(hips=(0, -0.03, -0.045), hipsr=(7, 0, 8), head=(-5, 0, -8), jaw=10.0, hat=(6, -4), slideR=0.38)),
        (CL - 0.22, dict(hips=(0, -0.01, -0.035), hipsr=(4, 0, 2), chest=(-2, 0, 0), head=(-5, 0, 0), jaw=4.0, slideR=0.2,
                         handR=H((-0.31, -0.08, 0.42), (-0.3, -0.25, 0.92), (0.9, 0.0, 0.38)), handL=PALM, hat=(-8, 2), earL=(10, 8), earR=(10, 8))),
        (CL, dict(BASE)),
    ]

    # ---- cast_aoe (goblin_mage_hex 30/2/36): sweeps the staff up high (crystal over its hat), the free hand
    #      spread toward the target ('!'), then THUMPS the foot of the staff down; the hat flops with the shock
    (awe, ase), AL = ticks(30, 2, 36)
    FRin = (-0.07, 0.04, 0.0, 0.0, -14.0)          # the right foot steps in and back: the staff comes down outside it
    HIGH = H((-0.35, -0.08, 0.48), (-0.3, -0.32, 0.9), (0.9, 0.0, 0.35))
    AOE = [
        (0.10, dict(hips=(0, 0.01, -0.045), hipsr=(4, 0, 0), chest=(0, 0, 0), head=(-2, 0, 0), footR=FR, footL=FL, jaw=3.0,
                    handR=H((-0.33, -0.07, 0.43), (-0.36, -0.14, 0.92), (0.9, 0.0, 0.38)), slideR=0.12)),
        (0.18, dict(footR=lift_step(FR, FRin, 0.03))),
        (0.26, dict(footR=FRin, hips=(0, 0.015, -0.02), hipsr=(-4, 0, -6), spine=(-3, 0, 0), chest=(-8, 0, -4), neck=(0, 0, 0), head=(-8, 0, 6),
                    handR=HIGH, slideR=0.30, handL=H((0.28, -0.12, 0.42), (0.6, -0.8, 0.2)), jaw=16.0, earL=(30, -4), earR=(42, -4),
                    hat=(16, 0))),
        (awe - 0.05, dict(hips=(0, 0.02, -0.015), hipsr=(-6, 0, -6), chest=(-10, 0, -4), head=(-9, 0, 6), slideR=0.32,
                          handR=add(HIGH, (0, 0, 0.01, 0, 0, 0, 0, 0, 0)), hat=(20, -4))),
        (awe, dict(hips=(0, -0.01, -0.06), hipsr=(8, 0, -2), chest=(6, 0, 0), head=(2, 0, 2), jaw=20.0, slideR=0.0,
                   handR=H((-0.33, -0.08, 0.43), (-0.3, -0.3, 0.9), (0.9, 0.0, 0.35)), tipzR=(0.012, -0.44, 1.0, 1), hat=(-10, 6))),
        (ase, dict(hips=(0, -0.01, -0.075), hipsr=(10, 0, -2), chest=(8, 0, 0), head=(4, 0, 2), slideR=0.0, earL=(-6, 22), earR=(-6, 22),
                   hat=(-26, 10), tipL=12.0, tipR=12.0)),
        (ase + 0.12, dict(hips=(0, -0.005, -0.05), hipsr=(6, 0, -2), chest=(2, 0, 0), head=(-2, 0, 0), jaw=8.0, hat=(14, -6), tipL=-4.0, tipR=-4.0)),
        (ase + 0.28, dict(hat=(-6, 3), earL=(10, 8), earR=(10, 8), tipL=0.0, tipR=0.0, handL=PALM, tipzR=(0.012, -0.44, 1.0, 1))),
        (AL - 0.30, dict(handR=H((-0.33, -0.07, 0.43), (-0.36, -0.14, 0.92), (0.9, 0.0, 0.38)), slideR=0.12, footR=FRin, tipzR=(0.0, -0.44, 0.0, 1),
                         hips=(0, 0.0, -0.035), hipsr=(3, 0, 0), chest=(-3, 0, 0), head=(-5, 0, 0), jaw=2.0)),
        (AL - 0.20, dict(footR=lift_step(FRin, FR, 0.03))),
        (AL - 0.12, dict(footR=FR, hat=(4, -2))),
        (AL, dict(BASE)),
    ]

    # ---- blink (goblin_mage_blink 8/2/18; it vanishes at frame 8): a squashed crouch clutching the staff, a
    #      stretched pop onto its toes; then it arrives: drops into a squash, overshoots up, settles, hat wobbling
    (bwe, bse), BL = ticks(8, 2, 18)
    TUCK = H((-0.31, -0.08, 0.41), (-0.38, -0.3, 0.87), (0.9, 0.0, 0.3))
    TOE = lambda f: (f[0], f[1], 0.0, 32.0, f[4])
    BLINK = [
        (0.07, dict(hips=(0, 0.0, -0.085), hipsr=(14, 0, 0), spine=(6, 0, 0), chest=(6, 0, 0), neck=(4, 0, 0), head=(8, 0, 0), jaw=0.0,
                    earL=(20, 30), earR=(34, 30), tipL=10.0, tipR=10.0, hat=(24, 0), handR=TUCK, slideR=0.18,
                    handL=H((0.20, -0.10, 0.34), (-0.3, -0.9, 0.2)), footL=FL, footR=FR)),
        (bwe, dict(hips=(0, 0.0, 0.005), hipsr=(-4, 0, 0), spine=(-3, 0, 0), chest=(-6, 0, 0), neck=(-4, 0, 0), head=(-10, 0, 0), jaw=12.0,
                   earL=(36, -8), earR=(36, -8), tipL=-6.0, tipR=-6.0, hat=(-24, 0), footL=TOE(FL), footR=TOE(FR), slideR=0.24)),
        (bse, dict(hips=(0, 0.0, 0.0), hipsr=(-2, 0, 0), chest=(-4, 0, 0), head=(-8, 0, 0), hat=(-28, 0))),
        (bse + 0.08, dict(hips=(0, 0.0, -0.09), hipsr=(12, 0, 0), spine=(5, 0, 0), chest=(4, 0, 0), neck=(2, 0, 0), head=(4, 0, 0), jaw=6.0,
                          footL=FL, footR=FR, earL=(0, 26), earR=(0, 26), tipL=12.0, tipR=12.0, hat=(26, 6), slideR=0.12)),
        (bse + 0.17, dict(hips=(0, 0.0, -0.015), hipsr=(0, 0, 0), spine=(0, 0, 0), chest=(-5, 0, 0), head=(-8, 0, 0), jaw=4.0,
                          earL=(20, 2), earR=(20, 2), tipL=-4.0, tipR=-4.0, hat=(-12, -6), handR=STAFF, handL=PALM)),
        (BL - 0.06, dict(hips=(0, 0.0, -0.033), hipsr=(2, 0, 0), chest=(-3, 0, 0), head=(-5, 0, 0), earL=(10, 8), earR=(10, 8),
                         tipL=0.0, tipR=0.0, hat=(5, 3))),
        (BL, dict(BASE)),
    ]

    # ---- hit: knocked back on its heels, the hat tip whips, the staff wobbles in its fist
    HIT = [
        (0.05, dict(hips=(0, 0.03, -0.035), hipsr=(-8, 0, 4), chest=(-6, 0, 0), neck=(4, 0, 0), head=(6, -6, 8), jaw=16.0,
                    earL=(30, 26), earR=(30, 26), tipL=18.0, tipR=18.0, hat=(-26, 12),
                    handR=H((-0.32, -0.08, 0.42), (-0.48, -0.32, 0.82), (0.9, 0.0, 0.4)), handL=H((0.27, 0.0, 0.40), (0.6, -0.4, 0.6)))),
        (0.14, dict(hipsr=(-3, 0, 0), head=(2, 4, -4), hat=(18, -8), jaw=8.0)),
        (0.27, dict(hips=(0, 0.005, -0.03), hipsr=(3, 0, 0), chest=(-3, 0, 0), head=(-6, 0, 0), earL=(12, 6), earR=(12, 6), tipL=-4.0, tipR=-4.0,
                    hat=(-8, 4), handR=STAFF, handL=PALM, jaw=3.0)),
        (0.38, dict(hat=(4, -2), tipL=0.0, tipR=0.0)),
        (0.50, dict(BASE)),
    ]

    # ---- death: a dizzy half turn, the staff slips away, knees fold, it sits down hard and flops onto its back;
    #      the hat tip flops last
    DEATH = [
        (0.07, dict(hips=(0, 0.02, -0.03), hipsr=(-6, 4, 6), chest=(-6, 0, 0), head=(4, 6, 10), jaw=20.0, earL=(34, 28), earR=(34, 28),
                    hat=(-24, 10), footL=FL, footR=FR, handL=H((0.29, 0.0, 0.40), (0.7, -0.3, 0.6)))),
        (0.30, dict(hips=(0, 0.04, -0.04), hipsr=(-2, -6, 24), chest=(-2, -4, 10), head=(6, -8, 14), hat=(14, -14),
                    handR=H((-0.33, -0.08, 0.43), (-0.48, -0.32, 0.82), (0.9, 0.0, 0.4)),
                    footL=(0.10, -0.01, 0.0, 0.0, 30.0), footR=(-0.12, 0.05, 0.0, 0.0, 10.0))),
        (0.55, dict(hips=(0, 0.07, -0.08), hipsr=(4, 6, 30), chest=(4, 4, 6), head=(10, 8, 4), hat=(-16, 14), jaw=10.0,
                    footL=(0.10, -0.01, 0.0, 26.0, 30.0), footR=(-0.12, 0.05, 0.0, 26.0, 10.0),
                    handL=H((0.30, 0.02, 0.32), (0.6, -0.6, -0.4)), handR=H((-0.30, 0.02, 0.32), (-0.6, -0.6, -0.4)), gripR=0.0)),
        (0.49, dict(handR=H((-0.33, -0.06, 0.40), (-0.6, -0.3, 0.74), (0.9, 0.0, 0.4)))),
        (0.85, dict(hips=(0, 0.12, -0.10), hipsr=(-20, 0, 28), chest=(-4, 0, 4), head=(0, 0, 4))),
        (1.10, dict(hips=(0, 0.24, -0.10), hipsr=(-82, 0, 28), spine=(-8, 0, 0), chest=(-6, 0, 0), neck=(2, 0, 0), head=(4, 0, 0),
                    handL=H((0.33, 0.02, 0.38), (0.6, -0.6, 0.0)), handR=H((-0.33, 0.02, 0.38), (-0.6, -0.6, 0.0)), jaw=12.0,
                    earL=(10, -6), earR=(10, -6), hat=(10, 0),
                    footL=(0.10, 0.12, 0.12, -45, 30), footR=(-0.12, 0.14, 0.12, -45, 10))),
        (1.24, dict(hips=(0, 0.25, -0.07), hat=(-18, 6), footL=(0.12, 0.10, 0.06, -65, 30), footR=(-0.13, 0.12, 0.06, -65, 10))),
        (1.36, dict(hips=(0, 0.25, -0.10), hat=(12, -4), footL=(0.12, 0.10, 0.02, -80, 30), footR=(-0.13, 0.12, 0.02, -80, 10),
                    earL=(30, 34), earR=(30, 34), jaw=20.0)),
        (1.60, dict(hat=(-6, 2))),
        (1.90, dict(hat=(18, 0))),
        (2.20, dict(hat=(18, 0))),
    ]
    death_drop = dict(t0=0.50, t1=0.78, final={"R": lying((-0.36, 0.05, 0.05), (-0.5, -1, 0))})

    def crystal(S):
        """The crystal (top of the staff) at the bolt's release: forward, up, side (+left), goblin units."""
        M = S.M["attach_weapon.R"]; p = M @ Vector((0, 0.56, 0))
        return "crystal [%.2f, %.2f, %.2f]" % (-p.y, p.z, p.x)

    clips = {
        "idle": dict(fn=idle, length=IL, loop=True, shots=[0.0, 1.0, 2.4, 2.7, 3.8, 4.8]),
        "run": dict(fn=run, length=2 * T, loop=True, ground_v=v, shots=[2 * T * k / 6 for k in range(6)]),
        "cast": dict(fn=lambda t: keyed(BASE, CAST, t), length=CL, marks=(we, se), shots=[0.0, 0.1, 0.3, we - 0.04, we, se, se + 0.14, CL - 0.15],
                     probe={"crystal": crystal}, probe_t={"crystal": se}),
        "cast_aoe": dict(fn=lambda t: keyed(BASE, AOE, t), length=AL, marks=(awe, ase),
                         shots=[0.0, 0.18, 0.26, awe - 0.05, awe, ase, ase + 0.12, ase + 0.28, AL - 0.2]),
        "blink": dict(fn=lambda t: keyed(BASE, BLINK, t), length=BL, marks=(bwe, bse), shots=[0.0, 0.07, bwe, bse, bse + 0.08, bse + 0.17, BL]),
        "hit": dict(fn=lambda t: keyed(BASE, HIT, t), length=0.5, shots=[0.0, 0.05, 0.14, 0.27, 0.38]),
        "death": dict(fn=lambda t: keyed(BASE, DEATH, t), length=2.2, drop=death_drop, ground_from=0.8, ground_lock=1.1, feet_follow=0.9,
                      shots=[0.07, 0.3, 0.55, 0.85, 1.1, 1.24, 1.36, 2.2]),
    }
    return {"clips": clips, "view": 1.9}


# =================================================================== CHIEF
def chief(ns):
    keyed, run_pose, bump, wave, snap, periodic, smooth, lerp, add, lying, Vector = (ns[k] for k in (
        "keyed", "run_pose", "bump", "wave", "snap", "periodic", "smooth", "lerp", "add", "lying", "Vector"))
    # Twin cleavers (0.43 blades). Each blade's broad side hangs below its spine: Z points out of the body side,
    # so the fist sits outside the grip. The head never pitches back past -2 degrees: the fur mantle and the cape
    # sit right behind it (that was the stand-in's cape-through-the-head).
    def cR(p, d, out=(-1.0, 0.0, 0.0)): return H(p, d, out)
    def cL(p, d, out=(1.0, 0.0, 0.0)): return H(p, d, out)
    # the cleavers extend the forearms (alignL/R: a straight wrist keeps the short handle inside the forearm),
    # never dipping below the floor (floorL/R); the wrists are placed, the blades follow the arms
    LOW_R = cR((-0.27, -0.10, 0.36), (-0.6, -0.66, -0.46))
    LOW_L = cL((0.27, -0.10, 0.36), (0.6, -0.66, -0.46))
    FLOOR = (0.12, 0.43)            # the broad blade hangs ~0.1 below its axis: its lower corner stays above the floor
    CHOKE = 0.06                    # the fist a little up the handle: the handle end clears the elbow
    BASE = dict(hips=(0.0, 0.0, -0.05), hipsr=(5, 0, 0), spine=(2, 0, 0), chest=(-1, 0, 0), neck=(2, 0, 0), head=(0, 0, 0),
                jaw=2.0, earL=(4, 12), earR=(4, 12), tipL=0.0, tipR=0.0,
                footL=(0.15, -0.03, 0.0, 0.0, 18.0), footR=(-0.15, 0.04, 0.0, 0.0, -18.0),
                handL=LOW_L, handR=LOW_R, slideL=CHOKE, slideR=CHOKE, twL=0.0, twR=0.0, wsL=0.0, wsR=0.0, gripL=0.0, gripR=0.0,
                elbowL=(1.0, 0.3, -0.3), elbowR=(-1.0, 0.3, -0.3), alignL=1.0, alignR=1.0, floorL=FLOOR, floorR=FLOOR)
    FL, FR = BASE["footL"], BASE["footR"]

    # ---- idle: a big slow chest heave, swaggering weight shifts, a growl with a head shake, and the right
    #      cleaver comes up to point at you, then drops back
    IL = 5.6
    def idle(t):
        P = dict(BASE)
        br = wave(t, IL, 3)
        x = periodic([(0, 0.0), (1.4, 0.016), (2.6, 0.012), (3.6, -0.014), (4.8, -0.012), (IL, 0.0)], t, IL)
        growl = bump(t, 1.9, 0.9, 0.25)
        point = bump(t, 3.7, 1.3, 0.3)
        P["hips"] = (x, 0.0, -0.05 + 0.005 * br - 0.01 * growl)
        P["hipsr"] = (5 + 1.2 * br, -x * 200, 5 * wave(t, IL, 1, 0.4))
        P["chest"] = (-1 - 3 * br + 3 * growl, x * 220, -3 * wave(t, IL, 1, 0.4) - 6 * point)
        P["spine"] = (2 - 1.2 * br, 0, 0)
        shake = growl * math.sin(2 * math.pi * 5 * t)
        P["neck"] = (2 + 3 * growl, 0, 2 * shake + 3 * point)
        P["head"] = (4 * growl - 1.0 * br, -x * 60 + 1.5 * shake, 2 * shake + 2 * point)
        P["jaw"] = 2 + 4 * growl * (0.6 + 0.4 * abs(math.sin(2 * math.pi * 9 * t)))    # the tusks allow only a small growl
        P["earL"] = (4 - 16 * growl, 12 + 8 * growl); P["earR"] = (4 - 16 * growl + 12 * bump(t, 0.6, 0.3), 12 + 8 * growl)
        P["tipL"] = 5 * growl; P["tipR"] = 5 * growl
        pL = 7 * max(0.0, -x) / 0.016; pR = 7 * max(0.0, x) / 0.016
        P["footL"] = (FL[0], FL[1], 0.0, pL, FL[4]); P["footR"] = (FR[0], FR[1], 0.0, pR, FR[4])
        P["handR"] = lerp(add(LOW_R, (0, 0.006 * br, 0.004 * br, 0, 0, 0, 0, 0, 0)), cR((-0.25, -0.13, 0.36), (-0.3, -0.95, 0.0)), point)
        P["handL"] = add(LOW_L, (0, 0.006 * br, 0.004 * br, 0, 0, 0.1 * growl, 0, 0, 0))
        return P

    # ---- run: a heavy, stomping charge, leaning in, cleavers held low and out, cape streaming behind
    T, v = run_cycle(sweep=0.21, duty=0.33)
    def arms(P, ph, c):
        pump = 0.03 * math.cos(2 * math.pi * ph)
        P["handL"] = cL((0.27, -0.08 - pump, 0.36), (0.6, -0.66, -0.46))
        P["handR"] = cR((-0.27, -0.08 + pump, 0.36), (-0.6, -0.66, -0.46))
    RP = dict(T=T, duty=0.33, sweep=(-0.105, 0.105), x=0.13, lift=0.045, drop=-0.06, bob=0.024, lean=14, roll=5, yaw=8,
              chest_yaw=-8, head=4, neck=(2, 0, 0), ears=(10, 14), toe=14.0, peel=24, arms=arms)
    def run(t):
        P = run_pose(t, BASE, RP)
        P["jaw"] = 3 + 2 * math.sin(4 * math.pi * t / T)
        return P

    # ---- attack_1 (goblin_chief_jab 11/4/17): a quick hack: the right cleaver snaps up beside the ear and
    #      chops down and across in front, the body twisting into it
    (we, se), AL1 = ticks(11, 4, 17)
    A1 = [
        (0.06, dict(hips=(0, 0.01, -0.055), hipsr=(5, 0, -10), chest=(-2, 0, -12), neck=(2, 0, 4), head=(0, 0, 3), jaw=4.0, earL=(18, 10), earR=(18, 10),
                    handR=cR((-0.31, 0.0, 0.38), (-0.55, 0.2, 0.8)), alignR=0.0, footL=FL, footR=FR)),
        (we, dict(hips=(0, 0.015, -0.06), hipsr=(4, 0, -16), chest=(-3, 0, -18), neck=(2, 0, 10), head=(0, 0, 4),
                  handR=cR((-0.31, 0.02, 0.38), (-0.6, 0.3, 0.74)), jaw=4.0)),
        (we + 0.035, dict(hips=(0, -0.02, -0.065), hipsr=(6, 0, 6), spine=(4, 0, 0), chest=(4, 0, 8), head=(2, 0, -2), jaw=6.0,
                          handR=cR((-0.25, -0.12, 0.37), (-0.3, -0.85, 0.4)), alignR=0.5)),
        (se, dict(hips=(0, -0.03, -0.075), hipsr=(6, 0, 18), spine=(8, 0, 4), chest=(5, 0, 16), neck=(2, 0, -12), head=(3, 0, -4), jaw=6.0,
                  handR=cR((-0.27, -0.12, 0.34), (-0.1, -0.85, -0.5)), alignR=1.0)),
        (se + 0.08, dict(hips=(0, -0.035, -0.08), hipsr=(7, 0, 21), spine=(9, 0, 4), chest=(6, 0, 18), handR=cR((-0.27, -0.12, 0.33), (-0.05, -0.85, -0.52)))),
        (AL1 - 0.16, dict(hips=(0, -0.01, -0.055), hipsr=(6, 0, 6), spine=(3, 0, 0), chest=(-1, 0, 4), head=(1, 0, -1), jaw=3.0,
                          handR=LOW_R, handL=LOW_L, earL=(6, 12), earR=(6, 12))),
        (AL1, dict(BASE)),
    ]

    # ---- attack_2 (goblin_chief_lunge 32/10/36): crouches, both cleavers spread wide and raised, a roar ('!');
    #      bounds forward, both cleavers chop down crossing in front, lands heavy, stomps back to its spot
    (owe, ose), AL2 = ticks(32, 10, 36)
    FLf, FRf = (0.15, -0.20, 0.0, 0.0, 18.0), (-0.15, -0.16, 0.0, 0.0, -18.0)
    WIDE_R = cR((-0.32, 0.0, 0.38), (-0.78, 0.3, 0.55)); WIDE_L = cL((0.32, 0.0, 0.38), (0.78, 0.3, 0.55))
    A2 = [
        (0.14, dict(hips=(0, 0.03, -0.085), hipsr=(12, 0, 0), spine=(4, 0, 0), chest=(0, 0, 0), neck=(2, 0, 0), head=(0, 0, 0),
                    handR=WIDE_R, handL=WIDE_L, alignR=0.0, alignL=0.0, jaw=6.0, earL=(-10, 26), earR=(-10, 26), footL=FL, footR=FR)),
        (0.30, dict(hipsr=(12, -3, 6), head=(0, 1, 2), jaw=6.5)),
        (0.42, dict(hipsr=(12, 3, -6), head=(0, -1, -2))),
        (owe - 0.06, dict(hips=(0, 0.04, -0.095), hipsr=(12, 0, 0), spine=(6, 0, 0), head=(2, 0, 0), jaw=5.0,
                          handR=cR((-0.32, 0.02, 0.38), (-0.75, 0.4, 0.53)), handL=cL((0.32, 0.02, 0.38), (0.75, 0.4, 0.53)), footL=FL, footR=FR)),
        (owe, dict(hips=(0, -0.02, -0.03), hipsr=(18, 0, 0), footL=(FL[0], FL[1], 0.0, 30.0, FL[4]), footR=(FR[0], FR[1], 0.0, 30.0, FR[4]))),
        (owe + 0.08, dict(hips=(0, -0.11, 0.07), hipsr=(10, 0, 0), spine=(6, 0, 0), chest=(2, 0, 0), jaw=6.0,
                          footL=(0.15, -0.12, 0.11, 20.0, 18.0), footR=(-0.15, -0.10, 0.11, 20.0, -18.0),
                          handR=cR((-0.31, -0.04, 0.38), (-0.7, -0.2, 0.68)), handL=cL((0.31, -0.04, 0.38), (0.7, -0.2, 0.68)))),
        (owe + 0.16, dict(hips=(0, -0.19, -0.06), hipsr=(8, 0, 0), spine=(12, 0, 0), chest=(6, 0, 0), head=(4, 0, 0), jaw=4.0,
                          footL=FLf, footR=FRf, alignR=1.0, alignL=1.0,
                          handR=cR((-0.21, -0.15, 0.34), (0.15, -0.8, -0.55)), handL=cL((0.21, -0.15, 0.34), (-0.15, -0.8, -0.55)))),
        (ose, dict(hips=(0, -0.20, -0.10), hipsr=(9, 0, 0), spine=(14, 0, 0), chest=(7, 0, 0), head=(5, 0, 0), jaw=3.0,
                   handR=cR((-0.21, -0.15, 0.32), (0.2, -0.8, -0.55)), handL=cL((0.21, -0.15, 0.32), (-0.2, -0.8, -0.55)),
                   earL=(-4, 30), earR=(-4, 30))),
        (ose + 0.14, dict(hips=(0, -0.19, -0.08), hipsr=(8, 0, 0), spine=(6, 0, 0), chest=(2, 0, 0), head=(3, 0, 0), jaw=4.0,
                          handR=LOW_R, handL=LOW_L, earL=(4, 14), earR=(4, 14))),
        (ose + 0.24, dict(hips=(0, -0.12, -0.06), hipsr=(10, 0, 2), footR=FRf, footL=FLf)),
        (ose + 0.31, dict(footR=lift_step(FRf, FR, 0.025), hips=(0, -0.08, -0.055), hipsr=(10, 0, 4))),
        (ose + 0.38, dict(footR=FR, footL=FLf)),
        (ose + 0.47, dict(footL=lift_step(FLf, FL, 0.025), hips=(0, -0.03, -0.05), hipsr=(8, 0, -2))),
        (ose + 0.54, dict(footL=FL, hips=(0, 0.0, -0.055), hipsr=(6, 0, 0))),
        (AL2, dict(BASE)),
    ]

    # ---- hit: a heavy shrug back, then an angry snort forward (it hardly gives: poise)
    HIT = [
        (0.06, dict(hips=(0, 0.025, -0.05), hipsr=(-2, 0, -6), chest=(-8, 0, -4), neck=(6, 0, 0), head=(4, 1, -2), jaw=5.0,
                    earL=(26, 24), earR=(26, 24), tipL=12.0, tipR=12.0)),
        (0.18, dict(hips=(0, 0.0, -0.06), hipsr=(9, 0, 2), chest=(2, 0, 2), head=(5, 0, 1), jaw=6.0, earL=(-12, 18), earR=(-12, 18))),
        (0.34, dict(hips=(0, 0.0, -0.05), hipsr=(5, 0, 0), chest=(-1, 0, 0), head=(0, 0, 0), jaw=3.0, earL=(4, 12), earR=(4, 12),
                    tipL=0.0, tipR=0.0)),
        (0.50, dict(BASE)),
    ]

    # ---- death: staggers, the cleavers fall, drops to its knees, sways, and topples forward onto its face
    #      (forward: the cape stays on top, never under it)
    DEATH = [
        (0.08, dict(hips=(0, 0.025, -0.05), hipsr=(-4, 0, 0), chest=(-6, 0, 0), head=(3, 0, 0), jaw=6.0, earL=(30, 26), earR=(30, 26),
                    footL=FL, footR=FR, handR=cR((-0.29, -0.06, 0.38), (-0.7, -0.6, 0.0)), handL=cL((0.29, -0.06, 0.38), (0.7, -0.6, 0.0)))),
        (0.30, dict(hips=(0, 0.03, -0.07), hipsr=(4, 4, -6), head=(4, 2, -2), footR=(-0.15, 0.06, 0.03, 15, -18))),
        (0.40, dict(footR=(-0.15, 0.08, 0.0, 0.0, -18.0))),
        (0.62, dict(hips=(0, 0.0, -0.10), hipsr=(10, -4, 4), chest=(4, 0, 0), head=(5, -2, 2), jaw=5.0, alignL=0.0, alignR=0.0,
                    footL=(0.15, -0.03, 0.0, 26.0, 18.0), footR=(-0.15, 0.08, 0.0, 26.0, -18.0),
                    handR=cR((-0.30, 0.0, 0.30), (-0.5, -0.5, -0.4)), handL=cL((0.30, 0.0, 0.30), (0.5, -0.5, -0.4)))),
        (0.90, dict(hipsr=(6, 4, -4), head=(4, 2, -2))),
        (1.10, dict(hips=(0, -0.06, -0.10), hipsr=(26, 0, 0), chest=(6, 0, 0), head=(6, 0, 0))),
        (1.36, dict(hips=(0, -0.30, -0.15), hipsr=(94, 0, 0), spine=(4, 0, 0), chest=(2, 0, 0), neck=(-2, 0, 0), head=(-2, 0, 2),
                    handR=H((-0.33, 0.02, 0.36), (-0.4, -0.7, -0.4)), handL=H((0.33, 0.02, 0.36), (0.4, -0.7, -0.4)), jaw=6.0,
                    earL=(20, 30), earR=(20, 30),
                    footL=(0.13, -0.13, 0.03, 75.0, 18.0), footR=(-0.13, -0.13, 0.03, 75.0, -18.0))),
        (1.48, dict(hips=(0, -0.30, -0.13), footL=(0.13, -0.12, 0.015, 82.0, 18.0), footR=(-0.13, -0.12, 0.015, 82.0, -18.0))),
        (1.60, dict(hips=(0, -0.30, -0.15), jaw=7.0, earL=(30, 36), earR=(30, 36))),
        (2.20, dict(hips=(0, -0.30, -0.15))),
    ]
    death_drop = dict(t0=0.50, t1=0.74, final={"R": lying((-0.40, -0.18, 0.025), (-0.4, -1, 0)),
                                               "L": lying((0.42, -0.10, 0.025), (0.6, -1, 0))})

    clips = {
        "idle": dict(fn=idle, length=IL, loop=True, shots=[0.0, 1.0, 2.15, 2.6, 4.2, 5.0]),
        "run": dict(fn=run, length=2 * T, loop=True, ground_v=v, shots=[2 * T * k / 6 for k in range(6)]),
        "attack_1": dict(fn=lambda t: keyed(BASE, A1, t), length=AL1, marks=(we, se), shots=[0.0, 0.06, we, we + 0.035, se, se + 0.08, AL1 - 0.1]),
        "attack_2": dict(fn=lambda t: keyed(BASE, A2, t), length=AL2, marks=(owe, ose),
                         shots=[0.0, 0.14, 0.3, owe - 0.06, owe + 0.08, owe + 0.16, ose, ose + 0.3, ose + 0.5, AL2]),
        "hit": dict(fn=lambda t: keyed(BASE, HIT, t), length=0.5, shots=[0.0, 0.06, 0.18, 0.34]),
        "death": dict(fn=lambda t: keyed(BASE, DEATH, t), length=2.2, drop=death_drop, ground_from=1.0, ground_lock=1.36, feet_follow=1.2,
                      shots=[0.08, 0.3, 0.62, 0.9, 1.1, 1.36, 1.6, 2.2]),
    }
    return {"clips": clips, "view": 2.0}


VARIANT_CLIPS = {"archer": archer, "mage": mage, "knight": knight, "chief": chief}
