"""Extract the level-15 race outfit atlas (and per-mesh UV triangles) from the delivery glb.
usage: python -I tools/items/extract_lv15_atlas.py <race_outfits_lv15.glb> <out_dir>
writes <out_dir>/lv15_atlas.jpg and <out_dir>/lv15_uv.json ({mesh: [[u,v]*3 per tri]})"""
import json, struct, sys, os
import numpy as np

def load(path):
    d = open(path, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack('<I', d[off:off + 4])[0]
    return j, d[off + 8:off + 8 + bl]

def accessor(j, b, i):
    a = j['accessors'][i]; v = j['bufferViews'][a['bufferView']]
    ct = {5126: 'f4', 5123: 'u2', 5125: 'u4'}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    o = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(b, dtype=ct, count=a['count'] * n, offset=o).reshape(-1, n) if n > 1 else np.frombuffer(b, dtype=ct, count=a['count'], offset=o)

def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    j, b = load(src)
    img = j['images'][0]; v = j['bufferViews'][img['bufferView']]
    open(os.path.join(out, 'lv15_atlas.jpg'), 'wb').write(b[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']])
    uv = {}
    for m in j['meshes']:
        for p in m['primitives']:
            uvs = accessor(j, b, p['attributes']['TEXCOORD_0'])
            idx = accessor(j, b, p['indices']).reshape(-1, 3)
            uv[m['name']] = uvs[idx].tolist()
    json.dump(uv, open(os.path.join(out, 'lv15_uv.json'), 'w'))
    print('meshes', list(uv), 'tris', sum(len(t) for t in uv.values()))
main()
