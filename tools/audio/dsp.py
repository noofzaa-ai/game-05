"""Small DSP toolkit shared by the zorx sound generators (make_sfx.py, make_music.py,
make_ambience.py). Pure numpy/scipy; every sound is built from these pieces.

Conventions: mono signals are 1-D float arrays, stereo are (n, 2); sample rate SR.
"""
import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100


# ------------------------------------------------------------------ basics

def n_of(seconds, sr=SR):
    return max(1, int(round(seconds * sr)))


def time(seconds, sr=SR):
    return np.arange(n_of(seconds, sr)) / sr


def silence(seconds, sr=SR):
    return np.zeros(n_of(seconds, sr))


def rng_of(seed):
    return np.random.default_rng(seed)


def white(seconds, rng):
    return rng.standard_normal(n_of(seconds))


def pink(seconds, rng):
    """1/f noise via spectral shaping (good for wind, rumble, fire)."""
    n = n_of(seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1]
    spec /= np.sqrt(f)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def brown(seconds, rng):
    n = n_of(seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1]
    spec /= f
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape)])


def mix(*parts, offsets=None):
    """Sums signals of any length; `offsets` (seconds) delays each part."""
    offsets = offsets or [0.0] * len(parts)
    length = max(n_of(o) + len(p) for p, o in zip(parts, offsets))
    shape = (length,) + parts[0].shape[1:]
    out = np.zeros(shape)
    for p, o in zip(parts, offsets):
        start = n_of(o) if o > 0 else 0
        out[start:start + len(p)] += p
    return out


def at(x, seconds, total):
    """Places x at `seconds` inside a silent buffer of `total` seconds."""
    out = np.zeros(n_of(total))
    start = n_of(seconds) if seconds > 0 else 0
    end = min(len(out), start + len(x))
    out[start:end] += x[:end - start]
    return out


# ------------------------------------------------------------------ envelopes

def exp_decay(seconds, tau, attack=0.001):
    t = time(seconds)
    env = np.exp(-t / max(tau, 1e-5)) * taper(len(t))
    a = n_of(attack)
    if a > 1:
        env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def taper(n, portion=0.2):
    """1.0 then a cosine fall to exactly 0 over the last `portion` of n samples: nothing that
    decays ever ends with a click when its buffer runs out."""
    out = np.ones(n)
    k = max(1, int(n * portion))
    out[-k:] = 0.5 * (1 + np.cos(np.linspace(0, np.pi, k)))
    return out


def ar(seconds, attack, release, curve=2.0):
    """Attack then a curved release that reaches 0 at the end."""
    t = time(seconds)
    env = np.ones_like(t)
    a = n_of(attack)
    if a > 1:
        env[:a] = np.linspace(0.0, 1.0, a) ** 0.7
    r = n_of(release)
    if r > 1:
        env[-r:] *= np.linspace(1.0, 0.0, r) ** curve
    return env


def bell_env(seconds, peak=0.4, sharp=2.0):
    """Swells up to a peak at `peak` (0..1 of the length) then falls; for whooshes."""
    u = np.linspace(0.0, 1.0, n_of(seconds))
    rise = np.clip(u / max(peak, 1e-4), 0, 1) ** sharp
    fall = np.clip((1.0 - u) / max(1.0 - peak, 1e-4), 0, 1) ** sharp
    return np.where(u < peak, rise, fall)


def fade(x, fade_in=0.002, fade_out=0.01):
    x = x.copy()
    a, b = n_of(fade_in), n_of(fade_out)
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)[(...,) + (None,) * (x.ndim - 1)]
    if b > 1:
        x[-b:] *= np.linspace(1, 0, b)[(...,) + (None,) * (x.ndim - 1)]
    return x


# ------------------------------------------------------------------ oscillators

def phase_of(freq, seconds=None):
    """Integrates a frequency (Hz, scalar or per-sample array) into phase (radians)."""
    if np.isscalar(freq):
        freq = np.full(n_of(seconds), float(freq))
    return 2 * np.pi * np.cumsum(freq) / SR


def sine(freq, seconds=None, phase0=0.0):
    return np.sin(phase_of(freq, seconds) + phase0)


def glide(f0, f1, seconds, tau=None):
    """Exponential pitch glide from f0 to f1 (tau = how fast; None = linear in log-frequency)."""
    t = time(seconds)
    if tau is None:
        return f0 * (f1 / f0) ** (t / seconds)
    return f1 + (f0 - f1) * np.exp(-t / tau)


def saw(freq, seconds=None, partials=40):
    ph = phase_of(freq, seconds)
    out = np.zeros_like(ph)
    f_max = np.max(freq) if not np.isscalar(freq) else freq
    for k in range(1, partials + 1):
        if k * f_max > SR * 0.45:
            break
        out += np.sin(k * ph) / k
    return out * (2 / np.pi)


def pulse(freq, seconds=None, width=0.5, partials=30):
    """Band-limited pulse (sum of two saws)."""
    ph = phase_of(freq, seconds)
    out = np.zeros_like(ph)
    f_max = np.max(freq) if not np.isscalar(freq) else freq
    for k in range(1, partials + 1):
        if k * f_max > SR * 0.45:
            break
        out += np.sin(k * ph) / k - np.sin(k * (ph - 2 * np.pi * width)) / k
    return out * (1 / np.pi)


def partials(freqs, amps, decays, seconds, rng=None, detune=0.0):
    """Sum of decaying sine partials: bells, metal, glass."""
    t = time(seconds)
    out = np.zeros_like(t)
    for f, a, d in zip(freqs, amps, decays):
        if rng is not None and detune > 0:
            f = f * (1 + detune * rng.uniform(-1, 1))
        if f < SR * 0.45:
            out += a * np.sin(2 * np.pi * f * t + (rng.uniform(0, 6.28) if rng is not None else 0)) * np.exp(-t / d)
    return out * taper(len(t)) * np.minimum(1.0, t / 0.0008)


def fm_bell(freq, seconds, ratio=3.5, index=3.0, decay=0.6, index_decay=0.15):
    """Two-operator FM bell/chime."""
    t = time(seconds)
    mod_index = index * np.exp(-t / index_decay)
    mod = np.sin(2 * np.pi * freq * ratio * t)
    return np.sin(2 * np.pi * freq * t + mod_index * mod) * np.exp(-t / decay) * taper(len(t)) * np.minimum(1.0, t / 0.002)


# ------------------------------------------------------------------ filters

def _sos(kind, fc, order, sr=SR):
    nyq = sr / 2
    if kind in ("bandpass", "bandstop"):
        lo, hi = fc
        lo = max(10.0, lo) / nyq
        hi = min(hi, nyq * 0.98) / nyq
        return signal.butter(order, [lo, hi], btype=kind, output="sos")
    return signal.butter(order, min(max(fc, 10.0), nyq * 0.98) / nyq, btype=kind, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("lowpass", fc, order), x, axis=0)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("highpass", fc, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", (lo, hi), order), x, axis=0)


def peak_eq(x, fc, gain_db, q=1.0):
    """RBJ peaking EQ."""
    a_gain = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a_gain, -2 * np.cos(w0), 1 - alpha * a_gain]
    a = [1 + alpha / a_gain, -2 * np.cos(w0), 1 - alpha / a_gain]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def sweep_band(x, centers, width_oct=0.6, floor=0.0, nperseg=512):
    """Time-varying band-pass via STFT masking. `centers` is a callable u(0..1) -> Hz
    or an array of Hz values spread over the signal. Used for whooshes and wind."""
    hop = nperseg // 4
    f, t, z = signal.stft(x, SR, nperseg=nperseg, noverlap=nperseg - hop, boundary="zeros")
    u = np.clip(t / max(len(x) / SR, 1e-6), 0, 1)
    if callable(centers):
        c = np.array([centers(v) for v in u])
    else:
        c = np.interp(u, np.linspace(0, 1, len(centers)), centers)
    ff = np.maximum(f, 1.0)[:, None]
    mask = np.exp(-0.5 * (np.log2(ff / c[None, :]) / width_oct) ** 2)
    mask = floor + (1 - floor) * mask
    _, y = signal.istft(z * mask, SR, nperseg=nperseg, noverlap=nperseg - hop, boundary=True)
    return pad_to(y, len(x))


def formant(x, formants):
    """Vowel colouring: parallel band-passes [(center Hz, bandwidth Hz, gain)]."""
    out = np.zeros_like(x)
    for fc, bw, g in formants:
        out += g * bp(x, fc - bw / 2, fc + bw / 2, order=2)
    return out


# ------------------------------------------------------------------ dynamics / colour

def drive(x, amount=2.0):
    """tanh saturation, gain-compensated."""
    return np.tanh(x * amount) / np.tanh(amount)


def crush(x, steps=64):
    return np.round(x * steps) / steps


def soft_limit(x, ceiling=0.97):
    peak = np.max(np.abs(x)) + 1e-12
    if peak <= ceiling * 0.8:
        return x
    k = ceiling
    return k * np.tanh(x / k)


def normalize(x, peak_db=-1.0):
    peak = np.max(np.abs(x)) + 1e-12
    return x * (10 ** (peak_db / 20) / peak)


def loudness_db(x, window=0.05):
    """Loudest short-window RMS (dBFS): a rough 'how loud does it hit' measure."""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    w = n_of(window)
    if len(mono) <= w:
        return 20 * np.log10(np.sqrt(np.mean(mono ** 2)) + 1e-12)
    sq = np.convolve(mono ** 2, np.ones(w) / w, mode="valid")
    return 10 * np.log10(np.max(sq) + 1e-12)


def level(x, target_db, ceiling=0.97):
    """Sets the loudest 50 ms RMS to target_db, then soft-limits peaks."""
    gain = 10 ** ((target_db - loudness_db(x)) / 20)
    return soft_limit(x * gain, ceiling)


def trim_tail(x, threshold_db=-45.0, keep=0.02):
    """Cuts trailing near-silence (keeps a short fade)."""
    mono = np.abs(x if x.ndim == 1 else x.max(axis=1))
    thr = 10 ** (threshold_db / 20) * (mono.max() + 1e-12)
    idx = np.nonzero(mono > thr)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + n_of(keep))
    return fade(x[:end], 0.0, min(keep, 0.01))


# ------------------------------------------------------------------ space

def make_ir(seconds, rt60, rng, stereo=False, bright=0.5, predelay=0.012, early=True):
    """Synthetic room/hall impulse response: early taps + exponentially decaying noise that
    gets darker over time."""
    n = n_of(seconds)
    t = np.arange(n) / SR
    chans = []
    for c in range(2 if stereo else 1):
        noise = rng.standard_normal(n)
        dark = lp(noise, 2500.0, 1)
        brightx = hp(noise, 2500.0, 1)
        k = 6.91 / rt60
        tail = dark * np.exp(-t * k) + bright * brightx * np.exp(-t * k * 2.2)
        tail[: n_of(predelay)] = 0
        if early:
            for _ in range(10):
                d = rng.uniform(0.004, 0.06)
                tail[n_of(d)] += rng.uniform(-1, 1) * 1.5 * np.exp(-d * k)
        chans.append(tail / np.sqrt(np.sum(tail ** 2)))
    return np.stack(chans, axis=1) if stereo else chans[0]


def reverb(x, ir, wet=0.2, dry=1.0):
    """Convolution reverb; output length = len(x) + len(ir) - 1."""
    if x.ndim == 1 and ir.ndim == 1:
        w = signal.fftconvolve(x, ir)
        return dry * pad_to(x, len(w)) + wet * w
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    if ir.ndim == 1:
        ir = np.stack([ir, ir], axis=1)
    w = np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)
    return dry * pad_to(x, len(w)) + wet * w


def pan(x, position):
    """Equal-power pan of a mono signal; position -1 (left) .. +1 (right)."""
    a = (position + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


# ------------------------------------------------------------------ output

def write_ogg(path, x, quality=0.5, sr=SR):
    """Writes Ogg Vorbis. quality 0..1 (libsndfile compression_level = 1 - quality)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    channels = 1 if x.ndim == 1 else x.shape[1]
    # Written in blocks: libsndfile's Vorbis encoder overflows the stack on one long write (music).
    with sf.SoundFile(path, "w", sr, channels, format="OGG", subtype="VORBIS", compression_level=1.0 - quality) as f:
        for start in range(0, len(x), 8192):
            f.write(x[start:start + 8192])


def write_wav(path, x, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, np.clip(x, -1.0, 1.0).astype(np.float32), sr, subtype="PCM_16")


def resample_to(x, src_sr, dst_sr):
    if src_sr == dst_sr:
        return x
    from math import gcd
    g = gcd(int(src_sr), int(dst_sr))
    return signal.resample_poly(x, dst_sr // g, src_sr // g, axis=0)
