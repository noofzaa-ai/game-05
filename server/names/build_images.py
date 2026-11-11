#!/usr/bin/env python3
"""Build two server images from minimal temporary contexts; no Secrets, no remote apply."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GODOT = {
    'linux/amd64': ('x86_64', 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'),
    'linux/arm64': ('arm64', '5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-tests', action='store_true', help='Build without running tests')
    parser.add_argument('--platform', choices=GODOT, default='linux/amd64')
    parser.add_argument('--worker-image', default='zorx-name-validator:m3-4-local')
    parser.add_argument('--nakama-image', default='zorx-nakama:m3-4-local')
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain', '--', 'logic', 'data', 'server/names', 'server/profile', 'server/shared'], cwd=ROOT, text=True).strip():
        revision += '-dirty'
    labels = ['--label', 'org.opencontainers.image.revision=' + revision, '--label', 'org.opencontainers.image.source=https://github.com/grislyhub/zorx']
    runtime = HERE / 'runtime'
    subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=runtime, check=True, timeout=180)
    subprocess.run(['npm', 'run', 'build'], cwd=runtime, check=True, timeout=120)
    if not args.skip_tests:
        subprocess.run(['npm', 'test'], cwd=runtime, check=True, timeout=60)
    arch, checksum = GODOT[args.platform]
    cache = ROOT / 'build/names-binaries'
    cache.mkdir(parents=True, exist_ok=True)
    name = 'Godot_v4.7.2-stable_linux.' + arch
    archive = cache / (name + '.zip')
    existing = ROOT / 'build/linux-probe/godot-linux.zip'
    if not archive.exists() and arch == 'x86_64' and existing.exists(): shutil.copy2(existing, archive)
    if not archive.exists():
        urllib.request.urlretrieve('https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/' + name + '.zip', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
        raise ValueError('Official Godot archive checksum mismatch')
    spec = importlib.util.spec_from_file_location('smoke_worker', HERE / 'smoke_worker.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='zorx-name-images-') as temporary:
        folder = Path(temporary)
        worker = folder / 'worker'; worker.mkdir()
        project = worker / 'project'; project.mkdir()
        module.prepare(project)
        with zipfile.ZipFile(archive) as source: (worker / 'godot').write_bytes(source.read(name))
        shutil.copy2(HERE / 'Dockerfile.worker', worker / 'Dockerfile')
        subprocess.run(['docker', 'build', '--platform', args.platform, *labels, '-t', args.worker_image, str(worker)], check=True, timeout=600)
        nakama = folder / 'nakama'; nakama.mkdir()
        shutil.copy2(ROOT / 'build/names-runtime/index.js', nakama / 'index.js')
        shutil.copy2(HERE / 'Dockerfile.nakama', nakama / 'Dockerfile')
        subprocess.run(['docker', 'build', '--platform', args.platform, *labels, '-t', args.nakama_image, str(nakama)], check=True, timeout=600)
    report = dict(revision=revision, platform=args.platform, worker=args.worker_image, nakama=args.nakama_image,
                  godot_archive_sha256=checksum,
                  runtime_sha256=hashlib.sha256((ROOT / 'build/names-runtime/index.js').read_bytes()).hexdigest())
    (ROOT / 'build/names-images.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Built server images locally; report: build/names-images.json')


if __name__ == '__main__':
    main()
