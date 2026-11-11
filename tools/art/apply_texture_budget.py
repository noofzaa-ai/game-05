#!/usr/bin/env python3
"""Apply assets_spec.md caps to embedded or local external GLB images without re-exporting meshes/rigs.

Requires Pillow. Run before Godot import, then optimize_npc_textures.py and import again.
Without paths, updates the five hub NPCs and the blacksmith workshop.
--scenes processes every map/prop GLB and its referenced local PNGs.
"""
import argparse
import io
import json
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CAPS = {'color': 1024, 'normal': 512, 'metallic_roughness': 512, 'occlusion': 512}


def image_roles(doc):
    roles = {}
    def add(info, role):
        if not info:
            return
        texture = doc['textures'][info['index']]
        if 'source' not in texture:
            raise ValueError('Compressed/extension textures require a dedicated conversion')
        roles.setdefault(texture['source'], set()).add(role)
    for material in doc.get('materials', []):
        pbr = material.get('pbrMetallicRoughness', {})
        add(pbr.get('baseColorTexture'), 'color')
        add(pbr.get('metallicRoughnessTexture'), 'metallic_roughness')
        add(material.get('normalTexture'), 'normal')
        add(material.get('occlusionTexture'), 'occlusion')
        # Leave emissive maps at the same cap as color; never upscale.
        add(material.get('emissiveTexture'), 'color')
    return roles


def apply(path):
    original = path.read_bytes()
    magic, version, total = struct.unpack_from('<III', original)
    if magic != 0x46546C67 or version != 2 or total != len(original):
        raise ValueError(f'Invalid GLB: {path}')
    length, kind = struct.unpack_from('<II', original, 12)
    if kind != 0x4E4F534A:
        raise ValueError('First GLB chunk must be JSON')
    doc = json.loads(original[20:20 + length])
    offset = 20 + length
    bin_length, bin_kind = struct.unpack_from('<II', original, offset)
    if bin_kind != 0x004E4942 or offset + 8 + bin_length != len(original):
        raise ValueError('Expected one embedded BIN chunk')
    blob = original[offset + 8:]
    replacements = {}
    external_writes = {}
    images = []
    for index, roles in image_roles(doc).items():
        image = doc['images'][index]
        if 'normal' in roles and len(roles) > 1 or 'color' in roles and len(roles) > 1:
            raise ValueError(f'Image shared between incompatible map roles: {roles}')
        cap = min(CAPS[role] for role in roles)
        external = None
        if 'bufferView' in image:
            view = doc['bufferViews'][image['bufferView']]
            start = view.get('byteOffset', 0)
            raw = blob[start:start + view['byteLength']]
        else:
            from urllib.parse import unquote
            uri = image.get('uri', '')
            if not uri or ':' in uri:
                raise ValueError('Expected a local relative image URI')
            external = (path.parent / unquote(uri)).resolve()
            if not external.is_relative_to(ROOT / 'art'):
                raise ValueError('Only game derivative images under art/ may be resized')
            raw = external.read_bytes()
        with Image.open(io.BytesIO(raw)) as decoded:
            old_size = decoded.size
            size = old_size
            if max(size) > cap:
                if decoded.format != 'PNG':
                    raise ValueError('Only lossless embedded PNG resizing is supported')
                size = tuple(max(1, round(v * cap / max(old_size))) for v in old_size)
                resized = decoded.resize(size, Image.Resampling.LANCZOS)
                output = io.BytesIO()
                resized.save(output, format='PNG')
                if external is None:
                    replacements[image['bufferView']] = output.getvalue()
                else:
                    external_writes[external] = output.getvalue()
        images.append({'name': image.get('name'), 'roles': sorted(roles),
                       'before': old_size, 'after': size})
    for external, data in external_writes.items():
        temp = external.with_suffix('.png.tmp')
        temp.write_bytes(data)
        temp.replace(external)
    if replacements:
        packed = bytearray()
        for index, view in enumerate(doc['bufferViews']):
            if view.get('buffer', 0) != 0:
                raise ValueError('Only a single embedded buffer is supported')
            start = view.get('byteOffset', 0)
            raw = replacements.get(index, blob[start:start + view['byteLength']])
            packed.extend(b'\x00' * (-len(packed) % 4))
            view['byteOffset'] = len(packed)
            view['byteLength'] = len(raw)
            packed.extend(raw)
        packed.extend(b'\x00' * (-len(packed) % 4))
        doc['buffers'][0]['byteLength'] = len(packed)
        encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
        encoded += b' ' * (-len(encoded) % 4)
        result = (struct.pack('<III', magic, version, 28 + len(encoded) + len(packed))
                  + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
                  + struct.pack('<II', len(packed), bin_kind) + packed)
        temp = path.with_suffix('.glb.tmp')
        temp.write_bytes(result)
        temp.replace(path)
    return {'asset': str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            'before_bytes': len(original), 'after_bytes': path.stat().st_size, 'images': images}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--scenes', action='store_true', help='Process every map/prop GLB and referenced images')
    args = parser.parse_args()
    paths = args.paths or ([*sorted((ROOT / 'art/maps').rglob('*.glb')),
                           *sorted((ROOT / 'art/props').rglob('*.glb'))] if args.scenes else
                          [*sorted((ROOT / 'art/npcs').glob('*.glb')),
                           ROOT / 'art/props/blacksmith_forge/blacksmith_forge.glb'])
    report = [apply(path.resolve()) for path in paths]
    text = json.dumps(report, indent=2) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text)
    for row in report:
        print(f"{row['asset']}: {row['before_bytes']} -> {row['after_bytes']} bytes")


if __name__ == '__main__':
    main()
