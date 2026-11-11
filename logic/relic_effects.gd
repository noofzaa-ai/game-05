extends RefCounted
## Deterministic authority-owned Relic runtime; no RNG, client amounts, recursive damage or grants.
const Relics=preload("res://logic/relics.gd")
static func attach(fighter,profile)->void:
 attach_loadout(fighter,profile.relics)
static func attach_loadout(fighter,loadout:Dictionary)->void:
 fighter.relic_state={"ids":Relics.equipped_types(loadout),"charge":0,"stack_wait":0,"lantern_ready":0,"lantern_wait":0}
static func tick(fighter)->void:
 var s:Dictionary=fighter.relic_state
 if s.is_empty():return
 if not fighter.is_alive():
  s.charge=0;s.lantern_ready=0
 for key in ["stack_wait","lantern_ready","lantern_wait"]:s[key]=maxi(0,int(s[key])-1)
static func definition(id:String)->Dictionary:
 return Relics.catalog().get(id,{}).get("effect",{})
static func has(fighter,id:String)->bool:
 return id in fighter.relic_state.get("ids",[])
static func basic(move_id:String)->bool:
 var kind:String=move_id.split("_",true,1)[1] if "_" in move_id else ""
 return kind.begins_with("light_") or kind in ["heavy","air","run_light","run_heavy","air_heavy"]
static func skill_cast(fighter)->void:
 if not has(fighter,"goblin_lantern") or not fighter.is_alive():return
 var s:Dictionary=fighter.relic_state
 if int(s.lantern_wait)>0:return
 var config=definition("goblin_lantern")
 s.lantern_ready=int(config.window_ticks);s.lantern_wait=int(config.cooldown_ticks)
static func multiplier(fighter,move_id:String)->float:
 if not basic(move_id) or not has(fighter,"goblin_medallion"):return 1.0
 var config=definition("goblin_medallion")
 return float(config.damage_multiplier) if int(fighter.relic_state.charge)>=int(config.hits) else 1.0
static func hit(attacker_id:int,attacker,target_id:int,target,move_id:String,data,events:Array[Dictionary])->void:
 if not basic(move_id):return
 var s:Dictionary=attacker.relic_state
 if has(attacker,"goblin_medallion"):
  var config=definition("goblin_medallion")
  if int(s.charge)>=int(config.hits):
   s.charge=0;s.stack_wait=int(config.stack_interval_ticks)
   events.append({"type":"relic_proc","player":attacker_id,"relic":"goblin_medallion","target":target_id})
  elif int(s.stack_wait)<=0:
   s.charge+=1;s.stack_wait=int(config.stack_interval_ticks)
 if has(attacker,"goblin_lantern") and int(s.lantern_ready)>0:
  s.lantern_ready=0
  if not target.is_alive():return
  var config=definition("goblin_lantern");var effect_id:String=config.effect_id
  # One poison instance; a later valid proc refreshes/replaces it, never adds stacks.
  target.effects[effect_id]={"left":int(config.duration_ticks),"stacks":1,"age":0,"source":attacker_id,"exact_dot":true,"dps":attacker.stat("ATK")*float(config.total_atk)*60.0/float(config.duration_ticks)}
  preload("res://logic/effects.gd").refresh(target,data)
  events.append({"type":"effect_applied","target":target_id,"effect":effect_id,"stacks":1,"source":attacker_id})
