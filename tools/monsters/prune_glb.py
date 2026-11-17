"""Drops the accessors and buffer views nothing references from a .glb (Godot's glTF writer keeps the replaced mesh data of
tools/monsters/simplify_monster.gd), compacts the BIN chunk and writes a compact JSON chunk. Usage: python prune_glb.py in.glb [out.glb]"""
import json, struct, sys


def prune(path_in, path_out):
    data = open(path_in, 'rb').read()
    jl = struct.unpack('<I', data[12:16])[0]
    gltf = json.loads(data[20:20 + jl])
    bin_start = 20 + jl + 8
    binary = data[bin_start:]
    used_acc = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ('indices', 'input', 'output', 'inverseBindMatrices') and isinstance(value, int):
                    used_acc.add(value)
                elif key == 'attributes':
                    used_acc.update(value.values())
                elif key == 'targets':
                    for target in value:
                        used_acc.update(target.values())
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)
    for section in ('meshes', 'animations', 'skins'):
        walk(gltf.get(section, []))
    acc_map = {old: new for new, old in enumerate(sorted(used_acc))}
    used_views = {gltf['accessors'][a]['bufferView'] for a in used_acc if 'bufferView' in gltf['accessors'][a]}
    for image in gltf.get('images', []):
        if 'bufferView' in image:
            used_views.add(image['bufferView'])
    view_map = {old: new for new, old in enumerate(sorted(used_views))}
    out = bytearray()
    views = []
    for old in sorted(used_views):
        view = dict(gltf['bufferViews'][old])
        while len(out) % 4:
            out.append(0)
        start = view.get('byteOffset', 0)
        view['byteOffset'] = len(out)
        out += binary[start:start + view['byteLength']]
        views.append(view)
    accessors = []
    for old in sorted(used_acc):
        accessor = dict(gltf['accessors'][old])
        if 'bufferView' in accessor:
            accessor['bufferView'] = view_map[accessor['bufferView']]
        accessors.append(accessor)

    def remap(node):
        if isinstance(node, dict):
            for key, value in list(node.items()):
                if key in ('indices', 'input', 'output', 'inverseBindMatrices') and isinstance(value, int):
                    node[key] = acc_map[value]
                elif key == 'attributes':
                    node[key] = {k: acc_map[v] for k, v in value.items()}
                elif key == 'targets':
                    node[key] = [{k: acc_map[v] for k, v in t.items()} for t in value]
                else:
                    remap(value)
        elif isinstance(node, list):
            for item in node:
                remap(item)
    for section in ('meshes', 'animations', 'skins'):
        remap(gltf.get(section, []))
    for image in gltf.get('images', []):
        if 'bufferView' in image:
            image['bufferView'] = view_map[image['bufferView']]
    gltf['accessors'] = accessors
    gltf['bufferViews'] = views
    while len(out) % 4:
        out.append(0)
    gltf['buffers'] = [{'byteLength': len(out)}]
    text = json.dumps(gltf, separators=(',', ':')).encode()
    while len(text) % 4:
        text += b' '
    total = 12 + 8 + len(text) + 8 + len(out)
    blob = struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(text), 0x4E4F534A) + text + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
    open(path_out, 'wb').write(blob)
    print(path_in, len(data), '->', len(blob), 'accessors', len(accessors), 'views', len(views))


if __name__ == '__main__':
    prune(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
