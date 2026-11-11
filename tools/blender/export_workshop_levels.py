"""Export six prop-only workshops from matching v3 study, with shared textures."""
import bpy,json,sys,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).parent));from build_orc_kit import glb_external_image
SOURCE=ROOT/'art_source/props/camp_modular/review/levels_matching_v3';OUT=ROOT/'art/props/camp_modular/workshops';OUT.mkdir(parents=True,exist_ok=True);reports=[]
for kind in ['refine','upgrade']:
 for level in [1,2,3]:
  sourcelevel=2 if kind=='upgrade' and level==1 else level;bpy.ops.wm.open_mainfile(filepath=str(SOURCE/f'blacksmith_level_{sourcelevel}.blend'))
  parts=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.name.startswith(kind+'_') or (kind=='refine' and o.name.startswith('original_brick_chimney_extension')))]
  if kind=='upgrade' and level==1:parts=[o for o in parts if o.name not in ['upgrade_rear_workbench','upgrade_source_barrel']]
  shift=0 if kind=='refine' and level==1 else 3.1 if kind=='refine' else -3.1
  bpy.ops.object.select_all(action='DESELECT')
  for o in parts:o.location.x+=shift;o.select_set(True)
  path=OUT/f'{kind}_lv{level}.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_extras=True,export_lights=False,export_cameras=False)
  raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);mapping={}
  for img in doc.get('images',[]):mapping[Path(img['name']).stem]='../blacksmith/blacksmith_'+img['name']+'.png'
  glb_external_image(str(path),mapping)
  triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc.get('meshes',[]) for p in m['primitives'])
  reports.append({'type':kind,'level':level,'asset':str(path.relative_to(ROOT)),'triangles':triangles,'npc':'bs_'+kind,'npc_height_m':1.5,'patrol_local_godot':{'from':[-.9,0,3.0],'to':[.9,0,3.0]},'runtime_unlock_rules':'not assigned; UpgradeLv1 visual prefab available'})
(OUT/'workshops.json').write_text(json.dumps({'version':1,'levels':reports,'shared_textures':'../blacksmith/','source_preserved':True},indent=2)+'\n')
print('WORKSHOPS',json.dumps(reports),flush=True)
