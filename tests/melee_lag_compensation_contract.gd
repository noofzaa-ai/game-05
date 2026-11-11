extends SceneTree
const Wire=preload("res://logic/net_wire.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var combat=preload("res://logic/combat_data_loader.gd").load_default()
 var sim=preload("res://logic/game_sim.gd").new(preload("res://logic/sim_world.gd").new(),combat,RandomNumberGenerator.new())
 sim.add_player(1,Vector3.ZERO,{},"blade");sim.add_player(2,Vector3(0,0,-.8),{},"blade");sim.fighters[2].team="enemy"
 var seen_box:AABB=sim.bodies[2].aabb()
 sim.bodies[2].position=Vector3(0,0,-5)
 var attacker=sim.fighters[1];attacker.state=1;attacker.direction=Vector2i(0,-1);attacker.move_id=combat.styles.blade.ground_light
 attacker.move_frame=float(combat.moves[attacker.move_id].startup)
 var hits:Array[Dictionary]=[]
 var Combat=preload("res://logic/combat.gd")
 Combat.resolve_hits(sim.fighters,sim.bodies,combat,sim.rng,hits)
 assert(hits.is_empty())
 var hp:float=sim.fighters[2].hp
 Combat.resolve_hits(sim.fighters,sim.bodies,combat,sim.rng,hits,{1:{2:seen_box}})
 assert(sim.fighters[2].hp<hp and hits.size()>0 and sim.bodies[2].position==Vector3(0,0,-5))
 var encoded=preload("res://logic/sim_input.gd").new().encode()
 for views in [[],[90]]:
  var packet=Wire.parse(Wire.inputs(1,1,1,105,[encoded],1,views));var decoded=Wire.read_inputs(packet.body)
  assert(decoded.frames[0]==encoded and decoded.view_ticks[0]==(-1 if views.is_empty() else 90))
 var manager=preload("res://server/rooms/manager.gd").new();var rng=RandomNumberGenerator.new()
 var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
 assert(manager.create("rewindtest123",55,[{"id":1,"profile":p.to_dict()}],true,1).ok)
 var room=manager.rooms["rewindtest123"].room
 for i in 50:room.tick()
 assert(room.input(1,51,encoded,49));room.tick();assert(room.sim.melee_target_boxes.has(1))
 assert(room.input(1,52,encoded,1));room.tick();assert(not room.sim.melee_target_boxes.has(1))
 assert(room.input(1,53,encoded,10000));room.tick();assert(not room.sim.melee_target_boxes.has(1))
 assert(room.melee_history.size()<=38)
 print("MELEE REWIND PASS: visible historical enemy hit,current far miss,no target teleport,legacy/new INPUT compatible,old/future views rejected,bounded history")
 quit()
