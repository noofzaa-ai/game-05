"""Orc camp prop kit (Boss 2026-10-15): splits the bought contact sheet (art_source/props/orc_camp/orc_source.glb,
one 50k-tri mesh, 12 props in a 4 x 3 grid, the whole sheet < 1 m, 3 x 4096 PBR maps) into 12 game props:
scaled to game size, standing on y = 0, centred, facing +Z (Godot) like our other assets.

v3 (Boss 2026-10-20, assets_spec.md): shared color1024 / normal512, metallic0 / roughness1.
Static non-fire props retain85% source geometry; gate/watchtower/forge/bonfire stay full detail to protect
small fire surfaces and light anchors. Original source is unchanged. Both geometry and texture detail are
reviewed against the previous live version before publishing. Never collapse below85% in this builder.

    art/props/orc_camp/orc_kit_atlas.png         shared basecolor1024
    art/props/orc_camp/orc_kit_normal.png        tangent-space normal512 (glTF / OpenGL +Y)
    art/props/orc_camp/orc_kit.glb              12 named nodes; external shared image URIs
    art_source/preview/orc_kit/*.png            preview renders

Each mesh has UVs into the atlas and a COLOR_0 per loop: a light contact darkening near the ground for the
textured faces (material orc_kit), the sampled texture colour for the fire faces (material orc_kit_fire:
flames, embers, torch heads), so a stage can merge the fire faces into its unshaded, vertex-coloured gf_fire.
Light anchors (where a stage should put light_fire_* empties) are stored as custom props `lights` on each node.
tools/blender/build_goblin_stages.py places the pieces into the stage glbs (keeping the normals).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_orc_kit.py [-- --no-render]
"""
import bpy, bmesh, math, os, sys, json, struct, subprocess, time
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "art_source/props/orc_camp/orc_source.glb")
OUT_DIR = os.path.join(ROOT, "art/props/orc_camp")
ATLAS = "orc_kit_atlas.png"
NORMAL = "orc_kit_normal.png"
PREVIEW = os.path.join(ROOT, "art_source/preview/orc_kit")
ATLAS_SIZE = 1024
NORMAL_SIZE = 512
# assets_spec.md: conservative 85% geometry on static non-fire props; fire-bearing
# landmarks retain full geometry to protect small flames/light anchors.
ATLAS_GAIN = 1.0    # (v1 lifted the sRGB values 15 % and clipped the highlights; v2 keeps the painted values)
CONTACT_DARK = 0.85  # COLOR_0 at the ground (v1: 0.62, which made every piece read as a dark blob from above)

# name -> (grid row, column, target height in metres, keep ratio). Heights judged from the art against our
# 1.61 m chibi: walls are a bit over head height, the gate and tower are landmarks. keep: the share of the
# source triangles kept (1.0 = full source geometry; never below 0.85 - a gentle collapse only)
PROPS = {
    "palisade":     (0, 0, 2.6, 0.85),
    "bone_fence":   (0, 1, 1.3, 0.85),
    "gate":         (0, 2, 4.2, 1.0),
    "watchtower":   (0, 3, 6.0, 1.0),
    "hut":          (1, 0, 3.1, 0.85),
    "bonfire":      (1, 1, 2.3, 1.0),
    "totem":        (1, 2, 3.0, 0.85),
    "cage":         (1, 3, 3.4, 0.85),
    "picket_fence": (2, 0, 1.8, 0.85),
    "forge":        (2, 1, 2.8, 1.0),
    "war_banner":   (2, 2, 3.0, 0.85),
    "throne":       (2, 3, 2.8, 0.85),
}
# Light anchors per prop, in the prop's own Godot space (x, y, z) after scaling (filled in from fire faces when
# the list is empty: one light at the centre of the fire faces).
LIGHT_KIND = {"bonfire": "light_fire", "forge": "light_fire", "watchtower": "light_fire", "gate": "light_lantern"}
# hand-placed anchors where the texture's fire is too small to find (the gate's two lanterns, the forge mouth)
LIGHT_AT = {"gate": [[-1.46, 1.3, 0.75], [1.46, 1.3, 0.75]], "forge": [[0.0, 1.0, 0.8]],
            "watchtower": [[1.4, 4.48, 0.63], [1.62, 2.51, -1.23]], "bonfire": [[0.0, 1.0, 0.0]]}


def log(*a):
    print("ORC_KIT", *a, flush=True)


def load_source():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    ob = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)  # Blender Z-up, front = -Y
    mat = ob.data.materials[0]
    img = nrm = None
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and "metallic" not in n.image.name:
            if "normal" in n.image.name:
                nrm = n.image
            else:
                img = n.image
    return ob, img, nrm


def loose_parts(bm):
    bm.verts.ensure_lookup_table()
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(comp)
    return parts


def assign(parts):
    """Part -> prop name. Parts whose front-view (x, z) boxes touch are one cluster (that gives 10 clusters on
    the sheet: the bonfire's smoke touches the forge chimney and the cage's gallows touches the tower's legs);
    each cluster's centre picks its grid cell, and the two merged clusters are split at the row gap."""
    boxes = []
    for p in parts:
        xs = [v.co.x for v in p]
        zs = [v.co.z for v in p]
        boxes.append((min(xs), max(xs), min(zs), max(zs)))
    n = len(parts)
    par = list(range(n))

    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    order = sorted(range(n), key=lambda i: boxes[i][0])
    for a in range(n):
        i = order[a]
        for b in range(a + 1, n):
            j = order[b]
            if boxes[j][0] > boxes[i][1]:
                break
            if boxes[j][2] <= boxes[i][3] and boxes[i][2] <= boxes[j][3]:
                par[find(i)] = find(j)
    clusters = {}
    for i in range(n):
        clusters.setdefault(find(i), []).append(i)
    log("clusters", len(clusters))
    names = {}
    # row gaps on the sheet (height, m) and column splits per row (x, m), measured from the part histograms
    rows = [0.42, 0.199]          # row 0 above 0.42, row 1 above 0.199, row 2 below
    cols = {0: [-0.26, -0.034, 0.29], 1: [-0.2, 0.015, 0.25], 2: [-0.262, -0.01, 0.175]}
    by_cell = {(r, c): k for k, (r, c, _, _) in PROPS.items()}
    for root, members in clusters.items():
        V = sum(len(parts[i]) for i in members)
        x0 = min(boxes[i][0] for i in members)
        x1 = max(boxes[i][1] for i in members)
        z0 = min(boxes[i][2] for i in members)
        z1 = max(boxes[i][3] for i in members)
        merged = z1 - z0 > 0.3   # two props stacked in one column
        cx = (x0 + x1) / 2
        cz = (z0 + z1) / 2
        log("cluster verts %6d parts %4d x %.3f..%.3f z %.3f..%.3f%s" % (V, len(members), x0, x1, z0, z1,
                                                                          " (merged: split at the row gap)" if merged else ""))
        for i in members:
            if merged:
                # split by each part's lowest point: every part of the upper prop starts above the row gap,
                # the forge chimney and the gallows post reach up into the gap from below
                zlow = boxes[i][2]
                row = 0 if zlow >= 0.399 else (1 if zlow >= 0.198 else 2)
            else:
                row = 0 if cz > rows[0] else (1 if cz > rows[1] else 2)
            c = sum(1 for s in cols[row] if cx > s)
            names[i] = by_cell[(row, c)]
    return names


def sample(img_px, w, h, uv):
    x = int((uv.x % 1.0) * (w - 1))
    y = int((uv.y % 1.0) * (h - 1))
    i = (y * w + x) * 4
    return img_px[i], img_px[i + 1], img_px[i + 2]


FIRE_PROPS = ("bonfire", "forge", "watchtower", "gate")   # (only these have flames: no false hits on banners)


def is_fire(c):
    """A flame / ember texel (sRGB): bright orange-yellow. Ivory horns and bone are less saturated, the red
    banners darker and redder."""
    r, g, b = c
    return r > 0.78 and g > 0.40 and b < 0.45 and r - b > 0.40 and g < r - 0.08


def is_smoke(c):
    r, g, b = c
    return min(c) > 0.55 and max(c) - min(c) < 0.22


def lin(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def build():
    ob, img, nrm = load_source()
    w, h = img.size
    px = list(img.pixels[:])   # (a byte sRGB image: the floats are the stored sRGB values; row 0 = uv.y 0)
    log("source tris", sum(len(p.vertices) - 2 for p in ob.data.polygons), "atlas", w, h)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # the source's shading normals (glTF NORMAL -> custom split normals) per loop: they are what makes the sheet
    # look right (smooth curves, crisp plank edges); carried through and set back as custom normals in finish()
    ln = [bm.loops.layers.float.new(k) for k in ("lnx", "lny", "lnz")]
    cn = ob.data.corner_normals
    bm.faces.ensure_lookup_table()
    for poly in ob.data.polygons:
        f = bm.faces[poly.index]
        for l, k in zip(f.loops, poly.loop_indices):
            l[ln[0]], l[ln[1]], l[ln[2]] = cn[k].vector
    # cluster on the raw loose parts (props whose bits touch stay apart), store the prop on each vertex.
    # (v2: no welding: the source vertices are kept exactly as they are)
    tag = bm.verts.layers.int.new("prop")   # (added before the walk: a new layer invalidates vertex refs)
    parts = loose_parts(bm)
    log("loose parts", len(parts))
    names = assign(parts)
    keys = list(PROPS)
    for i, p in enumerate(parts):
        for v in p:
            v[tag] = keys.index(names[i])
    bm.verts.index_update()
    vert_prop = {v.index: keys[v[tag]] for v in bm.verts}
    uv_src = bm.loops.layers.uv.active
    # one bmesh per prop (copy of the faces)
    out = {}
    for name in PROPS:
        b = bmesh.new()
        uv = b.loops.layers.uv.new("UVMap")
        bln = [b.loops.layers.float.new(k) for k in ("lnx", "lny", "lnz")]
        vmap = {}
        for f in bm.faces:
            if vert_prop[f.verts[0].index] != name:
                continue
            vs = []
            for v in f.verts:
                if v.index not in vmap:
                    vmap[v.index] = b.verts.new(v.co)
                vs.append(vmap[v.index])
            try:
                nf = b.faces.new(vs)
            except ValueError:
                continue
            for l_new, l_old in zip(nf.loops, f.loops):
                l_new[uv].uv = l_old[uv_src].uv.copy()
                for k in range(3):
                    l_new[bln[k]] = l_old[ln[k]]
        out[name] = b
    bm.free()
    for name, b in out.items():
        log("split", name, "faces", len(b.faces))
    return out, img, nrm, px, w, h


def finish(name, b, img_px, w, h):
    """Scale / place, (optionally gently decimate), face each triangle the way its source normals point, mark
    fire faces, paint COLOR_0, set the source shading normals. Returns the mesh object."""
    row, col, height, keep = PROPS[name]
    assert keep >= 0.85, "never collapse a piece below 85 % of its source triangles"
    xs = [v.co.x for v in b.verts]
    ys = [v.co.y for v in b.verts]
    zs = [v.co.z for v in b.verts]
    s = height / (max(zs) - min(zs))
    off = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    for v in b.verts:
        v.co = (v.co - off) * s   # (uniform scale: the shading normals stay valid as they are)
    node = name
    me = bpy.data.meshes.new(node)
    ob = bpy.data.objects.new(node, me)
    bpy.context.scene.collection.objects.link(ob)
    tris0 = sum(len(f.verts) - 2 for f in b.faces)
    if keep < 1.0:
        b.to_mesh(me)
        b.free()
        mod = ob.modifiers.new("dec", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = keep
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier="dec")
        b = bmesh.new()
        b.from_mesh(me)
        bmesh.ops.dissolve_degenerate(b, edges=b.edges, dist=1e-6)
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context='VERTS')
    bmesh.ops.triangulate(b, faces=b.faces)
    ln = [b.loops.layers.float.get(k) for k in ("lnx", "lny", "lnz")]
    # the sheet's face winding is not consistent (~1 % of the faces wind against their own shading normals); the
    # game draws this material two-sided, which flips a back-facing triangle's normal: wind every face the way
    # its source normals point so nothing shades inside-out (a flip keeps each loop's uv / normal on its vertex)
    flipped = 0
    for f in b.faces:
        n = Vector()
        for l in f.loops:
            n += Vector((l[ln[0]], l[ln[1]], l[ln[2]]))
        if f.normal.dot(n) < 0.0:
            f.normal_flip()
            flipped += 1
    uv = b.loops.layers.uv.active
    col_layer = b.loops.layers.float_color.new("Col")
    fire_pts = []
    smoke = []
    for f in b.faces:
        cols = [sample(img_px, w, h, l[uv].uv) for l in f.loops]
        c = tuple(sum(cc[i] for cc in cols) / 3 for i in range(3))
        if name == "bonfire" and f.calc_center_median().z > 1.15 and is_smoke(c):
            smoke.append(f)   # the smoke plume: a white blob from above, and it hides the flames
            continue
        fire = name in FIRE_PROPS and is_fire(c)
        f.material_index = 1 if fire else 0
        if fire:
            fire_pts.append(f.calc_center_median())
        for l, cc in zip(f.loops, cols):
            if fire:
                k = 1.2   # flames read brighter than the lit texture (gf_fire is unshaded); COLOR_0 is linear
                l[col_layer] = (lin(min(1, cc[0] * k)), lin(min(1, cc[1] * k)), lin(min(1, cc[2] * k)), 1.0)
            else:
                z = l.vert.co.z
                g = CONTACT_DARK + (1.0 - CONTACT_DARK) * min(1.0, z / 0.6)   # light contact darkening
                l[col_layer] = (g, g, g, 1.0)
    bmesh.ops.delete(b, geom=smoke, context='FACES')
    if name == "bonfire":
        b.faces.index_update()
        # the smoke cut leaves a few stray wisps (small islands floating over / beside the fire): drop them
        seen, stray = set(), []
        by_pos = {}
        for f in b.faces:
            for v in f.verts:
                by_pos.setdefault(tuple(round(c, 4) for c in v.co), []).append(f)
        for f0 in b.faces:
            if f0.index in seen or not f0.is_valid:
                continue
            isl, stack = [], [f0]
            seen.add(f0.index)
            while stack:
                f = stack.pop()
                isl.append(f)
                for v in f.verts:   # (by position: the source's uv seams split the vertices)
                    for g in by_pos[tuple(round(c, 4) for c in v.co)]:
                        if g.index not in seen:
                            seen.add(g.index)
                            stack.append(g)
            lo = min(v.co.z for f in isl for v in f.verts)
            if len(isl) < 300 and (lo > 0.9 or abs(isl[0].calc_center_median().x) > 0.8):
                stray += isl
        b.faces.index_update()
        bmesh.ops.delete(b, geom=stray, context='FACES')
        log("bonfire stray wisp faces removed", len(stray))
    for f in b.faces:
        f.smooth = True   # (the real shading comes from the source normals set below)
    bmesh.ops.delete(b, geom=[v for v in b.verts if not v.link_faces], context='VERTS')
    b.to_mesh(me)
    b.free()
    me.color_attributes.active_color_index = me.color_attributes.find("Col")
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    set_loop_normals(me)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    size = (max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys))   # Godot (w, h, d)
    lights = []
    if name in LIGHT_KIND and fire_pts:
        # cluster the fire faces into up to 4 spots (torches / the fire) -> light anchors (Godot coords)
        spots = []
        for p in fire_pts:
            for sp in spots:
                if (sp[0] / sp[1] - p).length < 0.9:
                    sp[0] += p
                    sp[1] += 1
                    break
            else:
                spots.append([p.copy(), 1])
        spots.sort(key=lambda sp: -sp[1])
        for sp in spots[:4]:
            if sp[1] < 3:
                continue
            c = sp[0] / sp[1]
            lights.append([round(c.x, 2), round(c.z + 0.25, 2), round(-c.y, 2)])
    if name in LIGHT_AT:
        lights = LIGHT_AT[name]
    ob["lights"] = json.dumps({"kind": LIGHT_KIND.get(name, ""), "at": lights})
    log("PIECE %-16s tris %5d (from %5d)  size w %.2f h %.2f d %.2f m  fire faces %d  flipped %d  lights %s" % (
        node, tris, tris0, size[0], size[1], size[2], len(fire_pts), flipped, lights))
    return ob, tris


def set_loop_normals(me):
    """The lnx/lny/lnz corner attributes (the carried source normals) -> the mesh's custom split normals."""
    a = [me.attributes[k] for k in ("lnx", "lny", "lnz")]
    nn = []
    for i in range(len(me.loops)):
        v = Vector((a[0].data[i].value, a[1].data[i].value, a[2].data[i].value))
        nn.append(v.normalized() if v.length > 1e-8 else Vector((0, 0, 1)))
    me.normals_split_custom_set(nn)
    for k in ("lnx", "lny", "lnz"):
        me.attributes.remove(me.attributes[k])


def downscale_png(img, out_name, size, non_color=False):
    """The source's embedded 4096 png (its original bytes) -> art/props/orc_camp/<out_name> at `size`, resampled
    by macOS sips (Lanczos-quality; Blender's Image.scale is a box filter and softens the paint)."""
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = os.path.join(bpy.app.tempdir or "/tmp", "orc_src_" + out_name)
    with open(tmp, "wb") as f:
        f.write(img.packed_file.data)
    out = os.path.join(OUT_DIR, out_name)
    if os.path.exists(out):
        os.remove(out)
    subprocess.run(["sips", "-s", "format", "png", "-z", str(size), str(size), tmp, "--out", out], check=True,
                   stdout=subprocess.DEVNULL)
    for _ in range(50):   # (sips can return a moment before the file is complete)
        if os.path.exists(out) and os.path.getsize(out) > 0:
            break
        time.sleep(0.1)
    os.remove(tmp)
    if ATLAS_GAIN != 1.0 and not non_color:
        raise NotImplementedError("ATLAS_GAIN: v2 keeps the painted values")
    im = bpy.data.images.load(out)
    im.name = os.path.splitext(out_name)[0]
    if non_color:
        im.colorspace_settings.name = 'Non-Color'
    return im


def make_atlas(img):
    return downscale_png(img, ATLAS, ATLAS_SIZE)


def make_materials(atlas, normal):
    mats = []
    for nm in ("orc_kit", "orc_kit_fire"):
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = atlas
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        if normal is not None and nm == "orc_kit":   # (the fire faces end up unshaded in gf_fire)
            nt_tex = nt.nodes.new("ShaderNodeTexImage")
            nt_tex.image = normal
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(nt_tex.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        mats.append(m)
    return mats


def glb_external_image(path, uri):
    """Rewrite a .glb so its images point at external files (`uri`, relative to the glb: one uri for every image,
    or {image name: uri}) instead of
    embedding the bytes: Godot's glTF import then loads that already-imported texture, so every glb that uses
    the kit shares ONE atlas texture instead of carrying its own copy."""
    data = open(path, "rb").read()
    magic, ver, _ = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, btype = struct.unpack_from("<II", data, off)
    binary = data[off + 8:off + 8 + blen]
    drop = set()
    for im in js.get("images", []):
        if "bufferView" in im:
            u = uri if isinstance(uri, str) else uri[os.path.splitext(im.get("name", ""))[0]]
            drop.add(im.pop("bufferView"))
            im.pop("mimeType", None)
            im["uri"] = u
    new_bin = bytearray()
    for i, bv in enumerate(js["bufferViews"]):
        chunk = binary[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        if i in drop:
            chunk = b"\0\0\0\0"   # (kept as a tiny unused view so no index shifts)
        while len(new_bin) % 4:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(chunk)
        new_bin += chunk
    while len(new_bin) % 4:
        new_bin.append(0)
    js["buffers"][0]["byteLength"] = len(new_bin)
    jb = json.dumps(js, separators=(",", ":")).encode()
    while len(jb) % 4:
        jb += b" "
    total = 12 + 8 + len(jb) + 8 + len(new_bin)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", magic, ver, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(new_bin), 0x004E4942))
        f.write(new_bin)


def export_glb(objs, path, uri):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_animations=False, export_lights=False,
              export_cameras=False, export_apply=False, export_yup=True, export_extras=True,
              export_image_format='AUTO')
    bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    glb_external_image(path, uri)


def render_previews(objs):
    os.makedirs(PREVIEW, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in
                                                                        bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.35, 0.37, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), 0, math.radians(20))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for o in objs:
        for other in objs:
            other.hide_render = other is not o
        hgt = max(o.dimensions.z, o.dimensions.x * 0.75)
        for view, rot, loc in (("front", (math.radians(80), 0, 0), (0, -hgt * 2.6, hgt * 0.5 + hgt * 0.45)),
                               ("top", (math.radians(32), 0, 0), (0, -hgt * 1.45, hgt * 2.6))):
            cam.rotation_euler = rot
            cam.location = loc
            cam.data.lens = 40
            sc.render.filepath = os.path.join(PREVIEW, "%s_%s.png" % (o.name, view))
            bpy.ops.render.render(write_still=True)
    for other in objs:
        other.hide_render = False


def main():
    no_render = "--no-render" in sys.argv
    if not os.path.exists(SRC):   # first run: keep the bought file in art_source (not imported by Godot)
        import shutil
        os.makedirs(os.path.dirname(SRC), exist_ok=True)
        shutil.copyfile(os.path.expanduser("~/Downloads/orc.glb"), SRC)
    out, img, nrm, px, w, h = build()
    objs = []
    total = 0
    for name, b in out.items():
        ob, t = finish(name, b, px, w, h)
        objs.append(ob)
        total += t
    log("TOTAL (one of each piece, spec budget) tris %d" % total)
    atlas = make_atlas(img)
    normal = downscale_png(nrm, NORMAL, NORMAL_SIZE, non_color=True)
    mats = make_materials(atlas, normal)
    for o in objs:
        o.data.materials.append(mats[0])
        o.data.materials.append(mats[1])
    path = os.path.join(OUT_DIR, "orc_kit.glb")
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in objs]:
        bpy.data.objects.remove(o)
    export_glb(objs, path, {atlas.name: ATLAS, normal.name: NORMAL})
    log("TOTAL tris %d  glb %d KB  atlas %d KB  normal %d KB" % (
        total, os.path.getsize(path) // 1024, os.path.getsize(os.path.join(OUT_DIR, ATLAS)) // 1024,
        os.path.getsize(os.path.join(OUT_DIR, NORMAL)) // 1024))
    if not no_render:
        render_previews(objs)


if __name__ == "__main__" and not os.environ.get("ORC_KIT_IMPORT"):
    main()
