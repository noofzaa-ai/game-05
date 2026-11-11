"""Renders zorx's music: original compositions (written here as note lists) played by the CC0
VSCO 2 CE orchestral samples (tools/audio/sampler.py). Direction from the Boss (GDD "เสียงและดนตรี"):
bright fantasy-orchestra mood in the spirit of classic MMO towns and fields, but entirely our own:
no melody, chord loop, hook or arrangement is taken from any reference game.

    python tools/audio/fetch_vsco2.py      # once: downloads the samples to audio_source/vsco2/
    python tools/audio/make_music.py       # renders audio/music/*.ogg
    python tools/audio/make_music.py hub   # only names starting with "hub"

Loops are made seamless by rendering one extra tail (reverb + ringing notes) and folding it back
onto the start, so the file can loop with no gap or click (the game sets loop = true).
"""
import os
import sys

import numpy as np

import dsp
from sampler import Instrument, Track

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio", "music")
TAIL = 4.0
NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def m(name):
    """'C#5' / 'Bb3' -> MIDI number (C4 = 60)."""
    letter, rest = name[0], name[1:]
    shift = 0
    while rest and rest[0] in "#b":
        shift += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NAMES[letter] + shift


_INST = {}


def inst(key):
    if key not in _INST:
        spec = {
            "flute": ("Woodwinds/Flute/susvib", dict(sustain=True, release=0.35, gain=0.9)),
            "flute_stac": ("Woodwinds/Flute/stac", dict(files="*rr1*.wav", max_len=1.2, gain=0.8)),
            "clarinet": ("Woodwinds/Clarinet/susLong", dict(sustain=True, release=0.4, gain=0.8)),
            "oboe": ("Woodwinds/Oboe/Vib", dict(sustain=True, release=0.35, gain=0.8)),
            "violins": ("Strings/Violin Section/susVib", dict(sustain=True, release=0.5, gain=0.8)),
            "violas": ("Strings/Viola Section/susvib", dict(sustain=True, release=0.6, gain=0.7)),
            "cellos": ("Strings/Cello Section/susvib", dict(sustain=True, release=0.6, gain=0.8)),
            "vln_pizz": ("Strings/Violin Section/Pizz", dict(max_len=1.5, gain=0.9)),
            "vc_pizz": ("Strings/Cello Section/pizzT", dict(max_len=1.8, gain=0.9)),
            "vln_spic": ("Strings/Violin Section/Spic", dict(max_len=0.6, gain=0.9)),
            "vc_spic": ("Strings/Cello Section/spic", dict(max_len=0.7, gain=1.0)),
            "bass_pizz": ("Strings/Solo Contrabass/Pizz", dict(max_len=2.0, gain=1.1)),
            "harp": ("Strings/Harp", dict(offset=0, max_len=3.5, gain=0.8)),
            "horn": ("Brass/F Horn/sus", dict(sustain=True, release=0.4, gain=0.85)),
            "horn_stac": ("Brass/F Horn/stac", dict(max_len=1.2, gain=0.9)),
            "glock": ("Percussion/Glock", dict(max_len=2.5, gain=0.35)),
        }[key]
        _INST[key] = Instrument(key, spec[0], **spec[1])
    return _INST[key]


_PERC = {}


def perc(name, pattern):
    """One-shot percussion sample (unpitched): name -> stereo array."""
    if name not in _PERC:
        import glob
        import soundfile as sf
        path = sorted(glob.glob(os.path.join(ROOT, "audio_source", "vsco2", "Percussion", pattern)))[0]
        x, sr = sf.read(path, always_2d=True)
        x = dsp.resample_to(x[:, :2] if x.shape[1] > 1 else np.repeat(x, 2, axis=1), sr, dsp.SR)
        _PERC[name] = x[: dsp.n_of(4.0)] * dsp.taper(min(len(x), dsp.n_of(4.0)), 0.2)[:, None]
    return _PERC[name]


def timpani(midi, vel=0.8):
    """Timpani hits are not named by pitch: the measured pitches of Timpani1..5 are repitched."""
    measured = {1: 29.8, 2: 46.6, 3: 37.4, 4: 53.2, 5: 42.4}
    drum = min(measured, key=lambda k: abs(measured[k] - midi))
    layer = "v3" if vel > 0.6 else "v1"
    x = perc("timp%d%s" % (drum, layer), "Timpani/Timpani%d_Hit_%s_rr1_Sum.wav" % (drum, layer))
    ratio = 2 ** ((midi - measured[drum]) / 12.0)
    pos = np.arange(int(len(x) / ratio)) * ratio
    return np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1) * vel


def loopify(track, loop_seconds):
    """Folds everything after the loop point back onto the start (seamless loop)."""
    n = dsp.n_of(loop_seconds)
    buf = track.buf
    out = buf[:n].copy()
    tail = buf[n:]
    out[: len(tail)] += tail[: n]
    return out


def finish(x, ir_seconds=2.6, rt60=1.9, wet=0.22, seed=3, loop_seconds=None, target=-17.0):
    ir = dsp.make_ir(ir_seconds, rt60, dsp.rng_of(seed), stereo=True, bright=0.35, predelay=0.02)
    y = dsp.reverb(x, ir, wet=wet)
    if loop_seconds is not None:
        n = dsp.n_of(loop_seconds)
        out = y[:n].copy()
        tail = y[n:]
        while len(tail):
            k = min(n, len(tail))
            out[:k] += tail[:k]
            tail = tail[k:]
        y = out
    y = dsp.hp(y, 35.0, 2)
    return dsp.level(y, target, ceiling=0.95)


D_MINOR = (2, 4, 5, 7, 9, 10, 0, 1)  # natural minor + the raised 7th (C#) for the A chords


def third_below(midi, scale):
    """The scale tone two steps under `midi` (a diatonic third: the harmony line)."""
    lower = [n for n in range(midi - 5, midi) if n % 12 in scale and n % 12 != 1 or (n % 12 == 1 and midi % 12 == 4)]
    return lower[-2] if len(lower) >= 2 else midi - 3


def chord_tones(root, quality):
    steps = {"maj": [0, 4, 7], "min": [0, 3, 7], "dom7": [0, 4, 7, 10], "min7": [0, 3, 7, 10]}[quality]
    return [root + s for s in steps]


# ====================================================================== Hub: "Ember Waltz"
# F major, 3/4, 100 BPM. 16-bar theme played twice: first on flute over harp and pizzicato,
# then on violins with a clarinet counter-line, glockenspiel sparkle and fuller strings.

HUB_BPM = 100
HUB_CHORDS = [  # (bass note, chord root, quality) per bar
    ("F2", "F3", "maj"), ("D2", "D3", "min"), ("Bb1", "Bb2", "maj"), ("C2", "C3", "maj"),
    ("F2", "F3", "maj"), ("A1", "A2", "min"), ("G1", "G2", "min7"), ("C2", "C3", "maj"),
    ("D2", "D3", "min"), ("Bb1", "Bb2", "maj"), ("F2", "F3", "maj"), ("C2", "C3", "maj"),
    ("Bb1", "Bb2", "maj"), ("E2", "C3", "maj"), ("F2", "F3", "maj"), ("C2", "C3", "dom7"),
]
HUB_MELODY = [  # one list of (note, beats) per bar; None = rest
    [("A4", 1), ("Bb4", 0.5), ("C5", 1.5)],
    [("D5", 1), ("C5", 1), ("A4", 1)],
    [("Bb4", 1.5), ("A4", 0.5), ("G4", 1)],
    [("G4", 2), ("E4", 1)],
    [("F4", 1), ("A4", 1), ("C5", 1)],
    [("E5", 2), ("C5", 1)],
    [("D5", 1), ("Bb4", 1), ("G4", 1)],
    [("C5", 3)],
    [("F5", 1.5), ("E5", 0.5), ("D5", 1)],
    [("D5", 1), ("C5", 1), ("Bb4", 1)],
    [("A4", 1), ("C5", 1), ("F5", 1)],
    [("E5", 2), ("G4", 1)],
    [("D5", 1), ("Bb4", 1), ("F4", 1)],
    [("G4", 1), ("Bb4", 1), ("E5", 1)],
    [("F5", 3)],
    [("C5", 1), ("Bb4", 1), ("G4", 1)],
]
HUB_COUNTER = [  # clarinet answer in the second pass: long notes under the tune
    ("F4", 3), ("F4", 3), ("D4", 3), ("E4", 3), ("C4", 3), ("C4", 3), ("Bb3", 3), ("E4", 3),
    ("A4", 3), ("F4", 3), ("C4", 3), ("G4", 3), ("F4", 3), ("E4", 3), ("A4", 3), ("Bb4", 3),
]


def hub_theme():
    beat = 60.0 / HUB_BPM
    bar = 3 * beat
    bars = 32
    loop = bars * bar
    tr = Track(loop + TAIL, np.random.default_rng(11))
    for b in range(bars):
        t0 = b * bar
        second = b >= 16
        bass, root, quality = HUB_CHORDS[b % 16]
        tones = chord_tones(m(root), quality)
        # oom-pah-pah: bass pizz on 1, cello pizz chord tones on 2 and 3
        tr.note(inst("bass_pizz"), m(bass), t0, beat, vel=0.75, pan=-0.1, gain=0.9)
        for k in (1, 2):
            for tone in tones[1:3]:
                tr.note(inst("vc_pizz"), tone + 12, t0 + k * beat, beat, vel=0.45, pan=0.25, gain=0.32)
        # harp: rising-falling arpeggio in eighths
        arp = [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[0] + 24, tones[2] + 12, tones[1] + 12]
        for k, note in enumerate(arp):
            tr.note(inst("harp"), note, t0 + k * beat / 2, beat, vel=0.5 if k else 0.62, pan=0.35, gain=0.55)
        # string pad (soft in pass 1, fuller in pass 2)
        pad_gain = 0.20 if not second else 0.30
        tr.note(inst("violas"), tones[1] + 12, t0, bar, vel=0.35, pan=-0.3, gain=pad_gain, human=0)
        tr.note(inst("cellos"), tones[0], t0, bar, vel=0.35, pan=0.3, gain=pad_gain, human=0)
        # tune
        t = t0
        for note, beats in HUB_MELODY[b % 16]:
            if note:
                if not second:
                    tr.note(inst("flute"), m(note), t, beats * beat * 0.96, vel=0.65, pan=-0.05, gain=0.85)
                else:
                    tr.note(inst("violins"), m(note), t, beats * beat * 0.98, vel=0.6, pan=-0.15, gain=0.75)
                    if beats >= 1.5 or t == t0:
                        tr.note(inst("glock"), m(note) + 12, t, beat, vel=0.5, pan=0.2, gain=0.6)
            t += beats * beat
        if second:
            note, beats = HUB_COUNTER[b % 16]
            tr.note(inst("clarinet"), m(note), t0, beats * beat * 0.97, vel=0.45, pan=0.3, gain=0.55)
        # a soft triangle every 4 bars, a tambourine shake leading into each phrase
        if b % 4 == 0:
            tr.add(perc("tri", "Triangle3-Hit_v1_rr1_Sum.wav"), t0, 0.4, 0.12)
        if b % 8 == 7:
            tr.add(perc("tamb", "Tamb1-Shake_v1_rr1_Sum.wav"), t0 + 2 * beat, -0.3, 0.12)
    return finish(tr.buf, loop_seconds=loop, wet=0.26, target=-19.0), loop


# ====================================================================== Stage: "Ink Trail March"
# D minor (dorian colour), 4/4, 132 BPM. Driving spiccato ostinato + timpani; the horns carry the
# tune in pass 1, the violins in pass 2 with horn harmony underneath.

STAGE_BPM = 132
STAGE_CHORDS = [
    ("D2", "D3", "min"), ("Bb1", "Bb2", "maj"), ("C2", "C3", "maj"), ("D2", "D3", "min"),
    ("D2", "D3", "min"), ("F2", "F3", "maj"), ("C2", "C3", "maj"), ("A1", "A2", "maj"),
    ("Bb1", "Bb2", "maj"), ("C2", "C3", "maj"), ("D2", "D3", "min"), ("A1", "A2", "min"),
    ("Bb1", "Bb2", "maj"), ("C2", "C3", "maj"), ("A1", "A2", "maj"), ("A1", "A2", "dom7"),
]
STAGE_MELODY = [
    [("D4", 1.5), ("E4", 0.5), ("F4", 1), ("A4", 1)],
    [("Bb4", 2), ("A4", 1), ("F4", 1)],
    [("G4", 1.5), ("F4", 0.5), ("E4", 1), ("C4", 1)],
    [("D4", 4)],
    [("A4", 1.5), ("G4", 0.5), ("F4", 1), ("D4", 1)],
    [("C5", 2), ("A4", 1), ("F4", 1)],
    [("G4", 1), ("A4", 1), ("Bb4", 1), ("G4", 1)],
    [("A4", 3), ("E4", 1)],
    [("D5", 2), ("C5", 1), ("Bb4", 1)],
    [("C5", 2), ("Bb4", 1), ("A4", 1)],
    [("A4", 1.5), ("Bb4", 0.5), ("A4", 1), ("F4", 1)],
    [("E4", 2), ("A4", 2)],
    [("F4", 1), ("G4", 1), ("Bb4", 1), ("D5", 1)],
    [("E5", 2), ("C5", 1), ("G4", 1)],
    [("A4", 2), ("C#5", 1), ("E5", 1)],
    [("A4", 4)],
]


def stage_theme():
    beat = 60.0 / STAGE_BPM
    bar = 4 * beat
    bars = 32
    loop = bars * bar
    tr = Track(loop + TAIL, np.random.default_rng(23))
    for b in range(bars):
        t0 = b * bar
        second = b >= 16
        bass, root, quality = STAGE_CHORDS[b % 16]
        tones = chord_tones(m(root), quality)
        # ostinato: cellos on the root in eighths with an accent pattern, violins on chord tones
        accents = [1.0, 0.5, 0.6, 0.5, 0.9, 0.5, 0.7, 0.6]
        for k in range(8):
            tr.note(inst("vc_spic"), tones[0], t0 + k * beat / 2, beat / 2, vel=0.45 + 0.35 * accents[k], pan=0.3, gain=0.45)
            if second or b % 2 == 1:
                upper = [tones[1], tones[2], tones[1] + 12 if k % 4 == 3 else tones[2]][k % 3] + 12
                tr.note(inst("vln_spic"), upper, t0 + k * beat / 2, beat / 2, vel=0.35 + 0.3 * accents[k], pan=-0.35, gain=0.3)
        tr.note(inst("bass_pizz"), m(bass), t0, beat, vel=0.85, pan=0.0, gain=0.8)
        tr.note(inst("bass_pizz"), m(bass), t0 + 2.5 * beat, beat, vel=0.65, pan=0.0, gain=0.6)
        # timpani on 1 and 3 (root / fifth), a fill at the end of every 4 bars
        timp_root = m(bass) + (12 if m(bass) < m("F2") else 0)
        tr.add(timpani(timp_root, 0.8), t0, 0.1, 0.5)
        tr.add(timpani(timp_root + 7 - 12 if timp_root + 7 > m("C3") else timp_root + 7, 0.55), t0 + 2 * beat, 0.1, 0.4)
        if b % 4 == 3:
            for k in range(4):
                tr.add(timpani(timp_root, 0.45 + 0.1 * k), t0 + 3 * beat + k * beat / 4, 0.1, 0.3)
        # drums: bass drum on 1, snare on 2 and 4 (soft), more in the second pass
        tr.add(perc("bd", "BDrumNewhit_v4_rr1_Sum.wav"), t0, 0.0, 0.32)
        tr.add(perc("sn_soft", "Snare2-HitSN_v3_rr1_Sum.wav"), t0 + beat, -0.15, 0.13 if not second else 0.18)
        tr.add(perc("sn_soft", "Snare2-HitSN_v3_rr1_Sum.wav"), t0 + 3 * beat, -0.15, 0.13 if not second else 0.18)
        if second:
            tr.add(perc("bd", "BDrumNewhit_v4_rr1_Sum.wav"), t0 + 2.5 * beat, 0.0, 0.22)
        if b % 8 == 0:
            tr.add(perc("crash", "cymbal-crash1_mp_rr1.wav"), t0, 0.3, 0.16)
        # pad: horns/low strings sustain (pass 1 strings, pass 2 horns under the violins)
        tr.note(inst("cellos"), tones[0], t0, bar, vel=0.4, pan=0.25, gain=0.22, human=0)
        tr.note(inst("violas"), tones[2], t0, bar, vel=0.4, pan=-0.25, gain=0.18, human=0)
        # tune
        t = t0
        for note, beats in STAGE_MELODY[b % 16]:
            if not second:
                tr.note(inst("horn"), m(note), t, beats * beat * 0.95, vel=0.7, pan=-0.1, gain=0.85)
                if b % 16 >= 8:
                    tr.note(inst("flute"), m(note) + 12, t, beats * beat * 0.9, vel=0.5, pan=0.15, gain=0.35)
            else:
                tr.note(inst("violins"), m(note) + 12, t, beats * beat * 0.97, vel=0.7, pan=-0.2, gain=0.7)
                tr.note(inst("horn"), third_below(m(note), D_MINOR), t, beats * beat * 0.95, vel=0.5, pan=0.2, gain=0.45)
                if beats >= 2:
                    tr.note(inst("glock"), m(note) + 24, t, beat, vel=0.5, pan=0.3, gain=0.45)
            t += beats * beat
    return finish(tr.buf, loop_seconds=loop, wet=0.2, rt60=1.6, target=-18.0), loop


# ====================================================================== stingers (not looped)

def stinger_clear():
    """Stage clear: a rising horn call into a bright D major chord with glock and cymbal."""
    beat = 60.0 / 120
    tr = Track(7.0, np.random.default_rng(31))
    call = [("A3", 0, 0.33), ("D4", 0.33, 0.33), ("F#4", 0.66, 0.34), ("A4", 1.0, 1.0)]
    for note, start, length in call:
        tr.note(inst("horn_stac" if length < 0.5 else "horn"), m(note), start * beat, length * beat, vel=0.85, gain=0.9)
        tr.note(inst("vln_spic"), m(note) + 12, start * beat, 0.3, vel=0.7, pan=-0.3, gain=0.4)
    t = 2 * beat
    for note in ("D3", "A3", "D4", "F#4", "A4"):
        tr.note(inst("horn") if m(note) < m("E4") else inst("violins"), m(note), t, 2.4, vel=0.8, pan=0.0, gain=0.55)
    tr.note(inst("violins"), m("D5"), t, 2.4, vel=0.8, pan=-0.2, gain=0.6)
    tr.note(inst("flute"), m("F#5"), t, 2.4, vel=0.7, pan=0.2, gain=0.5)
    tr.note(inst("bass_pizz"), m("D2"), t, 1.0, vel=0.9, gain=1.0)
    for k, note in enumerate(("D6", "F#6", "A6", "D7")):
        tr.note(inst("glock"), m(note), t + k * 0.09, 1.0, vel=0.6, pan=0.3, gain=0.7)
    for k, note in enumerate(("D3", "F#3", "A3", "D4", "F#4", "A4", "D5")):
        tr.note(inst("harp"), m(note), t + k * 0.05, 1.5, vel=0.6, pan=0.4, gain=0.5)
    tr.add(timpani(m("D3"), 0.9), t, 0.0, 0.6)
    tr.add(perc("crash_f", "cymbal-crash1_mf_rr1.wav"), t, 0.25, 0.3)
    x = finish(tr.buf, wet=0.28, target=-15.0)
    return dsp.trim_tail(x, -50.0, 0.3), None


def stinger_defeat():
    """Defeat: a falling oboe line over a low minor chord, fading out."""
    beat = 60.0 / 72
    tr = Track(7.0, np.random.default_rng(37))
    line = [("A4", 0, 1), ("G4", 1, 1), ("F4", 2, 1), ("E4", 3, 2.5)]
    for note, start, length in line:
        tr.note(inst("oboe"), m(note), start * beat, length * beat, vel=0.55, pan=-0.1, gain=0.8)
    for note in ("D3", "A3", "F4"):
        tr.note(inst("cellos") if m(note) < m("C4") else inst("violas"), m(note), 0.0, 4.2 * beat, vel=0.35, gain=0.35, human=0)
    tr.note(inst("cellos"), m("C#3"), 3 * beat, 2.5 * beat, vel=0.4, gain=0.3, human=0)
    tr.add(timpani(m("D2"), 0.5), 0.0, 0.0, 0.5)
    tr.add(perc("gong", "gongHit_p.wav"), 3 * beat, 0.0, 0.25)
    x = finish(tr.buf, wet=0.32, rt60=2.4, target=-18.0)
    return dsp.trim_tail(x, -50.0, 0.3), None


TRACKS = {
    "hub_ember_waltz": (hub_theme, 0.0),
    "stage_ink_trail": (stage_theme, 0.0),
    "stinger_stage_clear": (stinger_clear, 0.15),
    "stinger_defeat": (stinger_defeat, 0.15),
}


def main(prefixes):
    total = 0
    for name, (fn, quality) in TRACKS.items():
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        x, loop = fn()
        if loop is None:
            x = dsp.fade(x, 0.0, 0.05)
        path = os.path.join(OUT, name + ".ogg")
        dsp.write_ogg(path, x, quality)
        size = os.path.getsize(path)
        total += size
        print("%-22s %6.2fs  peak %5.1f dB  %6.1f KB%s" % (name, len(x) / dsp.SR, 20 * np.log10(np.max(np.abs(x)) + 1e-9),
                                                         size / 1024, "  (loop)" if loop else ""))
    print("total %.1f KB" % (total / 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
