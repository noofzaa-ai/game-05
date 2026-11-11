extends RefCounted
## Disposable sandbox. No Run, loot, wear, profile commands or save path exists here.
const Sim=preload("res://logic/game_sim.gd")
const Inputs=preload("res://logic/sim_input.gd")
const Fighter=preload("res://logic/fighter.gd")
const Build=preload("res://logic/skill_build.gd")
const CENTER:=Vector3(-18,0,4)
const REGION:=Rect2(-25,-2,14,13)
const DUMMY_IDS:=[901,902,903,904,905]
var sim
var enabled:=false
var damage:=0.0
var hits:=0
var hits_by_target:Dictionary={}
var _stats: Dictionary
var _style:String
var _build:Dictionary
var _relics:Dictionary={}

static func contains(at:Vector3)->bool:return REGION.has_point(Vector2(at.x,at.z))
static func dummy_position(index:int)->Vector3:return CENTER+Vector3((index-2)*2.1,0,-3)

func _init(world,combat,spawn:Vector3)->void:
 sim=Sim.new(world,combat)
 sim.add_player(1,spawn);sim.bodies[1].grounded=true
 for index in DUMMY_IDS.size():
  var id:int=DUMMY_IDS[index]
  sim.add_player(id,dummy_position(index),{"HP":1000000000,"DEF":0},"fists")
  sim.fighters[id].team="training_dummy";sim.bodies[id].grounded=true
  sim.fighters[id].max_poise=1000000000;sim.fighters[id].poise=1000000000

func configure(stats:Dictionary,style:String,build:Dictionary,relics:Dictionary={})->void:
 _relics=relics.duplicate(true)
 _stats=stats.duplicate(true);_style=style;_build=build.duplicate(true)
 sim.fighters[1].stats=sim.combat.full_stats(_stats);sim.fighters[1].style=_style
 reset()

func reset()->void:
 preload("res://logic/relic_effects.gd").attach_loadout(sim.fighters[1],_relics)
 damage=0;hits=0;hits_by_target.clear()
 sim.projectiles.clear();sim.areas.clear();sim._ranged={"projectiles":[],"areas":[],"next_id":1}
 if sim.skill_system!=null:sim.skill_system.dispose()
 sim.skill_system=null
 for id in sim.fighters:
  var fighter=sim.fighters[id]
  fighter.state=Fighter.State.IDLE;fighter.move_id="";fighter.move_frame=0
  fighter.buffered="";fighter.cooldowns.clear();fighter.effects.clear();fighter.hitstop=0
  fighter.hp=fighter.max_hp();fighter.energy=fighter.max_energy();fighter.skill_view={}
  fighter.skill_hit_filter=Callable();fighter.skill_base_hit=Callable()
  sim.bodies[id].velocity=Vector3.ZERO;sim.bodies[id].knockback=Vector2.ZERO
 if enabled and Build.validate(_build).is_empty():
  sim.skill_system=preload("res://logic/training_skill_system.gd").new();sim.skill_system.setup(sim);sim.skill_system.attach(1,_build)

func step(input)->void:
 var inside:=contains(sim.bodies[1].position)
 if inside!=enabled:enabled=inside;reset()
 var accepted=input
 if not enabled or _style=="fists":
  accepted=Inputs.new();accepted.move=input.move;accepted.run=input.run
 sim.set_input(1,accepted);sim.tick()
 _keep_camp_floor()
 for event in sim.events:
  if int(event.get("target",-1)) in DUMMY_IDS and event.type in ["hit","skill_hit","skill_dot","dot"]:
   damage+=float(event.get("damage",0));hits+=1
   hits_by_target[int(event.target)]=int(hits_by_target.get(int(event.target),0))+1
 for index in DUMMY_IDS.size():
  var id:int=DUMMY_IDS[index];var fighter=sim.fighters[id]
  sim.bodies[id].position=dummy_position(index);sim.bodies[id].velocity=Vector3.ZERO;sim.bodies[id].knockback=Vector2.ZERO
  fighter.hp=fighter.max_hp()
  if sim.skill_system!=null and sim.skill_system.targets.has(id):sim.skill_system.targets[id].hp=fighter.hp


func _keep_camp_floor()->void:
 # Camp/training is a continuous flat floor at Y=0, unlike dungeon ledges.
 # Skill motion writes actor positions after Movement; resolve a crossed floor
 # before rendering, including a player recovered from the previous bad state.
 var body=sim.bodies[1]
 if not body.position.is_finite():body.position=CENTER;body.velocity=Vector3.ZERO
 if body.position.y<0:
  body.position.y=0;body.velocity.y=maxf(0,body.velocity.y);body.grounded=true
  if sim.skill_system!=null:
   if sim.skill_system.casters.has(1):sim.skill_system.casters[1].actor.position=body.position
   if sim.skill_system.targets.has(1):sim.skill_system.targets[1].position=body.position

func dispose()->void:
 if sim!=null and sim.skill_system!=null:sim.skill_system.dispose();sim.skill_system=null
