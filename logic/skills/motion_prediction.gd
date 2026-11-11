extends RefCounted
## Owner-only phase/locomotion prediction. Uses the authority's cast and fixed-step runtime.
## First migrated behavior: blink. No hit, projectile, target status or visual side effects.
const Build=preload("res://logic/skill_build.gd")
class MotionRuntime:
 extends ZorxSkillRuntime
 func _release(data:Dictionary)->void:
  if data.skill.behavior=="blink":super._release(data)
 func _area_hit(_point:Vector3,_radius:float,_damage:float,_statuses:Array,_context:Dictionary)->void:pass
 func _area_damage(_point:Vector3,_radius:float,_damage:float,_context:Dictionary)->void:pass
 func _hit(_target:ZorxSkillTarget,_damage:float,_context:Dictionary)->void:pass
 func _spawn_visual(_skill:ZorxSkillData,_point:Vector3,_radius:float)->void:pass
 func _advance_projectiles(_dt:float)->void:pass
 func _advance_constructs(_dt:float)->void:pass
 func _advance_zones(_dt:float)->void:pass
 func _advance_passives(_dt:float)->void:pass
var system
var runtime:MotionRuntime
var id:int
var _sim_ref:WeakRef
var sim:
 get:return _sim_ref.get_ref() if _sim_ref!=null else null
var supported_casts:=0
func setup(simulation,owner:int,build:Dictionary,view:Dictionary)->void:
 _sim_ref=weakref(simulation);id=owner
 system=preload("res://logic/skills/system.gd").new();system.setup(sim)
 for target_id in sim.fighters:
  var target=ZorxSkillTarget.new();target.entity_id=target_id
  target.position=sim.bodies[target_id].position;target.hp=sim.fighters[target_id].hp;target.max_hp=sim.fighters[target_id].max_hp()
  system.targets[target_id]=target
 runtime=MotionRuntime.new();runtime.owner_id=id
 runtime.pattern={"katana":"fast","dagger":"fast","spear":"mid","hammer":"heavy","bow":"ranged","staff":"ranged"}.get(build.start,"mid")
 var actor=ZorxSkillActor.new();actor.base_max_hp=sim.fighters[id].max_hp();actor.max_hp=actor.base_max_hp;actor.hp=sim.fighters[id].hp;actor.position=sim.bodies[id].position
 runtime.bind_actor(actor);runtime.visuals_enabled=false
 runtime.configure_passives(Build.basic_stats(build))
 runtime.clock=float(view.get("clock",0));runtime.cast_pose=view.get("pose",{}).duplicate(true)
 var capsule:Dictionary=view.get("motion",{})
 runtime.cast_until=float(capsule.get("cast_until",runtime.clock))
 for slot in view.get("slots",[]):runtime.cooldowns[slot.skill]=runtime.clock+float(slot.left)
 system.casters[id]=runtime;system.builds[id]=build.duplicate(true)
 for target_id in system.targets:
  if sim.fighters[target_id].team!=sim.fighters[id].team:runtime.targets.append(system.targets[target_id])
 for plan in capsule.get("blink_jobs",[]):
  var stats=Build.calculate(build,int(plan.slot))
  stats["pattern"]=runtime.pattern
  var skill=load(Build.ROOT+"skills/"+str(plan.skill)+".tres")
  runtime.jobs.append({"time":plan.time,"kind":"release","data":{"skill":skill,"stats":stats,"origin":plan.origin,"point":plan.point,"aim":plan.aim,"dir":plan.dir,"pulse":plan.pulse}})
func before_tick()->void:
 runtime.actor.position=sim.bodies[id].position;runtime.actor.hp=sim.fighters[id].hp
 runtime.obstacles.assign(sim.world.solids)
 runtime.movement_bounds=AABB(Vector3(-sim.world.half_width,-1000,-sim.world.half_depth),Vector3(sim.world.half_width*2,2000,sim.world.half_depth*2))
 if runtime.actor.hp<=0:runtime._cancel_on_death()
func cast(slot:int,input)->void:
 if slot<0 or slot>3:return
 var row:Dictionary=system.builds[id].skills[slot]
 var skill=load(Build.ROOT+"skills/"+str(row.skill)+".tres")
 if skill.behavior!="blink":return # Other behaviors remain authority-only until parity-tested.
 var direction:Vector2=input.aim.normalized() if input.aim!=Vector2.ZERO else Vector2(sim.fighters[id].direction).normalized()
 var aim:Vector3=sim.bodies[id].position+Vector3(direction.x,0,direction.y)*input.aim_distance
 if system.cast(id,slot,aim).is_empty():supported_casts+=1
func advance()->void:
 var fighter=sim.fighters[id]
 fighter.gauge=0 # Authority publish_views disables the retired ultimate gauge.
 runtime.actor.position=sim.bodies[id].position
 runtime.advance(1.0/60.0)
 sim.bodies[id].position=runtime.actor.position
 var view:Dictionary=fighter.skill_view.duplicate(true)
 view["clock"]=runtime.clock;view["pose"]=runtime.cast_pose.duplicate(true);view["casting"]=runtime.is_casting()
 for slot in view.get("slots",[]):slot["left"]=maxf(0,float(runtime.cooldowns.get(slot.skill,0))-runtime.clock)
 fighter.skill_view=view
static func capsule(caster,build:Dictionary)->Dictionary:
 var plans:Array=[]
 for job in caster.jobs:
  if job.kind!="release" or job.data.skill.behavior!="blink":continue
  var slot:=-1
  for i in build.skills.size():
   if build.skills[i].skill==job.data.skill.id:slot=i;break
  if slot<0:continue
  var data:Dictionary=job.data
  plans.append({"slot":slot,"skill":data.skill.id,"time":job.time,"origin":data.origin,"point":data.point,"aim":data.aim,"dir":data.dir,"pulse":data.get("pulse",0)})
 return {"cast_until":caster.cast_until,"blink_jobs":plans}
