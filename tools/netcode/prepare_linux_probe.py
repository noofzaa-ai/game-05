#!/usr/bin/env python3
"""Download/verify the official Godot4.7.2 Linux x86_64 probe binary. No game export."""
import hashlib
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
NAME = 'Godot_v4.7.2-stable_linux.x86_64'
URL = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/' + NAME + '.zip'
SHA256 = 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'


def main():
    target = ROOT/'build/linux-probe'
    target.mkdir(parents=True, exist_ok=True)
    archive = target/'godot-linux.zip'
    if not archive.exists(): urllib.request.urlretrieve(URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError('Official binary checksum mismatch; refusing extraction')
    with zipfile.ZipFile(archive) as source:
        (target/NAME).write_bytes(source.read(NAME))
    (target/NAME).chmod(0o755)
    (target/'.dockerignore').write_text('godot-linux.zip\n')
    print('Verified official Linux x86_64 Godot4.7.2; binary ready under build/linux-probe')


if __name__ == '__main__': main()
