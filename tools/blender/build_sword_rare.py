"""Builds the plain Rare-tier sword and exports <project>/art/weapons/blade_rare.glb.

Run headless:
    blender --background --factory-startup --python tools/blender/build_sword_rare.py
    blender --background --factory-startup --python tools/blender/build_sword_rare.py -- --preview
With --preview it also renders art/weapons/preview/blade_rare_hero.png, blade_rare_icon.png and
blade_rare_vs_blade.png (next to the Normal art/weapons/blade.glb).

Same frame as the Normal sword (tools/blender/build_animations.py build_sword), so it drops into the
attach_weapon.R attachment unchanged: grip centre at the origin, blade along +Y, the blade's flat facing +-Z,
the edges along +-X. About 1.1 m from pommel to point.

Look: plain, clean and readable, one step above the Normal sword. Steel blade with a blued fuller (a blue strip
down the middle of each flat, which is what the steep top-down camera sees), a blue-enamel crossguard with steel
tips, a blue gem on each face of the guard and at the pommel, and a dark-blue wrapped grip. No glow, no runes.
Flat shaded low-poly, four materials.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEAPON_DIR = os.path.join(PROJECT, "art", "weapons")
PREVIEW_DIR = os.path.join(WEAPON_DIR, "preview")

# --------------------------------------------------------------------------------------- materials

COLORS = {
    # name: (base colour (linear), metallic, roughness)
    "steel": ((0.80, 0.83, 0.88, 1.0), 0.6, 0.35),
    "rare_blue": ((0.06, 0.24, 0.80, 1.0), 0.3, 0.35),  # the Rare tier colour: fuller and guard enamel
    "wrap": ((0.025, 0.07, 0.25, 1.0), 0.0, 0.8),  # dark blue leather on the grip
    "gem": ((0.20, 0.55, 1.0, 1.0), 0.1, 0.15),  # brighter blue than the enamel so it reads as a stone
}


def make_materials():
    mats = {}
    for name, (color, metallic, rough) in COLORS.items():
        mat = bpy.data.materials.new("blade_rare_" + name)
        mat.diffuse_color = color
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = rough
        mats[name] = mat
    return mats


# --------------------------------------------------------------------------------------- mesh helpers

class Builder:
    """Collects every piece into one bmesh; material slots follow MAT_ORDER."""

    MAT_ORDER = ["steel", "rare_blue", "wrap", "gem"]

    def __init__(self):
        self.bm = bmesh.new()

    def slot(self, name):
        return self.MAT_ORDER.index(name)

    def loft(self, rings, band_mats, cap_start=None, cap_end=None, point_start=None, point_end=None):
        """rings: lists of world-space Vectors, all the same length, in order. band_mats[i] is the material of the
        band between ring i and i+1 (a name, or a function(side_index) -> name). Ends are closed by an n-gon cap
        (cap_* = material) or a fan to a point (point_* = (Vector, material))."""
        bm = self.bm
        vrings = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for i in range(len(vrings) - 1):
            a, b = vrings[i], vrings[i + 1]
            for k in range(n):
                k2 = (k + 1) % n
                face = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                mat = band_mats[i](k) if callable(band_mats[i]) else band_mats[i]
                face.material_index = self.slot(mat)
        for ring, cap, point, flip in ((vrings[0], cap_start, point_start, True), (vrings[-1], cap_end, point_end, False)):
            if cap is not None:
                face = bm.faces.new(list(reversed(ring)) if flip else ring)
                face.material_index = self.slot(cap)
            elif point is not None:
                tip = bm.verts.new(point[0])
                for k in range(n):
                    k2 = (k + 1) % n
                    face = bm.faces.new((ring[k2], ring[k], tip) if flip else (ring[k], ring[k2], tip))
                    face.material_index = self.slot(point[1])

    def finish(self, mesh):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()


def ring_y(y, points, x0=0.0, z0=0.0):
    """A ring across the Y axis from (x, z) offsets."""
    return [Vector((x0 + x, y, z0 + z)) for x, z in points]


def ring_x(x, points, y0=0.0, z0=0.0):
    """A ring across the X axis from (y, z) offsets."""
    return [Vector((x, y0 + y, z0 + z)) for y, z in points]


def polygon(radius, sides, start=0.0, sx=1.0, sz=1.0):
    return [(math.cos(start + 2 * math.pi * k / sides) * radius * sx, math.sin(start + 2 * math.pi * k / sides) * radius * sz)
            for k in range(sides)]


# --------------------------------------------------------------------------------------- the sword

def blade_section(half_width, half_thick, fuller_depth):
    """Ten points around the blade: edge, shoulder, fuller lip x2, shoulder, edge, and the same on the back.
    fuller_depth 0 = flat face, 1 = the fuller sunk to half the thickness."""
    w, t = half_width, half_thick
    ft = t * (1.0 - 0.45 * fuller_depth)
    return [(w, 0.0), (0.5 * w, t), (0.28 * w, ft), (-0.28 * w, ft), (-0.5 * w, t),
            (-w, 0.0), (-0.5 * w, -t), (-0.28 * w, -ft), (0.28 * w, -ft), (0.5 * w, -t)]


def fuller_mat(side):
    # sides 1..3 = front fuller (shoulder->lip, lip->lip, lip->shoulder), 6..8 = back fuller
    return "rare_blue" if side in (1, 2, 3, 6, 7, 8) else "steel"


def build_sword(mats):
    b = Builder()
    T = 0.010  # blade half thickness (the Normal sword is 0.012 thick in all; a little thicker reads better top-down)

    # Blade: guard at y 0.12, point at y 1.10 (the Normal sword's point is at 1.10 too).
    blade_rings = [
        ring_y(0.120, blade_section(0.034, T, 0.0)),
        ring_y(0.175, blade_section(0.034, T, 1.0)),
        ring_y(0.760, blade_section(0.031, T, 1.0)),
        ring_y(0.840, blade_section(0.030, T, 0.0)),
        ring_y(0.960, blade_section(0.028, T * 0.9, 0.0)),
    ]
    b.loft(blade_rings, ["steel", fuller_mat, "steel", "steel"],
           cap_start="steel", point_end=(Vector((0.0, 1.10, 0.0)), "steel"))

    # Crossguard: a steel centre block, blue-enamel arms swept slightly toward the blade, steel tips.
    gy = 0.105
    block = [(-0.018, -0.030), (0.018, -0.030), (0.018, 0.030), (-0.018, 0.030)]  # (y, z) rectangle
    b.loft([ring_x(-0.028, block, gy), ring_x(0.028, block, gy)], ["steel"], cap_start="steel", cap_end="steel")

    def arm_ring(x, half_y, half_z, lift):
        return ring_x(x, [(-half_y, -half_z), (half_y, -half_z), (half_y, half_z), (-half_y, half_z)], gy + lift)

    for s in (1, -1):
        rings = [arm_ring(s * 0.026, 0.015, 0.022, 0.0),
                 arm_ring(s * 0.075, 0.012, 0.018, 0.004),
                 arm_ring(s * 0.102, 0.013, 0.019, 0.012),
                 arm_ring(s * 0.110, 0.016, 0.022, 0.016),
                 arm_ring(s * 0.126, 0.013, 0.018, 0.024)]
        if s < 0:
            rings = list(reversed(rings))
            mats_ = ["steel", "steel", "rare_blue", "rare_blue"]
        else:
            mats_ = ["rare_blue", "rare_blue", "steel", "steel"]
        b.loft(rings, mats_, cap_start="steel", cap_end="steel")

    # Gems on both faces of the guard block: flat four-sided diamonds.
    for s in (1, -1):
        base = ring_y(gy, [(0.016, 0.0), (0.0, 0.0), (-0.016, 0.0), (0.0, 0.0)], z0=s * 0.029)
        base[1].y += 0.020
        base[3].y -= 0.020
        base[1].z = base[3].z = s * 0.029
        if s < 0:
            base = list(reversed(base))
        b.loft([base, [Vector((p.x * 0.45, gy + (p.y - gy) * 0.45, s * 0.040)) for p in base]], ["gem"], cap_start="gem", cap_end="gem")

    # Grip: dark-blue wrap, six sides, ridges where the wrap overlaps.
    grip_rings = []
    ys = [-0.088, -0.059, -0.030, 0.000, 0.030, 0.059, 0.088]
    for i, y in enumerate(ys):
        r = 0.0185 if i % 2 else 0.0160
        grip_rings.append(ring_y(y, polygon(r, 6, 0.0, 1.0, 0.85)))
    b.loft(grip_rings, ["wrap"] * (len(ys) - 1), cap_start="wrap", cap_end="wrap")

    # Pommel: a steel faceted cap with a blue gem on its end.
    oct_ = lambda r: polygon(r, 6, 0.0, 1.0, 0.85)
    pommel = [ring_y(-0.086, oct_(0.014)), ring_y(-0.098, oct_(0.026)), ring_y(-0.122, oct_(0.026)),
              ring_y(-0.134, oct_(0.016))]
    pommel = list(reversed(pommel))  # loft from the bottom up so normals come out right after recalc
    b.loft(pommel, ["steel", "steel", "steel"], cap_end="steel",
           point_start=(Vector((0.0, -0.145, 0.0)), "gem"))

    mesh = bpy.data.meshes.new("blade_rare")
    b.finish(mesh)
    for name in Builder.MAT_ORDER:
        mesh.materials.append(mats[name])
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new("blade_rare", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)


# --------------------------------------------------------------------------------------- previews

def setup_render(bg=(0.42, 0.42, 0.44)):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("preview_world") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    bgnode = world.node_tree.nodes["Background"]
    bgnode.inputs["Color"].default_value = (*bg, 1.0)
    bgnode.inputs["Strength"].default_value = 1.0
    # ink outline like the game's Ink Garden look
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 1.6
    lineset = scene.view_layers[0].freestyle_settings.linesets[0] if scene.view_layers[0].freestyle_settings.linesets \
        else scene.view_layers[0].freestyle_settings.linesets.new("ink")
    lineset.select_by_visibility = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = False
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("ink")
    lineset.linestyle.color = (0.07, 0.07, 0.09)

    def light(name, rot, energy):
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = Euler([math.radians(a) for a in rot])
        scene.collection.objects.link(obj)

    light("key", (40, 10, 35), 3.5)
    light("fill", (-50, -20, -140), 1.2)
    light("top", (0, 0, 0), 1.0)


def camera(name, location, look_at, ortho_scale=None, lens=60):
    data = bpy.data.cameras.new(name)
    if ortho_scale:
        data.type = "ORTHO"
        data.ortho_scale = ortho_scale
    else:
        data.lens = lens
    cam = bpy.data.objects.new(name, data)
    cam.location = location
    direction = Vector(look_at) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


def frame(objs, margin=1.15):
    """World-space centre and largest extent (in the camera's X/Z image plane) of the meshes under objs."""
    bpy.context.view_layer.update()
    pts = []
    meshes = {o for r in objs for o in [r, *r.children_recursive] if o.type == "MESH"}
    for o in meshes:
        pts += [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (lo + hi) / 2, max(hi.x - lo.x, hi.z - lo.z) * margin


def render(cam, path, res=(1024, 1024)):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def set_visible(objs, visible):
    for o in objs:
        o.hide_render = not visible


def make_previews(sword):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    setup_render()
    scene = bpy.context.scene

    # hero three-quarter: sword standing point-up, turned so a flat and an edge both show
    sword.rotation_euler = Euler((0, 0, 0))
    hero_holder = bpy.data.objects.new("hero_holder", None)
    scene.collection.objects.link(hero_holder)
    sword.parent = hero_holder
    # Blender's +Y (the blade) becomes up (+Z), the flat faces the camera's side
    hero_holder.rotation_euler = Euler((math.radians(90), 0, math.radians(-30)))
    hero_holder.location = (0, 0, 0)
    center, size = frame([hero_holder])
    view = Vector((0.45, -1.0, 0.5)).normalized()
    cam = camera("hero_cam", center + view * size * 1.0, center, lens=50)
    render(cam, os.path.join(PREVIEW_DIR, "blade_rare_hero.png"))

    # icon: the flat straight on, diagonal like an inventory icon
    hero_holder.rotation_euler = Euler((math.radians(90), math.radians(45), 0))  # point to the top right
    center, size = frame([hero_holder], 1.08)
    cam = camera("icon_cam", center + Vector((0, -2.0, 0)), center, ortho_scale=size)
    render(cam, os.path.join(PREVIEW_DIR, "blade_rare_icon.png"))

    # side by side with the Normal sword, flats facing the camera, point up
    hero_holder.rotation_euler = Euler((math.radians(90), 0, 0))
    hero_holder.location = (0.17, 0, 0)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(WEAPON_DIR, "blade.glb"))
    imported = [o for o in bpy.data.objects if o not in before]
    old_holder = bpy.data.objects.new("old_holder", None)
    scene.collection.objects.link(old_holder)
    for o in imported:
        if o.parent is None:
            o.parent = old_holder
    old_holder.rotation_euler = Euler((math.radians(90), 0, 0))
    old_holder.location = (-0.17, 0, 0)
    center, size = frame([hero_holder, old_holder], 1.12)
    cam = camera("cmp_cam", center + Vector((0, -3.0, 0)), center, ortho_scale=size)
    render(cam, os.path.join(PREVIEW_DIR, "blade_rare_vs_blade.png"), res=(1024, 1024))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = make_materials()
    sword = build_sword(mats)
    os.makedirs(WEAPON_DIR, exist_ok=True)
    path = os.path.join(WEAPON_DIR, "blade_rare.glb")
    export(sword, path)
    print("EXPORTED", path, "tris:", tri_count(sword), "verts:", len(sword.data.vertices))
    if "--preview" in sys.argv:
        make_previews(sword)
    print("DONE")


main()
