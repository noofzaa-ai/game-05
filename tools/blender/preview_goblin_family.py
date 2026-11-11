"""Goblin family checks and previews (run after build_goblin_variants.py):

    blender -b --factory-startup -P tools/blender/preview_goblin_family.py -- [archer mage knight chief] [lineup] [noqa] [norender]

Per variant (art_source/monsters/goblin_<v>/preview/): views.png (front/side/back/top/game camera, rest),
clips.png (every goblin clip from art/animations/goblin.glb at key frames: game camera + 3/4 view), and a
clip QA printed as "QA ..." lines: accessory-vs-body intersecting triangle pairs (hat through ears, cloak
through legs...) and weapon-vs-body pairs (the holding fist excluded) per clip, and how far each prop
goes below the ground. "lineup" renders the player, the goblin and the four variants side by side from
the game camera into art_source/monsters/goblin_family_lineup.png.
"""
import bpy, os, sys, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ALL = ["archer", "mage", "knight", "chief"]
VARIANTS = [a for a in ARGS if a in ALL] or ([] if "lineup" in ARGS else ALL)
ANIM = os.path.join(ROOT, "art/animations/goblin.glb")
KEYS = {"idle": [0.18, 0.52, 0.86], "run": [0.0, 0.25, 0.5], "attack_1": [0.2, 0.45, 0.7], "attack_2": [0.3, 0.5, 0.75],
        "hit": [0.35], "death": [0.35, 0.65, 1.0], "taunt": [0.25, 0.6]}
GAME_DIR = Vector((0, -1, 1)).normalized(); GAME_DIST = 9.9      # the game's camera 8: (0, 7, 7) looking at the fighter

def scene_setup(res=(520, 520)):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'; sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    w = sc.world or bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.57, 0.52, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    if "sun" not in bpy.data.objects:
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
        sun.data.energy = 3.0; sun.rotation_euler = (math.radians(40), 0, math.radians(25))
    cam = bpy.data.objects.get("cam")
    if cam is None:
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
    sc.camera = cam; return sc, cam

def shot(cam, path, target, mode, size, direction=None):
    sc = bpy.context.scene; target = Vector(target)
    if mode == "game":
        cam.data.type = 'PERSP'; cam.data.sensor_fit = 'VERTICAL'
        cam.data.angle_y = 2 * math.atan(size / 2 / GAME_DIST); cam.location = target + GAME_DIR * GAME_DIST
    else:
        cam.data.type = 'ORTHO'; cam.data.sensor_fit = 'AUTO'; cam.data.ortho_scale = size; cam.location = target + Vector(direction).normalized() * 6
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = path; bpy.ops.render.render(write_still=True)

def sheet(files, out, cols):
    ims = []
    for f in files:
        if f is None: ims.append(None); continue
        im = bpy.data.images.load(f); w, h = im.size
        ims.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)); bpy.data.images.remove(im); os.remove(f)
    h, w = next(i for i in ims if i is not None).shape[:2]; rows = (len(ims) + cols - 1) // cols
    S = np.full((h * rows, w * cols, 4), 0.9, dtype=np.float32); S[..., 3] = 1
    for i, im in enumerate(ims):
        if im is None: continue
        r = rows - 1 - i // cols; S[r * h:(r + 1) * h, (i % cols) * w:(i % cols + 1) * w] = im
    o = bpy.data.images.new("sheet", w * cols, h * rows); o.pixels.foreach_set(S.ravel())
    o.filepath_raw = out; o.file_format = 'PNG'; o.save(); bpy.data.images.remove(o)

def load_actions():
    before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=ANIM)
    for o in set(bpy.data.objects) - before: bpy.data.objects.remove(o, do_unlink=True)
    acts = {a.name: a for a in bpy.data.actions}
    for a in acts.values(): a.use_fake_user = True
    return acts

def set_clip(rig, act, frac):
    for pb in rig.pose.bones: pb.rotation_mode = 'QUATERNION'
    rig.animation_data_create(); rig.animation_data.action = act
    if getattr(act, "slots", None) and len(act.slots): rig.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range; bpy.context.scene.frame_set(int(round(f0 + (f1 - f0) * frac)))

def clear_clip(rig):
    if rig.animation_data: rig.animation_data.action = None
    for pb in rig.pose.bones: pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

def world_bvh(o):
    dg = bpy.context.evaluated_depsgraph_get(); e = o.evaluated_get(dg); me = e.to_mesh()
    vs = [e.matrix_world @ v.co for v in me.vertices]; ps = [tuple(p.vertices) for p in me.polygons]
    e.to_mesh_clear(); return BVHTree.FromPolygons(vs, ps), vs

def qa(vname, rig, body, accs, props, acts):
    dom = []
    names = [g.name for g in body.vertex_groups]
    vbone = [max(v.groups, key=lambda g: g.weight).group if v.groups else -1 for v in body.data.vertices]
    for p in body.data.polygons: dom.append(names[vbone[p.vertices[0]]] if vbone[p.vertices[0]] >= 0 else "")
    def side_of(o):
        if o.parent_type == 'BONE': return o.parent_bone.split(".")[-1]
        return "L"
    worst = {}
    for clip, act in [("rest", None)] + sorted(acts.items()):
        f0, f1 = (act.frame_range if act else (0, 0))
        frames = range(int(f0), int(f1) + 1, 2) if act else [0]
        for f in frames:
            if act: set_clip(rig, act, (f - f0) / max(1, f1 - f0))
            else: clear_clip(rig)
            bb, bvs = world_bvh(body)
            for o in accs:
                ob, _ = world_bvh(o); ov = bb.overlap(ob); n = len(ov)
                if not act and n:
                    hist = {}
                    for pr in ov: hist[dom[pr[0]]] = hist.get(dom[pr[0]], 0) + 1
                    print("QA %s rest      %-22s touches %s" % (vname, o.name, hist))
                k = (clip, o.name)
                if n > worst.get(k, (0, 0))[0]:
                    hist = {}
                    for pr in ov: hist[dom[pr[0]]] = hist.get(dom[pr[0]], 0) + 1
                    worst[k] = (n, f, hist)
            for o in props:
                ob, vs = world_bvh(o); sd = side_of(o)
                pairs = [pr for pr in bb.overlap(ob) if dom[pr[0]] not in ("hand." + sd, "forearm." + sd)]
                k = (clip, o.name)
                if len(pairs) > worst.get(k, (0, 0))[0]:
                    hist = {}
                    for pr in pairs: hist[dom[pr[0]]] = hist.get(dom[pr[0]], 0) + 1
                    worst[k] = (len(pairs), f, hist)
                gz = min(v.z for v in vs); kg = (clip, o.name + "_ground")
                if gz < worst.get(kg, (0, 0, 0))[2]: worst[kg] = (0, f, gz)
    clear_clip(rig)
    for (clip, nm), val in sorted(worst.items()):
        if nm.endswith("_ground"):
            print("QA %s %-9s %-22s below ground %.3f m at frame %d" % (vname, clip, nm[:-7], val[2], val[1]))
        else:
            print("QA %s %-9s %-22s %4d intersecting tri pairs (frame %d) %s" % (vname, clip, nm, val[0], val[1], val[2] if len(val) > 2 else ""))

def variant(name, do_qa, do_render):
    vname = "goblin_" + name
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "art_source/monsters", vname, vname + ".blend"))
    rig = bpy.data.objects[vname + "_rig"]; body = bpy.data.objects[vname]
    rig.scale = (bpy.context.scene.get("intended_scale", 1.0),) * 3; bpy.context.view_layer.update()   # QA in real metres
    accs = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig and o.parent_type != 'BONE' and o not in (body,)
            and o.name != "bow" and not o.name.endswith("_mesh")]
    props = [o for o in bpy.data.objects if o.type == 'MESH' and (o.parent_type == 'BONE' or o.name == "bow")]
    for o in bpy.data.objects:
        if o.name.endswith("_mesh"): bpy.data.objects.remove(o, do_unlink=True)
    acts = load_actions()
    if do_qa: qa(vname, rig, body, accs, props, acts)
    if not do_render: return
    out = os.path.join(ROOT, "art_source/monsters", vname, "preview"); os.makedirs(out, exist_ok=True)
    sc, cam = scene_setup()
    zs = [(o.matrix_world @ Vector(b)).z for o in bpy.data.objects if o.type == 'MESH' and o.visible_get() for b in o.bound_box]
    top = max(zs); H = top * 1.12 + 0.1; c = (0, 0, top * 0.48)
    clear_clip(rig); files = []
    for tag, d in (("front", (0, -1, 0.08)), ("side", (1, 0, 0.08)), ("back", (0, 1, 0.08)), ("top", (0, -0.25, 1))):
        p = os.path.join(out, "_v_%s.png" % tag); shot(cam, p, c, "ortho", H, d); files.append(p)
    p = os.path.join(out, "_v_game.png"); shot(cam, p, c, "game", H); files.append(p)
    sheet(files, os.path.join(out, "views.png"), 5)
    files = []
    sc.render.resolution_x = sc.render.resolution_y = 300
    for clip in ("idle", "run", "attack_1", "attack_2", "hit", "death", "taunt"):
        act = acts[clip]
        row = []
        for fr in KEYS[clip] + [None] * (3 - len(KEYS[clip])):
            for tag in ("g", "q"):
                p = os.path.join(out, "_c_%s_%s_%s.png" % (clip, fr, tag))
                if fr is None: p = None
                else:
                    set_clip(rig, act, fr)
                    if tag == "g": shot(cam, p, c, "game", H * 1.15)
                    else: shot(cam, p, c, "ortho", H * 1.15, (0.8, -1, 0.35))
                row.append(p)
        files += row
    sheet(files, os.path.join(out, "clips.png"), 6)
    clear_clip(rig)

def lineup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc, cam = scene_setup((1600, 640))
    entries = [("player", os.path.join(ROOT, "art/characters/chibi-studio/chibi_base_animated.glb")),
               ("goblin", os.path.join(ROOT, "art/monsters/goblin/goblin.glb"))] + \
              [(v, os.path.join(ROOT, "art/monsters/goblin_%s/goblin_%s.glb" % (v, v))) for v in ALL]
    x = 0.0; gap = {"player": 0.9, "goblin": 0.95, "archer": 1.0, "mage": 1.05, "knight": 1.35, "chief": 1.9}
    for name, path in entries:
        before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=path); new = set(bpy.data.objects) - before
        k = {"archer": 1.06, "mage": 1.0, "knight": 1.28, "chief": 1.72}.get(name, 1.0)   # = build_goblin_variants CFG
        for o in new:
            if o.parent is None: o.scale = (k, k, k)
            if o.type == 'MESH' and (o.name.startswith("Icosphere") or "Boy " in o.name or "Short swept" in o.name
                                     or "fringe" in o.name.lower() or "Side lock" in o.name):
                o.hide_render = True
            if o.parent is None: o.location.x += x + gap[name] / 2
        x += gap[name]
    mid = x / 2
    shot(cam, os.path.join(ROOT, "art_source/monsters/goblin_family_lineup_game.png"), (mid, 0, 0.6), "game", 3.0)
    shot(cam, os.path.join(ROOT, "art_source/monsters/goblin_family_lineup_front.png"), (mid, 0, 1.0), "ortho", x * 1.02, (0, -1, 0.05))

do_qa, do_render = "noqa" not in ARGS, "norender" not in ARGS
for v in VARIANTS: variant(v, do_qa, do_render)
if "lineup" in ARGS: lineup()
