"""Create hair_boy_pompadour_01 as a standalone modular GLB.

Coordinate convention inside Blender:
  X = character left, Z = up, -Y = face/front.
The glTF exporter converts this to the project's GLB convention (+Y up, +Z front).
The supplied head reference is imported only for fit checks and previews; it is
never included in the exported hair asset.
"""
from __future__ import annotations

import json
import math
import os
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import bpy
import bmesh


PROJECT_ROOT = "/Users/user/godot-project/test01"
REFERENCE_GLB = os.path.join(
    PROJECT_ROOT, "art/characters/chibi-studio/hair_head_reference.glb"
)
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "art/characters/chibi-studio/hair")
ASSET_ID = "hair_boy_pompadour_01"
OUTPUT_GLB = os.path.join(OUTPUT_DIR, ASSET_ID + ".glb")
OUTPUT_JSON = os.path.join(OUTPUT_DIR, ASSET_ID + ".json")
PREVIEW_PREFIX = os.path.join(OUTPUT_DIR, "preview_" + ASSET_ID + "_")
PREVIEW_VIEWS = ("front", "side", "back", "top")

EPS = 1.0e-5


def fail(message: str) -> None:
    raise RuntimeError(message)


def ensure_inputs_and_non_overwrite() -> None:
    if not os.path.isfile(REFERENCE_GLB):
        fail("Missing required reference GLB: " + REFERENCE_GLB)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    planned = [OUTPUT_GLB, OUTPUT_JSON] + [
        PREVIEW_PREFIX + view + ".png" for view in PREVIEW_VIEWS
    ]
    existing = [path for path in planned if os.path.exists(path)]
    if existing:
        fail(
            "Refusing to overwrite existing output(s):\n"
            + "\n".join(existing)
        )


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"


def import_reference() -> list[bpy.types.Object]:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=REFERENCE_GLB)
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    if not imported:
        fail("Reference GLB imported no objects")
    marker = bpy.data.objects.get("hair_attach")
    if marker is None:
        fail("Reference GLB has no hair_attach marker")
    if marker.location.length > EPS or any(abs(v - 1.0) > EPS for v in marker.scale):
        fail("Reference hair_attach is not identity")
    return imported


def make_material() -> bpy.types.Material:
    material = bpy.data.materials.new("Pompadour clay")
    material.use_nodes = True
    material.diffuse_color = (0.12, 0.035, 0.008, 1.0)
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    if shader is None:
        fail("Could not create Principled BSDF material")
    shader.inputs["Base Color"].default_value = (0.12, 0.035, 0.008, 1.0)
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 0.84
    return material


def recalc_normals(mesh: bpy.types.Mesh) -> None:
    mesh.validate(verbose=False)
    mesh.update(calc_edges=True)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update(calc_edges=True)
    for poly in mesh.polygons:
        poly.use_smooth = False


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    parent: bpy.types.Object,
    material: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + " Mesh")
    mesh.from_pydata(vertices, [], faces)
    recalc_normals(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj.data.materials.append(material)
    obj["asset_type"] = "hair_mesh"
    obj["faceted"] = True
    return obj


def add_loft_cap(root: bpy.types.Object, material: bpy.types.Material) -> bpy.types.Object:
    """A faceted cap loft with a raised, rear-swept crown.

    Every ring is an elliptical contour around the scalp. Moving the ring center
    toward the back as it rises gives the pompadour its swept-back profile while
    keeping the side silhouette close to the head.
    """
    segments = 20
    # z, rx, ry, center_y. The lowest contour leaves a 4-10 mm scalp clearance
    # at the measured reference extremes; upper contours form the high quiff.
    rings = [
        (-0.180, 0.162, 0.153, 0.004),
        (-0.090, 0.164, 0.154, 0.005),
        (-0.012, 0.162, 0.150, 0.006),
        (0.040, 0.151, 0.137, 0.020),
        (0.086, 0.121, 0.109, 0.049),
        (0.116, 0.078, 0.076, 0.076),
    ]
    vertices: list[tuple[float, float, float]] = []
    for z, rx, ry, center_y in rings:
        for i in range(segments):
            t = 2.0 * math.pi * i / segments
            # A very slight asymmetry makes the front sweep read as designed,
            # without changing the socket or causing a lopsided fit.
            asym = 0.004 * max(0.0, math.sin(t))
            vertices.append((rx * math.sin(t) + asym, center_y - ry * math.cos(t), z))
    # Shifted apex is the rearward end of the swept volume.
    apex_index = len(vertices)
    vertices.append((-0.010, 0.104, 0.124))
    faces: list[tuple[int, ...]] = []
    for row in range(len(rings) - 1):
        for i in range(segments):
            a = row * segments + i
            b = row * segments + ((i + 1) % segments)
            faces.append((a, b, b + segments, a + segments))
    last = (len(rings) - 1) * segments
    for i in range(segments):
        faces.append((last + i, last + ((i + 1) % segments), apex_index))
    return mesh_object("Pompadour_Cap", vertices, faces, root, material)


def add_prism(
    root: bpy.types.Object,
    material: bpy.types.Material,
    name: str,
    outline: list[tuple[float, float, float]],
    thickness_y: float,
) -> bpy.types.Object:
    """Create a closed faceted prism from an x/z outline at two y depths."""
    vertices = [(x, y, z) for y in (p[1] for p in outline) for x, _, z in outline]
    # The helper above intentionally uses the outline's y only as a placeholder;
    # overwrite with consistent front/back offsets around each outline point.
    vertices = []
    for x, y, z in outline:
        vertices.append((x, y - thickness_y * 0.5, z))
    for x, y, z in outline:
        vertices.append((x, y + thickness_y * 0.5, z))
    n = len(outline)
    faces: list[tuple[int, ...]] = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return mesh_object(name, vertices, faces, root, material)


def add_quiff_ribbon(root: bpy.types.Object, material: bpy.types.Material) -> bpy.types.Object:
    """Add a shallow raised ribbon that visibly sweeps the front into the crown."""
    stations = [
        # y, z, half width; front to back, rising then curling backward
        (-0.143, -0.004, 0.120),
        (-0.132, 0.032, 0.124),
        (-0.102, 0.076, 0.118),
        (-0.060, 0.110, 0.102),
        (-0.010, 0.125, 0.079),
        (0.040, 0.119, 0.058),
    ]
    vertices: list[tuple[float, float, float]] = []
    # left edge, center ridge, right edge at each station; center is raised
    for y, z, half_width in stations:
        vertices.extend(
            [
                (-half_width, y, z),
                (0.0, y + 0.002, z + 0.008),
                (half_width, y, z),
            ]
        )
    # underside is a tiny offset, making a closed, non-transparent detail.
    top_count = len(vertices)
    top_vertices = list(vertices)
    vertices.extend((x, y, z - 0.006) for x, y, z in top_vertices)
    faces: list[tuple[int, ...]] = []
    for i in range(len(stations) - 1):
        a = i * 3
        b = (i + 1) * 3
        for col in (0, 1):
            faces.append((a + col, b + col, b + col + 1, a + col + 1))
            faces.append((top_count + a + col + 1, top_count + b + col + 1,
                          top_count + b + col, top_count + a + col))
    # close the left/right station edges and the two ends
    for i in range(len(stations) - 1):
        a = i * 3
        b = (i + 1) * 3
        for col in (0, 2):
            faces.append((a + col, top_count + a + col, top_count + b + col, b + col))
    faces.append((0, 1, 2, top_count + 2, top_count + 1, top_count + 0))
    end = (len(stations) - 1) * 3
    faces.append((end, top_count + end, top_count + end + 1, top_count + end + 2, end + 2, end + 1))
    return mesh_object("Pompadour_Front_Sweep", vertices, faces, root, material)


def add_side_locks(root: bpy.types.Object, material: bpy.types.Material) -> list[bpy.types.Object]:
    """Short tapered temple locks, kept outside the eyes and clear of the neck."""
    left = add_prism(
        root,
        material,
        "Pompadour_Side_Lock_L",
        [(-0.151, -0.120, -0.015), (-0.123, -0.132, -0.030),
         (-0.128, -0.119, -0.205), (-0.151, -0.091, -0.177)],
        0.014,
    )
    right = add_prism(
        root,
        material,
        "Pompadour_Side_Lock_R",
        [(0.151, -0.120, -0.015), (0.123, -0.132, -0.030),
         (0.128, -0.119, -0.205), (0.151, -0.091, -0.177)],
        0.014,
    )
    return [left, right]


def create_hair_asset() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = bpy.data.objects.new("HairRoot", None)
    bpy.context.collection.objects.link(root)
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.scale = (1.0, 1.0, 1.0)
    root["asset_type"] = "hair"
    root["spec_version"] = "1.0"
    root["id"] = ASSET_ID
    root["display_name"] = "เด็กผู้ชาย · ผมปอมปาดัวร์ 01"
    root["fit_profile"] = "chibi-sculpt-v1"
    root["target_socket"] = "attach_head"
    root["units"] = "meters"
    root["up_axis"] = "+Y"
    root["forward_axis"] = "+Z"
    root["attachment_mode"] = "rigid"

    marker = bpy.data.objects.new("hair_attach", None)
    bpy.context.collection.objects.link(marker)
    marker.parent = root
    marker.location = (0.0, 0.0, 0.0)
    marker.rotation_euler = (0.0, 0.0, 0.0)
    marker.scale = (1.0, 1.0, 1.0)
    marker["marker_type"] = "hair_attach"

    material = make_material()
    meshes = [add_loft_cap(root, material), add_quiff_ribbon(root, material)]
    meshes.extend(add_side_locks(root, material))
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        obj.select_set(False)
    return root, meshes


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.append(obj)
        stack.extend(obj.children)
    return result


def triangle_count(objects: list[bpy.types.Object]) -> int:
    total = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def export_hair(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in descendants(root):
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
        export_extras=True,
    )
    if not os.path.isfile(OUTPUT_GLB) or os.path.getsize(OUTPUT_GLB) == 0:
        fail("GLB export did not produce a non-empty file")


def bbox_for_objects(objects: list[bpy.types.Object]) -> tuple[tuple[float, ...], tuple[float, ...]]:
    points: list[Vector] = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    if not points:
        fail("No mesh vertices available for bounding box")
    mins = tuple(min(point[i] for point in points) for i in range(3))
    maxs = tuple(max(point[i] for point in points) for i in range(3))
    return mins, maxs


def validate_reimport(expected_triangles: int) -> dict:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=OUTPUT_GLB)
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    roots = [obj for obj in imported if obj.name == "HairRoot" or obj.name.startswith("HairRoot")]
    if len(roots) != 1:
        fail("Re-import did not produce exactly one HairRoot: " + str([o.name for o in roots]))
    imported_root = roots[0]
    imported_desc = descendants(imported_root)
    imported_meshes = [obj for obj in imported_desc if obj.type == "MESH"]
    imported_markers = [obj for obj in imported_desc if obj.name.startswith("hair_attach")]
    if len(imported_markers) != 1:
        fail("Re-import did not preserve exactly one hair_attach marker")
    if imported_root.parent is not None:
        fail("Re-imported HairRoot has an unexpected parent")
    for obj in [imported_root] + imported_desc:
        if obj.type in {"CAMERA", "LIGHT", "ARMATURE"}:
            fail("Forbidden object in exported asset: " + obj.type)
    if imported_root.location.length > 1e-4 or any(abs(v - 1.0) > 1e-4 for v in imported_root.scale):
        fail("Re-imported HairRoot transform is not identity")
    marker = imported_markers[0]
    if marker.location.length > 1e-4 or any(abs(v - 1.0) > 1e-4 for v in marker.scale):
        fail("Re-imported hair_attach transform is not identity")
    actual_triangles = triangle_count(imported_meshes)
    if actual_triangles != expected_triangles:
        fail("Triangle count changed on re-import: %d vs %d" % (actual_triangles, expected_triangles))
    mins, maxs = bbox_for_objects(imported_meshes)
    if any(not math.isfinite(v) for v in mins + maxs):
        fail("Invalid re-imported bounding box")
    # HairRoot must remain at the attachment origin and mesh must be in a useful range.
    if mins[2] > -0.01 or maxs[2] < 0.05:
        fail("Re-imported hair bounds do not cover the expected pompadour height")
    return {
        "root_name": imported_root.name,
        "marker_name": marker.name,
        "mesh_names": [obj.name for obj in imported_meshes],
        "triangle_count": actual_triangles,
        "bounding_box_blender_import": {
            "min": [round(v, 6) for v in mins],
            "max": [round(v, 6) for v in maxs],
        },
        "object_types": sorted({obj.type for obj in imported}),
        "forbidden_objects_present": False,
    }


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def make_preview_scene(reference_objects: list[bpy.types.Object]) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Pompadour Preview World")
    scene.world.color = (0.055, 0.055, 0.055)
    scene.render.image_settings.color_mode = "RGBA"

    camera_data = bpy.data.cameras.new("Preview Camera")
    camera = bpy.data.objects.new("Preview Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.lens = 58
    camera.data.sensor_width = 36

    def area(name: str, location: tuple[float, float, float], energy: float, size: float) -> None:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, Vector((0.0, 0.0, -0.08)))

    area("Preview Key", (-0.55, -0.65, 0.55), 85.0, 0.55)
    area("Preview Fill", (0.60, -0.35, 0.10), 35.0, 0.45)
    area("Preview Rim", (0.15, 0.55, 0.45), 55.0, 0.50)

    # Keep only reference head meshes visible as the fitting context; the
    # re-imported hair copy is hidden so it cannot double-render over the source.
    for obj in reference_objects:
        if obj.type == "MESH":
            obj.hide_render = False
            obj.hide_viewport = False
    for obj in bpy.context.scene.objects:
        if obj.name.startswith("HairRoot") and obj.name != "HairRoot":
            obj.hide_render = True
            obj.hide_viewport = True

    target = Vector((0.0, 0.0, -0.08))
    views = {
        "front": ((0.0, -0.92, -0.08), 0.92),
        "side": ((0.92, 0.02, -0.08), 0.92),
        "back": ((0.0, 0.92, -0.08), 0.92),
        "top": ((0.0, -0.02, 0.90), 0.92),
    }
    for view, (location, distance) in views.items():
        camera.location = location
        look_at(camera, target)
        camera.data.lens = 58 if view != "top" else 62
        scene.render.filepath = PREVIEW_PREFIX + view + ".png"
        bpy.ops.render.render(write_still=True)


def write_metadata(triangles: int, reimport_report: dict) -> None:
    metadata = {
        "asset_type": "hair",
        "spec_version": "1.0",
        "id": ASSET_ID,
        "display_name": "เด็กผู้ชาย · ผมปอมปาดัวร์ 01",
        "fit_profile": "chibi-sculpt-v1",
        "target_socket": "attach_head",
        "units": "meters",
        "up_axis": "+Y",
        "forward_axis": "+Z",
        "attachment_mode": "rigid",
        "style": "pompadour",
        "geometry": {
            "triangle_count": triangles,
            "budget": "200-800 triangles",
            "faceted": True,
            "mesh_names": ["Pompadour_Cap", "Pompadour_Front_Sweep",
                           "Pompadour_Side_Lock_L", "Pompadour_Side_Lock_R"],
        },
        "validation": {
            "reference_head_used_without_transform": True,
            "reimport": reimport_report,
            "preview_views": [
                PREVIEW_PREFIX + view + ".png" for view in PREVIEW_VIEWS
            ],
        },
    }
    with open(OUTPUT_JSON, "w", encoding="utf-8") as handle:
        json.dump(metadata, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main() -> None:
    ensure_inputs_and_non_overwrite()
    reset_scene()
    reference_objects = import_reference()
    root, meshes = create_hair_asset()
    hair_desc = descendants(root)
    triangles = triangle_count(meshes)
    if not 200 <= triangles <= 800:
        fail("Pompadour triangle budget violation: %d" % triangles)
    export_hair(root)
    reimport_report = validate_reimport(triangles)
    make_preview_scene(reference_objects)
    for view in PREVIEW_VIEWS:
        path = PREVIEW_PREFIX + view + ".png"
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            fail("Missing preview render: " + path)
    write_metadata(triangles, reimport_report)
    print("POMPADOUR_BUILD_OK")
    print("GLB:", OUTPUT_GLB)
    print("METADATA:", OUTPUT_JSON)
    print("TRIANGLES:", triangles)
    print("REIMPORT:", json.dumps(reimport_report, ensure_ascii=False, sort_keys=True))
    print("PREVIEWS:", ", ".join(PREVIEW_PREFIX + view + ".png" for view in PREVIEW_VIEWS))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POMPADOUR_BUILD_FAILED:", exc, file=sys.stderr)
        raise
