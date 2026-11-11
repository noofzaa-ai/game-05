#!/usr/bin/env python3
"""Replace Goblin scenery only over the currently deployed split packs."""
import argparse, gzip, hashlib, json, os, re, shutil
from pathlib import Path
from build_gem_patch import entries, raw, pack_files

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
args = ap.parse_args()
base, out = args.baseline, args.output
out.mkdir(parents=True, exist_ok=True)
manifest = json.loads((base / 'packs.json').read_text())
old_build = manifest['build']
descriptor = next(p for p in manifest['packs'] if p['name'] == 'goblin-base' and not p.get('format'))
original = entries(raw(base / descriptor['file']))
files = dict(original)
changed = []
for folder, suffix in [('art/maps/goblin_base', '.tscn'), ('art/props/goblin_base/meshes', '.res')]:
    for path in sorted((ROOT / folder).glob('*' + suffix)):
        key = path.relative_to(ROOT).as_posix()
        assert key in files, key
        files[key] = path.read_bytes()
        changed.append(key)
assert len(changed) == 15
assert all(files[key] == value for key, value in original.items() if key not in changed)
packed = pack_files(out, files, '/Applications/Godot.app/Contents/MacOS/Godot')
assert entries(packed) == files
filename = 'goblin-base.' + hashlib.sha256(packed).hexdigest()[:12] + '.pck.wasm'
web = out / 'web'
shutil.copytree(base, web, copy_function=lambda src, dst: shutil.copy2(src, dst) if Path(src).name in ['packs.json', 'play.html'] else os.link(src, dst))
compressed = gzip.compress(packed, compresslevel=9, mtime=0)
(web / filename).write_bytes(compressed)
old_file = descriptor['file']
descriptor.update(file=filename, bytes=len(compressed), raw_bytes=len(packed))
build = hashlib.sha256('|'.join([manifest['engine'], manifest['core']] + [p['file'] for p in manifest['packs']]).encode()).hexdigest()[:12]
manifest['build'] = build
(web / 'packs.json').write_text(json.dumps(manifest, indent=2) + '\n')
(web / 'play.html').write_text((web / 'play.html').read_text().replace(old_build, build))
if old_file != filename: (web / old_file).unlink()
(out / 'patch-report.json').write_text(json.dumps({'build': build, 'baseline': old_build, 'changed': changed, 'old_pack': old_file, 'new_pack': filename, 'gzip_delta': len(compressed) - (base / old_file).stat().st_size}, indent=2) + '\n')
print((out / 'patch-report.json').read_text())
