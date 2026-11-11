#!/usr/bin/env python3
"""Prepare ../assets/merchance_shop.glb as a grounded 4.8m-wide camp building.
Preserves source geometry/materials; applies assets_spec texture caps and a root transform.
"""
from pathlib import Path
import hashlib
import json
import shutil
import struct
from apply_texture_budget import apply

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'assets/merchance_shop.glb'
OUT = ROOT / 'art/props/merchant_shop'
OUT.mkdir(parents=True, exist_ok=True)
path = OUT / 'merchant_shop.glb'
shutil.copyfile(SOURCE, path)
apply(path)
data = path.read_bytes()
length = struct.unpack_from('<I', data, 12)[0]
doc = json.loads(data[20:20 + length])
# Preserve the supplied +90 degree root rotation; measure the transformed corners.
if doc.get('skins') or doc.get('animations') or any(n.get('children') for n in doc['nodes']):
    raise ValueError('Expected static flat source hierarchy; review normalization for a new source')
import itertools
import math
points = []
for node in doc['nodes']:
    if 'mesh' not in node:
        continue
    q = node.get('rotation', [0, 0, 0, 1])
    norm = math.sqrt(sum(v*v for v in q))
    x, y, z, w = [v/norm for v in q]
    for primitive in doc['meshes'][node['mesh']]['primitives']:
        accessor = doc['accessors'][primitive['attributes']['POSITION']]
        for corner in itertools.product(*zip(accessor['min'], accessor['max'])):
            v = [corner[i] * node.get('scale', [1, 1, 1])[i] for i in range(3)]
            if 'matrix' in node:
                m = node['matrix']
                v = [sum(m[c*4+r]*v[c] for c in range(3)) + m[12+r] for r in range(3)]
            else:
                cross = [y*v[2]-z*v[1], z*v[0]-x*v[2], x*v[1]-y*v[0]]
                twice = [y*cross[2]-z*cross[1], z*cross[0]-x*cross[2], x*cross[1]-y*cross[0]]
                v = [v[i]+2*w*cross[i]+2*twice[i]+node.get('translation',[0,0,0])[i] for i in range(3)]
            points.append(v)
lo = [min(v[i] for v in points) for i in range(3)]
hi = [max(v[i] for v in points) for i in range(3)]
scale = 4.8 / (hi[0] - lo[0])
translation = [-scale * (lo[0] + hi[0]) / 2, -scale * lo[1],
               -scale * (lo[2] + hi[2]) / 2]
for scene in doc['scenes']:
    index = len(doc['nodes'])
    doc['nodes'].append({'name': 'MerchantShop', 'children': scene['nodes'],
                         'scale': [scale] * 3, 'translation': translation})
    scene['nodes'] = [index]
encoded = json.dumps(doc, separators=(',', ':')).encode()
encoded += b' ' * (-len(encoded) % 4)
chunks = data[20 + length:]
path.write_bytes(struct.pack('<III', 0x46546C67, 2, 20 + len(encoded) + len(chunks))
                 + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + chunks)
report = {'source': str(SOURCE.name), 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
          'game_size_xyz': [(hi[i] - lo[i]) * scale for i in range(3)],
          'triangles': sum(doc['accessors'][p['indices']]['count'] // 3
                           for m in doc['meshes'] for p in m['primitives']),
          'texture_budget': {'color': 1024, 'normal': 512, 'metallic_roughness': 512},
          'position': [9.4, 0, 4.4], 'bytes': path.stat().st_size}
(OUT / 'asset.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
