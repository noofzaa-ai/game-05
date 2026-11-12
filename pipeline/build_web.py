#!/usr/bin/env python3
"""Build zorx's existing split-PCK Web distribution on macOS/Linux."""
import argparse
import datetime
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
MIB = 1024 * 1024
from build_metadata import write as write_build_metadata


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-tests', action='store_true', help='Skip the Godot test suite')
    parser.add_argument('--pack-base', default='', help='Absolute HTTP(S) directory URL for packs; default: same origin')
    parser.add_argument('--godot-bin', default=os.environ.get('GODOT_BIN', ''), help='Godot executable, or set GODOT_BIN')
    parser.add_argument('--timeout', type=int, default=600, help='Timeout in seconds per Godot step (default: 600)')
    parser.add_argument('--max-file-mb', type=float, default=15, help='Reject files at/above this MiB size; 0 disables the artifact-host limit')
    args = parser.parse_args()
    if args.timeout <= 0 or not math.isfinite(args.max_file_mb) or args.max_file_mb < 0:
        parser.error('timeout must be positive and max-file-mb must be finite and nonnegative')
    if args.pack_base:
        url = urlsplit(args.pack_base)
        if url.scheme not in ('http', 'https') or not url.netloc or url.username or url.password or url.query or url.fragment:
            parser.error('pack-base must be an absolute HTTP(S) directory URL without credentials, query or fragment')
        args.pack_base = args.pack_base.rstrip('/') + '/'
    return args


def godot_binary(value):
    if value:
        candidate = shutil.which(value) or str(Path(value).expanduser().resolve())
    else:
        candidate = shutil.which('godot') or shutil.which('godot4')
        if not candidate and Path('/Applications/Godot.app/Contents/MacOS/Godot').is_file():
            candidate = '/Applications/Godot.app/Contents/MacOS/Godot'
    if not candidate or not Path(candidate).is_file() or not os.access(candidate, os.X_OK):
        raise RuntimeError('Godot not found. Set GODOT_BIN or --godot-bin to the Godot 4.7.2 executable.')
    version = subprocess.run([candidate, '--version'], capture_output=True, text=True, timeout=30, check=True).stdout.strip()
    if not re.match(r'^4\.7\.2(?:\.|$)', version):
        raise RuntimeError(f'Expected Godot 4.7.2 to match the team; found {version!r}')
    print(f'Godot: {candidate} ({version})', flush=True)
    return candidate


def invoke(binary, name, argv, logs, timeout):
    out, err = logs / (name + '.out.log'), logs / (name + '.err.log')
    print(f'  {name}: logs {out}', flush=True)
    with out.open('w') as stdout, err.open('w') as stderr:
        # A separate session lets timeout/interrupt terminate the whole child group on Unix.
        process = subprocess.Popen([binary, '--headless', '--path', str(ROOT)] + argv,
                                   cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            import signal
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise RuntimeError(f'{name} interrupted or exceeded {timeout}s; logs: {logs}')
    errors = err.read_text(errors='replace')
    if code != 0 or re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:)', errors):
        print(errors[-6000:], file=sys.stderr)
        raise RuntimeError(f'{name} failed (exit {code}); logs: {logs}')
    return out.read_text(errors='replace')


def publish(source, name, suffix, destination):
    if not source.is_file() or not source.stat().st_size:
        raise RuntimeError(f'Missing/empty build output: {source}')
    digest = hashlib.sha256()
    with source.open('rb') as stream:
        for chunk in iter(lambda: stream.read(MIB), b''):
            digest.update(chunk)
    short_hash = digest.hexdigest()[:12]
    filename = f'{name}.{short_hash}.{suffix}'
    with source.open('rb') as stream, (destination / filename).open('wb') as target:
        with gzip.GzipFile(filename='', fileobj=target, mode='wb', compresslevel=9, mtime=0) as packed:
            shutil.copyfileobj(stream, packed)
    return dict(file=filename, bytes=(destination / filename).stat().st_size,
                raw_bytes=source.stat().st_size, hash=short_hash)


def package(stage, args):
    split = stage / '_split'
    report = json.loads((split / 'split.json').read_text(encoding='utf-8-sig'))
    if not isinstance(report, list) or not any(p.get('name') == 'core' for p in report):
        raise RuntimeError('Invalid split.json: expected pack entries including core')
    engine = publish(stage / 'index.wasm', 'engine', 'wasm', stage)
    core = publish(split / 'core.pck', 'core', 'pck.wasm', stage)
    packs, seen = [], set()
    for entry in report:
        name = entry['name']
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*', name) or name in seen:
            raise RuntimeError(f'Invalid/duplicate pack name: {name!r}')
        seen.add(name)
        if name == 'core':
            continue
        part = publish(split / (name + '.pck'), name, 'pck.wasm', stage)
        load_stage = entry.get('stage', 'boot')
        if load_stage not in ('boot', 'battle'):
            raise RuntimeError(f'Invalid stage for pack {name!r}: {load_stage!r}')
        packs.append(dict(name=name, stage=load_stage, format=entry.get('format', ''), file=part['file'],
                          bytes=part['bytes'], raw_bytes=part['raw_bytes']))
    seed = '|'.join([engine['hash'], core['hash']] + [p['file'] for p in packs])
    build_id = hashlib.sha256(seed.encode()).hexdigest()[:12]
    built = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    metadata = json.loads((ROOT / 'data/ui/build_info.json').read_text())
    manifest = dict(source=metadata, build=build_id, built=built, engine=engine['file'], engine_bytes=engine['bytes'],
                    core=core['file'], core_bytes=core['bytes'], packs=packs)
    (stage / 'packs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    index = (stage / 'index.html').read_text(encoding='utf-8-sig')
    match = re.search(r'const GODOT_CONFIG\s*=\s*(\{.*?\});', index, re.S)
    if not match:
        raise RuntimeError('GODOT_CONFIG not found in exported index.html')
    config = json.loads(match[1])
    if config.get('gdextensionLibs'):
        raise RuntimeError('This pipeline expects the existing non-extension Web preset')
    config['ensureCrossOriginIsolationHeaders'] = False
    config.setdefault('fileSizes', {})['index.pck'] = core['raw_bytes']
    formats = [p['format'] for p in packs if p['format']]
    pick = formats[0] if formats else ''
    # First download (what the loading page shows): engine + core + the boot packs, one texture format.
    # The battle packs load in the background on the card screen (client/pack_fetcher.gd).
    device = [p for p in packs if not p['format'] or p['format'] == pick]
    download = engine['bytes'] + core['bytes'] + (stage / 'index.js').stat().st_size
    battle = sum(p['bytes'] for p in device if p['stage'] == 'battle')
    download += sum(p['bytes'] for p in device if p['stage'] == 'boot')
    background = ROOT / 'assets/ui/camp_menu/farm-v1.png'
    background_name = 'loading.' + hashlib.sha256(background.read_bytes()).hexdigest()[:12] + '.png'
    shutil.copyfile(background, stage / background_name)
    page = (ROOT / 'tools/web/play_template.html').read_text(encoding='utf-8-sig')
    # The existing template embeds PACK_BASE inside a single-quoted JS literal.
    safe_base = json.dumps(args.pack_base, ensure_ascii=True)[1:-1].replace("'", '\\u0027').replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    substitutions = {'__LOADING_BACKGROUND__': background_name, '__GODOT_CONFIG__': json.dumps(config, separators=(',', ':')),
                     '__SIZE_MB__': str(math.ceil(download / MIB)), '__BUILD_DATE__': built,
                     '__BUILD_ID__': build_id, '__PACK_BASE__': safe_base,
                     '__SOURCE_DATE__': metadata['source_date'],
                     '__COMMIT__': metadata['short_commit'] + (' + local changes' if metadata['dirty'] else '')}
    # One pass: user-supplied text cannot become a second template placeholder.
    page = re.sub('|'.join(map(re.escape, substitutions)), lambda m: substitutions[m[0]], page)
    (stage / 'play.html').write_text(page, encoding='utf-8')
    for filename in ('index.html', 'index.pck', 'index.wasm'):
        (stage / filename).unlink()
    shutil.rmtree(split)
    print(f'\nPer device ({pick or "no"} textures): boot download {download / MIB:.2f} MiB, '
          f'battle download {battle / MIB:.2f} MiB, total {(download + battle) / MIB:.2f} MiB')
    print(f'\nSize table (build {build_id}):')
    oversized = []
    for file in sorted(stage.iterdir(), key=lambda p: p.stat().st_size, reverse=True):
        if not file.is_file():
            continue
        size = file.stat().st_size / MIB
        print(f'  {file.name:48} {size:8.2f} MiB')
        if args.max_file_mb and size >= args.max_file_mb:
            oversized.append(file.name)
    if oversized:
        raise RuntimeError(f'Files reach/exceed {args.max_file_mb:g} MiB: {oversized}. For your own host, use --max-file-mb 0.')
    return build_id


def main():
    args = arguments()
    binary = godot_binary(args.godot_bin)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    lock = build / '.web-build.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        raise RuntimeError(f'Another Web build may be running ({lock}); inspect it before removing a stale lock.')
    stage = None
    try:
        (lock / 'pid').write_text(str(os.getpid()))
        logs = Path(tempfile.mkdtemp(prefix='web-', dir=build))
        print(f'Logs: {logs}', flush=True)
        print('1/6 Import assets', flush=True)
        invoke(binary, 'import', ['--editor', '--import'], logs, args.timeout)
        invoke(binary, 'skill-flipbooks', ['--script', 'res://tools/art/optimize_skill_scenes.gd'], logs, args.timeout)
        write_build_metadata()
        print('2/6 Tests' + (' (skipped)' if args.skip_tests else ''), flush=True)
        if not args.skip_tests:
            result = invoke(binary, 'tests', ['--script', 'res://tests/run_all.gd'], logs, args.timeout)
            summaries = re.findall(r'passed=(\d+) failed=(\d+)', result)
            if not summaries or int(summaries[-1][1]) != 0:
                raise RuntimeError(f'Tests failed or did not finish; logs: {logs}')
            print('  passed=%s failed=%s' % summaries[-1])
        stage = Path(tempfile.mkdtemp(prefix='.web-staging-', dir=build))
        print('3/6 Export Web preset (requires matching Web export templates)', flush=True)
        invoke(binary, 'export', ['--export-release', 'Web', str(stage / 'index.html')], logs, args.timeout)
        print('4/6 Split PCK', flush=True)
        split = stage / '_split'
        split.mkdir()
        invoke(binary, 'split', ['--script', 'res://tools/web/pck_split.gd', '--', str(stage / 'index.pck'),
                                str(ROOT / 'tools/web/pack_layout.json'), str(split)], logs, args.timeout)
        print('5/6 Compress and hash packs\n6/6 Write manifest and play.html', flush=True)
        build_id = package(stage, args)
        subprocess.run([sys.executable, str(ROOT / "tools/web/verify_mall_pack.py"), str(stage)], check=True, timeout=30)
        destination = build / 'web'
        # Keep the artifact-link metadata used by the existing Windows workflow.
        if (destination / '.claude').is_dir():
            shutil.copytree(destination / '.claude', stage / '.claude')
        previous = build / (stage.name + '-previous')
        if destination.exists():
            destination.rename(previous)
        try:
            stage.rename(destination)
        except BaseException:
            if previous.exists():
                previous.rename(destination)
            raise
        if previous.exists():
            shutil.rmtree(previous)
        stage = None
        print(f'\nDone: {destination} (build {build_id})\nServe play.html; upload every output file. No deployment was performed.')
    finally:
        if stage is not None and stage.exists():
            print(f'Incomplete build retained for diagnosis: {stage}', file=sys.stderr)
        shutil.rmtree(lock)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
