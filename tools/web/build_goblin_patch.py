#!/usr/bin/env python3
"""Release the prepared Goblin region over an immutable deployed split-pack Web."""
import argparse, datetime, gzip, hashlib, json, os, re, shutil
from pathlib import Path
from zoneinfo import ZoneInfo
from build_gem_patch import entries, raw, pack_files

ROOT = Path(__file__).resolve().parents[2]
MAPS = ['goblin_base_gate', 'goblin_base_courtyard', 'goblin_base_quarry', 'goblin_base_chief', 'goblin_base_rest']
PATCH = ['client/world_map_screen.gd', 'client/world_map.gdshader', 'data/maps/index.json', 'data/journeys/ink_road.json'] + ['data/maps/'+name+'.json' for name in MAPS]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--baseline', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args(); base = a.baseline; out = a.output
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((base/'packs.json').read_text())
    old_build = manifest['build']; old_core = manifest['core']
    original = entries(raw(base/old_core)); files = dict(original); allowed = set()
    # Geometry/route only; preserve every combat, reward and skill tuning value.
    before = json.loads(original['data/journeys/ink_road.json'])
    after = json.loads((ROOT/'data/journeys/ink_road.json').read_text())
    route_keys = {'name', 'blurb', '_design', 'world_region', 'combat_maps', 'arena_maps', 'camp_map', 'boss_map'}
    assert all(before.get(k) == after.get(k) for k in before.keys() | after.keys() if k not in route_keys)
    for name in PATCH:
        for key in [name, name+'c', name+'.remap']:
            files.pop(key, None); allowed.add(key)
        files[name] = (ROOT/name).read_bytes()
    now = datetime.datetime.now(ZoneInfo('Asia/Bangkok'))
    meta = dict(manifest['source'], baseline_build=old_build, patch_paths=PATCH,
                source_modified=now.isoformat(), source_date=now.strftime('%Y-%m-%d %H:%M:%S UTC+07:00'))
    files['data/ui/build_info.json'] = (json.dumps(meta, indent=2)+'\n').encode()
    allowed.add('data/ui/build_info.json')
    assert all(files[k] == v for k, v in original.items() if k not in allowed)
    godot = '/Applications/Godot.app/Contents/MacOS/Godot'
    core = pack_files(out, files, godot); assert entries(core) == files
    web = out/'web'; shutil.copytree(base, web, copy_function=lambda src,dst: shutil.copy2(src,dst) if Path(src).name in ["packs.json","play.html"] else os.link(src,dst), dirs_exist_ok=True)
    digest = hashlib.sha256(core).hexdigest()[:12]; core_name = 'core.'+digest+'.pck.wasm'
    (web/core_name).write_bytes(gzip.compress(core, compresslevel=9, mtime=0))
    for path in web.glob('core.*.pck.wasm'):
        if path.name != core_name: path.unlink()
    groups = {'goblin-base': {}, 'goblin-base.s3tc': {}, 'goblin-base.etc2': {}}
    for folder, suffix in [('art/maps/goblin_base', '.tscn'), ('art/props/goblin_base/meshes', '.res')]:
        for path in (ROOT/folder).glob('*'+suffix):
            groups['goblin-base'][path.relative_to(ROOT).as_posix()] = path.read_bytes()
    for path in (ROOT/'art/props/goblin_base/shared').glob('*.import'):
        groups['goblin-base'][path.relative_to(ROOT).as_posix()] = path.read_bytes()
        for target in set(re.findall(r'"(res://\.godot/imported/[^"\n]+)"', path.read_text())):
            name = target.removeprefix('res://')
            group = 'goblin-base.s3tc' if '.s3tc.' in name else 'goblin-base.etc2' if '.etc2.' in name else 'goblin-base'
            groups[group][name] = (ROOT/name).read_bytes()
    added = []
    for group, assets in groups.items():
        (out/group).mkdir(exist_ok=True)
        data = pack_files(out/group, assets, godot); assert entries(data) == assets
        filename = group+'.'+hashlib.sha256(data).hexdigest()[:12]+'.pck.wasm'
        compressed = gzip.compress(data, compresslevel=9, mtime=0); (web/filename).write_bytes(compressed)
        desc = dict(name=group, format=group.split('.')[1] if '.' in group else '', file=filename, bytes=len(compressed), raw_bytes=len(data))
        manifest['packs'].append(desc); added.append(desc)
    seed = '|'.join([manifest['engine'].split('.')[1], digest]+[p['file'] for p in manifest['packs']])
    build = hashlib.sha256(seed.encode()).hexdigest()[:12]
    manifest.update(build=build, core=core_name, core_bytes=(web/core_name).stat().st_size, source=meta)
    (web/'packs.json').write_text(json.dumps(manifest, indent=2)+'\n')
    page = (web/'play.html').read_text().replace(old_build, build)
    page = re.sub(r'("index.pck"\s*:\s*)\d+', lambda m: m[1]+str(len(core)), page)
    (web/'play.html').write_text(page)
    for pack in json.loads((base/'packs.json').read_text())['packs']:
        assert (web/pack['file']).read_bytes() == (base/pack['file']).read_bytes()
    report = dict(build=build, baseline=old_build, paths=PATCH, unrelated_core_and_existing_packs_identical=True,
                  combat_and_rewards_identical=True, asset_packs=added,
                  core_gzip_delta=manifest['core_bytes']-json.loads((base/'packs.json').read_text())['core_bytes'])
    (out/'patch-report.json').write_text(json.dumps(report, indent=2)+'\n'); print(json.dumps(report))

if __name__ == '__main__':
    main()
