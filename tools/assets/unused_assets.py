#!/usr/bin/env python3
"""Finds files that nothing in the game references (docs/tech/unused_assets_2026-11-17.md).

  python tools/assets/unused_assets.py [--shipped files.tsv] [--json out.json]

Reference graph: roots = project.godot, export_presets include list, every script/scene/resource/data file in
client/ logic/ scenes/ data/ addons/ (they all ship), art/**/*.json|tscn|tres|gd. A file under art/ audio/ assets/ is
USED when a reachable file names its res:// path (or a res:// pattern with %s / {race} / a res:// folder prefix that
matches it). Dependencies of reached scenes/resources/glb (ext_resource, glb "uri") are followed. Lv15 chains from
client/item_assets.gd (<name>_lv15 variants, race_shared/<race>_<slot>(_lv15)) are expanded against data/races + slots.
Scripts that only exist for tests/tools do not count as references (tests/ tools/ docs/ art_source/ are not roots).
Without --shipped every file is a candidate; with --shipped (the TSV from tools/web/pack_files.gd) only files that
really land in the web pack are listed, with the size they cost (raw bytes in the pack, one texture format).
"""
import argparse
import collections
import fnmatch
import json
import os
import re
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXT_EXT = {'.gd', '.tscn', '.tres', '.json', '.cfg', '.gdshader', '.gdshaderinc', '.godot', '.gdc'}
ROOT_DIRS = ['client', 'logic', 'scenes', 'data', 'addons']
ART_TEXT = {'.json', '.tscn', '.tres', '.gd', '.gdshader', '.cfg'}
REF = re.compile(r'(?:res://)?((?:art|audio|assets|data|client|scenes|logic|addons)/[^\s"\'<>()\[\]|,;:]+)')
RES = re.compile(r'res://([^\s"\'<>()\[\]|,;]+)')
SLOTS = ['shirt', 'pants', 'armband', 'shoes']


def rel(p):
    return os.path.relpath(p, ROOT).replace('\\', '/')


def read_text(p):
    try:
        with open(p, 'rb') as f:
            return f.read().decode('utf-8', 'replace')
    except OSError:
        return ''


def glb_uris(p):
    """External image/buffer uris inside a .glb/.gltf json chunk."""
    try:
        with open(p, 'rb') as f:
            data = f.read()
    except OSError:
        return []
    if p.endswith('.glb'):
        if data[:4] != b'glTF':
            return []
        n = int.from_bytes(data[12:16], 'little')
        text = data[20:20 + n].decode('utf-8', 'replace')
    else:
        text = data.decode('utf-8', 'replace')
    return [unquote(u) for u in re.findall(r'"uri"\s*:\s*"([^"]+)"', text)]


def all_files():
    out = []
    for base, dirs, files in os.walk(ROOT):
        r = rel(base)
        if r == '.':
            dirs[:] = [d for d in dirs if d not in ('.git', '.godot', 'build', 'art_source', 'node_modules')]
        for fn in files:
            out.append(rel(os.path.join(base, fn)))
    return out


def pattern_regex(s):
    s = re.escape(s)
    s = s.replace(re.escape('%s'), '[^/]+').replace(re.escape('%d'), '[0-9]+').replace(re.escape('{race}'), '[^/_]+')
    s = re.sub(r'\\\{[a-z_]+\\\}', '[^/]+', s)
    return re.compile('^' + s + '$')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--shipped', default='')
    ap.add_argument('--json', default='')
    ap.add_argument('--debug', action='store_true', help='print the folder prefixes and patterns that were treated as references')
    args = ap.parse_args()
    files = all_files()
    fileset = set(files)

    races = [os.path.splitext(f)[0] for f in os.listdir(os.path.join(ROOT, 'data/races')) if f.endswith('.json') and f != 'rules.json']
    exact, patterns, prefixes = set(), [], set()

    skill_ids = set(re.findall(r'class_skill/([a-z_]+)', read_text(os.path.join(ROOT, 'data/class_skills/class_skills.json'))))
    for sid in skill_ids:  # client/skills/class_skill_vfx.gd: ROOT + <id> + "/effect.tscn"
        exact.add(f'art/vfx/class_skills/{sid}/effect.tscn')
    status_kinds = set(re.findall(r'"([a-z]+)"', read_text(os.path.join(ROOT, 'client/status_vfx.gd'))))
    for f in files:  # client/status_vfx.gd: ROOT + <status key> + "/effect.tscn"
        m = re.match(r'art/vfx/status/([a-z]+)/effect\.tscn$', f)
        if m and m.group(1) in status_kinds:
            exact.add(f)

    def add_ref(token):
        token = token.rstrip('.\\')
        if not token:
            return
        if '%' in token or '{' in token:
            patterns.append(pattern_regex(token))
        elif token.endswith('/'):
            prefixes.add(token)
        elif token in fileset:
            exact.add(token)
        elif '.' not in os.path.basename(token):
            prefixes.add(token)  # "res://art/x/" + name, or "res://art/x/prefix_" + name
        else:
            exact.add(token)

    roots = ['project.godot']
    for f in files:
        ext = os.path.splitext(f)[1]
        if f.split('/')[0] in ROOT_DIRS and ext in TEXT_EXT:
            roots.append(f)
        elif f.startswith('art/') and ext in ART_TEXT:
            roots.append(f)
    preset = read_text(os.path.join(ROOT, 'export_presets.cfg'))
    inc = re.search(r'(?m)^include_filter="([^"]*)"', preset)
    include = [x.strip() for x in inc.group(1).split(',')] if inc else []

    uid_of = {}  # uid://... -> source file (from .import files and .gd.uid / .tscn headers)
    for f in files:
        if f.endswith('.import'):
            m = re.search(r'(?m)^uid="(uid://[a-z0-9]+)"', read_text(os.path.join(ROOT, f)))
            if m:
                uid_of[m.group(1)] = f[:-7]
    reach, queue = set(), list(dict.fromkeys(roots))
    while queue:
        f = queue.pop()
        if f in reach or f not in fileset:
            continue
        reach.add(f)
        ext = os.path.splitext(f)[1]
        refs = []
        if ext in TEXT_EXT or f == 'project.godot':
            text = read_text(os.path.join(ROOT, f))
            refs = RES.findall(text) + REF.findall(text)
            if ext in ('.tscn', '.tres'):  # ext_resource path="effect.glb" is relative to the scene's folder
                for rp in re.findall(r'path="([^"]+)"', text):
                    if not rp.startswith(('res://', 'uid://')):
                        refs.append(os.path.normpath(os.path.join(os.path.dirname(f), rp)).replace(chr(92), '/'))
        elif ext in ('.res', '.scn'):  # binary resources keep their dependencies as res:// strings
            try:
                with open(os.path.join(ROOT, f), 'rb') as fh:
                    refs = [re.split(r'[\x00-\x1f\x7f-\xff]', r)[0] for r in RES.findall(fh.read().decode('latin-1'))]
            except OSError:
                refs = []
        elif ext in ('.glb', '.gltf'):
            base = os.path.dirname(f)
            for u in glb_uris(os.path.join(ROOT, f)):
                if not u.startswith('data:'):
                    refs.append(os.path.normpath(os.path.join(base, u)).replace('\\', '/'))
        if f + '.import' in fileset:  # use_external/path of extracted glb textures, uid-less references
            refs += [r for r in RES.findall(read_text(os.path.join(ROOT, f + '.import'))) if not r.startswith('.godot/')]
        if ext in TEXT_EXT:
            for u in re.findall(r'uid://[a-z0-9]+', read_text(os.path.join(ROOT, f))):
                if u in uid_of:
                    refs.append(uid_of[u])
        for r in refs:
            add_ref(r)
            if r in fileset and r not in reach:
                queue.append(r)
        if not queue:  # a wave ended: patterns and prefixes seen so far reach new files
            for g in files:
                if g not in reach and (g in exact or any(p.match(g) for p in patterns)):
                    queue.append(g)

    if args.debug:
        print('PREFIXES', sorted(prefixes))
        print('PATTERNS', sorted(p.pattern for p in patterns))
    used = set(reach) | set(exact)
    extra = set()
    for u in list(used):
        if u.startswith('art/weapons/race_') and '_lv15' not in u:
            stem, ext = os.path.splitext(u)
            extra.add(stem + '_lv15' + ext)
    for race in races:
        for slot in SLOTS:
            extra.add(f'art/armor/race_shared/{race}_{slot}_lv15.glb')
            extra.add(f'art/armor/race_shared/icon-{race}_{slot}_lv15.png')
    used |= {e for e in extra if e in fileset}
    for f in list(used):  # textures a used glb points at
        if os.path.splitext(f)[1] in ('.glb', '.gltf'):
            base = os.path.dirname(f)
            for u in glb_uris(os.path.join(ROOT, f)):
                if not u.startswith('data:'):
                    used.add(os.path.normpath(os.path.join(base, u)).replace('\\', '/'))
    for pat in include:
        used |= {f for f in files if fnmatch.fnmatch(f, pat)}

    # weaker evidence: the file's basename appears in a used script/data file (path built from folder + name)
    blob = '\n'.join(read_text(os.path.join(ROOT, f)) for f in used
                     if os.path.splitext(f)[1] in ('.gd', '.json', '.tscn', '.tres', '.cfg') and f.split('/')[0] in ROOT_DIRS + ['art'])
    by_base = collections.defaultdict(list)
    for f in files:
        by_base[os.path.basename(f)].append(f)
    basenames_used = set()
    for base, lst in by_base.items():
        if os.path.splitext(base)[1] in ('.import', '.uid', '.gd', '.json'):
            continue
        if base in blob:
            basenames_used.update(lst)

    pre_list = sorted(prefixes, key=len, reverse=True)

    def prefix_of(f):
        for p in pre_list:
            if f.startswith(p) and p not in ('', '.godot/'):
                return p
        return ''

    # a file's stem in quotes ("hub_panel_tabs") in a used script/data file: a name resolved at run time (ART_DIR + name + ".png")
    quoted = set(re.findall(r'["\']([A-Za-z0-9_\-]{3,60})["\']', blob))
    stems_used = {f for f in files if os.path.splitext(os.path.basename(f))[0] in quoted}

    shipped = None
    if args.shipped:
        shipped = collections.defaultdict(int)
        for line in open(args.shipped, encoding='utf-8'):
            p, s, pack, o = line.rstrip('\n').split('\t')
            if o.startswith('res://'):
                shipped[o[6:]] += 0 if pack.endswith('etc2') else int(s)
    result = []
    for f in files:
        if f.split('/')[0] not in ('art', 'audio', 'assets', 'data'):
            continue
        if os.path.splitext(f)[1] in ('.import', '.uid') or f in used:
            continue
        if shipped is not None and f not in shipped:
            continue
        size = os.path.getsize(os.path.join(ROOT, f))
        result.append((f, size, shipped[f] if shipped is not None else 0, (1 if f in basenames_used else 0) + (2 if f in stems_used else 0), prefix_of(f)))
    result.sort(key=lambda r: -(r[2] or r[1]))
    print('files scanned', len(files), 'reachable/used', len(used), 'candidates', len(result))
    for f, s, sh, bn, pf in result:
        print(f'{s / 1024:10.1f}KB shipped={sh / 1024:9.1f}KB evidence={int(bn)} prefix={pf or "-"} {f}')
    if args.json:
        json.dump([dict(path=f, bytes=s, shipped=sh, basename_hit=bn, prefix=pf) for f, s, sh, bn, pf in result], open(args.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
