#!/usr/bin/env python3
"""Build a minimal local room-worker image. Never tags/pushes a registry or applies k3s."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]

def module(name, source):
    spec = importlib.util.spec_from_file_location(name, source)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result

def main():
    binaries = module('worker_binaries', ROOT / 'server/names/build_images.py')
    smoke = module('room_prepare', ROOT / 'server/rooms/smoke.py')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=binaries.GODOT, default='linux/amd64')
    parser.add_argument('--image', default='zorx-room-worker:m4-1-local')
    args = parser.parse_args()
    arch, checksum = binaries.GODOT[args.platform]
    name = 'Godot_v4.7.2-stable_linux.' + arch
    archive = ROOT / 'build/names-binaries' / (name + '.zip')
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        urllib.request.urlretrieve('https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/' + name + '.zip', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum: raise ValueError('Official Godot checksum mismatch')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain', '--', 'server/rooms', 'server/shared', 'logic', 'data'], cwd=ROOT, text=True).strip(): revision += '-dirty'
    with tempfile.TemporaryDirectory(prefix='zorx-room-image-') as directory:
        root = Path(directory); project = root / 'project'; project.mkdir(); smoke.prepare(project)
        with zipfile.ZipFile(archive) as source: (root / 'godot').write_bytes(source.read(name))
        template = (ROOT / 'server/names/Dockerfile.worker').read_text()
        (root / 'Dockerfile').write_text(template.replace('res://server/names/worker.gd', 'res://server/rooms/worker.gd'))
        subprocess.run(['docker', 'build', '--platform', args.platform, '--label', 'org.opencontainers.image.revision=' + revision, '-t', args.image, str(root)], cwd=ROOT, check=True, timeout=600)
    print('Local room image built; no image push or deployment')

if __name__ == '__main__': main()
