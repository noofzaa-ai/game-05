"""Workshop progression based on the actual supplied Lv1 FBX palette/geometry."""
import bpy,bmesh,sys,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT/'art_source/props/camp_modular/review/blacksmith_stations_review.blend';OUT=BASE.parent/'levels_matching_v3';OUT.mkdir(parents=True,exist_ok=True)
reports=[]
for level in [1,2,3]:
 bpy.ops.wm.open_mainfile(filepath=str(BASE));s=bpy.context.scene
 def ancestors(o):
  result=[]
  while o.parent:o=o.parent;result.append(o.name)
  return result
 # Reuse source benches, rack, anvil, crates and barrel. No replacement gold/runic architecture.
 for o in list(s.objects):
  if o.name.startswith(('upgrade_canopy','upgrade_roof_tile','upgrade_worktable','upgrade_table_leg','upgrade_inlay_workplate')):bpy.data.objects.remove(o,do_unlink=True)
 bpy.context.view_layer.update()
 for name in ['refine_tool_rack','refine_anvil_station']:
  o=bpy.data.objects.get(name)
  if o:
   o.data=o.data.copy();bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.delete(bm,geom=[f for f in bm.faces if (o.matrix_world@f.calc_center_median()).z>1.3],context='FACES');bm.to_mesh(o.data);bm.free()
 if level==1:
  remove=[o for o in s.objects if o.name.startswith('upgrade_') or 'upgrade_npc_preview' in ancestors(o)]
  for o in remove:bpy.data.objects.remove(o,do_unlink=True)
  for o in s.objects:
   if o.name.startswith('refine_') and o.parent is None:o.location.x+=3.1
  for o in list(s.objects):
   if o.type=='FONT':bpy.data.objects.remove(o,do_unlink=True)
 else:
  # Remove the loose fused-beam remnant above re-used anvil/rack.
  bpy.context.view_layer.update()
  for name in ['upgrade_tool_rack','upgrade_anvil_station']:
   o=bpy.data.objects.get(name)
   if not o:continue
   o.data=o.data.copy();bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.delete(bm,geom=[f for f in bm.faces if (o.matrix_world@f.calc_center_median()).z>1.3],context='FACES');bm.to_mesh(o.data);bm.free()
  def reuse(name,newname,loc):
   original=bpy.data.objects[name];o=original.copy();o.data=original.data.copy();bpy.context.collection.objects.link(o);o.name=newname;o.location=loc;return o
  reuse('refine_front_workbench','upgrade_rear_workbench',(3.25,.55,.12))
  reuse('refine_quench_barrel_left','upgrade_source_barrel',(4.25,.1,.12))
  # Reuse original stone paving as an extra surface, no new texture palette.
  pave=reuse('refine_stone_foundation','upgrade_original_stone_floor',(3.1,-.2,.02))
  # The original stove grows. Every selected core part shares one coherent transform,
  # preserving source UVs/materials and seams; loose work props and NPC keep their size.
  bpy.context.view_layer.update();cx=-3.47126;cy=-.1264;factor=1.12 if level==2 else 1.32;vertical=1.13 if level==2 else 1.42
  core=[]
  for name in ['refine_forge_chimney','refine_roof_canopy','refine_rear_support','refine_right_support_tools']:
   o=bpy.data.objects.get(name)
   if not o:continue
   o.data=o.data.copy();inverse=o.matrix_world.inverted()
   for v in o.data.vertices:
    world=o.matrix_world@v.co;world.x=cx+(world.x-cx)*factor;world.y=cy+(world.y-cy)*(1.05 if level==2 else 1.14);world.z=.12+(world.z-.12)*vertical;v.co=inverse@world
   core.append(o)
  for name in ['refine_tool_rack','refine_anvil_station','refine_quench_barrel_left']:
   o=bpy.data.objects.get(name)
   if o:o.location.x-= .12 if level==2 else .34
  # Foundation grows modestly to support the original forge core.
  for name in ['refine_stone_foundation','refine_continuous_foundation']:
   o=bpy.data.objects.get(name)
   if o:o.scale.x*=1.05 if level==2 else 1.16;o.scale.y*=1.03 if level==2 else 1.10
  if level==3:
   # Extend the original brick chimney with its own textured top masonry.
   bpy.context.view_layer.update();top=max((o.matrix_world@v.co).z for o in core for v in o.data.vertices)
   for o in core:
    faces=[p.index for p in o.data.polygons if all((o.matrix_world@o.data.vertices[i].co).z>top-.42 for i in p.vertices)]
    if not faces:continue
    for row in [1,2]:
     mesh=o.data.copy();part=bpy.data.objects.new('original_brick_chimney_extension',mesh);bpy.context.collection.objects.link(part);part.matrix_world=o.matrix_world.copy();bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();keep=set(faces);bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES');bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(mesh);bm.free();part.location.z+=row*.32
   # Add working capacity using exactly the same source bench/crates, not new buildings.
   reuse('refine_front_workbench','upgrade_second_original_bench',(3.25,1.55,.12))
   reuse('refine_supply_crates','upgrade_extra_original_supplies',(4.45,1.2,.12))
   # Keep the original single quench barrel at its established working position.
   # Materials and scale are inherited unchanged; a small source tool rack adds a rear working edge.
   rack=reuse('upgrade_tool_rack','upgrade_rear_original_tool_rack',(1.5,1.05,.12))
 cam=s.camera;cam.location=(8,-15,12);cam.rotation_euler=(Vector((0,-.15,1.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=15.5
 s.cycles.samples=16;s.cycles.use_denoising=True;s.cycles.max_bounces=3;s.render.threads_mode='FIXED';s.render.threads=4;s.render.resolution_x=1440;s.render.resolution_y=960;s.render.resolution_percentage=100
 s.render.filepath=str(OUT/f'blacksmith_level_{level}.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'blacksmith_level_{level}.blend'));bpy.ops.render.render(write_still=True)
 reports.append({'level':level,'source':'actual original supplied Blacksmith FBX, not primitive Lv1 replacement','unlocks':['refine'] if level==1 else ['refine','upgrade'],'palette':'original texture/UV retained, no new gold/rune materials','npc_height_m':1.8,'proposal_only':True,'growth':'original forge core expands; chimney uses duplicated source masonry; upgrade reuses source work props'})
(OUT/'proposal.json').write_text(json.dumps(reports,indent=2)+'\n')
