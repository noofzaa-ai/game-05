"""Local native concept renders for camp workshop growth. Not live gameplay configuration."""
import bpy,bmesh,math,json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT/'art_source/props/camp_modular/review/blacksmith_stations_review.blend';OUT=BASE.parent/'levels';OUT.mkdir(parents=True,exist_ok=True)
def material(name,color,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
 if emission:bs.inputs['Emission Color'].default_value=(*color,1);bs.inputs['Emission Strength'].default_value=emission
 return m
def box(name,loc,size,mat):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat);mod=o.modifiers.new('beveled_edges','BEVEL');mod.width=.045;mod.segments=1;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name);return o
def copy_part(source,loc):
 p=source.copy();p.data=source.data;bpy.context.collection.objects.link(p);p.location=loc;return p
reports=[]
for level in ([int(v) for v in sys.argv[sys.argv.index('--')+1:]] if '--' in sys.argv else [1,2,3]):
 bpy.ops.wm.open_mainfile(filepath=str(BASE));s=bpy.context.scene
 stone=material('level_stone',(.26,.28,.31));wood=material('level_wood',(.26,.13,.065));slate=material('level_slate',(.10,.17,.29));brass=material('level_brass',(.68,.39,.09));fire=material('ember_orange',(1,.17,.015),2)
 # Keep original heroes at fixed scale in all comparisons.
 if level==1:
  keep={'refine_front_workbench','refine_anvil_station','refine_tool_rack','refine_quench_barrel_left','refine_continuous_foundation'}
  npc=bpy.data.objects.get('refine_npc_preview')
  for o in list(s.objects):
   if o.name.startswith('upgrade_') or (o.type=='MESH' and o.name.startswith('refine_') and o.name not in keep):bpy.data.objects.remove(o,do_unlink=True)
  # Remove hidden imported upgrade character descendants as well.
  for o in list(s.objects):
   if o.type=='MESH' and not o.name.startswith('refine_') and o.name!='Plane':
    ancestor=o.parent;is_refine=False
    while ancestor:
     if ancestor==npc:is_refine=True
     ancestor=ancestor.parent
    if not is_refine:bpy.data.objects.remove(o,do_unlink=True)
  for o in s.objects:
   if o.name in keep or o==npc:o.location.x+=3.1
  # Remove a detached remnant of the fused rear beam from the tool rack draft.
  bpy.context.view_layer.update()
  for rack in [o for o in s.objects if o.name in keep and o.name!='refine_continuous_foundation']:
   rack.data=rack.data.copy();bm=bmesh.new();bm.from_mesh(rack.data)
   bmesh.ops.delete(bm,geom=[f for f in bm.faces if (rack.matrix_world@f.calc_center_median()).z>1.3],context='FACES');bm.to_mesh(rack.data);bm.free()
  # Compact clean small forge, grown into the original full forge at level2.
  box('small_hearth_back',(.1,.7,.8),(1.1,.35,1.35),stone)
  for x in [-.48,.68]:box('small_hearth_side',(x,.35,.55),(.24,.85,.9),stone)
  box('small_hearth_lintel',(.1,.3,1.05),(1.4,.9,.24),stone);box('small_hearth_floor',(.1,.25,.22),(1.4,1.0,.22),stone)
  box('small_chimney',(.1,.65,1.55),(.65,.6,.8),stone)
  for i in range(6):
   bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.14,location=(-.3+i*.15,.25,.4));bpy.context.object.data.materials.append(fire)
  for o in list(s.objects):
   if o.type=='FONT':bpy.data.objects.remove(o,do_unlink=True)
 elif level==3:
  # Additional floor area, supply wings, canopy and second work surfaces: no whole-building scaling.
  for x in [-3.1,3.1]:
   box('expanded_back_platform',(x,1.35,.025),(5.6,2.3,.18),stone)
   for dx in [-2.35,2.35]:box('expanded_canopy_post',(x+dx,1.55,1.38),(.18,.18,2.7),wood)
   box('expanded_canopy_beam',(x,1.55,2.72),(5.2,.23,.23),wood)
   for j in range(9):box('expanded_back_roof_tile',(x-2.25+j*.56,1.85,2.85),(.55,1.5,.13),slate)
  # Same existing assets instanced again; their dimensions remain unchanged.
  for name,pos in [('refine_front_workbench',(-5.5,.6,.12)),('upgrade_worktable',(5.3,.4,.82)),('refine_supply_crates',(-5.8,1.7,.12)),('upgrade_supply_crates',(5.8,1.7,.12)),('refine_quench_barrel_left',(-5.7,-.5,.12))]:
   src=bpy.data.objects.get(name)
   if src:copy_part(src,pos)
  for x in [-6.0,6.0]:
   box('workshop_stone_marker',(x,1.25,.65),(.45,.45,1.3),stone);box('workshop_marker_cap',(x,1.25,1.36),(.6,.6,.13),brass)
 cam=s.camera;cam.location=(8,-15,12);cam.rotation_euler=(Vector((0,-.15,.9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=16.5
 s.cycles.samples=16;s.cycles.use_denoising=True;s.cycles.max_bounces=3;s.render.threads_mode='FIXED';s.render.threads=4;s.render.resolution_x=1280;s.render.resolution_y=840;s.render.resolution_percentage=100
 # The plane must stay large enough to catch all contact shadows.
 s.render.filepath=str(OUT/f'blacksmith_level_{level}.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'blacksmith_level_{level}.blend'));bpy.ops.render.render(write_still=True)
 reports.append({'level':level,'proposal_only':True,'unlocks': ['refine'] if level==1 else ['refine','upgrade'],'npc_height_m':1.8,'camera_ortho_scale':16.5,'growth':'add components and floor area, fixed NPC/prop size'})
(OUT/'proposal.json').write_text(json.dumps(reports,indent=2)+'\n')
