"""Prepare supplied FBX kits without altering originals. Spatial cuts are draft boundaries."""
import bpy,bmesh,json,sys,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
from build_orc_kit import glb_external_image

def smith_part(c):
 x,y,z=c
 if z<.048:return 'stone_foundation'
 if y<-.295:return 'front_workbench'
 if x<-.315 and y<-.13:return 'anvil_station'
 if x<-.315:return 'tool_rack'
 if -.34<x<-.18 and -.15<y<.055 and z<.22:return 'quench_barrel_left'
 if x>.245 and y<-.105:return 'supply_crates'
 if x>.18 and -.16<y<.06 and z<.24:return 'quench_barrel_right'
 if z>.33 and x>.015:return 'roof_canopy'
 if y>.17:return 'rear_support'
 if x>.15:return 'right_support_tools'
 return 'forge_chimney'

def main():
 reports={}
 for key,source in [('blacksmith','backsmith'),('merchant','merchance'),('storage','storage'),('tailor','tailor')]:
  src=ROOT.parent/'assets'/f'{source}_assets_split.fbx';out=ROOT/'art/props/camp_modular'/key;editable=ROOT/'art_source/props/camp_modular'/key
  out.mkdir(parents=True,exist_ok=True);editable.mkdir(parents=True,exist_ok=True)
  bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(src))
  meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
  for o in meshes:
   bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  # Resize actual embedded bytes. Role names originate in FBX material images.
  for im in list(bpy.data.images):
   if not im.size[0]:continue
   cap=512 if any(t in im.name.lower() for t in ('normal','metallic','roughness','occlusion')) else 1024
   if max(im.size)>cap:im.scale(round(im.size[0]*cap/max(im.size)),round(im.size[1]*cap/max(im.size)))
   im.filepath_raw=str(editable/(im.name+'.png'));im.file_format='PNG';im.save();payload=Path(im.filepath_raw).read_bytes();im.pack(data=payload,data_len=len(payload))
  # 4.2m-wide foundation, shared scale for geometry and component placement.
  xs=[v.co.x for o in meshes for v in o.data.vertices];scale=4.2/(max(xs)-min(xs))
  groups={}
  for o in meshes:
   for p in o.data.polygons:
    c=p.center
    name=smith_part(c) if key=='blacksmith' else ('foundation' if c.z<.035 else 'left_section' if c.x<-.17 else 'right_section' if c.x>.17 else 'central_section')
    groups.setdefault((o.name,name),[]).append(p.index)
  parts=[];meta=[]
  for (objname,name),faces in groups.items():
   original=bpy.data.objects[objname];mesh=original.data.copy();part=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(part)
   bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();keep=set(faces);bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES');bm.to_mesh(mesh);bm.free()
   # Strip orphan vertices, retain existing UV loops and polygon material assignments.
   bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(mesh);bm.free()
   pts=[v.co.copy() for v in mesh.vertices];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
   mesh.transform(Matrix.Scale(scale,4)@Matrix.Translation(-pivot));part.location=pivot*scale;mesh.calc_loop_triangles();part['component_id']=key+'_'+name;part['draft_spatial_boundary']=True
   parts.append(part);meta.append({'name':part.name,'triangles':len(mesh.loop_triangles),'assembly_location_blender':list(part.location),'dimensions':list((hi-lo)*scale),'pivot':'bottom-center','boundary':'draft spatial face classification; no hidden-side caps generated'})
  for o in meshes:bpy.data.objects.remove(o,do_unlink=True)
  bpy.ops.wm.save_as_mainfile(filepath=str(editable/(key+'_assembled.blend')))
  def export(path,items):
   bpy.ops.object.select_all(action='DESELECT')
   for o in items:o.select_set(True)
   bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_extras=True,export_cameras=False,export_lights=False)
  export(out/(key+'_assembled.glb'),parts)
  for part in parts:
   loc=part.location.copy();part.location=(0,0,0);export(out/(part.name+'.glb'),[part]);part.location=loc
  # Externalize images across every component so duplicated textures are not shipped.
  import struct
  mapping={}
  for path in sorted(out.glob('*.glb')):
   raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n])
   binstart=20+n+8;binary=raw[binstart:]
   local={}
   for i,img in enumerate(doc.get('images',[])):
    name=img.get('name',f'image_{i}');fn=key+'_'+name+'.png';bv=doc['bufferViews'][img['bufferView']];offset=bv.get('byteOffset',0);(out/fn).write_bytes(binary[offset:offset+bv['byteLength']]);local[Path(name).stem]=fn
   if local:glb_external_image(str(path),local)
  report={'id':key+'_modular_draft','source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'source_bytes':src.stat().st_size,'scale':scale,'parts':meta,'triangles':sum(p['triangles'] for p in meta),'status':'assembly review draft, not deployed; fused source spatial cuts require review before arbitrary rearrangement','texture_caps':{'albedo':1024,'normal':512,'metallic_roughness':512}}
  (out/'kit.json').write_text(json.dumps(report,indent=2)+'\n');reports[key]=report
  print('PREPARED',key,report['triangles'],len(meta),flush=True)
 (ROOT/'art_source/props/camp_modular/report.json').write_text(json.dumps(reports,indent=2)+'\n')
if __name__=='__main__':main()
