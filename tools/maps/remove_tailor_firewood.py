#!/usr/bin/env python3
"""Remove the four legacy firewood logs and their collider, preserving other map data."""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def remove(path):
    data = path.read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + size])
    raw = bytearray(data[28 + size:])
    if doc['asset'].get('extras', {}).get('tailor_firewood_removed'):
        return
    primitive = next(m for m in doc['meshes'] if m['name'] == 'camp_paint')['primitives'][0]
    def read(index):
        a = doc['accessors'][index]
        v = doc['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC3': 3}[a['type']]
        fmt = {5126: 'f', 5123: 'H', 5125: 'I'}[a['componentType']]
        stride = v.get('byteStride', struct.calcsize(fmt) * width)
        offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from('<' + fmt * width, raw, offset + i * stride) for i in range(a['count'])]
    positions = read(primitive['attributes']['POSITION'])
    indices = [row[0] for row in read(primitive['indices'])]
    kept = []
    removed = 0
    for start in range(0, len(indices), 3):
        triangle = indices[start:start + 3]
        if all(-4.81 < x < -3.79 and -.01 < y < .6 and -2.6 < z < -1.4
               for x, y, z in (positions[i] for i in triangle)):
            removed += 1
        else:
            kept.extend(triangle)
    assert removed == 64, (path, removed)
    a = doc['accessors'][primitive['indices']]
    v = doc['bufferViews'][a['bufferView']]
    fmt = {5123: 'H', 5125: 'I'}[a['componentType']]
    assert 'byteStride' not in v
    offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    packed = struct.pack('<' + fmt * len(kept), *kept)
    raw[offset:offset + len(packed)] = packed
    a['count'] = len(kept)
    a['min'], a['max'] = [min(kept)], [max(kept)]
    target = next(i for i, n in enumerate(doc['nodes']) if n.get('name') == 'col_firewood')
    assert not doc['nodes'][target].get('children')
    doc['nodes'].pop(target)
    for parent in doc['nodes'] + doc['scenes']:
        key = 'children' if 'children' in parent else 'nodes'
        if key in parent:
            parent[key] = [i - (i > target) for i in parent[key] if i != target]
    doc['asset'].setdefault('extras', {})['tailor_firewood_removed'] = True
    text = json.dumps(doc, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    raw += b'\0' * (-len(raw) % 4)
    result = struct.pack('<III', 0x46546c67, 2, 28 + len(text) + len(raw))
    result += struct.pack('<II', len(text), 0x4e4f534a) + text
    result += struct.pack('<II', len(raw), 0x004e4942) + raw
    path.write_bytes(result)
    print(f'{path.name}: removed {removed} triangles and col_firewood')

if __name__ == '__main__':
    for name in ('camp_hub.glb', 'camp_training.glb'):
        path = ROOT / 'art/maps/camp_hub' / name
        if path.exists():
            remove(path)
