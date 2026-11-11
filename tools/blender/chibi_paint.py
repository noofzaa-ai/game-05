import bpy, bmesh, sys, math, random
from mathutils import Vector, noise
mode, src, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
SKIN=(0.96,0.78,0.66); HAIR=(0.30,0.19,0.13); TUNIC=(0.22,0.47,0.58); SHORTS=(0.30,0.24,0.19)
BOOT=(0.45,0.27,0.14); DARK=(0.10,0.08,0.10); MOUTH=(0.62,0.30,0.30)
def part(name):
    n=name.lower()
    if "eye inset" in n: return "eye", DARK
    if n=="mouth": return "mouth", MOUTH
    if "boot" in n: return "boot", BOOT
    if "shorts" in n: return "shorts", SHORTS
    if "tunic" in n: return "tunic", TUNIC
    if any(k in n for k in ("bob","fringe","hair","lock","brow")): return "hair", HAIR
    return "skin", SKIN
mats={}
def mat(key,color):
    name={"hair":"hair_tint","eye":"eye_tint"}.get(key,key)
    if name in mats: return mats[name]
    m=bpy.data.materials.new(name); m.use_nodes=True
    bsdf=m.node_tree.nodes["Principled BSDF"]; bsdf.inputs["Roughness"].default_value=0.85
    if mode=="flat":
        bsdf.inputs["Base Color"].default_value=(*[c**2.2 for c in color],1)
    else:
        a=m.node_tree.nodes.new("ShaderNodeVertexColor"); a.layer_name="Col"
        m.node_tree.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
    mats[name]=m; return m
for o in list(bpy.data.objects):
    if o.name=="Icosphere": bpy.data.objects.remove(o, do_unlink=True); continue
    if o.type!='MESH': continue
    key,color=part(o.name)
    o.data.materials.clear(); o.data.materials.append(mat(key,color))
    if mode=="painted":
        me=o.data
        attr=me.color_attributes.new("Col",'BYTE_COLOR','CORNER')
        # world-space rest positions/normals (meshes are skinned, rest pose is fine)
        mw=o.matrix_world; nm=mw.to_3x3()
        zs=[(mw@v.co).z for v in me.vertices]; z0,z1=min(zs),max(zs)
        for poly in me.polygons:
            for li in poly.loop_indices:
                v=me.vertices[me.loops[li].vertex_index]
                p=mw@v.co; n=(nm@v.normal).normalized()
                light=0.62+0.38*max(0.0,n.dot(Vector((0.35,-0.45,0.82)).normalized()))   # soft key from upper front
                under=0.85+0.15*max(0.0,n.z+0.3)                                           # darker undersides
                h=(p.z-z0)/max(1e-4,z1-z0)
                grad=0.92+0.12*h if key in("hair","tunic","shorts","boot") else 1.0      # painted top-light gradient
                stroke=1.0+0.07*noise.noise(Vector((p.x*9,p.y*9,p.z*22)))                  # brush streaks
                rim=1.0+0.18*max(0.0,1.0-abs(n.dot(Vector((0,-1,0.2)).normalized())))**3 if key=="hair" else 1.0
                k=light*under*grad*stroke*rim
                c=[min(1.0,ch*k) for ch in color]
                if key=="skin":  # blush on cheeks area of the face
                    if "face" in o.name.lower() and abs(p.x)>0.05 and n.y<-0.5: c=[min(1,c[0]*1.05),c[1]*0.93,c[2]*0.92]
                attr.data[li].color=(*c,1.0)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_vertex_color='MATERIAL' if mode=="painted" else 'NONE')
print("DONE",mode,len(mats))
