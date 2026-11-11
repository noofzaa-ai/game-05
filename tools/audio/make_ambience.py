"""Synthesizes zorx's ambience loops (pure numpy/scipy, no samples):

    ambience_ink_garden  wind through a painted garden, leaves, small birds, a trickle of water
    ambience_shrine      cold high wind, insects, a far temple bell, wooden chimes
    ambience_campfire    the hub's fire: low roar, crackles and pops, night crickets

    python tools/audio/make_ambience.py [name prefix ...]

Every loop is exactly periodic: noise beds are shaped in the frequency domain (an inverse FFT is
circular), slow swells use whole numbers of cycles per loop, and one-shot events that run past
the end are folded back onto the start. So the files loop with no seam at all.
"""
import os
import sys

import numpy as np

import dsp

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio", "ambience")
LOOP = 24.0
SR = dsp.SR


def circ_noise(rng, lo, hi, slope=0.0, seconds=LOOP):
    """Band-limited noise that loops perfectly. slope: dB per octave tilt (-3 = pink-ish)."""
    n = dsp.n_of(seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1.0
    gain = (f / 1000.0) ** (slope / 6.02)
    # soft band edges (half-octave cosine skirts)
    gain *= np.clip(np.log2(f / (lo / 1.41)) / 0.5, 0, 1) * np.clip(np.log2((hi * 1.41) / f) / 0.5, 0, 1)
    x = np.fft.irfft(spec * gain, n)
    return x / (np.std(x) + 1e-12)


def lfo(cycles, phase=0.0, seconds=LOOP):
    """0..1 slow swell with a whole number of cycles per loop."""
    t = np.arange(dsp.n_of(seconds)) / SR
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * t / seconds + phase)


def gusts(rng, count, seconds=LOOP, depth=0.6):
    """Sum of a few slow swells (whole cycles) -> natural-feeling wind strength, 1-depth..1."""
    env = np.zeros(dsp.n_of(seconds))
    for _ in range(count):
        env += lfo(int(rng.integers(1, 5)), rng.uniform(0, 6.28), seconds) * rng.uniform(0.5, 1.0)
    env /= env.max()
    return (1 - depth) + depth * env


class Bed:
    """Stereo loop buffer; events that run past the end wrap to the start."""

    def __init__(self, seconds=LOOP):
        self.n = dsp.n_of(seconds)
        self.buf = np.zeros((self.n, 2))

    def add(self, x, at, pan=0.0, gain=1.0):
        if x.ndim == 1:
            x = dsp.pan(x, pan)
        x = x * gain
        start = dsp.n_of(at) % self.n
        pos = 0
        while pos < len(x):
            k = min(self.n - start, len(x) - pos)
            self.buf[start:start + k] += x[pos:pos + k]
            pos += k
            start = 0

    def bed(self, x, width=0.5, rng=None):
        """A continuous stereo bed from a mono loop (a circular shift decorrelates the sides)."""
        shift = dsp.n_of(0.37)
        side = np.roll(x, shift)
        self.buf[:, 0] += x * (1 - width / 2) + side * width / 2
        self.buf[:, 1] += side * (1 - width / 2) + x * width / 2


# ------------------------------------------------------------------ sound pieces

def bird_chirp(rng, base):
    """One small songbird phrase: 2-6 quick FM sweeps."""
    notes = int(rng.integers(2, 7))
    parts = []
    for k in range(notes):
        d = rng.uniform(0.04, 0.11)
        f0 = base * rng.uniform(0.85, 1.2)
        f1 = f0 * rng.uniform(0.7, 1.5)
        freq = dsp.glide(f0, f1, d)
        tone = np.sin(dsp.phase_of(freq)) + 0.15 * np.sin(2 * dsp.phase_of(freq))
        parts.append(tone * dsp.bell_env(d, 0.3, 1.5))
        parts.append(dsp.silence(rng.uniform(0.02, 0.07)))
    return np.concatenate(parts)


def drip(rng):
    f = rng.uniform(700, 1600)
    d = 0.06
    freq = dsp.glide(f, f * 1.8, d, tau=0.02)
    return np.sin(dsp.phase_of(freq)) * dsp.exp_decay(d, 0.015)


def leaf_rustle(rng, seconds):
    x = dsp.hp(dsp.white(seconds, rng), 2500.0, 2)
    grains = (rng.random(len(x)) < 0.004).astype(float)
    grains = np.convolve(grains, np.exp(-np.arange(dsp.n_of(0.006)) / dsp.n_of(0.0015)), mode="same")
    return x * grains * dsp.bell_env(seconds, 0.4, 1.2)


def temple_bell(rng, f):
    """A large bronze bell far away: inharmonic partials, long hum, softened by distance."""
    ratios = [0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0, 4.07]
    amps = [0.6, 1.0, 0.5, 0.35, 0.3, 0.18, 0.12, 0.06]
    decays = [7.0, 5.0, 3.0, 2.5, 2.0, 1.4, 1.0, 0.6]
    x = dsp.partials([f * r for r in ratios], amps, decays, 8.0, rng, detune=0.003)
    beat = 1 + 0.25 * np.sin(2 * np.pi * 0.9 * np.arange(len(x)) / SR)  # the slow beating of a real bell
    return dsp.lp(x * beat, 2500.0, 2)


def wood_chime(rng):
    f = rng.choice([620.0, 740.0, 830.0, 990.0])
    return dsp.partials([f, f * 2.76, f * 5.4], [1.0, 0.4, 0.15], [0.18, 0.07, 0.03], 0.5, rng, 0.01)


def cricket(rng, f, seconds):
    """Pulse-train chirps: groups of 3-4 pulses."""
    t = np.arange(dsp.n_of(seconds)) / SR
    carrier = np.sin(2 * np.pi * f * t)
    rate = rng.uniform(26, 34)
    pulses = (np.sin(2 * np.pi * rate * t) > 0.3).astype(float)
    group = (np.sin(2 * np.pi * rng.uniform(1.6, 2.4) * t) > 0.1).astype(float)
    env = dsp.lp(pulses * group, 300.0, 2)
    return carrier * env


def crackle(rng, strength):
    """A wood crackle: a click and a short band of noise."""
    d = rng.uniform(0.004, 0.03)
    x = dsp.bp(dsp.white(d, rng), rng.uniform(1200, 3000), rng.uniform(4000, 9000), 2)
    return x * dsp.exp_decay(d, d / 4) * strength


def pop(rng):
    d = 0.09
    body = np.sin(dsp.phase_of(dsp.glide(rng.uniform(250, 400), 120, d, tau=0.01))) * dsp.exp_decay(d, 0.012)
    snap = dsp.hp(dsp.white(0.012, rng), 1800.0, 2) * dsp.exp_decay(0.012, 0.003)
    return dsp.mix(body * 0.6, snap)


# ------------------------------------------------------------------ the loops

def ink_garden(rng):
    bed = Bed()
    wind = circ_noise(rng, 180, 1400, -4.0) * gusts(rng, 4, depth=0.65)
    bed.bed(wind * 0.25, 0.8)
    air = circ_noise(rng, 2500, 9000, -3.0) * gusts(rng, 3, depth=0.8)  # leaves hiss with the gusts
    bed.bed(air * 0.012, 0.9)
    for _ in range(14):  # rustles
        bed.add(leaf_rustle(rng, rng.uniform(0.4, 1.2)), rng.uniform(0, LOOP), rng.uniform(-0.8, 0.8), rng.uniform(0.04, 0.09))
    for species, base in ((0, 3400.0), (1, 4600.0), (2, 2700.0)):
        for _ in range(int(rng.integers(3, 6))):
            far = rng.uniform(0.3, 1.0)
            chirp = dsp.lp(bird_chirp(rng, base), 3000 + 5000 * far, 2)
            bed.add(chirp, rng.uniform(0, LOOP), rng.uniform(-0.9, 0.9), 0.2 * far)
    for _ in range(40):  # a small stream somewhere to the left
        bed.add(drip(rng), rng.uniform(0, LOOP), rng.uniform(-0.8, -0.3), rng.uniform(0.02, 0.05))
    return bed.buf, -30.0


def shrine(rng):
    bed = Bed()
    wind = circ_noise(rng, 90, 700, -5.0) * gusts(rng, 5, depth=0.75)
    bed.bed(wind * 0.3, 0.7)
    whistle = circ_noise(rng, 900, 1300, 0.0) * gusts(rng, 3, depth=0.95) ** 2  # wind singing over the stones
    bed.bed(whistle * 0.025, 0.6)
    for k, f in enumerate((4300.0, 4700.0, 5200.0)):
        c = cricket(rng, f, LOOP) * lfo(int(rng.integers(1, 4)), rng.uniform(0, 6.28)) ** 2
        bed.add(c, 0.0, [-0.6, 0.5, 0.1][k], 0.012)
    bell = temple_bell(rng, 196.0)
    bed.add(bell, 2.0, 0.15, 0.45)
    for _ in range(7):
        bed.add(wood_chime(rng), rng.uniform(0, LOOP), rng.uniform(0.2, 0.7), rng.uniform(0.02, 0.04))
    return bed.buf, -30.0


def campfire(rng):
    bed = Bed()
    roar = circ_noise(rng, 60, 500, -4.0) * (0.7 + 0.3 * gusts(rng, 6, depth=0.9))
    bed.bed(roar * 0.3, 0.3)
    hiss = circ_noise(rng, 3000, 10000, -2.0) * gusts(rng, 5, depth=0.7)
    bed.bed(hiss * 0.007, 0.4)
    t = 0.0
    while t < LOOP:  # crackles in little clusters, like real burning wood
        t += rng.exponential(0.16)
        cluster = int(rng.integers(1, 4))
        for c in range(cluster):
            bed.add(crackle(rng, rng.uniform(0.05, 0.3) ** 1.5), t + c * rng.uniform(0.01, 0.05), rng.uniform(-0.35, 0.35), 1.6)
    for _ in range(6):
        bed.add(pop(rng), rng.uniform(0, LOOP), rng.uniform(-0.3, 0.3), rng.uniform(0.08, 0.16))
    for k, f in enumerate((4500.0, 5000.0)):
        bed.add(cricket(rng, f, LOOP) * lfo(int(rng.integers(1, 3)), rng.uniform(0, 6.28)), 0.0, [-0.8, 0.8][k], 0.006)
    return bed.buf, -27.0


LOOPS = {"ambience_ink_garden": (ink_garden, 41), "ambience_shrine": (shrine, 42), "ambience_campfire": (campfire, 43)}


def main(prefixes):
    total = 0
    for name, (fn, seed) in LOOPS.items():
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        x, target = fn(dsp.rng_of(seed))
        # level with the gain only (no fades or limiting: either would break the seamless loop)
        x = x * 10 ** ((target - dsp.loudness_db(x, 0.4)) / 20)
        x = np.clip(x, -0.98, 0.98)
        path = os.path.join(OUT, name + ".ogg")
        dsp.write_ogg(path, x, 0.0)
        size = os.path.getsize(path)
        total += size
        print("%-22s %5.1fs  peak %5.1f dB  %6.1f KB" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-9), size / 1024))
    print("total %.1f KB" % (total / 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
