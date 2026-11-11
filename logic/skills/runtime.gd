class_name ZorxSkillRuntime
extends ZorxSkillCaster

signal behavior_event(skill_id: String, kind: String)
var movement_bounds := AABB(Vector3(-10000,-10000,-10000),Vector3(20000,20000,20000))
var owner_id := 0
var cast_pose: Dictionary = {}
var visual_serial := 0
var construct_serial: int = 0
var actor: ZorxSkillActor
var pattern: String = "mid"
var active_id: String = "fire_ring"
var cooldowns: Dictionary = {}
var jobs: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var constructs: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var movements: Array[Dictionary] = []
var parry: Dictionary = {}
var second_dash: Dictionary = {}
var obstacles: Array[AABB] = []
var last_skill: ZorxSkillData
var total_hits: int = 0
var blast_budgets: Dictionary = {}
var blast_serial: int = 0
var buff_visuals: Array[Dictionary] = []
var passive_context: Dictionary = {}
var proc_seen: Dictionary = {}
var blood_heals: Array[Dictionary] = []
var dodge_ready: float = 0
var dodge_state: Dictionary = {}
var crit_rng:=RandomNumberGenerator.new()

func configure_passives(stats: Dictionary) -> void:
 passive_context=stats
 if actor!=null:actor.configure_passives(stats.get("player_passives",{}))

func connect_target(target: ZorxSkillTarget) -> void:
 super.connect_target(target)
 target.status_applied.connect(_on_status_applied)


func bind_actor(value: ZorxSkillActor) -> void:
 if is_instance_valid(actor):
  if actor.died.is_connected(_cancel_on_death): actor.died.disconnect(_cancel_on_death)
  if actor.parried.is_connected(_counter): actor.parried.disconnect(_counter)
  if actor.shield_broken.is_connected(_shield_break): actor.shield_broken.disconnect(_shield_break)
 actor=value
 actor.died.connect(_cancel_on_death)
 if not actor.parried.is_connected(_counter): actor.parried.connect(_counter)
 if not actor.shield_broken.is_connected(_shield_break): actor.shield_broken.connect(_shield_break)

func _cancel_on_death() -> void:
 # Independent effects already released keep their lifetime; unreleased casts do not.
 pending = pending.filter(func(e: Dictionary)->bool:return e.get("started",false))
 jobs = jobs.filter(func(j: Dictionary)->bool:
  return not j["kind"] in ["melee","parry_end"] and not (j["kind"]=="release" and int(j["data"].get("pulse",0))==0))
 cast_until=clock
 movements.clear()
 second_dash.clear()
 parry.clear()
 if actor!=null:
  actor.invulnerable=false
  actor.parry_left=0
  actor.buffs.clear()
  actor.shield=0

func target_preview(skill: ZorxSkillData, stats: Dictionary, origin: Vector3, aim: Vector3) -> Dictionary:
 if skill.behavior=="chain" or (skill.behavior=="strike" and pattern in ["fast","ranged"]):
  var range_m:=16.0 if skill.behavior=="strike" and pattern=="ranged" else float(stats["range"])
  var candidates:=_in_radius(origin,range_m)
  if skill.behavior=="chain": candidates=candidates.filter(func(t: ZorxSkillTarget)->bool:return has_line_of_sight(origin,t.position))
  if skill.behavior=="strike": candidates=candidates.filter(func(t: ZorxSkillTarget)->bool:return t.statuses.has("shock"))
  var chosen:=_nearest(aim,candidates)
  if chosen==null: return {"error":"ไม่มีเป้าสายฟ้าที่มองเห็น · ไม่เสียคูลดาวน์"} if skill.behavior=="chain" else {}
  return {"target":chosen,"distance":origin.distance_to(chosen.position),"range":range_m,"error":""}
 if skill.behavior!="blood": return {}
 var target:=_nearest(aim,targets)
 if target==null: return {"error":"ไม่มีเป้าหมาย · ไม่เสียคูลดาวน์"}
 var distance:=origin.distance_to(target.position)
 var valid:=distance<=float(stats["range"])+.000001
 return {"target":target,"distance":distance,"range":float(stats["range"]),"error":"" if valid else "เป้าหมายอยู่นอกระยะ · ไม่เสียคูลดาวน์"}

func select_skill(id: String) -> void:
 active_id=id
 ready_at=float(cooldowns.get(id,0))

func request_cast(skill: ZorxSkillData, stats: Dictionary, origin: Vector3, aim: Vector3) -> String:
 if stats.has("error"): return str(stats["error"])
 if actor!=null and actor.hp<=0: return "ผู้ร่ายตายแล้ว"
 if is_casting(): return "กำลังร่าย"
 select_skill(skill.id)
 if skill.behavior=="storm" and not second_dash.is_empty() and clock<=float(second_dash.get("until",-1)):
  var follow: Dictionary=second_dash.duplicate(true)
  second_dash.clear()
  follow["origin"]=origin
  follow["aim"]=aim
  follow["dir"]=_direction(origin,aim)
  follow["point"]=origin
  follow["followup"]=true
  follow["stats"]["damage"]=8.0*float(follow["stats"].get("damage_factor",1))
  _schedule(clock,"release",follow)
  return ""
 if remaining_cooldown()>0.000001: return "กำลังคูลดาวน์"
 if skill.behavior=="consume_burn" and _in_radius(origin,float(stats["range"])).filter(func(t: ZorxSkillTarget)->bool:return t.statuses.has("burn")).is_empty():
  return "ไม่มีศัตรูติดไฟ · ไม่เสียคูลดาวน์"
 var preview:=target_preview(skill,stats,origin,aim)
 if not str(preview.get("error","")).is_empty(): return preview["error"]
 configure_passives(stats)
 var s:=stats.duplicate(true)
 s["pattern"]=pattern
 s["intrinsic"]=skill.built_in_statuses[0] if not skill.built_in_statuses.is_empty() else ""
 s["damage_factor"]=float(s["damage"])/maxf(.00001,float(s["base_damage"])) if float(s["base_damage"])>0 else 1.0
 if actor!=null:
  s["damage"]*=actor.multiplier("buff_damage_mul")
  s["stun_build"]*=actor.multiplier("buff_stun_mul")
 if float(s["base_damage"])>0: s["damage_factor"]=float(s["damage"])/float(s["base_damage"])
 var direction:=_direction(origin,aim)
 var point:=origin
 if s["origin"]=="target": point=origin+direction*minf(origin.distance_to(aim),float(s["target_range"]))
 if skill.behavior=="blink":
  var destination:=origin+direction*minf(origin.distance_to(aim),float(s["blink_range"]))
  if _blocked(destination): return "จุดวาร์ปอยู่ในสิ่งกีดขวาง"
 blast_serial+=1
 s["origin_cast_id"]=blast_serial
 if skill.behavior in ["area","consume_burn","fireball","trap"]:
  s["explosion_cast"]=blast_serial
 if skill.id=="fire_ring":
  var error:=super.request_cast(skill,s,origin,aim)
  if error.is_empty(): cooldowns[skill.id]=ready_at
  return error
 var duration:=float(s["cast_time"])
 if skill.behavior=="slam" and pattern=="fast": duration=.3*(duration/.6)
 cast_until=clock+duration
 ready_at=cast_until+float(s["cooldown"])
 cooldowns[skill.id]=ready_at
 last_skill=skill
 _schedule(cast_until,"release",{"skill":skill,"stats":s,"origin":origin,"point":point,"aim":aim,"dir":direction,"pulse":0,"locked_target":preview.get("target")})
 return ""

func _schedule(time: float, kind: String, data: Dictionary) -> void:
 jobs.append({"time":time,"kind":kind,"data":data})
 jobs.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a["time"])<float(b["time"]))

func advance(delta: float) -> void:
 var remaining:=maxf(0,delta)
 if remaining==0: _step(0)
 while remaining>0.0000001:
  var dt:=minf(remaining,1.0/120.0)
  _step(dt)
  remaining-=dt

func _step(dt: float) -> void:
 super.advance(dt)
 for key in blast_budgets.keys():
  if clock-float(blast_budgets[key]["last"])>60: blast_budgets.erase(key)
 if not second_dash.is_empty() and clock>float(second_dash.get("until",0)): second_dash.clear()
 if actor!=null: actor.advance(dt)
 for i in range(buff_visuals.size()-1,-1,-1):
  var entry: Dictionary=buff_visuals[i]
  if actor==null or not actor.buffs.any(func(b: Dictionary)->bool:return b["id"]==entry["id"]):
   buff_visuals.remove_at(i)
 while not jobs.is_empty() and float(jobs[0]["time"])<=clock+.000001:
  var job: Dictionary=jobs.pop_front()
  var d: Dictionary=job["data"]
  match job["kind"]:
   "release": _release(d)
   "shot": _launch(d)
   "melee": _melee(d)
   "parry_end":
    if not parry.is_empty() and parry.get("token")==d.get("token"):
     var fallback:=parry.duplicate(true)
     parry.clear()
     if actor!=null: actor.parry_left=0
     _melee(fallback)
     _queue_parry_echo(fallback)
   "chain": _chain_hit(d)
 _advance_movement(dt)
 _advance_projectiles(dt)
 _advance_constructs(dt)
 _advance_zones(dt)
 _advance_passives(dt)

func _release(d: Dictionary) -> void:
 var skill: ZorxSkillData=d["skill"]
 var s: Dictionary=d["stats"]
 var kind:=skill.behavior
 var pulse:=int(d.get("pulse",0))
 if actor!=null and actor.hp<=0 and kind in ["storm","blink","shield","armor","parry","cry"]: return
 var damage:=float(s["damage"])*(float(s["repeat_damage_mul"]) if pulse>0 else 1.0)
 var context:=s.duplicate(true)
 context["stun_build"]*=float(s["repeat_damage_mul"]) if pulse>0 else 1.0
 d=d.duplicate(true)
 d["amount"]=damage
 d["context"]=context
 if pulse==0 and int(s["repeat"])>1 and not kind in ["trap","totem","trail","wall","parry"]:
  var repeated:=d.duplicate(true)
  repeated["pulse"]=1
  if kind=="storm": repeated["aim"]=d["origin"]
  if kind=="blink": repeated["point"]=d["origin"]+d["dir"]*minf(d["origin"].distance_to(d["aim"]),float(s["blink_range"]))
  _schedule(clock+float(s["repeat_delay"]),"release",repeated)
 behavior_event.emit(skill.id,kind)
 match kind:
  "blood":
   var target: ZorxSkillTarget=d.get("locked_target")
   if is_instance_valid(target) and not target.dead and target in _in_radius(d["origin"],float(s["range"])):
    var bonus:=target.consume("bleed")*float(s["consume_mul"])
    if actor!=null: actor.position=_safe_destination(actor.position,target.position-_direction(actor.position,target.position)*.5)
    _hit(target,damage+bonus*(float(s["repeat_damage_mul"]) if pulse>0 else 1),context)
    _spawn_visual(skill,target.position,.6)
  "consume_burn":
   var eligible:=_in_radius(d["origin"],float(s["range"])).filter(func(t: ZorxSkillTarget)->bool:return t.statuses.has("burn"))
   if eligible.is_empty() and pulse==0:
    cooldowns[skill.id]=clock
    if active_id==skill.id: ready_at=clock
   var bursts: Array[Dictionary]=[]
   for target: ZorxSkillTarget in eligible:
    bursts.append({"point":target.position,"bonus":target.consume("burn")*float(s["consume_mul"])})
   for burst in bursts:
    _area_damage(burst["point"],float(s["radius"]),damage+float(burst["bonus"])*(float(s["repeat_damage_mul"]) if pulse>0 else 1),context)
    _spawn_visual(skill,burst["point"],float(s["radius"]))
  "fireball","lance","piercing","chain": _launch(d)
  "storm","trail": _dash(d)
  "trap","wall","totem":
   if pulse==0: _place(d)
  "shield":
   if actor!=null:
    actor.hp*=1.0-float(s["hp_cost"])
    actor.shield=actor.max_hp*float(s["shield_pct"])
    actor.add_buff("shield",float(s["duration"]),context)
    _buff_visual(skill,"shield")
  "armor":
   if actor!=null:
    actor.add_buff("armor",float(s["duration"]),context)
    _buff_visual(skill,"armor")
  "shatter":
   if s["pattern"]=="ranged":
    d["shot_behavior"]="shatter"
    d["stats"]["range"]=12.0
    _launch(d)
   elif s["pattern"]=="fast":
    for i in range(3):
     var hit:=d.duplicate(true)
     hit["amount"]=9.0*float(s["damage_factor"])*(float(s["repeat_damage_mul"]) if pulse>0 else 1)
     hit["consume_final"]=i==2
     _schedule(clock+i*.1,"melee",hit)
   else: _melee(d)
  "strike": _strike(d)
  "blink":
   var start: Vector3=actor.position if actor!=null else d["origin"]
   var end: Vector3=start+d["dir"]*minf(start.distance_to(d["aim"]),float(s["blink_range"]))
   if pulse==0:
    _area_damage(start,float(s["radius"]),damage,context)
    _spawn_visual(skill,start,float(s["radius"]))
    if actor!=null: actor.position=end
    d["point"]=end
   else: end=d["point"]
   _area_damage(end,float(s["radius"]),damage,context)
   _spawn_visual(skill,end,float(s["radius"]))
  "slam": _melee(d)
  "parry":
   if pulse>0: _melee(d)
   else:
    var window:=float(s["parry_window"])
    if s["pattern"]=="fast": window*=.35/.5
    if s["pattern"]=="heavy": window*=.7/.5
    parry=d.duplicate(true)
    parry["token"]=clock
    if actor!=null: actor.parry_left=window
    _schedule(clock+window,"parry_end",parry.duplicate(true))
    _spawn_visual(skill,d["origin"],.7)
  "cry":
   _area_damage(d["point"],float(s["radius"]),0,context)
   _spawn_visual(skill,d["point"],float(s["radius"]))
   if actor!=null: actor.add_buff("cry",float(s["duration"]),context)
   _buff_visual(skill,"cry")
 released.emit(d.get("point",d["origin"]),damage,pulse)

func _hit(target: ZorxSkillTarget, damage: float, context: Dictionary) -> void:
 if target.dead: return
 var was_bleeding:=target.statuses.has("bleed")
 var critical: bool=damage>0 and (bool(context.get("force_critical",false)) or (target.statuses.has("freeze") and "frozen_crit" in context.get("events",[])) or crit_rng.randf()<float(context.get("crit_chance",0)))
 if critical:damage*=float(context.get("crit_multiplier",1.5))
 var hit_context:=context.duplicate(true)
 hit_context["critical"]=critical
 if damage>0 and "all_hits_burn" in context.get("events",[]):
  if not "burn" in hit_context.get("statuses",[]):hit_context["statuses"]=hit_context.get("statuses",[])+["burn"]
 if damage>0 and context.has("explosion_cast"):
  var vulnerability:=target._vulnerability()
  damage=_blast_allowance(int(context["explosion_cast"]),target.entity_id,damage*vulnerability)/vulnerability
  if damage<=.000001: return
 total_hits+=1
 var actual:=target.receive_hit(damage,hit_context.get("statuses",[]),hit_context)
 if actual>0 and was_bleeding and "blood_leech" in context.get("events",[]) and actor!=null:
  blood_heals=blood_heals.filter(func(e: Dictionary)->bool:return clock-float(e["at"])<1)
  var used: float=0
  for entry in blood_heals:used+=float(entry["amount"])
  var healing:=minf(actor.max_hp*.01,maxf(0,actor.max_hp*.03-used))
  actor.heal(healing);blood_heals.append({"at":clock,"amount":healing})
 if float(context.get("root_time",0))>0: target.statuses["root"]={"left":context["root_time"]}
 if float(context.get("knockback",0))>0 and not target.dead:
  var from: Vector3=actor.position if actor!=null else Vector3.ZERO
  target.position=_safe_destination(target.position,target.position+_direction(from,target.position)*float(context["knockback"]))
 if float(context.get("leech",0))>0:
  var before: float=actor.hp if actor!=null else 0
  healed.emit(actual*float(context["leech"]))
  if actor!=null and actor.hp>before:_gem_visual("leech",actor.position,.45)

func _on_target_died(target: ZorxSkillTarget, context: Dictionary) -> void:
 if int(context.get("owner_id",0)) != owner_id:return
 _passive_death(target,context)
 if not bool(context.get("burning",false)) or not "burn_death_explosion" in context.get("events",[]):return
 var source_id:=int(context.get("origin_cast_id",0))
 if source_id==0:
  blast_serial+=1
  source_id=blast_serial
 explosion.emit(target.global_position)
 _spawn_visual(load("res://data/skill_system/skills/fire_ring.tres"),target.global_position,2)
 _area_damage(target.global_position,2,15*float(context.get("equipment_scale",1)),{"hit_height":2.5,"owner_id":owner_id,"origin_cast_id":source_id,"explosion_cast":-source_id})

func _blast_allowance(cast_id: int, target_id: int, amount: float) -> float:
 if not blast_budgets.has(cast_id): blast_budgets[cast_id]={"last":clock,"targets":{}}
 var budget: Dictionary=blast_budgets[cast_id]
 budget["last"]=clock
 if not budget["targets"].has(target_id): budget["targets"][target_id]={"max":0.0,"sum":0.0}
 var entry: Dictionary=budget["targets"][target_id]
 entry["max"]=maxf(float(entry["max"]),amount)
 var allowed:=minf(amount,maxf(0,1.5*float(entry["max"])-float(entry["sum"])))
 entry["sum"]+=allowed
 return allowed

func _area_hit(point: Vector3, radius: float, damage: float, _status_ids: Array, context: Dictionary) -> void:
 _area_damage(point,radius,damage,context)

func has_line_of_sight(start: Vector3,end: Vector3) -> bool:
 var a:=start+Vector3.UP*.65
 var b:=end+Vector3.UP*.65
 for box in obstacles:
  if box.intersects_segment(a,b)!=null: return false
 for entity in constructs:
  if entity["kind"]!="wall": continue
  var direction: Vector3=entity["dir"]
  var basis:=Basis(Vector3(direction.z,0,-direction.x),Vector3.UP,direction)
  var half:=float(entity["stats"]["wall_length"])*float(entity["stats"]["radius"])*.5+.15
  var bounds:=AABB(Vector3(-half,0,-.2),Vector3(half*2,2,.4))
  if bounds.intersects_segment(basis.transposed()*(a-entity["position"]),basis.transposed()*(b-entity["position"]))!=null: return false
 return true

func _area_damage(point: Vector3, radius: float, damage: float, context: Dictionary) -> void:
 for target in _in_radius(point,radius): _hit(target,damage,context)

func _in_radius(point: Vector3, radius: float) -> Array[ZorxSkillTarget]:
 var result: Array[ZorxSkillTarget]=[]
 for target in targets:
  if is_instance_valid(target) and not target.dead and absf(target.position.y-point.y)<=2.5 and Vector2(target.position.x-point.x,target.position.z-point.z).length()<=radius+.000001: result.append(target)
 return result

func _nearest(point: Vector3, candidates: Array) -> ZorxSkillTarget:
 var best: ZorxSkillTarget
 var distance:=INF
 for target: ZorxSkillTarget in candidates:
  if is_instance_valid(target) and not target.dead:
   var length:=point.distance_squared_to(target.position)
   if length<distance: best=target;distance=length
 return best

func _direction(a: Vector3,b: Vector3) -> Vector3:
 var v:=b-a
 v.y=0
 return v.normalized() if v.length_squared()>.000001 else Vector3.RIGHT

func _melee(d: Dictionary) -> void:
 var s: Dictionary=d["stats"]
 var skill: ZorxSkillData=d["skill"]
 var origin: Vector3=d["point"] if s["origin"]=="target" else d["origin"]
 var radius:=float(s["radius"])
 var context: Dictionary=d["context"].duplicate(true)
 var damage:=float(d["amount"])
 var kind:=skill.behavior
 var style: String=s["pattern"]
 var candidates: Array[ZorxSkillTarget]=[]
 if kind=="slam":
  if style=="fast": radius*=2.5/3.0;context["stun_build"]*=45.0/60
  if style=="heavy": context["stun_build"]*=80.0/60
  if style=="ranged": origin=d["origin"]+d["dir"]*6.0;radius*=2.5/3.0
  if style=="mid": candidates=_line_targets(origin,origin+d["dir"]*5.0,1.5*radius/3.0,true)
  else: candidates=_in_radius(origin,radius)
 elif kind=="shatter":
  if style=="heavy": candidates=_in_radius(origin,radius)
  elif style=="mid": candidates=_line_targets(origin,origin+d["dir"]*4.0,.45,false)
  else: candidates=_line_targets(origin,origin+d["dir"]*float(s["range"]),radius*.5,false)
 elif kind=="parry":
  if style=="mid": candidates=_line_targets(origin,origin+d["dir"]*4.0,.5,false)
  elif style=="heavy": candidates=_in_radius(origin+d["dir"],2)
  elif style=="ranged":
   if actor!=null and not d.get("echo_attack",false): actor.position=_safe_destination(actor.position,actor.position-d["dir"]*3)
   var shot:=d.duplicate(true)
   shot["origin"]=d["origin"] if d.get("echo_attack",false) else (actor.position if actor!=null else origin-d["dir"]*3)
   shot["shot_behavior"]="parry"
   shot["stats"]["range"]=12.0
   _launch(shot)
   return
  else: candidates=_line_targets(origin,origin+d["dir"]*3,.6,false)
 for target in candidates:
  if kind=="shatter": _shatter_hit(target,damage,d,bool(d.get("consume_final",true)))
  elif kind=="parry": _hit(target,damage*(float(s["vs_stunned_mul"]) if target.statuses.has("stun") else 1),context)
  else: _hit(target,damage,context)
 _spawn_visual(skill,origin,maxf(.5,radius))

func _shatter_hit(target: ZorxSkillTarget, amount: float, d: Dictionary, final: bool) -> void:
 var s: Dictionary=d["stats"]
 var frozen:=target.statuses.has("freeze")
 var damage:=amount
 if frozen and final:
  target.consume("freeze")
  damage*=float(s["frozen_mul"])
 elif not frozen: damage*=1+float(s["chill_bonus_per_stack"])*int(target.statuses.get("chill",{}).get("stacks",0))
 var hit_context: Dictionary=d["context"].duplicate(true)
 if frozen and "frozen_crit" in hit_context.get("events",[]):hit_context["force_critical"]=true
 _hit(target,damage,hit_context)
 if frozen and final:
  for nearby in _in_radius(target.position,float(s["shard_radius"])*float(s["radius"])/2.5):
   if nearby==target: continue
   for i in range(3 if "chill" in s["gem_ids"] else 2): nearby.apply_status("chill",d["context"])
  _spawn_visual(d["skill"],target.position,float(s["shard_radius"]))

func _strike(d: Dictionary) -> void:
 var s: Dictionary=d["stats"]
 var style: String=s["pattern"]
 var range_m:=16.0 if style=="ranged" else float(s["range"])
 var shocked:=_in_radius(d["origin"],range_m).filter(func(t: ZorxSkillTarget)->bool:return t.statuses.has("shock"))
 var target:=_nearest(d["aim"],shocked)
 var point: Vector3=d["origin"]+_direction(d["origin"],d["aim"])*minf(d["origin"].distance_to(d["aim"]),range_m)
 var radius:=float(s["radius"])
 if style=="mid": point=d["origin"]+d["dir"]*3;radius*=2
 if style=="heavy": point=d["origin"];radius*=3
 if target!=null and not style in ["mid","heavy"]: point=target.position
 var ctx: Dictionary=d["context"]
 if style=="fast":
  var bonus:=target!=null
  if target!=null: target.consume("shock")
  for i in range(3):
   var strike:=d.duplicate(true)
   strike["point"]=point
   strike["amount"]=float(d["amount"])/25.0*10*(2 if bonus else 1)
   strike["context"]=ctx
   _schedule(clock+i*.12,"chain",{"area":true,"point":point,"radius":radius,"amount":strike["amount"],"context":ctx,"skill":d["skill"]})
 else:
  for victim in _in_radius(point,radius):
   var bonus:=victim.consume("shock")>0
   _hit(victim,float(d["amount"])*(.8 if style=="heavy" else 1)*(float(s["shocked_mul"]) if bonus else 1),ctx)
  _spawn_visual(d["skill"],point,radius)

func _counter(source: ZorxSkillTarget) -> void:
 if parry.is_empty(): return
 var d:=parry.duplicate(true)
 parry.clear()
 var s: Dictionary=d["stats"]
 if actor!=null: d["origin"]=actor.position
 if is_instance_valid(source): d["dir"]=_direction(d["origin"],source.position);d["aim"]=source.position
 d["amount"]*=float(s["counter_mul"])
 if s["pattern"]=="fast":
  cooldowns["riposte"]=clock+float(s["cooldown"])*.5
  if active_id=="riposte": ready_at=cooldowns["riposte"]
 _melee(d)
 _queue_parry_echo(d)

func _queue_parry_echo(d: Dictionary) -> void:
 if int(d["stats"]["repeat"])<=1: return
 var echo:=d.duplicate(true)
 echo["amount"]*=float(d["stats"]["repeat_damage_mul"])
 echo["context"]["stun_build"]*=float(d["stats"]["repeat_damage_mul"])
 echo["echo_attack"]=true
 if actor!=null and d["stats"]["pattern"]=="ranged": echo["origin"]=actor.position
 _schedule(clock+float(d["stats"]["repeat_delay"]),"melee",echo)

func _shield_break(context: Dictionary) -> void:
 if actor==null: return
 var c:=context.duplicate(true)
 c["statuses"]=["bleed"]
 c["intrinsic"]="bleed"
 c["status_stacks"]=2
 _area_damage(actor.position,float(context["break_radius"]),0,c)

func _line_targets(start: Vector3,end: Vector3,width: float,cone: bool=false) -> Array[ZorxSkillTarget]:
 var result: Array[ZorxSkillTarget]=[]
 for target in _in_radius(start,start.distance_to(end)+width):
  var along: float=(target.position-start).dot((end-start).normalized())
  if cone and (along<0 or along>start.distance_to(end)+.25): continue
  var nearest:=Geometry3D.get_closest_point_to_segment(target.position,start,end)
  var factor:=start.distance_to(nearest)/maxf(.01,start.distance_to(end)) if cone else 1.0
  if target.position.distance_to(nearest)<=width*maxf(.1,factor)+.25: result.append(target)
 result.sort_custom(func(a: ZorxSkillTarget,b: ZorxSkillTarget)->bool:return start.distance_squared_to(a.position)<start.distance_squared_to(b.position))
 return result

func _dash(d: Dictionary) -> void:
 var s: Dictionary=d["stats"]
 var kind: String=s["behavior"]
 var start: Vector3=actor.position if actor!=null else d["origin"]
 var distance:=float(s["dash_distance"])
 var direction: Vector3=d["dir"]
 if kind=="storm":
  if s["pattern"]=="mid": distance=7
  if s["pattern"]=="heavy": distance=3
  if s["pattern"]=="ranged": distance=5;direction=-direction
  if int(d.get("pulse",0))>0: direction=_direction(start,d["origin"])
 var end:=_safe_destination(start,start+direction*distance)
 movements.append({"start":start,"end":end,"born":clock,"duration":.25,"data":d,"hit":[],"invuln":kind=="storm"})
 if kind=="storm" and s["pattern"]=="fast" and int(d.get("pulse",0))==0 and not d.get("followup",false) and not second_dash.has("until"):
  second_dash=d.duplicate(true)
  second_dash["until"]=clock+.65
 if kind=="trail":
  var zone:=d.duplicate(true)
  zone["start"]=start
  zone["end"]=end
  zone["left"]=s["duration"]
  zone["tick"]=s["tick_interval"]
  zone["kind"]="trail"
  zone["born"]=clock
  zone["context"]["periodic"]=true  # ground ticks: no hit-stop / camera kick per tick
  zones.append(zone)
  _persistent_visual(zone,d["skill"],(start+end)*.5,Vector3(float(s["trail_width"])*float(s["radius"]),1,maxf(.1,start.distance_to(end)*.5)),direction)
  if int(s["repeat"])>1:
   var echo:=d.duplicate(true)
   echo["point"]=(start+end)*.5
   echo["amount"]=8.0*float(s["damage_factor"])*.5
   echo["start"]=start
   echo["end"]=end
   _schedule(clock+1,"chain",{"trail_echo":true,"data":echo})
 else: _spawn_visual(d["skill"],start,.7)

func _advance_movement(_dt: float) -> void:
 if actor!=null: actor.invulnerable=false
 for i in range(movements.size()-1,-1,-1):
  var movement: Dictionary=movements[i]
  var fraction:=clampf((clock-float(movement["born"]))/float(movement["duration"]),0,1)
  var position: Vector3=movement["start"].lerp(movement["end"],fraction)
  if actor!=null: actor.position=position;actor.invulnerable=movement["invuln"]
  var d: Dictionary=movement["data"]
  var s: Dictionary=d["stats"]
  if s["behavior"]=="storm" and s["pattern"]!="ranged":
   for target in _line_targets(movement["start"],position,.45):
    if target.entity_id in movement["hit"]: continue
    movement["hit"].append(target.entity_id)
    _hit(target,d["amount"],d["context"])
  if fraction>=1:
   if s["behavior"]=="storm" and s["pattern"]=="heavy": _area_damage(position,2,15.0*float(s["damage_factor"]),d["context"])
   if s["behavior"]=="storm" and s["pattern"]=="ranged":
    var shot:=d.duplicate(true)
    shot["origin"]=position
    shot["amount"]=6.0*float(s["damage_factor"])
    shot["stats"]["projectile_count"]=3
    shot["stats"]["range"]=15
    shot["shot_behavior"]="storm"
    _launch(shot)
   movements.remove_at(i)
   if actor!=null: actor.invulnerable=false

func _launch(d: Dictionary) -> void:
 var s: Dictionary=d["stats"]
 if s["behavior"]=="chain":
  var target:=_nearest(d["aim"],_in_radius(d["origin"],float(s["range"])).filter(func(t: ZorxSkillTarget)->bool:return has_line_of_sight(d["origin"],t.position)))
  var candidates:=_in_radius(d["origin"],float(s["range"])).filter(func(t: ZorxSkillTarget)->bool:return has_line_of_sight(d["origin"],t.position))
  for i in range(int(s["projectile_count"])):
   if target==null: break
   var chain:=d.duplicate(true)
   chain["target"]=target
   chain["hop_range"]=s["range"]
   chain["visited"]=[]
   chain["remaining"]=s["chain"]
   _schedule(clock+.06,"chain",chain)
   candidates.erase(target)
   target=_nearest(d["aim"],candidates)
  return
 var count:=int(s["projectile_count"])
 for i in range(count):
  var direction: Vector3=d["dir"].rotated(Vector3.UP,(float(i)-float(count-1)*.5)*.18)
  var p:=d.duplicate(true)
  p["position"]=d["origin"]
  p["direction"]=direction
  p["distance"]=0.0
  p["visited"]=[]
  p["pierces"]=int(s["pierce"])
  p["chains"]=int(s["chain"])
  p["hits"]=0
  p["speed"]=s["projectile_speed"]
  p["kind"]=d.get("shot_behavior",s["behavior"])
  p["born"]=clock
  visual_serial+=1
  p["visual_id"]=visual_serial
  p["visual"]=_projectile_visual(d["skill"],p["position"],direction)
  projectiles.append(p)

func _advance_projectiles(dt: float) -> void:
 for i in range(projectiles.size()-1,-1,-1):
  var p: Dictionary=projectiles[i]
  var s: Dictionary=p["stats"]
  var distance:=minf(float(p["speed"])*minf(dt,maxf(0,clock-float(p["born"]))),maxf(0,float(s["range"])-float(p["distance"])))
  var start: Vector3=p["position"]
  var end: Vector3=start+p["direction"]*distance
  var safe:=_safe_destination(start,end)
  var wall_hit:=safe.distance_to(end)>.001
  end=safe
  var remove:=wall_hit
  for target in _line_targets(start,end,.18):
   if target.entity_id in p["visited"]: continue
   p["visited"].append(target.entity_id)
   var amount:=float(p["amount"])
   if p["kind"]=="piercing": amount*=maxf(float(s["min_falloff"]),pow(float(s["pierce_falloff"]),int(p["hits"])))
   if p["kind"]=="parry" and target.statuses.has("stun"): amount*=float(s["vs_stunned_mul"])
   if p["kind"]=="fireball":
    _area_damage(target.position,float(s["radius"]),amount,p["context"])
    _spawn_visual(p["skill"],target.position,float(s["radius"]))
   elif p["kind"]=="shatter": _shatter_hit(target,amount,p,true)
   else: _hit(target,amount,p["context"])
   p["hits"]+=1
   if int(p["chains"])>0:
    var choices:=_in_radius(target.position,float(s.get("chain_range",5.0))).filter(func(t: ZorxSkillTarget)->bool:return not t.entity_id in p["visited"] and has_line_of_sight(target.position,t.position))
    var next:=_nearest(target.position,choices)
    if next!=null:
     p["chains"]-=1
     p["direction"]=_direction(target.position,next.position)
     end=_safe_destination(target.position,target.position+p["direction"]*.35)
     break
   if int(p["pierces"])<99:
    if int(p["pierces"])<=0: remove=true;end=target.position;break
    p["pierces"]-=1
  if wall_hit and p["kind"]=="fireball":
   _area_damage(end,float(s["radius"]),float(p["amount"]),p["context"])
   _spawn_visual(p["skill"],end,float(s["radius"]))
  p["distance"]+=start.distance_to(end)
  p["position"]=end
  if float(p["distance"])>=float(s["range"])-.00001: remove=true
  if remove:
   projectiles.remove_at(i)

func _chain_hit(d: Dictionary) -> void:
 if d.get("area",false):
  _area_damage(d["point"],d["radius"],d["amount"],d["context"])
  _spawn_visual(d["skill"],d["point"],d["radius"])
  return
 if d.get("trail_echo",false):
  var e: Dictionary=d["data"]
  for target in _line_targets(e["start"],e["end"],float(e["stats"]["trail_width"])*float(e["stats"]["radius"])*.5): _hit(target,e["amount"],e["context"])
  return
 var target: ZorxSkillTarget=d["target"]
 if not is_instance_valid(target) or target.dead: return
 var s: Dictionary=d["stats"]
 if not has_line_of_sight(d["origin"],target.position) or d["origin"].distance_to(target.position)>float(d.get("hop_range",s["chain_range"]))+.000001: return
 _hit(target,d["amount"],d["context"])
 _beam_visual(d["skill"],d["origin"],target.position)
 d["visited"].append(target.entity_id)
 if int(d["remaining"])>0:
  var candidates:=_in_radius(target.position,float(s["chain_range"])).filter(func(t: ZorxSkillTarget)->bool:return not t.entity_id in d["visited"] and has_line_of_sight(target.position,t.position))
  var next:=_nearest(target.position,candidates)
  if next!=null:
   d=d.duplicate(true)
   d["target"]=next
   d["origin"]=target.position
   d["hop_range"]=s["chain_range"]
   d["remaining"]-=1
   d["amount"]*=float(s["chain_falloff"])
   _schedule(clock+.07,"chain",d)

func _place(d: Dictionary) -> void:
 var s: Dictionary=d["stats"]
 var point: Vector3=d["origin"]+d["dir"]*minf(d["origin"].distance_to(d["aim"]),float(s["place_range"]))
 if s["behavior"]=="wall": point=d["origin"]+d["dir"]*float(s["place_distance"])
 var same:=constructs.filter(func(e: Dictionary)->bool:return e["kind"]==s["behavior"])
 while same.size()>=int(s.get("max_active",1)):
  var old: Dictionary=same.pop_front()
  _destroy_construct(old,false)
 var entity:=d.duplicate(true)
 construct_serial+=1
 entity["source_id"]=construct_serial
 entity["kind"]=s["behavior"]
 entity["position"]=point
 entity["left"]=s["duration"]
 entity["age"]=0.0
 entity["born"]=clock
 entity["tick"]=s.get("fire_interval",1.0)
 entity["hp"]=s.get("wall_hp",s.get("totem_hp",1.0))
 entity["triggered"]=false
 if entity["kind"]=="totem": entity["context"]["periodic"]=true  # auto-fire every interval: no hit-stop / camera kick
 var scale:=Vector3.ONE
 if entity["kind"]=="wall":
  scale=Vector3(float(s["wall_length"])*float(s["radius"])*.5,1,.2)
  var side: Vector3=Vector3(d["dir"].z,0,-d["dir"].x)*float(s["wall_length"])*float(s["radius"])*.5
  for target in _line_targets(point-side,point+side,.3): _hit(target,d["amount"],d["context"])
  if int(s["repeat"])>1: _schedule(clock+1,"chain",{"area":true,"point":point,"radius":float(s["wall_length"])*float(s["radius"])*.5,"amount":float(d["amount"])*.5,"context":d["context"],"skill":d["skill"]})
 elif entity["kind"]=="trap": scale=Vector3.ONE*.5
 _persistent_visual(entity,d["skill"],point,scale,d["dir"])
 constructs.append(entity)

func _advance_constructs(dt: float) -> void:
 for entity in constructs.duplicate():
  if not entity in constructs: continue
  var s: Dictionary=entity["stats"]
  entity["age"]=clock-float(entity["born"])
  entity["left"]=float(s["duration"])-float(entity["age"])
  if entity["kind"]=="trap" and not entity["triggered"] and float(entity["age"])>=float(s["arm_time"]):
   if not _in_radius(entity["position"],.5).is_empty():
    entity["triggered"]=true
    _area_damage(entity["position"],float(s["radius"]),entity["amount"],entity["context"])
    _spawn_visual(entity["skill"],entity["position"],float(s["radius"]))
    if int(s["repeat"])>1:
     _schedule(clock+1,"chain",{"area":true,"point":entity["position"],"radius":s["radius"],"amount":float(entity["amount"])*.5,"context":entity["context"],"skill":entity["skill"]})
    _destroy_construct(entity,false)
  elif entity["kind"]=="totem":
   entity["tick"]-=minf(dt,float(entity["age"]))
   if float(entity["tick"])<=.000001:
    entity["tick"]+=float(s["fire_interval"])
    var target:=_nearest(entity["position"],_in_radius(entity["position"],float(s["target_range"])))
    if target!=null:
     var shot: Dictionary=entity.duplicate(true)
     shot["origin"]=entity["position"]
     shot["dir"]=_direction(entity["position"],target.position)
     shot["aim"]=target.position
     shot["stats"]["range"]=s["target_range"]
     _launch(shot)
     if int(s["repeat"])>1:
      shot["amount"]*=.5
      _schedule(clock+1,"shot",shot)
  if float(entity["left"])<=.000001: _destroy_construct(entity,true)

func damage_construct(index: int, amount: float) -> void:
 if index<0 or index>=constructs.size(): return
 var e: Dictionary=constructs[index]
 e["hp"]-=amount
 if float(e["hp"])<=0: _destroy_construct(e,true)

func _destroy_construct(entity: Dictionary, burst: bool) -> void:
 if not entity in constructs: return
 constructs.erase(entity)
 var source_id: int=entity["source_id"]
 jobs=jobs.filter(func(j: Dictionary)->bool:return int(j["data"].get("source_id",-1))!=source_id)
 if burst and entity["kind"]=="wall":
  var c: Dictionary=entity["context"].duplicate(true)
  c["status_stacks"]=1
  _area_damage(entity["position"],float(entity["stats"]["wall_length"])*float(entity["stats"]["radius"])*.5,0,c)

func _advance_zones(dt: float) -> void:
 for i in range(zones.size()-1,-1,-1):
  var zone: Dictionary=zones[i]
  var s: Dictionary=zone["stats"]
  zone["left"]=float(s["duration"])-(clock-float(zone["born"]))
  zone["tick"]-=minf(dt,maxf(0,clock-float(zone["born"])))
  if float(zone["tick"])<=.000001:
   zone["tick"]+=float(s["tick_interval"])
   for target in _line_targets(zone["start"],zone["end"],float(s["trail_width"])*float(s["radius"])*.5):
    _hit(target,float(s["tick_damage"])*float(s["damage_factor"]),zone["context"])
  if float(zone["left"])<=.000001:
   zones.remove_at(i)

func _blocked(point: Vector3) -> bool:
 if not movement_bounds.has_point(point): return true
 for box in _boxes():
  if box.has_point(point+Vector3.UP*.5): return true
 for entity in constructs:
  if entity["kind"]!="wall": continue
  var offset: Vector3=point-entity["position"]
  var direction: Vector3=entity["dir"]
  var side:=Vector3(direction.z,0,-direction.x)
  if absf(offset.dot(side))<=float(entity["stats"]["wall_length"])*float(entity["stats"]["radius"])*.5+.15 and absf(offset.dot(direction))<=.2 and absf(offset.y)<2: return true
 return false

func _boxes() -> Array[AABB]:
 return obstacles.duplicate()

func _safe_destination(start: Vector3,end: Vector3) -> Vector3:
 var length:=start.distance_to(end)
 var steps:=maxi(1,int(ceil(length/.04)))
 var previous:=start
 for i in range(1,steps+1):
  var point:=start.lerp(end,float(i)/steps)
  if _blocked(point): return previous
  previous=point
 return end

func _persistent_visual(owner: Dictionary, skill: ZorxSkillData, point: Vector3, scale: Vector3, direction: Vector3) -> void:
 owner["visual"]=null
 visual_requested.emit({"kind":"persistent","skill":skill.id,"position":point,"scale":scale,"direction":direction,"source":owner.get("source_id",0),"duration":owner.get("left",0)})

func _projectile_visual(skill: ZorxSkillData, point: Vector3, direction: Vector3):
 visual_requested.emit({"kind":"projectile","skill":skill.id,"position":point,"direction":direction})
 return null

func _buff_visual(skill: ZorxSkillData, id: String) -> void:
 if actor!=null: visual_requested.emit({"kind":"buff","skill":skill.id,"position":actor.position,"buff":id})

func _gem_visual(id: String, point: Vector3, duration_s: float, buff_id: String=""):
 visual_requested.emit({"kind":"gem","gem":id,"position":point,"duration":duration_s,"buff":buff_id})
 return null

func _beam_visual(skill: ZorxSkillData, start: Vector3, end: Vector3) -> void:
 visual_requested.emit({"kind":"beam","skill":skill.id,"position":start,"end":end})

func reset() -> void:
 proc_seen.clear();blood_heals.clear();dodge_state.clear();dodge_ready=0
 super.reset()
 for group in [projectiles,constructs,zones,buff_visuals]:
  group.clear()
 jobs.clear()
 blast_budgets.clear()
 movements.clear()
 cooldowns.clear()
 parry.clear()
 second_dash.clear()
 if actor!=null: actor.reset_combat()
 total_hits=0

# Proc fan-out is bounded by target IDs per root cast; status-only relays never recurse into hits.
func _on_status_applied(target: ZorxSkillTarget,id: String,context: Dictionary) -> void:
 if int(context.get("owner_id",0)) != owner_id: return
 var events: Array=context.get("events",[])
 if id=="bleed" and "burning_blood" in events:target.apply_status("burn",context)
 if id=="shock" and "overload" in events and not context.get("overload_applied",false):
  var extra:=context.duplicate(true);extra["overload_applied"]=true;target.apply_status("bleed",extra)
 if id=="chill" and target.statuses.has("freeze") and target.statuses.has("burn") and "steam_burst" in events:
  target.remove_status("burn");target.remove_status("freeze");target.remove_status("chill")
  var burst:=context.duplicate(true);burst["statuses"]=[];burst["events"]=[];burst["explosion_cast"]=-100000-int(context.get("origin_cast_id",0))
  _area_damage(target.position,2.5,30*float(context.get("equipment_scale",1)),burst);_spawn_visual(load("res://data/skill_system/skills/eruption.tres"),target.position,2.5)
 if id=="shock" and target.statuses.has("freeze") and "shatter" in events:
  target.remove_status("freeze")
  target.take_damage(25*float(context.get("equipment_scale",1)),"shatter",context);_spawn_visual(load("res://data/skill_system/skills/shatter_smash.tres"),target.position,1)
 if id=="shock" and ("shock_spread" in events or "storm_caller" in events) and not context.get("shock_relay",false):
  var key:=str(context.get("origin_cast_id",clock))+":shock"
  if not proc_seen.has(key):proc_seen[key]={}
  var visited: Dictionary=proc_seen[key]
  if visited.has(target.entity_id):return
  visited[target.entity_id]=true
  var queue: Array[ZorxSkillTarget]=[target];var remaining:=targets.size() if "storm_caller" in events else 2
  var relay:=context.duplicate(true);relay["shock_relay"]=true
  while not queue.is_empty() and remaining>0:
   var from: ZorxSkillTarget=queue.pop_front()
   var nearby:=_in_radius(from.position,5).filter(func(t: ZorxSkillTarget)->bool:return not visited.has(t.entity_id) and has_line_of_sight(from.position,t.position))
   nearby.sort_custom(func(a: ZorxSkillTarget,b: ZorxSkillTarget)->bool:return from.position.distance_squared_to(a.position)<from.position.distance_squared_to(b.position))
   for next in nearby:
    if remaining<=0:break
    visited[next.entity_id]=true;remaining-=1
    next.apply_status("shock",relay);_beam_visual(load("res://data/skill_system/skills/chain_lightning.tres"),from.position,next.position);queue.append(next)

func _passive_death(target: ZorxSkillTarget,context: Dictionary) -> void:
 if int(context.get("owner_id",0)) != owner_id: return
 var events: Array=context.get("events",passive_context.get("events",[]))
 var snapshot: Dictionary=context.get("status_snapshot",target.statuses)
 if "bleed_spread" in events and snapshot.has("bleed"):
  var neighbors:=_in_radius(target.position,3).filter(func(t: ZorxSkillTarget)->bool:return t!=target)
  var next:=_nearest(target.position,neighbors)
  if next!=null:
   for stack in snapshot["bleed"]:
    next.apply_status("bleed",stack.get("context",context))
    next.statuses["bleed"][-1]["left"]=stack["left"]
    next.statuses["bleed"][-1]["dps"]=stack["dps"]
 if "shock_kill_cdr" in events and bool(context.get("shocked",false)):
  for id in cooldowns:cooldowns[id]=maxf(clock,float(cooldowns[id])-.5)
  ready_at=float(cooldowns.get(active_id,ready_at))

func _advance_passives(dt: float) -> void:
 for target in targets:
  if target.dead or not target.statuses.has("burn"):continue
  var burn: Dictionary=target.statuses["burn"];var context: Dictionary=burn.get("context",{})
  if int(context.get("owner_id",0)) != owner_id:continue
  if not "burn_spread" in context.get("events",[]):continue
  burn["spread_timer"]=float(burn.get("spread_timer",2))-dt
  if float(burn["spread_timer"])<=0:
   burn["spread_timer"]+=2
   var next:=_nearest(target.position,_in_radius(target.position,4).filter(func(t: ZorxSkillTarget)->bool:return t!=target and not t.statuses.has("burn")))
   if next!=null:next.apply_status("burn",context)
 # Bound old proc ledgers. Root IDs are monotonically increasing; a single cast never spans 256 later casts.
 if proc_seen.size()>256:proc_seen.erase(proc_seen.keys()[0])
 if not dodge_state.is_empty() and actor!=null:
  var u:=clampf((clock-float(dodge_state["start_time"]))/.25,0,1)
  actor.position=dodge_state["start"].lerp(dodge_state["end"],u);actor.invulnerable=u<1
  if u>=1:dodge_state.clear()

func request_dodge(direction: Vector3) -> bool:
 if actor==null or actor.hp<=0 or clock<dodge_ready or is_casting() or not movements.is_empty():return false
 var start:=actor.position;var end:=_safe_destination(start,start+direction.normalized()*3)
 dodge_state={"start":start,"end":end,"start_time":clock};dodge_ready=clock+float(passive_context.get("player_passives",{}).get("dodge_cd_mul",1))
 if "dodge_chill" in passive_context.get("events",[]):
  for target in _in_radius(start,3):
   for i in range(2):target.apply_status("chill",passive_context)
  _spawn_visual(load("res://data/skill_system/skills/ice_lance.tres"),start,1)
 return true
