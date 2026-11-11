"""Extract 11 semantic props from the supplied single-mesh kit, preserve UVs/materials.
Blender -b --factory-startup -P tools/blender/prepare_mummy_kit.py
"""
import bpy,bmesh,json,math,sys,hashlib,struct
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT.parent/'assets/modular_mummy_assets.glb'
OUT=ROOT/'art/props/mummy_tomb';SOURCE=ROOT/'art_source/props/mummy_tomb'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path(__file__).parent));from build_orc_kit import glb_external_image
# Source-space centres identify disconnected pieces, including separate flame and handle islands.
PARTS={
 'coffin':((-0.377,.135,.328),2.8),
 'torch':((-.384,.24,.32),2.6),
 'pillar':((-.186,.13,.336),3.6),
 'anubis_urn':((.238,.126,.305),1.3),
 'brazier':((.441,.261,.248),1.25),
 'altar':((.0395,-.045,.247),1.1),
 'stairs':((.0395,-.102,.05),.6),
 'chest':((-.151,-.272,.067),.9),
 'obelisk':((-.322,-.43,.124),2.7),
 'wall_panel':((.23,-.304,.107),1.6),
 'urn':((.424,-.295,.111),.65),
}
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(SRC))
body=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.context.view_layer.objects.active=body;body.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Weld scratch topology only to identify semantic islands, not the final mesh/UVs.
bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bm.verts.index_update();seen=set();classification={}
for vertex in bm.verts:
 if vertex.index in seen:continue
 stack=[vertex];seen.add(vertex.index);verts=[]
 while stack:
  v=stack.pop();verts.append(v)
  for edge in v.link_edges:
   other=edge.other_vert(v)
   if other.index not in seen:seen.add(other.index);stack.append(other)
 center=sum((v.co for v in verts),Vector())/len(verts)
 name=min(PARTS,key=lambda n:(center-Vector(PARTS[n][0])).length)
 low=min(v.co.z for v in verts)
 fire=(name=='torch' and low>.35) or (name=='brazier' and low>.25)
 for v in verts:classification[tuple(round(c,5) for c in v.co)]=(name,fire)
bm.free()
# Resize actual images and save one shared set for kit and all future scenes.
for image in list(bpy.data.images):
 if not image.size[0]:continue
 role='normal' if 'normal' in image.name.lower() else 'mr' if any(t in image.name.lower() for t in ['metallic','roughness']) else 'albedo'
 image.name='mummy_kit_'+role;cap=1024 if role=='albedo' else 512
 if max(image.size)>cap:image.scale(round(image.size[0]*cap/max(image.size)),round(image.size[1]*cap/max(image.size)))
 image.filepath_raw=str(OUT/(image.name+'.png'));image.file_format='PNG';image.save()
 # Refresh packed bytes explicitly; imported GLB images can otherwise retain original4K PNGs.
 payload=Path(image.filepath_raw).read_bytes();image.pack(data=payload,data_len=len(payload))
material=body.data.materials[0];material.name='mummy_kit_stone'
firemat=material.copy();firemat.name='mummy_kit_flame'
bs=next(n for n in firemat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
color=next(n for n in firemat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'albedo' in n.image.name)
firemat.node_tree.links.new(color.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.7
parts=[];report={}
for name,(_,height) in PARTS.items():
 mesh=body.data.copy();piece=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(piece)
 bm=bmesh.new();bm.from_mesh(mesh)
 drop=[v for v in bm.verts if classification[tuple(round(c,5) for c in v.co)][0]!=name]
 bmesh.ops.delete(bm,geom=drop,context='VERTS');bm.to_mesh(mesh);bm.free()
 if not len(mesh.polygons):raise RuntimeError('Empty kit piece '+name)
 mesh.materials.clear();mesh.materials.append(material);mesh.materials.append(firemat)
 for poly in mesh.polygons:
  poly.material_index=1 if any(classification[tuple(round(c,5) for c in mesh.vertices[i].co)][1] for i in poly.vertices) else 0
 points=[v.co for v in mesh.vertices];lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
 pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));scale=height/(hi.z-lo.z)
 mesh.transform(Matrix.Scale(scale,4)@Matrix.Translation(-pivot));mesh.calc_loop_triangles()
 piece['mummy_kit_part']=name;piece['version']=1
 report[name]={'height_m':height,'size_blender':list((hi-lo)*scale),'triangles':len(mesh.loop_triangles),'source_center':list(pivot),'fit_scale':scale}
 parts.append(piece)
bpy.data.objects.remove(body,do_unlink=True)
for i,piece in enumerate(parts):piece.location=((i%4)*4,(i//4)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'mummy_kit.blend'))
# Kit export uses individual bottom-centred pieces, all placed at origin for instancing by name.
for piece in parts:piece.location=(0,0,0)
bpy.ops.object.select_all(action='DESELECT')
for piece in parts:piece.select_set(True)
path=OUT/'mummy_kit.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_extras=True,export_lights=False,export_cameras=False)
def externalize(path,prefix=''):
 data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+length]);mapping={}
 for image in doc.get('images',[]):
  name=image.get('name','');role='normal' if 'normal' in name else 'mr' if any(t in name for t in ['mr','metallic','roughness']) else 'albedo'
  mapping[Path(name).stem]=prefix+'mummy_kit_'+role+'.png'
 glb_external_image(str(path),mapping)
externalize(path)
metadata={'id':'mummy_tomb_kit_01','version':1,'source':str(SRC),'source_sha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'source_bytes':SRC.stat().st_size,'triangles':sum(p['triangles'] for p in report.values()),'parts':report,'textures':{i.name:list(i.size) for i in bpy.data.images if i.size[0]},'source_preserved':True}
(OUT/'mummy_kit.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('MUMMY_KIT',json.dumps({'parts':len(parts),'triangles':metadata['triangles'],'glb_bytes':path.stat().st_size}),flush=True)
