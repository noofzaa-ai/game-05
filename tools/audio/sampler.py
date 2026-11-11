"""A tiny multi-sample player used by make_music.py to render OUR OWN compositions with the
VSCO 2 Community Edition orchestral samples (CC0 1.0). Run tools/audio/fetch_vsco2.py first.

    inst = Instrument("flute", "Woodwinds/Flute/susvib", offset=12, sustain=True)
    track = Track(seconds); track.note(inst, midi=72, start=1.0, length=0.6, vel=0.7, pan=-0.2)

Name offsets: VSCO 2 names most samples one octave low (its "C3" is middle C = MIDI 60), so
offset=12; the harp names real pitch (offset 0). Measured with an FFT pitch check (2026-10-05).
"""
import glob
import os
import re

import numpy as np
import soundfile as sf

import dsp

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VSCO = os.path.join(ROOT, "audio_source", "vsco2")
NOTE_RE = re.compile(r"(?:^|_)([A-G]#?)(-?\d)(?=_|\.wav$)", re.IGNORECASE)
VEL_RE = re.compile(r"_v(\d+)", re.IGNORECASE)
SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def _onset_trim(x, threshold_db=-38.0, pre=0.004):
    """Cuts the silence a sample file starts with, so notes land on the beat."""
    mono = np.abs(x).max(axis=1)
    thr = 10 ** (threshold_db / 20) * (mono.max() + 1e-12)
    idx = np.nonzero(mono > thr)[0]
    start = max(0, (idx[0] if len(idx) else 0) - dsp.n_of(pre))
    return x[start:]


class Instrument:
    def __init__(self, name, folder, offset=12, sustain=False, release=0.25, max_len=6.0, gain=1.0,
                 files=None, attack_skip=0.0):
        self.name = name
        self.sustain = sustain  # True: the note is cut to its length + release; False: rings out
        self.release = release
        self.max_len = max_len
        self.gain = gain
        self.attack_skip = attack_skip  # seconds of a slow sample attack to skip for snappier notes
        self.samples = []  # (midi, velocity layer, path)
        pattern = os.path.join(VSCO, folder, files or "*.wav")
        for path in sorted(glob.glob(pattern)):
            base = os.path.basename(path)
            m = NOTE_RE.search(base)
            if not m:
                continue
            midi = 12 * (int(m.group(2)) + 1) + SEMI[m.group(1).upper()] + offset
            v = VEL_RE.search(base)
            self.samples.append((midi, int(v.group(1)) if v else 1, path))
        if not self.samples:
            raise RuntimeError("no samples for %s in %s (run tools/audio/fetch_vsco2.py)" % (name, pattern))
        self.layers = sorted({s[1] for s in self.samples})
        self._cache = {}

    def _load(self, path):
        if path not in self._cache:
            x, sr = sf.read(path, always_2d=True)
            x = dsp.resample_to(x[:, :2] if x.shape[1] > 1 else np.repeat(x, 2, axis=1), sr, dsp.SR)
            x = _onset_trim(x)
            if self.attack_skip > 0:
                x = x[dsp.n_of(self.attack_skip):]
            self._cache[path] = x[: dsp.n_of(self.max_len + 1.0)]
        return self._cache[path]

    def pick(self, midi, vel):
        """Nearest sampled note (ties prefer shifting down, which sounds more natural), then the
        velocity layer nearest to vel (0..1)."""
        best = min(self.samples, key=lambda s: (abs(s[0] - midi), s[0] < midi))
        same_note = [s for s in self.samples if s[0] == best[0]]
        layers = sorted({s[1] for s in same_note})
        want = layers[min(len(layers) - 1, int(vel * len(layers)))]
        return next(s for s in same_note if s[1] == want)

    def render(self, midi, length, vel=0.8):
        root, _, path = self.pick(midi, vel)
        x = self._load(path)
        ratio = 2 ** ((midi - root) / 12.0)
        out_len = len(x) / ratio
        if self.sustain:
            out_len = min(out_len, dsp.n_of(length + self.release))
        else:
            out_len = min(out_len, dsp.n_of(self.max_len))
        n = int(out_len)
        pos = np.arange(n) * ratio
        y = np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1)
        env = np.ones(n)
        r = dsp.n_of(self.release)
        if self.sustain and n > r:
            env[-r:] = np.linspace(1, 0, r) ** 1.5
        else:
            env *= dsp.taper(n, 0.15)
        return y * env[:, None] * (0.35 + 0.65 * vel) * self.gain


class Track:
    """A stereo buffer that notes are mixed into. Times in seconds."""

    def __init__(self, seconds, rng=None):
        self.buf = np.zeros((dsp.n_of(seconds), 2))
        self.rng = rng or np.random.default_rng(7)

    def add(self, x, start, pan=0.0, gain=1.0):
        a = (pan + 1) * np.pi / 4
        x = x * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2) * gain
        s = max(0, dsp.n_of(start)) if start > 0 else 0
        e = min(len(self.buf), s + len(x))
        if e > s:
            self.buf[s:e] += x[: e - s]

    def note(self, inst, midi, start, length, vel=0.8, pan=0.0, gain=1.0, human=0.006):
        jitter = self.rng.uniform(-human, human) if human > 0 else 0.0
        v = float(np.clip(vel + self.rng.uniform(-0.04, 0.04), 0.05, 1.0))
        self.add(inst.render(midi, length, v), max(0.0, start + jitter), pan, gain)
