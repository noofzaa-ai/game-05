"""Synthesizes every zorx sound effect into audio/sfx/*.ogg (mono Ogg Vorbis).

    python tools/audio/make_sfx.py            # all sounds
    python tools/audio/make_sfx.py hit_ ui_   # only names starting with these prefixes

Everything here is made from scratch (noise, sines, filters); no recordings are used, so there is
nothing to credit. Hits are built in three layers: a TRANSIENT (2-6 ms crack so it reads instantly),
a BODY (pitched thump + mid smack: the weight) and a TAIL (low rumble / room: the size).
Loudness is set per sound with dsp.level() (loudest 50 ms RMS), so the mix in data/audio/events.json
starts from consistent levels.
EXTENDING: write a function returning a mono array, register it in SOUNDS with its loudness target,
then map it to an event in data/audio/events.json.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F403

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio", "sfx")
ROOM = make_ir(0.6, 0.35, rng_of(7))  # small room for body sounds
HALL = make_ir(2.2, 1.6, rng_of(8), bright=0.35)  # big space for ultimates


# ================================================================== building blocks

def click(rng, dur=0.004, fc=3000.0, tone=3200.0):
    """The very first milliseconds of an impact: a crack the ear locks on to."""
    n = hp(white(dur * 4, rng), fc, 2) * exp_decay(dur * 4, dur * 0.4, 0.0)
    b = sine(tone, dur * 4) * exp_decay(dur * 4, dur * 0.5, 0.0) * 0.5
    return n + b


def thump(f0, f1, pitch_tau, decay, dur=None, attack=0.0015):
    dur = dur or decay * 6
    return sine(glide(f0, f1, dur, pitch_tau), dur) * exp_decay(dur, decay, attack)


def smack(rng, lo, hi, decay, dur=None):
    dur = dur or decay * 6
    return bp(white(dur, rng), lo, hi, 2) * exp_decay(dur, decay, 0.0005)


def rumble(rng, dur, fc, decay):
    return lp(brown(dur, rng), fc, 2) * exp_decay(dur, decay, 0.004)


def grains(rng, dur, count, lo, hi, decay=0.006, spread=1.0, amp_fall=3.0):
    """Many tiny crunchy grains (dirt, gravel, bone crunch, rubble). Times skew early."""
    out = np.zeros(n_of(dur))
    g = bp(white(decay * 8, rng), lo, hi, 2) * exp_decay(decay * 8, decay, 0.0)
    for _ in range(count):
        u = rng.random() ** 1.8 * spread
        start = n_of(u * dur * 0.9)
        amp = rng.uniform(0.3, 1.0) * np.exp(-amp_fall * u)
        seg = g * amp * (1 if rng.random() < 0.5 else -1)
        end = min(len(out), start + len(seg))
        out[start:end] += seg[: end - start]
    return out


def whoosh(rng, dur, c0, c_peak, c1, width=0.5, peak=0.4, sharp=1.6, source="white"):
    noise = pink(dur, rng) if source == "pink" else white(dur, rng)
    cent = lambda u: (c0 * (c_peak / c0) ** (u / peak)) if u < peak else (c_peak * (c1 / c_peak) ** ((u - peak) / (1 - peak)))
    return sweep_band(noise, cent, width) * bell_env(dur, peak, sharp)


def flutter(rng, dur, rate=28.0, fc=1400.0):
    """Cloth flapping: amplitude-modulated low-passed noise."""
    t = time(dur)
    am = 0.55 + 0.45 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) * np.sin(2 * np.pi * rate * 0.37 * t)
    return lp(white(dur, rng), fc, 2) * am


def metal(rng, base, dur, decay, ratios=(1.0, 2.61, 4.35, 6.8, 9.2), amps=(1.0, 0.7, 0.45, 0.3, 0.2)):
    freqs = [base * r for r in ratios]
    decays = [decay / (1 + 0.45 * i) for i in range(len(ratios))]
    return partials(freqs, amps, decays, dur, rng, detune=0.01)


def crackle(rng, dur, rate=60.0, lo=1500.0, hi=7000.0):
    """Fire crackle: sparse sharp pops."""
    out = np.zeros(n_of(dur))
    count = int(rate * dur)
    pop = hp(white(0.01, rng), lo, 2) * exp_decay(0.01, 0.0015, 0.0)
    for _ in range(count):
        start = rng.integers(0, max(1, len(out) - len(pop)))
        out[start:start + len(pop)] += pop * rng.uniform(0.2, 1.0) * (1 if rng.random() < 0.5 else -1)
    return bp(out, lo * 0.7, hi, 1)


def creature(rng, dur, f0_curve, vowel, rough=0.3, breath=0.25):
    """A monster vocal: jittery pulse source through vowel formants, plus breath."""
    n = n_of(dur)
    jitter = np.cumsum(rng.standard_normal(n)) / np.sqrt(n) * 0.06
    f0 = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(f0_curve)), f0_curve) * (1 + jitter)
    src = pulse(f0, width=0.3, partials=60)
    sub = pulse(f0 * 0.5, width=0.4, partials=40) * rough  # growl subharmonic
    src = src + sub + breath * white(dur, rng)
    shaped = formant(src, vowel)
    return drive(shaped * 2.0, 1.6)


VOWEL_AH = [(720, 140, 1.0), (1240, 160, 0.55), (2650, 220, 0.25)]
VOWEL_UH = [(560, 120, 1.0), (1000, 150, 0.5), (2500, 220, 0.2)]
VOWEL_OH = [(480, 110, 1.0), (850, 130, 0.6), (2400, 220, 0.18)]
VOWEL_AW = [(620, 160, 1.0), (980, 160, 0.7), (2550, 250, 0.2)]
VOWEL_EH = [(560, 120, 0.9), (1720, 180, 0.55), (2500, 220, 0.3)]


def body_fall(rng, heavy=1.0):
    dur = 0.7
    a = thump(110, 45, 0.03, 0.07 * heavy, dur)
    b = at(thump(90, 40, 0.03, 0.06, 0.4), 0.085, dur) * 0.6
    dirt = grains(rng, dur, 40, 600, 5000, 0.005, 0.5) * 0.35
    cloth = lp(white(dur, rng), 1800, 2) * exp_decay(dur, 0.09, 0.004) * 0.2
    x = mix(a, b, dirt, cloth, click(rng, 0.003, 2000, 1500) * 0.4)
    return reverb(x, ROOM, 0.12)


# ================================================================== movement

def footstep(rng, run=False):
    dur = 0.16 if run else 0.13
    body = thump(95 if run else 85, 55, 0.012, 0.022 if run else 0.018, dur) * (0.8 if run else 0.6)
    crunch = grains(rng, dur, 14 if run else 9, 700, 5200, 0.0045, 0.45, 5.0) * (0.55 if run else 0.4)
    scuff = bp(white(dur, rng), 300, 2500, 1) * exp_decay(dur, 0.03 if run else 0.022, 0.003) * 0.25
    x = mix(body, crunch, scuff, click(rng, 0.002, 2500, 1100) * 0.15)
    return fade(x, 0.0005, 0.02)


def jump(rng):
    dur = 0.3
    push = smack(rng, 250, 2000, 0.03, dur) * 0.5
    air = whoosh(rng, dur, 500, 1500, 900, 0.6, 0.35) * 0.6
    return mix(push, air, flutter(rng, dur, 22, 1500) * bell_env(dur, 0.3) * 0.25)


def land(rng):
    dur = 0.4
    x = mix(thump(120, 48, 0.02, 0.055, dur), grains(rng, dur, 30, 800, 5500, 0.005, 0.5) * 0.45,
            rumble(rng, dur, 250, 0.08) * 0.4, click(rng, 0.003, 2000, 1200) * 0.25)
    return reverb(x, ROOM, 0.08)


def dodge(rng):
    dur = 0.3
    return mix(whoosh(rng, dur, 450, 2600, 1100, 0.5, 0.33, 1.4),
               flutter(rng, dur, 30, 1800) * bell_env(dur, 0.3) * 0.35,
               smack(rng, 300, 1800, 0.02, dur) * 0.3)


def launch(rng):
    dur = 0.4
    return whoosh(rng, dur, 350, 1800, 1500, 0.55, 0.7, 1.3)


def get_up(rng):
    dur = 0.35
    return mix(flutter(rng, dur, 18, 1200) * bell_env(dur, 0.4) * 0.6, grains(rng, dur, 8, 600, 4000, 0.004) * 0.3)


# ================================================================== swings

SWINGS = {
    # weapon: (duration light, heavy), band (start, peak, end) for light, width, extra layer
    "fists": ((0.16, 0.28), (700, 1900, 900), 0.55),
    "blade": ((0.2, 0.36), (1400, 4300, 2300), 0.45),
    "dagger": ((0.12, 0.2), (2300, 6000, 3400), 0.4),
    "spear": ((0.18, 0.32), (600, 2700, 2400), 0.5),
    "hammer": ((0.3, 0.52), (260, 950, 420), 0.7),
}


def swing(rng, weapon, heavy=False):
    durs, band, width = SWINGS[weapon]
    dur = durs[1] if heavy else durs[0]
    scale = 0.75 if heavy else 1.0
    c0, cp, c1 = (b * scale for b in band)
    peak = 0.72 if weapon == "spear" else 0.38
    x = whoosh(rng, dur, c0, cp, c1, width, peak, 1.5)
    if weapon == "fists":
        x = mix(x, flutter(rng, dur, 32, 1600) * bell_env(dur, 0.35) * 0.35)
    elif weapon == "blade":
        ring = metal(rng, 3150 if not heavy else 2700, dur, 0.09 if not heavy else 0.14, (1.0, 1.53, 2.31, 3.1), (0.6, 0.45, 0.3, 0.2))
        x = mix(x, ring * bell_env(dur, 0.45, 1.0) * 0.18)
    elif weapon == "dagger":
        x = mix(x, whoosh(rng, dur, 3000, 7000, 4000, 0.3, 0.5) * 0.4)
    elif weapon == "spear":
        t = time(dur)
        shaft = lp(white(dur, rng), 900, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 46 * t)) * bell_env(dur, 0.6) * 0.35
        x = mix(x, shaft)
    elif weapon == "hammer":
        vw = sine(glide(60 if heavy else 75, 105 if heavy else 120, dur), dur) * bell_env(dur, 0.45, 1.3) * 0.5
        x = mix(x, vw, whoosh(rng, dur, 150, 500, 220, 0.8, 0.45, source="pink") * 0.6)
    if heavy:
        x = mix(x, whoosh(rng, dur, c0 * 0.5, cp * 0.45, c1 * 0.5, 0.8, 0.42, source="pink") * 0.45)
    return fade(x, 0.003, 0.02)


def monster_swipe(rng):
    dur = 0.45
    x = mix(whoosh(rng, dur, 200, 900, 300, 0.8, 0.45, 1.4, "pink"),
            whoosh(rng, dur, 500, 1800, 700, 0.6, 0.45) * 0.5,
            creature(rng, dur, [70, 85, 60], VOWEL_AW, 0.6, 0.4) * bell_env(dur, 0.4) * 0.25)
    return fade(x, 0.003, 0.03)


def monster_bite(rng):
    dur = 0.32
    clack = mix(click(rng, 0.005, 1200, 1800), at(click(rng, 0.004, 1500, 2200), 0.06, 0.1) * 0.8)
    snap = smack(rng, 900, 3500, 0.012, dur) * 0.7
    huff = creature(rng, dur, [180, 220, 150], VOWEL_EH, 0.2, 0.8) * ar(dur, 0.01, 0.2) * 0.35
    return mix(at(clack, 0.0, dur), snap, huff)


# ================================================================== hits

def hit_light(rng):
    dur = 0.38
    x = mix(click(rng, 0.003, 3500, 3000) * 0.7,
            thump(rng.uniform(150, 175), 68, 0.028, 0.065, dur),
            drive(smack(rng, 700, 2600, 0.028, dur) * 1.5, 2.0) * 0.45,
            rumble(rng, dur, 320, 0.1) * 0.3)
    return trim_tail(reverb(drive(x, 1.4), ROOM, 0.1))


def hit_heavy(rng):
    dur = 0.65
    x = mix(click(rng, 0.004, 3000, 2600) * 0.9,
            thump(rng.uniform(135, 155), 44, 0.045, 0.13, dur),
            thump(70, 46, 0.08, 0.22, dur) * 0.55,
            drive(smack(rng, 420, 2200, 0.045, dur) * 1.5, 2.5) * 0.5,
            grains(rng, 0.12, 18, 1500, 5500, 0.004, 0.6) * 0.3,
            rumble(rng, dur, 220, 0.25) * 0.45)
    return trim_tail(reverb(drive(x, 2.2), ROOM, 0.14))


def hit_crit(rng):
    dur = 1.1
    crack = hp(white(0.05, rng), 4000, 2) * exp_decay(0.05, 0.006, 0.0)
    ring = metal(rng, 2150, dur, 0.35, (1.0, 1.55, 2.42, 3.3), (0.6, 0.5, 0.35, 0.25))
    boom = thump(66, 42, 0.12, 0.38, dur)
    x = mix(hit_heavy(rng) * 0.9, crack * 0.9, ring * 0.2, boom * 0.7)
    return trim_tail(reverb(drive(x, 1.6), HALL, 0.12))


def sweet_slice(rng):
    dur = 0.2
    sw = whoosh(rng, dur, 7000, 5000, 2500, 0.45, 0.12, 1.2)
    ring = metal(rng, 4100, dur, 0.06, (1.0, 1.54, 2.2), (0.6, 0.4, 0.25))
    return mix(sw, ring * 0.25, click(rng, 0.002, 5000, 6000) * 0.4)


def sweet_pierce(rng):
    dur = 0.18
    return mix(smack(rng, 1000, 3200, 0.02, dur), thump(900, 600, 0.01, 0.025, dur) * 0.5, click(rng, 0.002, 3000, 2500) * 0.5)


def sweet_crush(rng):
    dur = 0.45
    return mix(grains(rng, 0.2, 40, 300, 1800, 0.007, 0.7) * 0.8, thump(88, 44, 0.05, 0.18, dur), rumble(rng, dur, 180, 0.2) * 0.5)


# ================================================================== guard

def guard_block(rng):
    dur = 0.6
    x = mix(click(rng, 0.004, 2500, 2800) * 0.8,
            metal(rng, 430, dur, 0.28, (1.0, 2.6, 4.35, 6.86, 9.53), (0.9, 0.7, 0.5, 0.35, 0.2)) * 0.55,
            thump(130, 80, 0.02, 0.05, dur) * 0.7,
            smack(rng, 1000, 4500, 0.018, dur) * 0.5)
    return trim_tail(reverb(x, ROOM, 0.15))


def guard_break(rng):
    dur = 1.2
    crack = drive(bp(white(0.15, rng), 700, 6500, 2) * exp_decay(0.15, 0.03, 0.0) * 2.0, 4.0)
    shatter = np.zeros(n_of(dur))
    for _ in range(45):
        u = rng.random() ** 2.0 * 0.4
        f = rng.uniform(2200, 9000)
        ping = sine(f, 0.12) * exp_decay(0.12, rng.uniform(0.015, 0.06), 0.0) * rng.uniform(0.1, 0.4) * np.exp(-u * 4)
        s = n_of(u)
        shatter[s:s + len(ping)] += ping
    boom = thump(95, 44, 0.07, 0.32, dur)
    clang = metal(rng, 370, dur, 0.4, (1.0, 2.3, 3.7, 5.9), (0.8, 0.6, 0.4, 0.3)) * 0.35
    x = mix(at(crack, 0, dur), shatter * 0.6, boom * 0.9, clang, rumble(rng, dur, 200, 0.35) * 0.4)
    return trim_tail(reverb(drive(x, 1.5), HALL, 0.18))


# ================================================================== creatures

def enemy_hurt(rng, variant):
    dur = 0.32
    curves = [[118, 150, 96], [132, 165, 104], [104, 138, 88]]
    vowels = [VOWEL_UH, VOWEL_AH, VOWEL_EH]
    v = creature(rng, dur, curves[variant], vowels[variant], 0.35, 0.3) * ar(dur, 0.012, 0.2, 1.5)
    return reverb(v, ROOM, 0.1)


def enemy_death(rng, variant):
    dur = 1.2
    curve = [140, 125, 100, 80, 70] if variant == 0 else [125, 118, 92, 74, 62]
    t = time(0.75)
    voice = creature(rng, 0.75, curve, VOWEL_OH if variant == 0 else VOWEL_AW, 0.5, 0.35)
    voice *= ar(0.75, 0.02, 0.5, 1.4) * (1 + 0.25 * np.sin(2 * np.pi * 7 * t))
    x = mix(at(voice, 0.0, dur), at(body_fall(rng) * 0.8, 0.5, dur))
    return trim_tail(reverb(x, ROOM, 0.1))


def enemy_windup(rng):
    """Attack tell: a bright glint the player learns to react to."""
    dur = 0.45
    glint = fm_bell(1760, dur, 1.41, 2.0, 0.18, 0.05) * 0.6 + fm_bell(2637, dur, 1.41, 1.5, 0.12, 0.04) * 0.3
    rise = whoosh(rng, dur, 600, 3000, 3000, 0.5, 0.95, 1.2) * 0.35
    return mix(glint, rise)


def monster_roar(rng):
    dur = 1.3
    curve = [62, 78, 88, 84, 76, 64]
    t = time(dur)
    v = creature(rng, dur, curve, VOWEL_AW, 0.9, 0.6) * ar(dur, 0.08, 0.6, 1.5)
    v *= 1 + 0.3 * np.sin(2 * np.pi * 13 * t)  # throat rattle
    return trim_tail(reverb(drive(v, 2.5), HALL, 0.15))


def player_down(rng):
    dur = 1.6
    tone = sine(glide(220, 110, dur), dur) * exp_decay(dur, 0.5, 0.05) * 0.25
    tone = lp(tone + 0.3 * sine(glide(330, 165, dur), dur) * exp_decay(dur, 0.4, 0.05) * 0.25, 1500)
    return trim_tail(reverb(mix(body_fall(rng, 1.4), tone), HALL, 0.2))


# ================================================================== effects (buffs / debuffs)

def buff_up(rng):
    dur = 0.8
    notes = [1046.5, 1318.5, 1568.0, 2093.0]
    x = sum(at(fm_bell(f, 0.6, 2.0, 1.2, 0.35, 0.05) * 0.35, i * 0.055, dur) for i, f in enumerate(notes))
    air = whoosh(rng, dur, 1500, 6000, 6000, 0.5, 0.8) * 0.25
    return trim_tail(reverb(mix(x, air), HALL, 0.15))


def debuff(rng):
    dur = 0.6
    f = glide(330, 170, dur)
    tone = lp(pulse(f, width=0.35) + 0.6 * pulse(f * 1.06, width=0.4), 1100) * ar(dur, 0.01, 0.4) * 0.35
    hiss = bp(white(dur, rng), 2000, 6000, 1) * ar(dur, 0.02, 0.4) * 0.12
    return trim_tail(reverb(mix(tone, hiss), ROOM, 0.15))


def resist(rng):
    dur = 0.35
    return mix(fm_bell(2349, dur, 1.0, 1.5, 0.12, 0.03) * 0.5, thump(200, 150, 0.01, 0.03, dur) * 0.4, click(rng, 0.002, 3000, 2600) * 0.3)


def dot_tick(rng):
    dur = 0.12
    return mix(smack(rng, 600, 2000, 0.015, dur), thump(260, 160, 0.01, 0.02, dur) * 0.5)


def stamina_empty(rng):
    dur = 0.4
    breath = bp(white(dur, rng), 500, 2200, 1) * ar(dur, 0.04, 0.3, 1.5) * 0.4
    dull = mix(thump(150, 100, 0.01, 0.03, dur), at(thump(130, 90, 0.01, 0.03, 0.2), 0.09, dur) * 0.7) * 0.6
    return mix(breath, dull)


# ================================================================== skills

def cast_fists(rng):  # Raging Fist: a fire ignites around the fists
    dur = 0.7
    fw = sweep_band(pink(dur, rng), lambda u: 200 * (15 ** u), 1.0) * bell_env(dur, 0.45, 1.2)
    growl = lp(saw(glide(70, 110, dur), dur), 600) * bell_env(dur, 0.5) * 0.3
    return mix(fw, crackle(rng, dur, 60) * bell_env(dur, 0.6, 1) * 0.6, growl, thump(90, 60, 0.05, 0.1, dur) * 0.4)


def cast_blade(rng):  # Ember Slash: the blade sings and catches fire
    dur = 0.75
    ring = metal(rng, 1980, dur, 0.5, (1.0, 1.5, 2.25, 3.37), (0.6, 0.5, 0.35, 0.25)) * ar(dur, 0.12, 0.3, 1.0)
    fire = sweep_band(pink(dur, rng), lambda u: 400 * (8 ** u), 0.9) * bell_env(dur, 0.6, 1.2)
    return mix(ring * 0.35, fire * 0.8, crackle(rng, dur, 40) * 0.4)


def cast_dagger(rng):  # Venom Dance: quick swishes and a poison bubble
    dur = 0.7
    sw = mix(*(at(whoosh(rng, 0.12, 2500, 6000, 3500, 0.4, 0.4), o, dur) * a for o, a in ((0.0, 0.7), (0.13, 0.8), (0.26, 1.0))))
    bub = np.zeros(n_of(dur))
    for _ in range(18):
        s = rng.uniform(0.05, 0.6)
        f = rng.uniform(350, 1100)
        b = sine(glide(f, f * 1.8, 0.04), 0.04) * exp_decay(0.04, 0.012, 0.002)
        bub += at(b, s, dur) * rng.uniform(0.2, 0.5)
    return mix(sw, bub, bp(white(dur, rng), 3000, 8000, 1) * bell_env(dur, 0.6) * 0.15)


def zap_noise(rng, dur, density=0.35):
    gate = (rng.random(n_of(dur) // 200 + 1) < density).repeat(200)[: n_of(dur)].astype(float)
    return hp(white(dur, rng), 2500, 2) * lp(gate, 400, 1) * 1.5


def cast_spear(rng):  # Thunder Thrust: electricity charges along the shaft
    dur = 0.75
    buzz = drive(saw(glide(110, 220, dur), dur) * 0.6, 3) * bell_env(dur, 0.7, 1.0) * 0.3
    t = time(dur)
    buzz *= 0.6 + 0.4 * np.sin(2 * np.pi * 37 * t)
    return mix(lp(buzz, 3000), zap_noise(rng, dur) * bell_env(dur, 0.7, 1.0) * 0.5)


def cast_hammer(rng):  # Earthshaker: the ground starts to growl
    dur = 0.85
    rum = lp(brown(dur, rng), 160, 2) * bell_env(dur, 0.75, 1.0) * 1.2
    grind = grains(rng, dur, 70, 200, 1500, 0.01, 1.0, 0.5) * bell_env(dur, 0.7) * 0.5
    return mix(rum, grind, sine(glide(45, 70, dur), dur) * bell_env(dur, 0.8) * 0.4)


def impact_fists(rng):  # fiery burst
    dur = 0.8
    burst = sweep_band(pink(dur, rng), lambda u: 4000 * (0.07 ** u), 1.1) * exp_decay(dur, 0.18, 0.002) * 1.4
    return trim_tail(mix(burst, crackle(rng, dur, 70) * exp_decay(dur, 0.3) * 0.6, thump(100, 40, 0.05, 0.15, dur) * 0.6))


def impact_blade(rng):  # flaming cut
    dur = 0.8
    cut = whoosh(rng, 0.2, 7000, 4500, 1500, 0.5, 0.1)
    fire = sweep_band(pink(dur, rng), lambda u: 2500 * (0.15 ** u), 1.0) * exp_decay(dur, 0.25, 0.005)
    sizzle = hp(white(dur, rng), 5000, 2) * exp_decay(dur, 0.3, 0.02) * 0.15
    return trim_tail(mix(at(cut, 0, dur), fire, sizzle, crackle(rng, dur, 50) * exp_decay(dur, 0.35) * 0.4))


def impact_dagger(rng):  # poison splash
    dur = 0.6
    t = time(dur)
    squelch = bp(white(dur, rng), 300, 1300, 2) * exp_decay(dur, 0.09, 0.002) * (0.6 + 0.4 * np.sin(2 * np.pi * 55 * t))
    hiss = bp(white(dur, rng), 3000, 9000, 1) * exp_decay(dur, 0.25, 0.01) * 0.25
    return trim_tail(mix(squelch * 1.4, hiss, cast_dagger(rng)[n_of(0.3):] * 0.4))


def impact_spear(rng):  # thunder zap
    dur = 1.0
    crack = hp(white(0.03, rng), 2000, 2) * exp_decay(0.03, 0.004, 0.0) * 1.5
    zap = zap_noise(rng, dur, 0.5) * exp_decay(dur, 0.15) * 0.8
    thunder = lp(brown(dur, rng), 250, 2) * exp_decay(dur, 0.35, 0.02) * 1.2
    return trim_tail(reverb(mix(at(crack, 0, dur), zap, thunder), HALL, 0.12))


def impact_hammer(rng):  # ground slam
    dur = 1.1
    x = mix(click(rng, 0.006, 1500, 900),
            thump(80, 42, 0.08, 0.4, dur) * 1.2,
            grains(rng, dur, 90, 150, 1600, 0.012, 1.0, 2.5) * 0.7,
            rumble(rng, dur, 200, 0.45) * 0.7)
    return trim_tail(reverb(drive(x, 1.8), HALL, 0.15))


def ultimate_cast(rng):
    """Shared charge-up riser (the per-weapon flavour is layered on by the data)."""
    dur = 1.05
    rise = sweep_band(white(dur, rng), lambda u: 300 * (25 ** u), 0.8) * (np.linspace(0, 1, n_of(dur)) ** 2) * 0.8
    t = time(dur)
    tones = sum(sine(glide(f, f * 2, dur), dur) for f in (110, 165, 220)) * (np.linspace(0, 1, n_of(dur)) ** 3) * 0.12
    sub = sine(glide(35, 55, dur), dur) * (np.linspace(0, 1, n_of(dur)) ** 2) * 0.6
    shimmer = hp(white(dur, rng), 6000, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * (8 + 20 * t) * t)) * np.linspace(0, 1, n_of(dur)) ** 2 * 0.15
    return fade(mix(rise, tones, sub, shimmer), 0.05, 0.02)


def ultimate_boom(rng):
    dur = 2.4
    x = mix(click(rng, 0.008, 1800, 1200) * 1.2,
            thump(90, 40, 0.1, 0.6, dur) * 1.3,
            hp(white(0.08, rng), 3000, 2) * exp_decay(0.08, 0.01, 0.0),
            rumble(rng, dur, 160, 0.8) * 0.9,
            sweep_band(pink(dur, rng), lambda u: 3000 * (0.05 ** u), 1.0) * exp_decay(dur, 0.35, 0.002) * 0.8)
    return trim_tail(reverb(drive(x, 1.8), HALL, 0.25))


def ult_fists(rng):  # Heaven Palm: a radiant open-palm blast
    dur = 1.8
    chord = sum(fm_bell(f, dur, 1.0, 0.8, 0.9, 0.2) for f in (523.3, 659.3, 784.0, 1046.5, 1318.5)) * 0.18
    air = sweep_band(white(dur, rng), lambda u: 6000 * (0.3 ** u), 0.9) * exp_decay(dur, 0.5, 0.01) * 0.5
    return trim_tail(reverb(mix(chord, air), HALL, 0.35))


def ult_blade(rng):  # Crimson Heaven Edge: a huge ringing cut wrapped in fire
    dur = 1.6
    ring = metal(rng, 1480, dur, 0.8, (1.0, 1.5, 2.0, 3.0, 4.2), (0.7, 0.5, 0.45, 0.3, 0.2)) * 0.3
    cut = whoosh(rng, 0.35, 6000, 3000, 900, 0.7, 0.15) * 1.2
    fire = sweep_band(pink(dur, rng), lambda u: 1800 * (0.2 ** u), 1.0) * exp_decay(dur, 0.5, 0.01)
    return trim_tail(reverb(mix(at(cut, 0, dur), ring, fire, crackle(rng, dur, 60) * exp_decay(dur, 0.6) * 0.5), HALL, 0.2))


def ult_dagger(rng):  # Shadow Hunt: dark reversed rush and whispers
    dur = 1.4
    rev = whoosh(rng, dur, 300, 2500, 200, 0.7, 0.85, 2.0, "pink")
    whisper = formant(white(dur, rng), [(2800, 900, 1.0), (5200, 1200, 0.6)]) * bell_env(dur, 0.6, 1.5) * 0.4
    cuts = mix(*(at(whoosh(rng, 0.1, 3000, 7000, 4000, 0.35, 0.3), 0.75 + i * 0.09, dur) * 0.6 for i in range(4)))
    return trim_tail(reverb(mix(rev, whisper, cuts), HALL, 0.25))


def ult_spear(rng):  # Lullaby Lance: a soft falling chime that lulls to sleep
    dur = 2.2
    notes = [1568.0, 1318.5, 1046.5, 784.0, 659.3]
    x = sum(at(fm_bell(f, 1.2, 1.0, 1.2, 0.7, 0.08) * 0.3, 0.12 * i, dur) for i, f in enumerate(notes))
    hush = bp(white(dur, rng), 800, 4000, 1) * bell_env(dur, 0.2, 1.5) * 0.12
    return trim_tail(reverb(mix(x, hush, whoosh(rng, 0.3, 4000, 2000, 900, 0.6, 0.1) * 0.6), HALL, 0.4))


def ult_hammer(rng):  # Mountain Fall: rockslide and a mountain landing
    dur = 2.2
    rocks = grains(rng, dur, 220, 120, 2000, 0.015, 1.0, 1.2) * 0.8
    x = mix(rocks, thump(72, 40, 0.15, 0.7, dur) * 1.0, rumble(rng, dur, 140, 0.9) * 0.8)
    return trim_tail(reverb(drive(x, 1.6), HALL, 0.2))


# ================================================================== loot / camp

def coin(rng, f):
    return partials([f, f * 1.43, f * 2.04, f * 2.77], [1.0, 0.6, 0.5, 0.3], [0.12, 0.09, 0.06, 0.05], 0.3, rng, 0.01)


def gold(rng):
    dur = 0.6
    x = np.zeros(n_of(dur))
    for i in range(6):
        x += at(coin(rng, rng.uniform(2600, 3600)) * rng.uniform(0.4, 1.0), 0.02 + rng.random() ** 1.5 * 0.25, dur)
    return trim_tail(reverb(mix(x * 0.5, grains(rng, 0.25, 10, 2000, 7000, 0.003) * 0.3), ROOM, 0.12))


def item_drop(rng):
    dur = 0.5
    return trim_tail(mix(thump(140, 70, 0.015, 0.04, dur) * 0.6, grains(rng, 0.15, 10, 800, 4000, 0.004) * 0.3,
                         at(fm_bell(2637, 0.4, 2.0, 1.0, 0.15, 0.03) * 0.35, 0.05, dur)))


def item_pickup(rng):
    dur = 0.45
    a = fm_bell(1318.5, 0.3, 2.0, 1.0, 0.12, 0.03)
    b = fm_bell(1975.5, 0.4, 2.0, 1.0, 0.18, 0.03)
    rustle = lp(white(0.15, rng), 3000, 2) * bell_env(0.15, 0.3) * 0.25
    return trim_tail(mix(at(rustle, 0, dur), at(a * 0.4, 0.02, dur), at(b * 0.45, 0.09, dur)))


def material_pickup(rng):
    dur = 0.35
    rustle = lp(white(0.2, rng), 2500, 2) * bell_env(0.2, 0.3) * 0.5
    knock = thump(520, 400, 0.01, 0.03, 0.2) * 0.6
    return mix(at(rustle, 0, dur), at(knock, 0.06, dur), at(knock * 0.6, 0.12, dur))


def rest(rng):
    dur = 2.2
    notes = [523.3, 659.3, 784.0, 987.8, 1174.7]  # Cmaj9 rising: warm, at ease
    x = sum(at(fm_bell(f, 1.4, 1.0, 0.8, 0.8, 0.15) * 0.22, 0.14 * i, dur) for i, f in enumerate(notes))
    breath = bp(white(1.0, rng), 400, 2000, 1) * ar(1.0, 0.25, 0.6) * 0.15
    fire = crackle(rng, dur, 15) * 0.15
    return trim_tail(reverb(mix(x, at(breath, 0.1, dur), fire), HALL, 0.3))


# ================================================================== UI (one family: wooden tick, soft bell, brush swish)

def ui_hover(rng):
    dur = 0.04
    return fade(sine(2600, dur) * exp_decay(dur, 0.005, 0.0005) * 0.6 + hp(white(dur, rng), 5000, 2) * exp_decay(dur, 0.002, 0.0) * 0.2, 0.0005, 0.01)


def ui_click(rng):
    dur = 0.08
    tick = (sine(1500, dur) + 0.5 * sine(3150, dur)) * exp_decay(dur, 0.012, 0.0005)
    body = sine(320, dur) * exp_decay(dur, 0.015, 0.001) * 0.6
    return fade(mix(tick, body, hp(white(dur, rng), 3000, 2) * exp_decay(dur, 0.003, 0.0) * 0.3), 0.0005, 0.01)


def ui_select(rng):
    dur = 0.07
    return fade(mix((sine(900, dur) + 0.4 * sine(1890, dur)) * exp_decay(dur, 0.02, 0.0008),
                    hp(white(dur, rng), 3000, 2) * exp_decay(dur, 0.002, 0.0) * 0.2), 0.0005, 0.01)


def brush(rng, dur, up=True):
    c = (1200, 4800) if up else (4500, 1100)
    return sweep_band(white(dur, rng), lambda u: c[0] * (c[1] / c[0]) ** u, 0.55) * bell_env(dur, 0.35 if up else 0.25, 1.5)


def ui_tab(rng):
    dur = 0.13
    return fade(mix(brush(rng, dur) * 0.7, ui_select(rng) * 0.5), 0.001, 0.01)


def ui_equip(rng):
    dur = 0.3
    cloth = lp(white(0.15, rng), 1500, 2) * bell_env(0.15, 0.4) * 0.6
    clink = metal(rng, 2500, 0.25, 0.08, (1.0, 1.56, 2.24), (0.8, 0.5, 0.3))
    return trim_tail(mix(at(cloth, 0, dur), at(clink * 0.4, 0.045, dur), at(thump(220, 150, 0.01, 0.025, 0.1) * 0.4, 0.04, dur)))


def ui_unequip(rng):
    dur = 0.28
    clink = metal(rng, 2000, 0.2, 0.06, (1.0, 1.56, 2.24), (0.8, 0.5, 0.3))
    cloth = lp(white(0.15, rng), 1800, 2) * bell_env(0.15, 0.7) * 0.5
    return trim_tail(mix(at(clink * 0.35, 0, dur), at(cloth, 0.05, dur)))


def ui_error(rng):
    dur = 0.24
    note = lambda f, d: lp(pulse(f, d, 0.4), 1200, 2) * ar(d, 0.004, 0.04)
    return mix(at(note(185, 0.08), 0, dur), at(note(165, 0.1), 0.1, dur)) * 0.8


def ui_open(rng):
    dur = 0.45
    return trim_tail(reverb(mix(brush(rng, 0.25) * 0.6, at(fm_bell(1046.5, 0.35, 1.0, 0.9, 0.15, 0.03) * 0.3, 0.08, dur)), ROOM, 0.12))


def ui_close(rng):
    dur = 0.3
    return trim_tail(mix(brush(rng, 0.2, up=False) * 0.6, at(sine(500, 0.06) * exp_decay(0.06, 0.015) * 0.3, 0.12, dur)))


def ui_discard(rng):
    dur = 0.35
    return trim_tail(mix(grains(rng, 0.25, 50, 1000, 6000, 0.004, 1.0, 1.5) * 0.6, brush(rng, 0.25, up=False) * 0.4))


def ui_repair(rng):
    dur = 0.5
    tink = lambda: metal(rng, 1900, 0.3, 0.12, (1.0, 2.47, 3.63, 5.1), (0.9, 0.5, 0.35, 0.2))
    return trim_tail(reverb(mix(at(tink() * 0.5, 0, dur), at(tink() * 0.4, 0.15, dur), at(click(rng, 0.003, 2000, 2500) * 0.3, 0, dur)), ROOM, 0.1))


def ui_upgrade(rng):
    dur = 1.1
    notes = [659.3, 987.8, 1318.5]
    x = sum(at(fm_bell(f, 0.7, 1.0, 1.0, 0.45, 0.06) * 0.35, 0.09 * i, dur) for i, f in enumerate(notes))
    return trim_tail(reverb(mix(x, whoosh(rng, 0.6, 2000, 7000, 7000, 0.5, 0.8) * 0.12), HALL, 0.18))


# ================================================================== registry: name -> (function, loudness target dB)

def _variants(base, fn, count, target, seed0):
    return {"%s_%d" % (base, i + 1): (lambda rng, f=fn: f(rng), target, seed0 + i) for i in range(count)}


SOUNDS = {}
SOUNDS.update(_variants("footstep", lambda r: footstep(r, False), 4, -24, 100))
SOUNDS.update(_variants("footstep_run", lambda r: footstep(r, True), 4, -21, 110))
SOUNDS.update({
    "jump": (jump, -20, 120), "land": (land, -16, 121), "dodge": (dodge, -17, 122), "launch": (launch, -18, 123),
    "body_fall": (lambda r: body_fall(r), -13, 124), "get_up": (get_up, -24, 125),
})
for i, w in enumerate(SWINGS):
    SOUNDS.update(_variants("swing_%s_light" % w, lambda r, w=w: swing(r, w, False), 2, -17 if w != "hammer" else -15, 200 + i * 10))
    SOUNDS["swing_%s_heavy" % w] = (lambda r, w=w: swing(r, w, True), -13 if w != "hammer" else -11, 250 + i)
SOUNDS["swing_monster"] = (monster_swipe, -13, 270)
SOUNDS["bite_monster"] = (monster_bite, -14, 271)
SOUNDS.update(_variants("hit_light", hit_light, 3, -10, 300))
SOUNDS.update(_variants("hit_heavy", hit_heavy, 3, -8, 310))
SOUNDS.update(_variants("hit_crit", hit_crit, 2, -7, 320))
SOUNDS.update({"hit_slice": (sweet_slice, -16, 330), "hit_pierce": (sweet_pierce, -16, 331), "hit_crush": (sweet_crush, -13, 332)})
SOUNDS.update({"guard_block": (guard_block, -10, 400), "guard_block_2": (guard_block, -10, 401), "guard_break": (guard_break, -7, 402)})
SOUNDS.update({"enemy_hurt_%d" % (i + 1): (lambda r, i=i: enemy_hurt(r, i), -14, 500 + i) for i in range(3)})
SOUNDS.update({"enemy_death_%d" % (i + 1): (lambda r, i=i: enemy_death(r, i), -12, 510 + i) for i in range(2)})
SOUNDS.update({"enemy_windup": (enemy_windup, -16, 520), "monster_roar": (monster_roar, -11, 521), "player_down": (player_down, -11, 522)})
SOUNDS.update({"buff_up": (buff_up, -16, 600), "debuff": (debuff, -17, 601), "resist": (resist, -18, 602),
               "dot_tick": (dot_tick, -24, 603), "stamina_empty": (stamina_empty, -18, 604)})
for i, (w, c, im, ul) in enumerate([("fists", cast_fists, impact_fists, ult_fists), ("blade", cast_blade, impact_blade, ult_blade),
                                    ("dagger", cast_dagger, impact_dagger, ult_dagger), ("spear", cast_spear, impact_spear, ult_spear),
                                    ("hammer", cast_hammer, impact_hammer, ult_hammer)]):
    SOUNDS["skill_cast_%s" % w] = (c, -14, 700 + i)
    SOUNDS["skill_impact_%s" % w] = (im, -12, 710 + i)
    SOUNDS["ultimate_%s" % w] = (ul, -12, 720 + i)
SOUNDS.update({"ultimate_cast": (ultimate_cast, -13, 730), "ultimate_boom": (ultimate_boom, -7, 731)})
SOUNDS.update({"gold_1": (gold, -15, 800), "gold_2": (gold, -15, 801), "item_drop": (item_drop, -16, 802),
               "item_pickup": (item_pickup, -15, 803), "material_pickup": (material_pickup, -17, 804), "rest": (rest, -16, 805)})
SOUNDS.update({"ui_hover": (ui_hover, -30, 900), "ui_click": (ui_click, -20, 901), "ui_select": (ui_select, -22, 902),
               "ui_tab": (ui_tab, -22, 903), "ui_equip": (ui_equip, -18, 904), "ui_unequip": (ui_unequip, -19, 905),
               "ui_error": (ui_error, -20, 906), "ui_open": (ui_open, -20, 907), "ui_close": (ui_close, -21, 908),
               "ui_discard": (ui_discard, -20, 909), "ui_repair": (ui_repair, -18, 910), "ui_upgrade": (ui_upgrade, -17, 911)})


def main(prefixes):
    total = 0
    for name, (fn, target, seed) in SOUNDS.items():
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        x = hp(fn(rng_of(seed)), 40.0, 2)  # nothing below 40 Hz: phones/laptops cannot play it
        x = level(x, target)
        x = fade(x, 0.0, 0.004)
        path = os.path.join(OUT, name + ".ogg")
        write_ogg(path, x, 0.45)
        size = os.path.getsize(path)
        total += size
        print("%-24s %5.2fs  peak %5.1f dB  %5.1f KB" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-9), size / 1024))
    print("total %.1f KB" % (total / 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
