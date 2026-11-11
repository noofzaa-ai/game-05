"""Three Mummy pyramid scenes: shared kit + generated art and matching per-scene map JSON.
Blender -b --factory-startup -P tools/blender/build_mummy_stage.py
Godot X=east,Y=up,Z=south; source conversion P(x,y,z)=(x,-z,y).
"""
import bpy,bmesh,math,random,json,sys,struct
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'art/maps/mummy_tomb';SOURCE=ROOT/'art_source/maps/mummy_tomb';KIT=ROOT/'art/props/mummy_tomb'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path(__file__).parent));from build_orc_kit import glb_external_image
P=lambda x,y,z:Vector((x,-z,y))
def mat(name,color,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=.92
 if emission:b.inputs['Emission Color'].default_value=(*color,1);b.inputs['Emission Strength'].default_value=emission
 return m
def begin(stage):
 global rng,originals,parts,art,placements,solids,lights,sand,stone,lightstone,darkstone,blue,cavity,gold,glow
 rng=random.Random(2102+stage)
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(KIT/'mummy_kit.glb'))
 originals={o.name:o for o in bpy.context.scene.objects if o.type=='MESH'}
 parts=json.loads((KIT/'mummy_kit.json').read_text())['parts']
 if set(originals)!=set(parts):raise RuntimeError('Kit names differ')
 art=[];placements=[];solids=[{'center':[0,-.2,0],'size':[28,.4,22],'material':'ink'}];lights=0
 sand=mat('gf_mummy_sand',(.49,.36,.23));stone=mat('gf_mummy_stone',(.57,.46,.32));lightstone=mat('gf_mummy_light_stone',(.68,.57,.41));darkstone=mat('gf_mummy_shadow_stone',(.32,.25,.17));blue=mat('gf_mummy_blue',(.025,.095,.11));cavity=mat('gf_mummy_cavity',(.028,.020,.013));gold=mat('gf_mummy_gold',(.54,.34,.10));glow=mat('gf_mummy_glow',(.22,.62,.67),.6)
def block(name,x,y,z,w,h,d,material=None,bevel=0):
 if material is None:material=stone
 bpy.ops.mesh.primitive_cube_add(size=1,location=P(x,y,z));o=bpy.context.object;o.name=name;o.dimensions=(w,d,h);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('Worn stone edges','BEVEL');mod.width=bevel;mod.segments=1
  bpy.ops.object.modifier_apply(modifier=mod.name)
 art.append(o);return o
def empty(name,x,y,z):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=P(x,y,z);return o
def prop(kind,x,z,y=0,yaw=0,scale=1,cover=None):
 global lights
 if cover is None:cover=(y<.1 and abs(x)<13.85 and abs(z)<10.85 and kind!="stairs")
 o=originals[kind].copy();o.data=originals[kind].data; o.name=kind+'_'+str(len(placements));bpy.context.collection.objects.link(o)
 o.location=P(x,y,z);o.rotation_euler.z=math.radians(yaw);o.scale=(scale,)*3;art.append(o)
 placements.append({'part':kind,'position':[x,y,z],'yaw':yaw,'scale':scale,'solid':cover})
 if cover:
  size=parts[kind]['size_blender'];w,h,d=size[0]*scale,size[2]*scale,size[1]*scale
  # Conservative inscribed box, hidden by the prop's geometry; never collide on all decoration.
  if abs(yaw)%180>45:w,d=d,w
  solids.append({'center':[x,y+h*.46,z],'size':[w*.62,h*.86,d*.62],'material':'ink'})
 if kind in ['torch','brazier'] and lights<6:
  empty('light_fire_'+str(lights),x,y+parts[kind]['height_m']*scale*.9,z);lights+=1
 return o
def pyramid(name,x,z,width,height,y=0,material=None):
 if material is None:material=stone
 verts=[P(x-width/2,y,z-width/2),P(x+width/2,y,z-width/2),P(x+width/2,y,z+width/2),P(x-width/2,y,z+width/2),P(x,y+height,z)]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[(4,1,0),(4,2,1),(4,3,2),(4,0,3),(0,1,2,3)]);mesh.materials.append(material)
 o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);art.append(o)
 return o

def exterior():
 # Sand shelf with open-fight paved courtyard (28 x22m). Boundaries belong to JSON, not guessed meshes.
 block('Desert shelf',0,-.22,-1,400,.38,400,sand)
 for ix in range(14):
  for iz in range(11):
   x=-13+ix*2;z=-10+iz*2
   material=lightstone if ix in [6,7] else stone
   block('Courtyard slab',x,-.015+rng.uniform(-.004,.004),z,1.94,.075,1.94,material,.025)
 # Teal/gold inlaid edge, softly weathered not saturated.
 for x in [-13.45,13.45]:
  block('Inlay border',x,.033,0,.10,.012,21.4,blue)
  for z in range(-9,11,2):block('Border gold key',x,.044,z,.36,.014,.13,gold)
 for z in [-10.5,10.5]:block('End inlay',0,.033,z,26.9,.012,.10,blue)
 # Low perimeter walls and columns, deliberately outside combat bounds.
 for sign in [-1,1]:
  for z in [-9,-5,-1,3,7]:
   block('Outer low wall',sign*15.1,.60,z,1.0,1.2,3.9,stone,.06)
  for z in [-10.3,-2,6.5]:
   prop('pillar',sign*15.1,z,scale=1.0)
  for x in [sign*9,sign*12]:
   block('Entry wall',x,.46,12,2.8,.9,1.2,stone,.05)
  prop('obelisk',sign*5.8,11.8,scale=1.05)
  prop('brazier',sign*7.1,10.9,scale=.95)
 # North sanctuary, framing two exits while leaving exit landings unobstructed.
 block('Temple podium',0,.55,-15,16,1.1,7,lightstone,.10)
 for x in [-2.1,-1.05,0,1.05,2.1]:prop('stairs',x,-11.5,scale=1.0)
 for sign in [-1,1]:
  x=sign*5.4
  tower=block('Temple pylon',x,4.05,-15,3.2,5.9,3.5,stone,.08)
  for v in tower.data.vertices:
   if v.co.z>0:v.co.x*=.77;v.co.y*=.84
  tower.data.update()
  block('Pylon blue panel',x,3.7,-13.20,.83,3.0,.07,blue)
  for h in [2.5,3.2,3.9,4.6]:
   block('Pylon carved key',x,h,-13.14,.59,.11,.07,gold)
   block('Pylon glyph stem',x+sign*.17,h+.19,-13.14,.1,.34,.07,gold)
  block('Pylon crown',x,6.95,-15,3.0,.25,3.3,lightstone,.06)
  prop('coffin',sign*8.0,-14.0,y=1.1,scale=1.0)
  prop('torch',sign*10.1,-13.6,y=0,scale=1.0)
  prop('anubis_urn',sign*5.4,-13.1,y=5.6,scale=.8)
 block('Temple lintel',0,6.0,-15,8,1.0,2.4,lightstone,.09)
 block('Dark inner door',0,3.0,-16.35,5.2,4.0,.12,cavity)
 for z in [-14.5,-15.6]:
  for x in [-1.4,0,1.4]:block('Sanctuary tile',x,1.14,z,1.3,.08,1,lightstone,.025)
 prop('altar',0,-14.0,y=1.2,scale=1.2)
 # Ribbed side buttresses and broken floor-side memorials.
 for sign in [-1,1]:
  for z in [-7,0,7]:
   prop('wall_panel',sign*16.1,z,yaw=sign*90,scale=1.2)
  for z in [-7.5,5.5]:prop('anubis_urn',sign*12.0,z,scale=.9)
 # Six distinct cover groups leave a broad central/south-north route.
 prop('obelisk',-7,1.8,cover=True)
 prop('pillar',7,-1.6,scale=.72,cover=True)
 prop('altar',-7.8,-5.2,yaw=-12,cover=True)
 prop('chest',8.1,5.5,yaw=12,cover=True)
 prop('coffin',-10,6,scale=.82,yaw=15,cover=True)
 for i,(x,z) in enumerate([(10,-6.4),(10.7,-5.6),(9.6,-5.6)]):prop('urn',x,z,scale=1.0 if i==0 else .75,cover=i==0)
 # Scattered fragments hug the edges; kept out of the fight lane.
 for i in range(24):
  sign=-1 if i%2 else 1;x=sign*rng.uniform(11.5,14);z=rng.uniform(-9.5,9)
  o=block('Stone fragment',x,.08,z,rng.uniform(.18,.55),rng.uniform(.08,.18),rng.uniform(.2,.6),lightstone,.02);o.rotation_euler.z=rng.uniform(0,math.tau)
 # Sand dunes outside arena, low-poly contours, no collision or hidden gameplay.
 for i in range(14):
  sign=-1 if i%2 else 1;x=sign*rng.uniform(19,27);z=rng.uniform(-22,20)
  bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=P(x,-.75,z));o=bpy.context.object;o.name='Desert dune';o.scale=(rng.uniform(4,7),rng.uniform(5,8),rng.uniform(1.4,2.2));o.data.materials.append(sand);art.append(o)
 # Central seal is purely inlaid floor art.
 for i in range(16):
  a=i*math.tau/16;x=math.sin(a)*1.9;z=-1+math.cos(a)*1.9
  o=block('Sun seal inlay',x,.045,z,.16,.015,.52,blue);o.rotation_euler.z=-a
 block('Sun seal centre',0,.045,-1,.8,.016,.8,gold,.08)

 # True square pyramid behind the entrance, far outside play bounds.
 pyramid('Great Pyramid',0,-37,38,22)
 for h in range(2,22,2):
  width=38*(1-h/22)
  block('Pyramid stone course',0,h,-37,width+.04,.055,width+.04,darkstone)
 pyramid('Pyramid gilded cap',0,-37,3.45,2.0,y=20,material=gold)

def room_floor(top=False):
 block('Interior subfloor',0,-.24,0,33,.42,27,darkstone)
 for ix in range(14):
  for iz in range(11):
   material=lightstone if ix in [6,7] else stone
   if not top:material=stone if ix in [6,7] else darkstone
   block('Chamber slab',-13+ix*2,-.015+rng.uniform(-.003,.003),-10+iz*2,1.95,.075,1.95,material,.02)
 for x in [-13.4,13.4]:
  block('Floor edging',x,.04,0,.12,.02,21.4,gold)
  for z in range(-10,11,2):block('Floor edge glyph',x,.055,z,.45,.02,.18,blue)
 # North and side walls are cut away at the south for gameplay camera readability.
 for sign in [-1,1]:
  for z in [-9,-5,-1,3,7]:
   block('Chamber wall',sign*14.6,2.4,z,1.1,4.8,3.95,stone,.04)
   block('Wall blue course',sign*13.99,1.2,z,.045,.32,3.8,blue)
   block('Wall gold course',sign*13.95,1.41,z,.045,.055,3.85,gold)
  block('Roof cutaway cornice',sign*14.5,4.92,-1,1.5,.25,22,lightstone,.04)
  block('Near cutaway wall',sign*10,.55,11.8,7.5,1.1,1.0,stone,.03)
 for x in [-10.8,-5.4,5.4,10.8]:
  block('Back chamber wall',x,2.6,-12.1,5.3,5.2,1.2,stone,.04)
 block('Back wall crown',0,5.28,-12.1,28,.25,1.5,lightstone,.04)
 for sign in [-1,1]:
  for z in [-8,0,7]:prop('wall_panel',sign*13.8,z,yaw=sign*90,scale=1.3)


def interior():
 room_floor()
 # Four support columns form aisles and cover, not a narrow corridor.
 for x in [-6.5,6.5]:
  for z in [-3.8,3.8]:
   prop('pillar',x,z,scale=1.15,cover=True)
   block('Column cap',x,4.22,z,1.55,.23,1.4,lightstone,.025)
 for sign in [-1,1]:
  for z in [-7.8,-2.5,3,7.8]:prop('coffin',sign*12.2,z,yaw=sign*90,scale=.88)
  for z in [-6,6]:prop('brazier',sign*9.3,z,scale=1)
  for z in [-9.5,9.5]:prop('anubis_urn',sign*11.8,z,scale=.9)
  prop('chest',sign*10.4,8.5,yaw=sign*10,scale=.85)
 # Ascending doorway is scenery beyond northern play edge; each scene uses local floor zero.
 block('Ascending passage darkness',0,2.55,-13.8,4.4,5.1,.1,cavity)
 for x in [-1.55,-.52,.52,1.55]:prop('stairs',x,-11.8,scale=1.0)
 for sign in [-1,1]:
  x=sign*3.1
  prop('obelisk',x,-11.9,scale=1.5)
  block('Guard statue plinth',sign*6.1,.55,-11.6,1.7,1.1,1.5,lightstone,.04)
  prop('anubis_urn',sign*6.1,-11.6,y=1.1,scale=1.25)
 block('Ascending door lintel',0,5.05,-12.8,7.8,.55,1.4,lightstone,.04)
 for z in [-8,-4,0,4,8]:
  block('Aisle gold waymark',0,.045,z,.18,.015,.75,gold)
 for i in range(18):
  x=rng.choice([-1,1])*rng.uniform(10.4,13.2);z=rng.uniform(-9.6,9.6)
  o=block('Interior rubble',x,.06,z,rng.uniform(.2,.5),.1,rng.uniform(.2,.6),stone,.015);o.rotation_euler.z=rng.random()*math.tau


def summit():
 room_floor(top=True)
 # Open roof outline under the pyramid apex: the roof is intentionally absent over combat.
 def roof_section(name,width,base,height,material):
  verts=[P(x,y,z) for z in [-12.0,-13.6] for x,y in [(-width/2,base),(width/2,base),(0,base+height)]]
  mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]);mesh.materials.append(material)
  bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
  o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);art.append(o)
 roof_section('Cutaway pyramid apex',28,5.4,5.4,lightstone)
 roof_section('Gilded apex cap',3.0,10.22,.58,gold)
 block('Royal back wall',0,2.6,-12.1,5.3,5.2,1.2,stone,.04)
 block('Royal blue backdrop',0,2.9,-11.44,3.3,4.0,.07,blue)
 bpy.ops.mesh.primitive_circle_add(vertices=16,radius=.86,fill_type='NGON',location=P(0,7.6,-11.95),rotation=(math.pi/2,0,0))
 sun=bpy.context.object;sun.name='Winged solar disk';sun.data.materials.append(gold);art.append(sun)
 for sign in [-1,1]:
  for level in range(4):block('Winged solar crest',sign*(2.0+level*.32),7.8-level*.24,-11.94,2.1-level*.28,.14,.055,gold)

 for sign in [-1,1]:
  x=sign*5.8
  prop('pillar',x,-10.6,scale=1.35)
  block('Upper chamber blue panel',sign*10.5,3,-11.43,2.4,3.4,.08,blue)
  for i in range(5):
   block('Upper chamber gold glyph',sign*10.5,1.8+i*.56,-11.35,1.6,.13,.07,gold)
   block('Upper chamber glyph stem',sign*10.5+sign*.55,2+i*.56,-11.35,.12,.35,.07,gold)
  for z in [-3.4,4.2]:prop('obelisk',sign*8.2,z,scale=.95,cover=True)
  for z in [-7,7.2]:prop('brazier',sign*11,z,scale=1.15)
  for z in [-8,0,8]:prop('anubis_urn',sign*12.5,z,scale=1.15)
  prop('coffin',sign*12.8,-5.1,yaw=sign*90,scale=1.1)
 # Royal sarcophagus on a small inscribed dais, with clear exits on either side.
 block('Royal dais lower',0,.20,-7.2,5.7,.4,3.2,lightstone,.05)
 block('Royal dais gold course',0,.44,-7.2,5.4,.1,3.0,gold,.03)
 block('Royal dais top',0,.53,-7.2,5.1,.08,2.8,lightstone,.03)
 solids.append({'center':[0,.27,-7.2],'size':[5.0,.54,2.75],'material':'ink'})
 prop('coffin',0,-7.4,y=.58,scale=1.3)
 prop('altar',0,-4.4,scale=.9,cover=True)
 prop('chest',-11.5,7.8,scale=.9)
 # Bright, concentric solar floor pattern makes this chamber read as the destination.
 for radius,count in [(3.3,16),(4.2,24)]:
  for i in range(count):
   a=i*math.tau/count;x=math.sin(a)*radius;z=.7+math.cos(a)*radius
   o=block('Royal solar inlay',x,.048,z,.16,.018,.48,gold if radius>4 else blue);o.rotation_euler.z=-a
 block('Royal sun diamond',0,.05,.7,1.1,.02,1.1,glow,.04).rotation_euler.z=math.pi/4
 # Roof-edge sunbeams are geometry accents outside the walk bounds, not particle effects.
 for x in [-11.8,11.8]:
  block('Upper clerestory',x,5.5,-8,1.0,1.1,.5,blue,.02)
  block('Upper sun window',x,5.5,-7.72,.6,.72,.04,glow)


def finish(map_id,stage,name,mood):
 spawn=[0,.05,8.4];exits=[[-4.5,.05,-8.7],[4.5,.05,-8.7]]
 if stage==3:exits=[[-5.5,.05,-8.7],[5.5,.05,-8.7]]
 enemies=[[-3.4,.05,3.0],[3.4,.05,1.5],[-3.2,.05,-3.0],[3.8,.05,-5.0]]
 empty('spawn',*spawn)
 for i,point in enumerate(enemies):empty('enemy_'+str(i),*point)
 for i,point in enumerate(exits):
  empty('exit_portal_'+str(i),*point)
  for dx in [-.7,0,.7]:block('Exit landing',point[0]+dx,.05,point[2],.64,.07,1.4,lightstone,.03)
 for obj in originals.values():bpy.data.objects.remove(obj,do_unlink=True)
 bpy.ops.object.select_all(action='DESELECT')
 for o in art:o.select_set(True)
 bpy.context.view_layer.objects.active=art[0];bpy.ops.object.join();joined=bpy.context.object;joined.name='MummyTombGeometry'
 joined.data.calc_loop_triangles();tri=len(joined.data.loop_triangles)
 mapdata={'version':1,'id':map_id,'name':name,'_design':'Generated by tools/blender/build_mummy_stage.py. Ordered scene2 presentation: exterior -> interior -> summit. 28x22m each,cutaway roofs/near walls for gameplay camera. Separate draft,not linked to existing Journey/index/world map.4Mummy draft spots;shared1024/512 kit textures. Decorative chests are not reward chests. Local floor0 in all three maps.','modes':['pve'],'kind':'fight','camera_style':'top_down','atmosphere':'ink','art_mood':mood,'art_scene':'res://art/maps/mummy_tomb/'+map_id+'.glb','bounds':{'half_width':14,'half_depth':11},'spawn':spawn,'exit_portals':exits,'solids':solids,'enemy_spawns':[{'type':'mummy','level':1,'position':p} for p in enemies],'props':[],'camera_zones':[]}
 (ROOT/'data/maps'/str(map_id+'.json')).write_text(json.dumps(mapdata,indent=2)+'\n')
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(map_id+'.blend')))
 path=OUT/(map_id+'.glb');bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_animations=False,export_extras=True,export_lights=False,export_cameras=False)
 data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+length]);mapping={}
 for image in doc.get('images',[]):
  image_name=image.get('name','');role='normal' if 'normal' in image_name else 'mr' if any(t in image_name for t in ['mr','metallic','roughness']) else 'albedo'
  mapping[Path(image_name).stem]='../../props/mummy_tomb/mummy_kit_'+role+'.png'
 glb_external_image(str(path),mapping)
 layout={'version':2,'stage':stage,'name':name,'triangles':tri,'kit_instances':len(placements),'render_objects':1,'render_surfaces':sum(len(m['primitives']) for m in doc['meshes']),'placements':placements,'shared_textures':'../../props/mummy_tomb/','map':'res://data/maps/'+map_id+'.json','state':'scene2 ordered draft;runtime route integration pending'}
 (OUT/(map_id+'.layout.json')).write_text(json.dumps(layout,indent=2)+'\n')
 if stage==1:(OUT/'layout.json').write_text(json.dumps(layout,indent=2)+'\n')
 print('MUMMY_STAGE',json.dumps({'map':map_id,'triangles':tri,'kit_instances':len(placements),'glb_bytes':path.stat().st_size,'solids':len(solids)}),flush=True)


STAGES=[('mummy_arena_a',exterior,'Mummy — Pyramid Approach','camp'),('mummy_arena_b',interior,'Mummy — Inner Burial Hall','night'),('mummy_arena_c',summit,'Mummy — Apex Solar Chamber','camp')]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for number,(map_id,build,name,mood) in enumerate(STAGES,1):
 if args and map_id not in args:continue
 begin(number);build();finish(map_id,number,name,mood)
(OUT/'route.json').write_text(json.dumps({'version':1,'id':'mummy_ascent','state':'presentation order only;not consumed by Journey runtime','maps':[{'order':i+1,'map':s[0],'name':s[2],'next':STAGES[i+1][0] if i+1<len(STAGES) else None} for i,s in enumerate(STAGES)]},indent=2)+'\n')
