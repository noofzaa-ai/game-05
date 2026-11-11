extends SceneTree
func _initialize()->void:
 var Sim=preload("res://logic/game_sim.gd")
 var combat=preload("res://logic/combat_data_loader.gd").load_default()
 var full=Sim.new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
 var predicted=Sim.new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
 for sim in [full,predicted]:
  sim.add_player(1,Vector3.ZERO,{},"blade")
  sim.add_player(2,Vector3(0,0,-.8),{},"blade")
  sim.fighters[2].team="enemy";sim.fighters[2].stats.HP=100000;sim.fighters[2].hp=100000
  sim.fighters[1].stats.ATKSPD=2.199645
 var witnessed:=false
 for tick in 60:
  var input=preload("res://logic/sim_input.gd").new();input.light=tick==0;input.aim=Vector2(0,-1)
  full.set_input(1,input);predicted.set_input(1,input)
  full.tick();predicted.tick(1)
  for event in full.events:
   if event.get("type")=="hit" and event.get("attacker")==1:
    witnessed=true
    print("OUTGOING HIT tick=",tick," authority_hitstop=",full.fighters[1].hitstop," predicted_hitstop=",predicted.fighters[1].hitstop)
  if witnessed and full.fighters[1].move_frame!=predicted.fighters[1].move_frame:
   push_error("MOVE_FRAME diverged tick="+str(tick));quit(1);return
 assert(witnessed)
 assert(predicted.fighters[2].hp==100000)
 print("OUTGOING HITSTOP PASS: attack frame parity; target HP remains authoritative")
 quit()
