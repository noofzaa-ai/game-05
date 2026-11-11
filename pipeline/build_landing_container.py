#!/usr/bin/env python3
"""Build the sibling landing site from an explicit public-source allowlist; never copy .env."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT.parent / 'zorx_web')
    parser.add_argument('--image', required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='zorx-landing-') as directory:
        context = Path(directory)
        for name in ['package.json', 'package-lock.json', 'index.html', 'config.js', 'trail.js', 'auth.js', 'styles.css']:
            shutil.copy2(args.source / name, context / name)
        for name in ['server', 'assets', 'admin']:
            shutil.copytree(args.source / name, context / name, ignore=shutil.ignore_patterns('.env', '*.pem', 'node_modules', '.DS_Store'))
        # Versioned admin overlay; authentication continues in the existing landing server.
        overlay = ROOT / 'server/landing/dashboard'
        if overlay.exists(): shutil.copytree(overlay, context, dirs_exist_ok=True)
        shutil.copy2(ROOT / 'pipeline/Dockerfile.landing', context / 'Dockerfile')
        subprocess.run(['docker', 'build', '--platform', 'linux/amd64', '-t', args.image, str(context)], check=True, timeout=600)

if __name__ == '__main__':
    main()
