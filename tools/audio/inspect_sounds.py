"""Draws waveform + spectrogram sheets of rendered sounds, for checking layering and tails by eye.

    python tools/audio/inspect_sounds.py out.png audio/sfx/hit_heavy_1.ogg audio/sfx/ui_click.ogg ...
"""
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402


def main(out, paths):
    fig, axes = plt.subplots(len(paths), 2, figsize=(14, 2.2 * len(paths)), squeeze=False)
    for row, path in enumerate(paths):
        x, sr = sf.read(path)
        mono = x if x.ndim == 1 else x.mean(axis=1)
        t = np.arange(len(mono)) / sr
        axes[row][0].plot(t, mono, lw=0.5)
        axes[row][0].set_ylim(-1, 1)
        axes[row][0].set_title(path.replace("\\", "/").split("/")[-1], fontsize=8, loc="left")
        axes[row][1].specgram(mono + 1e-9, NFFT=512, Fs=sr, noverlap=384, cmap="magma", vmin=-120)
        axes[row][1].set_ylim(0, 12000)
    fig.tight_layout()
    fig.savefig(out, dpi=70)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
