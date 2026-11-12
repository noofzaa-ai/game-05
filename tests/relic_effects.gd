extends SceneTree
const RE=preload("res://logic/relic_effects.gd")
const Combat=preload("res://logic/combat.gd")
var manager
func _initialize()->void:call_deferred("run")
func profile(id:String):
 var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
 p.relics.owned=[{"id":"owned","relic":id}];p.relics.equipped=["owned","",""]
 return p
func pair(id:String):
 var world=preload("res://logic/sim_world.gd").new()
 var sim=preload("res://logic/game_sim.gd").new(world,manager.combat,RandomNumberGenerator.new())
 sim.rng.seed=11;sim.add_player(1,Vector3.ZERO,{"ATK":100,"HP":1000,"CRIRATE":0},"blade");sim.add_enemy(2,Vector3(1,0,0),"goblin")
 sim.fighters[2].stats.HP=10000;sim.fighters[2].hp=10000;sim.fighters[2].stats.DEF=0;sim.fighters[2].stats.EFFECT_RES=0
 RE.attach(sim.fighters[1],profile(id));return sim
func damage(sim,move:String="blade_light_1")->float:
 var before:float=sim.fighters[2].hp
 Combat.apply_hit(1,2,move,sim.fighters,sim.bodies,manager.combat,sim.rng,sim.events)
 return before-sim.fighters[2].hp
func run()->void:
 manager=load("res://server/rooms/manager.gd").new();assert(manager.combat.is_valid())
 var sim=pair("goblin_medallion");var actor=sim.fighters[1]
 var baseline=damage(sim);assert(actor.relic_state.charge==1)
 for n in range(4):damage(sim)
 assert(actor.relic_state.charge==1,"spam/AoE cannot gain extra stacks within0.5s")
 for n in range(4):
  for tick in range(30):RE.tick(actor)
  damage(sim)
 assert(actor.relic_state.charge==5)
 var charge:int=actor.relic_state.charge
 damage(sim,"blade_special");assert(actor.relic_state.charge==charge,"skills never consume or stack medallion")
 var boosted=damage(sim);assert(boosted==roundf(baseline*1.25));assert(actor.relic_state.charge==0)
 # Guarded hits neither consume a ready charge nor trigger poison.
 actor.relic_state.charge=5
 var enemy=sim.fighters[2];enemy.state=enemy.State.GUARD;enemy.direction=Vector2i(-1,0);enemy.energy=1000
 damage(sim);assert(actor.relic_state.charge==5);enemy.state=enemy.State.IDLE
 sim=pair("goblin_lantern");actor=sim.fighters[1];enemy=sim.fighters[2]
 damage(sim);assert(not enemy.effects.has("relic_goblin_poison"))
 RE.skill_cast(actor);assert(actor.relic_state.lantern_ready==240 and actor.relic_state.lantern_wait==480)
 damage(sim,"blade_special");assert(actor.relic_state.lantern_ready==240)
 enemy.effects.clear()
 damage(sim);assert(actor.relic_state.lantern_ready==0 and enemy.effects.relic_goblin_poison.stacks==1)
 var hp:float=enemy.hp
 for tick in range(180):preload("res://logic/effects.gd").tick(2,enemy,manager.combat,sim.events)
 assert(is_equal_approx(hp-enemy.hp,30),"poison is30%ATK over3seconds")
 assert(not enemy.effects.has("relic_goblin_poison"))
 RE.skill_cast(actor);assert(actor.relic_state.lantern_ready==0,"8second cooldown cannot rearm")
 for tick in range(480):RE.tick(actor)
 RE.skill_cast(actor)
 for tick in range(240):RE.tick(actor)
 damage(sim);assert(not enemy.effects.has("relic_goblin_poison"),"expired4second window")
 # Low ATK remains exactly30%, not six forced minimum-damage ticks.
 sim=pair("goblin_lantern");actor=sim.fighters[1];enemy=sim.fighters[2];actor.stats.ATK=7
 RE.skill_cast(actor);damage(sim);hp=enemy.hp
 for tick in range(180):preload("res://logic/effects.gd").tick(2,enemy,manager.combat,sim.events)
 assert(absf(hp-enemy.hp-2.1)<.001)
 # DOT events never feed back into charge and a lethal poison awards exactly one kill.
 actor.relic_state.ids=["goblin_medallion","goblin_lantern"];actor.relic_state.charge=0;actor.relic_state.lantern_wait=0;enemy.hp=100
 RE.skill_cast(actor);damage(sim);var initial_charge:int=actor.relic_state.charge
 enemy.hp=.1;sim.events.clear()
 for tick in range(60):preload("res://logic/effects.gd").tick(2,enemy,manager.combat,sim.events)
 assert(actor.relic_state.charge==initial_charge)
 assert(sim.events.filter(func(e):return e.type=="killed").size()==1)
 assert(enemy.effects.is_empty())
 # Actual successful/failed skill request path (class skills, logic/class_skills/engine.gd).
 sim=pair("goblin_lantern");actor=sim.fighters[1]
 var Skills=load("res://logic/class_skills/engine.gd");Skills.attach(sim,1,"sword_shield")
 actor.energy=0;assert(not Skills.cast(sim,1,"breaker_slam",{"target":2}).is_empty());assert(actor.relic_state.lantern_ready==0)
 actor.energy=1000;assert(Skills.cast(sim,1,"breaker_slam",{"target":2}).is_empty());assert(actor.relic_state.lantern_ready==240)
 # Full JSON simulation checkpoint must retain charge/timers and restore deterministically.
 var saved:Dictionary=sim.snapshot();var restored=pair("goblin_lantern")
 assert(restored.restore(JSON.parse_string(JSON.stringify(saved))))
 assert(restored.fighters[1].relic_state==actor.relic_state)
 # Charge and active poison survive full checkpoint and authoritative wire serialization.
 sim=pair("goblin_medallion");actor=sim.fighters[1];actor.relic_state.charge=4;actor.relic_state.stack_wait=17
 saved=sim.snapshot();restored=pair("goblin_medallion");assert(restored.restore(JSON.parse_string(JSON.stringify(saved))))
 assert(restored.fighters[1].relic_state==actor.relic_state)
 sim=pair("goblin_lantern");actor=sim.fighters[1];RE.skill_cast(actor);damage(sim)
 saved=sim.snapshot();restored=pair("goblin_lantern");assert(restored.restore(JSON.parse_string(JSON.stringify(saved))))
 assert(restored.fighters[2].effects==sim.fighters[2].effects)
 var wire=load("res://logic/net_wire.gd");var fields=[]
 for field in wire.FIGHTER_FIELDS:fields.append(actor.get(field))
 var decoded=wire.decode(wire.encode(fields))
 assert(decoded.has("value") and decoded.value[-1]==actor.relic_state)
 var p_for_command=profile("goblin_medallion")
 var context={"profile":p_for_command,"rules":manager.rules,"camp":manager.camp,"location":"camp"}
 var before:Dictionary=p_for_command.to_dict()
 assert(not load("res://logic/commands.gd").apply(context,{"type":"relic_proc","damage":999999},RandomNumberGenerator.new()).ok)
 assert(p_for_command.to_dict()==before)
 # Unknown owned definitions have no effect; unequipped ownership never activates.
 var p=profile("fake");RE.attach(actor,p);assert(actor.relic_state.ids.is_empty())
 p=profile("goblin_medallion");p.relics.equipped=["","",""];RE.attach(actor,p);assert(actor.relic_state.ids.is_empty())
 print("RELIC EFFECTS PASS:5+1charge,0.5srate,25%bonus,blocked/skills excluded,30%poison/3s,4swindow,8scooldown,realcastauthorization,JSONrestore,noownershipgrant")
 quit()
