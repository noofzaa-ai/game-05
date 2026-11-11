"""One source of build identity for the Web shell and Godot title screen."""
import datetime
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def collect(root=ROOT):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    revision = git('rev-parse', 'HEAD')
    paths = git('ls-files', '-z').split('\0')
    # Ignore generated metadata itself: regenerating it must not advance source time.
    modified = max((root / p).stat().st_mtime for p in paths
                   if p and p != 'data/ui/build_info.json' and (root / p).is_file())
    stamp = datetime.datetime.fromtimestamp(modified, datetime.timezone(datetime.timedelta(hours=7)))
    return {'channel': 'BETA-TEST', 'commit': revision, 'short_commit': revision[:12],
            'dirty': bool(git('status', '--porcelain', '--untracked-files=no', '--', '.', ':(exclude)data/ui/build_info.json')),
            'source_modified': stamp.isoformat(timespec='seconds'),
            'source_date': stamp.strftime('%Y-%m-%d %H:%M:%S UTC+07:00')}

def write(root=ROOT):
    data = collect(root)
    (root / 'data/ui/build_info.json').write_text(json.dumps(data, indent=2) + '\n')
    return data

if __name__ == '__main__':
    print(json.dumps(write(), indent=2))
