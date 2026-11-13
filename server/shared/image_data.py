"""Copy the data/ folders the headless logic actually loads into a minimal worker image context.

The list is derived from the GDScript sources, so a new data/<folder> used by logic/ or server/
is packaged automatically instead of failing at runtime with an empty folder (2026-11-13 audit:
races, relics, progression, skill_tree and classes were missing from the worker images)."""
from pathlib import Path
import re
import shutil

PATTERN = re.compile(r'res://data/([A-Za-z0-9_]+)/')
SOURCES = ('logic', 'server/rooms', 'server/profile', 'server/names', 'server/shared', 'runtime/netfox')


def folders(root):
    root = Path(root)
    found = set()
    for source in SOURCES:
        for path in (root / source).rglob('*.gd'):
            found.update(PATTERN.findall(path.read_text(encoding='utf-8', errors='replace')))
    return sorted(name for name in found if (root / 'data' / name).is_dir())


def copy(source_root, destination, required=()):
    source_root = Path(source_root)
    names = sorted(set(folders(source_root)) | set(required))
    for name in names:
        shutil.copytree(source_root / 'data' / name, Path(destination) / 'data' / name,
                        ignore=shutil.ignore_patterns('*.import', '*.uid'))
    return names
