"""Native assembly preview: separate Refine/Upgrade stations using prepared FBX parts."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'art_source/props/camp_modular/review';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art_source/props/camp_modular/blacksmith/blacksmith_assembled.blend'))
source=[o for o in bpy.context.scene.objects if o.type=='MESH'];station_objects={}
for kind,shift in [('refine',-3.1),('upgrade',3.1)]:
 keep={o.name for o in source} if kind=='refine' else {'front_workbench','anvil_station','tool_rack','supply_crates'}
 parts=[]
 for o in source:
  if o.name not in keep:continue
  p=o.copy();p.data=o.data;bpy.context.collection.objects.link(p);p.name=kind+'_'+o.name;p.location.x+=shift;parts.append(p)
 station_objects[kind]=parts
for o in source:bpy.data.objects.remove(o,do_unlink=True)
# Each station gets the actual game blacksmith model, scaled uniformly to a readable 1.8m.
for kind,shift in [('refine',-3.1),('upgrade',3.1)]:
 before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(ROOT/'art/npcs/blacksmith.glb'));new=set(bpy.context.scene.objects)-before
 bpy.context.view_layer.update();meshes=[o for o in new if o.type=='MESH'];pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);scale=1.8/(hi.z-lo.z)
 bpy.ops.object.empty_add(type='PLAIN_AXES');parent=bpy.context.object;parent.name=kind+'_npc_preview'
 for o in new:
  if o.parent not in new:o.parent=parent
 parent.scale=(scale,scale,scale);parent.location=(shift-(lo.x+hi.x)*.5*scale,-2.9-(lo.y+hi.y)*.5*scale,.02-lo.z*scale)
# Neutral stage, no fake item aura; small warm/cool practical light distinguishes workshop purpose.
def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1);return m
# Clean continuous floor under fused-source slab; Upgrade gets its own clean foundation/canopy.
stone=mat('workshop_stone',(.24,.26,.29));wood=mat('workshop_timber',(.26,.13,.065));blue=mat('upgrade_slate_roof',(.10,.17,.29));gold=mat('upgrade_brass',(.68,.39,.09))
def cube(name,loc,scale,material,kind):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material);bevel=o.modifiers.new('small_edge_bevel','BEVEL');bevel.width=.035;bevel.segments=1;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=bevel.name);station_objects[kind].append(o);return o
for kind,x in [('refine',-3.1),('upgrade',3.1)]:
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=2.25,depth=.14,location=(x,-.2,-.015));o=bpy.context.object;o.name=kind+'_continuous_foundation';o.scale.y=.88;o.data.materials.append(stone);station_objects[kind].append(o)
x=3.1
for px in [-1.45,1.45]:
 for y in [.85,-.1]:cube('upgrade_canopy_post',(x+px,y,1.0),(.15,.15,1.95),wood,'upgrade')
cube('upgrade_canopy_crossbeam',(x,.85,1.95),(3.35,.19,.19),wood,'upgrade')
for j in range(6):
 for side in [-1,1]:
  o=cube('upgrade_roof_tile',(x-1.4+j*.56,.4+side*.38,2.04),(.55,.84,.11),blue,'upgrade');o.rotation_euler.x=side*.22
cube('upgrade_worktable',(x,.05,.82),(1.6,.75,.16),wood,'upgrade')
for dx in [-.63,.63]:cube('upgrade_table_leg',(x+dx,.05,.43),(.15,.5,.8),wood,'upgrade')
bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.28,depth=.08,location=(x,.02,.95));o=bpy.context.object;o.name='upgrade_inlay_workplate';o.data.materials.append(gold);station_objects['upgrade'].append(o)
floor=mat('neutral_stage',(.045,.075,.08))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.035));bpy.context.object.data.materials.append(floor)
for kind,x,color in [('refine',-3.1,(1,.45,.12)),('upgrade',3.1,(.4,.75,1))]:
 bpy.ops.object.text_add(location=(x,-3.8,.02));o=bpy.context.object;o.name=kind+'_label';o.data.body=kind.upper();o.data.align_x='CENTER';o.data.size=.38;o.data.extrude=0;o.data.materials.append(mat(kind+'_label_material',color))
 bpy.ops.object.light_add(type='POINT',location=(x,0,1.1));bpy.context.object.data.color=color;bpy.context.object.data.energy=25;bpy.context.object.data.shadow_soft_size=.6
for loc,power,size in [((0,-6,10),1500,8),((-6,1,7),1100,7),((7,4,8),1700,6)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(7,-13,10));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=12.5
s=bpy.context.scene;s.camera=cam;s.world=bpy.data.worlds.new('World');s.world.color=(.2,.2,.2);s.render.engine='CYCLES';s.cycles.samples=24;s.render.resolution_x=1800;s.render.resolution_y=1050;s.render.resolution_percentage=100
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blacksmith_stations_review.blend'))
s.render.filepath=str(OUT/'blacksmith_stations_comparison.png');bpy.ops.render.render(write_still=True)
# Draft assemblies export only props, no duplicate NPCs/cameras/lights/text.
out=ROOT/'art/props/camp_modular/blacksmith'
for kind,parts in station_objects.items():
 bpy.ops.object.select_all(action='DESELECT')
 for o in parts:o.location.x-= -3.1 if kind=='refine' else 3.1;o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(out/(kind+'_station.glb')),export_format='GLB',use_selection=True,export_animations=False,export_extras=True,export_lights=False,export_cameras=False)
# Shared texture extraction uses the same names as prepared kit.
import struct,sys
sys.path.insert(0,str(Path(__file__).parent));from build_orc_kit import glb_external_image
for kind in station_objects:
 path=out/(kind+'_station.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);mapping={}
 for img in doc.get('images',[]):mapping[Path(img['name']).stem]='blacksmith_'+img['name']+'.png'
 glb_external_image(str(path),mapping)
