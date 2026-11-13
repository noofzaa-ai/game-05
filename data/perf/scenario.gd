extends RefCounted
## Fixed synthetic workload. No account, database, grants or persistence.
const Wire=preload("res://logic/net_wire.gd")
const Inputs=preload("res://logic/sim_input.gd")
var rules
var camp
var profile
var run
var map
var sim
var tick_us: Array=[]
var meta: Dictionary
func _init():
 rules=load("res://logic/item_rules_loader.gd").load_default()
 camp=load("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
 var rng:=RandomNumberGenerator.new();rng.seed=2662026
 profile=load("res://logic/profile.gd").new_player(rules,camp,rng);profile.name="PERF SYNTHETIC"
 map=load("res://logic/map_loader.gd").load_by_id("goblin_arena_c")
 var world=load("res://logic/sim_world.gd").new();world.half_width=map.half_width;world.half_depth=map.half_depth
 for solid in map.solids:world.add_solid(solid.box)
 sim=load("res://logic/game_sim.gd").new(world,load("res://logic/combat_data_loader.gd").load_default(),rng)
 sim.add_player(1,Vector3(0,0,0));run=load("res://logic/run.gd").start(profile,camp)
 sim.attach_run(1,run,rules,load("res://logic/loot_data_loader.gd").load_default(camp.materials.keys(),rules.tiers.size()))
 sim.fighters[1].stats.HP=100000;sim.fighters[1].hp=100000
 var index:=100
 for spawn in map.enemy_spawns:
  if index>=108:break
  sim.add_enemy(index,spawn.position,spawn.type,1);sim.fighters[index].stats.HP=100000;sim.fighters[index].hp=100000;index+=1
 meta={"scene_loading":false,"scene_waiting":[],"content_name":"PERF LAB","stage_count":1,"party":{},"boss_intro":{},"status":"playing","end_reason":"","map":map.id,"stage":1,"current":{},"state":"in_stage","choices":[],"treasure_pending":false,"path":[],"players":[1],"profiles":{1:profile.to_dict()},"run":run.to_dict(false),"connected":{1:true},"cloud_saved":false,"command_id":0}
static func input_at(tick: int):
 var input=Inputs.new();input.aim=Vector2(0,-1);input.aim_distance=3
 var phase: int=(tick/180)%4
 if phase==1:input.move=Vector2(1 if tick%180<90 else -1,0)
 elif phase==2:input.light=tick%12==0
 elif phase==3:
  if tick%180<6:input.skill_slot=0
  elif tick%180>=45 and tick%180<51:input.skill_slot=1
  elif tick%180>=90 and tick%180<96:input.skill_slot=2
  elif tick%180>=135 and tick%180<141:input.skill_slot=3
 return input
func advance(frame=null):
 var started:=Time.get_ticks_usec()
 sim.set_input(1,input_at(sim.tick_count) if frame==null else frame);sim.tick();tick_us.append(Time.get_ticks_usec()-started)
func state() -> Dictionary:
 var entities: Dictionary={}
 for id in sim.bodies:
  var body: Array=[];var fighter: Array=[]
  for field in Wire.BODY_FIELDS:body.append(sim.bodies[id].get(field))
  for field in Wire.FIGHTER_FIELDS:fighter.append(Wire.fighter_value(sim.fighters[id],field))
  entities[id]=[body,fighter]
 meta.profiles={1:profile.to_dict()};meta.run=run.to_dict(false)
 return {"tick":sim.tick_count,"epoch":1,"entities":entities,"projectiles":sim.projectiles.duplicate(true),"areas":sim.areas.duplicate(true),"meta":meta}
