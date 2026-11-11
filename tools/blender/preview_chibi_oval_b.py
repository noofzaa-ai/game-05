"""Non-destructive oval-B head draft and surface-fitted face samples from live assets."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/characters/chibi-oval-b';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
ORIGINAL=ROOT/'art_source/characters/chibi-oval-b/original'
def canonical(path):
 backup=ORIGINAL/path.relative_to(ROOT)
 return backup if backup.exists() else path
bpy.ops.import_scene.gltf(filepath=str(canonical(ROOT/'art/characters/chibi-studio/chibi_base_animated.glb')))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
rig.animation_data_clear()
for b in rig.pose.bones:
 b.matrix_basis.identity()
bpy.context.view_layer.update()
head=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.split('.')[0]=='Face')
old=[head.matrix_world@v.co for v in head.data.vertices]
# Continuous closed egg surface: no splice under the eyes and no rear jaw pouch.
import bmesh
head.data.calc_loop_triangles()
old_triangles=[tuple(t.vertices) for t in head.data.loop_triangles]
tree=BVHTree.FromPolygons(old,old_triangles,all_triangles=True)
bm=bmesh.new();inv=head.matrix_world.inverted()
SEG=48;LEVELS=28
rings=[]
for level in range(1,LEVELS):
 phi=math.pi*level/LEVELS
 z=1.354+.169*math.cos(phi)
 horizontal=math.sin(phi)
 # Forehead/cheek gently fuller above; chin centre moves forward beneath mouth.
 lower=max(0,(1.354-z)/.169)
 cy=-.032*lower**1.3
 rx=.158*horizontal
 front=.143*horizontal
 back=.145*horizontal*(1-.28*lower)
 loop=[]
 for i in range(SEG):
  theta=math.tau*i/SEG
  c=math.cos(theta)
  y=cy-(front if c>=0 else back)*c
  loop.append(bm.verts.new(inv@Vector((rx*math.sin(theta),y,z))))
 if rings:
  for i in range(SEG):
   j=(i+1)%SEG;bm.faces.new((rings[-1][i],rings[-1][j],loop[j],loop[i]))
 rings.append(loop)
for loop,z,cy,top in [(rings[0],1.523,0,True),(rings[-1],1.185,-.032,False)]:
 pole=bm.verts.new(inv@Vector((0,cy,z)))
 for i in range(SEG):
  j=(i+1)%SEG
  bm.faces.new((pole,loop[j],loop[i]) if top else (pole,loop[i],loop[j]))
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
assert all(edge.is_manifold for edge in bm.edges), "Head must be a closed manifold"
bm.to_mesh(head.data);bm.free()
# Face is a rigid head skin; all regenerated vertices follow the same Head bone.
head.vertex_groups.clear();vg=head.vertex_groups.new(name='Head');vg.add(list(range(len(head.data.vertices))),1,'REPLACE')
for polygon in head.data.polygons:polygon.use_smooth=True
head.data.update();head.data.calc_loop_triangles()
new=[head.matrix_world@v.co for v in head.data.vertices]
triangles=[tuple(t.vertices) for t in head.data.loop_triangles]
new_tree=BVHTree.FromPolygons(new,triangles,all_triangles=True)
def transfer(ob,anchor=Vector()):
 mw=ob.matrix_world;inv=mw.inverted()
 for v in ob.data.vertices:
  p=mw@v.co+anchor
  closest,normal,index,distance=tree.find_nearest(p)
  hit,_,_,_=new_tree.ray_cast(Vector((p.x,-1,p.z)),Vector((0,1,0)))
  if closest is None or hit is None:continue
  # Keep features shallow and attached to the new curved surface.
  relief=max(.0015,min(.006,.0015+(closest.y-p.y)*.3))
  v.co=inv@(Vector((p.x,hit.y-relief,p.z))-anchor)
 ob.data.update()
for ob in list(bpy.context.scene.objects):
 if ob.type=='MESH' and ob!=head and any(ob.name.startswith(n) for n in ('Eyelid','Eye inset','Brow','Nose','Mouth')):transfer(ob)
for ob in list(bpy.context.scene.objects):
 if ob.type!='MESH' or not ob.get('studio_hair_style'):continue
 mw=ob.matrix_world;inv=mw.inverted()
 for v in ob.data.vertices:
  p=mw@v.co
  t=max(0,min(1,(1.40-p.z)/.16));t=t*t*(3-2*t)
  back=max(0,min(1,p.y/.12))
  p.y-=.045*t*back;p.z+=.025*t*back
  v.co=inv@p
head['head_shape_revision']='oval_b_continuous_v2_20261020'
source_out=ROOT/'art_source/characters/chibi-oval-b';source_out.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(source_out/'oval_b.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'oval_b.glb'),export_format='GLB',export_animations=False,export_extras=True)
anchor=rig.matrix_world@rig.data.bones['attach_head'].head_local
faces=[p.stem for p in sorted((ROOT/'art/items/faces').glob('face_*.glb'))]
for name in faces:
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=str(canonical(ROOT/'art/items/faces'/f'{name}.glb')))
 parts=list(set(bpy.data.objects)-before)
 for ob in parts:
  if ob.type=='MESH':transfer(ob,anchor)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in parts:ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
 for ob in parts:bpy.data.objects.remove(ob,do_unlink=True)
hairs=[p.stem for p in sorted((ROOT/'art/items/hair').glob('*.glb'))]
for name in hairs:
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=str(canonical(ROOT/'art/items/hair'/f'{name}.glb')))
 parts=list(set(bpy.data.objects)-before)
 for ob in parts:
  if ob.type!='MESH':continue
  mw=ob.matrix_world;inv=mw.inverted()
  for v in ob.data.vertices:
   p=mw@v.co+anchor
   t=max(0,min(1,(1.40-p.z)/.16));t=t*t*(3-2*t)
   back=max(0,min(1,p.y/.12))
   p.y-=.045*t*back;p.z+=.025*t*back
   v.co=inv@(p-anchor)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in parts:ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
 for ob in parts:bpy.data.objects.remove(ob,do_unlink=True)
report={'draft':True,'surface':'continuous 48x28 oval; full skull rebuilt to match reference','lower_head_rebuilt':True,'closed_manifold':True,'head_bounds_blender':{'min':[min(p[i] for p in new) for i in range(3)],'max':[max(p[i] for p in new) for i in range(3)]},'head_triangles':len(triangles),'faces':faces,'hair':'draft copies; rear lower cap fitted to oval skull, original production GLBs unchanged','rig':'unchanged rest skeleton; draft static export, production clips external'}
(OUT/'fit_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('OVAL_REPORT',report)
