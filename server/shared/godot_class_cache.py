"""Prepare global script types for minimal headless images without the editor or client assets."""
import json
from pathlib import Path
import re


def prepare(root):
    root = Path(root)
    rows = []
    for folder in (root / 'logic', root / 'data/skill_system/scripts', root / 'addons'):
        if not folder.exists():
            continue
        for path in sorted(folder.rglob('*.gd')):
            source = path.read_text()
            name = re.search(r'^class_name\s+(\w+)', source, re.M)
            base = re.search(r'^extends\s+(\w+)', source, re.M)
            if not name or not base:
                continue
            rows.append('{\n"base": &' + json.dumps(base[1]) + ',\n"class": &' + json.dumps(name[1]) + ',\n"icon": "",\n"is_abstract": false,\n"is_tool": false,\n"language": &"GDScript",\n"path": ' + json.dumps('res://' + path.relative_to(root).as_posix()) + '\n}')
    target = root / '.godot/global_script_class_cache.cfg'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('list=[' + ', '.join(rows) + ']\n')
