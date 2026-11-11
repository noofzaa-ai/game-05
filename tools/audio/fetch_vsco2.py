"""Downloads the part of the VSCO 2 Community Edition orchestral sample library (CC0 1.0,
https://github.com/sgossner/VSCO-2-CE) that make_music.py uses to render OUR OWN compositions.

The raw samples are NOT shipped with the game: they go to audio_source/vsco2/ (which has a
.gdignore, so Godot neither imports nor exports them). Only the rendered .ogg tracks ship.

    python tools/audio/fetch_vsco2.py
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEST = os.path.join(ROOT, "audio_source", "vsco2")
REPO = "sgossner/VSCO-2-CE"
TREE = "https://api.github.com/repos/%s/git/trees/master?recursive=1" % REPO
RAW = "https://raw.githubusercontent.com/%s/master/" % REPO

# (folder prefix, required substrings, rejected substrings)
WANTED = [
    ("Strings/Violin Section/susVib/", [], []),
    ("Strings/Viola Section/susvib/", [], []),
    ("Strings/Cello Section/susvib/", [], []),
    ("Strings/Violin Section/Pizz/", ["rr1"], []),
    ("Strings/Cello Section/pizzT/", ["RR1"], []),
    ("Strings/Violin Section/Spic/", ["rr1"], []),
    ("Strings/Cello Section/spic/", ["RR1"], []),
    ("Strings/Solo Contrabass/Pizz/", ["rr1"], []),
    ("Strings/Harp/", [], []),
    ("Woodwinds/Flute/susvib/", [], []),
    ("Woodwinds/Flute/stac/", ["rr1"], []),
    ("Woodwinds/Clarinet/susLong/", [], []),
    ("Woodwinds/Oboe/Vib/", [], []),
    ("Brass/F Horn/sus/", [], []),
    ("Brass/F Horn/stac/", ["rr1"], []),
    ("Percussion/Glock/", [], []),
    ("Percussion/Timpani/Timpani", ["Hit", "rr1"], []),
    ("Percussion/Marimba/", [], []),
    ("Percussion/cymbal-crash1_", ["rr1"], []),
    ("Percussion/susCymb1-cresc", [], []),
    ("Percussion/BDrumNewhit_", ["rr1"], []),
    ("Percussion/Snare2-HitSN_", ["rr1"], []),
    ("Percussion/Triangle3-Hit_", ["rr1"], []),
    ("Percussion/Tamb1-Hit_", [], []),
    ("Percussion/Tamb1-Shake_", [], []),
    ("Percussion/gongHit_", [], []),
]


def wanted(path):
    for prefix, need, reject in WANTED:
        if path.startswith(prefix) and path.lower().endswith(".wav"):
            if all(n in path for n in need) and not any(r in path for r in reject):
                return True
    return False


def fetch(path):
    out = os.path.join(DEST, path.replace("/", os.sep))
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return 0
    os.makedirs(os.path.dirname(out), exist_ok=True)
    url = RAW + urllib.parse.quote(path)
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    with open(out + ".part", "wb") as f:
        f.write(data)
    os.replace(out + ".part", out)
    return len(data)


def main():
    with urllib.request.urlopen(TREE, timeout=60) as response:
        tree = json.load(response)
    paths = [x["path"] for x in tree["tree"] if x["type"] == "blob" and wanted(x["path"])]
    print("%d files to fetch" % len(paths))
    with ThreadPoolExecutor(8) as pool:
        total = sum(pool.map(fetch, paths))
    with urllib.request.urlopen(RAW + "LICENSE", timeout=60) as response:
        with open(os.path.join(DEST, "LICENSE.txt"), "wb") as f:
            f.write(response.read())
    print("downloaded %.1f MB into %s" % (total / 1e6, DEST))


if __name__ == "__main__":
    sys.exit(main())
