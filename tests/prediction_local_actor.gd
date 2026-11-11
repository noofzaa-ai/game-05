extends SceneTree
const Sim=preload("res://logic/game_sim.gd")
const SimInput=preload("res://logic/sim_input.gd")
var failures:=0
func _initialize():
 var combat=preload("res://logic/combat_data_loader.gd").load_default()
 for style in ["blade","dagger","spear","hammer","bow"]:
  var full=Sim.new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
  var local=Sim.new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
  for sim in [full,local]:
   sim.add_player(1,Vector3.ZERO,{},style)
   sim.add_player(2,Vector3(20,0,20),{},style)
  var remote_before=local.bodies[2].position
  local.projectiles=[{"authority_sentinel":true}]
  for tick in range(240):
   for sim in [full,local]:
    if tick==30:sim.fighters[1].hitstop=3
    if tick==60:sim.fighters[1].skill_view={"movement":0.0,"casting":true}
    if tick==100:sim.fighters[1].skill_view={}
    if tick==180:sim.bodies[1].knockback=Vector2(1,0)
   var input=SimInput.new();input.aim=Vector2(0,-1)
   input.move=Vector2.RIGHT if tick<60 else Vector2.ZERO
   input.light=tick%30==0;input.heavy=tick%79==0;input.jump=tick==90;input.dodge=tick==150;input.guard=tick>=200 and tick<210
   full.set_input(1,input);local.set_input(1,input)
   full.tick();local.tick(1)
   for field in ["position","velocity","grounded"]:
    if full.bodies[1].get(field)!=local.bodies[1].get(field):failures+=1;push_error(style+" body "+field+" tick "+str(tick))
   for field in ["state","move_id","move_frame","energy","dodge_cooldown"]:
    if full.fighters[1].get(field)!=local.fighters[1].get(field):failures+=1;push_error(style+" fighter "+field+" tick "+str(tick))
  if local.bodies[2].position!=remote_before:failures+=1
  if local.projectiles!=[{"authority_sentinel":true}]:failures+=1
 print("PREDICTION CORRECTNESS 5 weapons x 240 ticks failures=",failures)
 quit(0 if failures==0 else 1)
