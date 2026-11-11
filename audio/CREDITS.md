# Audio credits and sources

Every sound in `audio/` is either synthesized by our own scripts or rendered from CC0 samples.
No audio from any other game (including the reference games) is used.

| Folder / files | How it was made | Source | Licence |
|---|---|---|---|
| `audio/sfx/*.ogg` (all) | Synthesized from scratch (numpy/scipy) by `tools/audio/make_sfx.py` + `tools/audio/dsp.py` | zorx team | Our own work |
| `audio/ambience/*.ogg` (ink garden, shrine, campfire) | Synthesized from scratch by `tools/audio/make_ambience.py` | zorx team | Our own work |
| `audio/music/*.ogg` (hub waltz, stage march, stingers) | Original compositions (note lists in `tools/audio/make_music.py`) rendered with `tools/audio/sampler.py` | Instrument samples: VSCO 2 Community Edition by Versilian Studios, https://github.com/sgossner/VSCO-2-CE | Samples: CC0 1.0 (copy in `audio_source/vsco2/LICENSE.txt`). Compositions: our own work |

The raw VSCO 2 samples are NOT shipped: `tools/audio/fetch_vsco2.py` downloads the subset we use
to `audio_source/vsco2/` (which has a `.gdignore`); only the rendered `.ogg` files ship.

Music direction (Boss, GDD "เสียงและดนตรี"): bright fantasy orchestra in the spirit of classic MMO
towns and fields, but entirely our own. No melody, chord loop, hook or arrangement was taken from
any reference game.

Regenerate everything:

    python tools/audio/make_sfx.py
    python tools/audio/fetch_vsco2.py   # once
    python tools/audio/make_music.py
    python tools/audio/make_ambience.py
