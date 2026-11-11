"""Local native concept renders for camp workshop growth. Not live gameplay configuration."""
import bpy,bmesh,math,json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT/'art_source/props/camp_modular/review/blacksmith_stations_review.blend';OUT=BASE.parent/'levels_forge_v2';OUT.mkdir(parents=True,exist_ok=True)
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
  # Forge-first progression: monumental masonry and furnace silhouette.
  for name in ['refine_forge_chimney','refine_roof_canopy','refine_rear_support','refine_right_support_tools']:
   o=bpy.data.objects.get(name)
   if o:bpy.data.objects.remove(o,do_unlink=True)
  for o in list(s.objects):
   if o.name.startswith(('upgrade_canopy','upgrade_roof_tile')):bpy.data.objects.remove(o,do_unlink=True)
  dark=material('furnace_interior',(.035,.025,.023));iron=material('dark_iron',(.10,.12,.15));rune=material('molten_rune',(1,.34,.025),3)
  x=-3.1
  box('grand_furnace_plinth',(x,.55,.15),(4.8,2.85,.35),stone)
  box('grand_furnace_back',(x,1.2,1.65),(3.2,.7,2.8),stone)
  box('deep_dark_hearth',(x,.74,1.15),(2.2,.25,1.6),dark)
  for side in [-1,1]:
   box('massive_furnace_side',(x+side*1.48,.55,1.25),(.72,1.9,2.2),stone)
   for z in [.4,1.05,1.7,2.35]:
    box('buttress_stone',(x+side*1.95,.8,z),(.6,1.35,.58),stone)
   box('buttress_metal_cap',(x+side*1.95,.8,2.72),(.77,1.5,.18),brass)
  # Individual stone arch segments, open mouth and recessed glowing fuel bed.
  for j in range(11):
   theta=math.pi*j/10
   o=box('great_arch_keystone',(x+1.28*math.cos(theta),-.28,1.05+1.28*math.sin(theta)),(.42,.8,.6),stone);o.rotation_euler.y=math.pi/2-theta
   if j%2==0:
    r=box('arch_inlaid_rune',(x+1.28*math.cos(theta),-.705,1.05+1.28*math.sin(theta)),(.10,.035,.20),rune);r.rotation_euler.y=math.pi/2-theta
  box('iron_hearth_lip',(x,-.28,.39),(2.7,1.2,.19),iron)
  for j in range(10):
   bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.19,location=(x-.95+j*.21,.05,.62));bpy.context.object.data.materials.append(fire)
  # Twin high stone flues with metal reinforcement and open cap silhouettes.
  for side in [-1,1]:
   cx=x+side*.88
   for z in [2.65,3.25,3.85,4.45]:box('tall_flue_stone',(cx,1.0,z),(.93,.85,.56),stone)
   for z in [2.95,4.15]:box('flue_iron_band',(cx,1.0,z),(1.05,.97,.14),iron)
   for dx,dy,sx,sy in [(-.5,0,.18,1.1),(.5,0,.18,1.1),(0,-.46,.85,.18),(0,.46,.85,.18)]:box('open_chimney_crown',(cx+dx,1.0+dy,4.85),(sx,sy,.27),brass)
  box('central_crest_pedestal',(x,.75,3.0),(1.2,.55,.65),iron)
  bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.42,depth=.13,location=(x,.39,3.05),rotation=(math.pi/2,0,0));bpy.context.object.data.materials.append(brass)
  for side in [-1,1]:box('crest_rune',(x+side*.12,.30,3.05),(.055,.045,.36),rune)
  bpy.ops.object.light_add(type='POINT',location=(x,-.25,1.1));bpy.context.object.data.energy=120;bpy.context.object.data.color=(1,.26,.035);bpy.context.object.data.shadow_soft_size=.5
  # Upgrade becomes a heavy runic work altar, with no sun canopy.
  cool=material('upgrade_rune',(.12,.6,1),2)
  ux=3.1
  for side in [-1,1]:
   for z in [.5,1.25,2.0,2.75]:box('upgrade_stone_pylon',(ux+side*1.45,.65,z),(.7,.8,.68),stone)
   box('upgrade_pylon_cap',(ux+side*1.45,.65,3.16),(.9,1.0,.18),brass)
   for z in [1.3,2.0,2.7]:box('pylon_lit_inlay',(ux+side*1.45,.225,z),(.13,.04,.32),cool)
  box('upgrade_altar_base',(ux,.05,.43),(2.3,1.25,.8),stone)
  box('upgrade_altar_top',(ux,.05,.91),(2.6,1.45,.18),iron)
  for j in range(7):
   theta=math.pi*j/6
   o=box('upgrade_arch',(ux+1.4*math.cos(theta),.65,2.1+1.0*math.sin(theta)),(.82,.65,.52),stone);o.rotation_euler.y=math.pi/2-theta
 cam=s.camera;cam.location=(8,-15,12);cam.rotation_euler=(Vector((0,-.15,1.6 if level==3 else .9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=16.5
 s.cycles.samples=16;s.cycles.use_denoising=True;s.cycles.max_bounces=3;s.render.threads_mode='FIXED';s.render.threads=4;s.render.resolution_x=1280;s.render.resolution_y=840;s.render.resolution_percentage=100
 # The plane must stay large enough to catch all contact shadows.
 s.render.filepath=str(OUT/f'blacksmith_level_{level}.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'blacksmith_level_{level}.blend'));bpy.ops.render.render(write_still=True)
 reports.append({'level':level,'proposal_only':True,'unlocks': ['refine'] if level==1 else ['refine','upgrade'],'npc_height_m':1.8,'camera_ortho_scale':16.5,'growth':'L3 monumental furnace, reinforced stone flues and runic altar; NPC scale fixed'})
(OUT/'proposal.json').write_text(json.dumps(reports,indent=2)+'\n')
