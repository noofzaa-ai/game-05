#!/usr/bin/env python3
"""Produce separate UV-aware Goblin scenery derivatives; preserve authoring kit."""
import ctypes
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/skills"))
from shrink_skills import Glb

source = ROOT / "art_source/props/goblin_base/kit_parts"
dest = source.parent / "kit_parts_optimized"
dest.mkdir(exist_ok=True)
library = ctypes.CDLL("/Applications/Blender.app/Contents/Resources/lib/libmeshoptimizer.dylib")
simplify = library.meshopt_simplifyWithAttributes
simplify.restype = ctypes.c_size_t
simplify.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_float, ctypes.c_uint, ctypes.c_void_p]
report = {}
for path in sorted(source.glob("*.glb")):
    model = Glb(path)
    primitive = model.j["meshes"][0]["primitives"][0]
    positions = np.ascontiguousarray(model.read(primitive["attributes"]["POSITION"]), dtype="<f4")
    indices = np.ascontiguousarray(model.read(primitive["indices"]).reshape(-1), dtype="<u4")
    normal = model.read(primitive["attributes"]["NORMAL"])
    uv = model.read(primitive["attributes"]["TEXCOORD_0"])
    attributes = np.ascontiguousarray(np.hstack([normal, uv]), dtype="<f4")
    weights = np.array([0.1, 0.1, 0.1, 0.25, 0.25], dtype="<f4")
    result = np.empty_like(indices)
    error = ctypes.c_float()
    target = max(3, (int(len(indices) * 0.45) // 3) * 3)
    count = simplify(result.ctypes.data, indices.ctypes.data, len(indices), positions.ctypes.data, len(positions), 12, attributes.ctypes.data, 20, weights.ctypes.data, 5, None, target, 0.03, 32, ctypes.byref(error))
    assert count > 0 and count % 3 == 0 and count <= len(indices)
    used, remapped = np.unique(result[:count], return_inverse=True)
    output = {"attributes": {}, "material": primitive["material"]}
    for role, accessor_id in primitive["attributes"].items():
        accessor = model.j["accessors"][accessor_id]
        values = model.read(accessor_id)[used].copy()
        output["attributes"][role] = model.add_accessor(values, accessor["type"], accessor["componentType"], role == "POSITION")
    output["indices"] = model.add_accessor(remapped.astype("<u2").reshape(-1, 1), "SCALAR", 5123)
    model.j["meshes"][0]["primitives"] = [output]
    model.save(dest / path.name)
    report[path.stem] = {"before": len(indices) // 3, "after": count // 3, "error": error.value}
(dest / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
