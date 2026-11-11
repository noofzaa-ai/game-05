extends SceneTree
const State=preload("res://logic/net/actor_continuation.gd")
const Step=preload("res://logic/net/actor_step.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/catalog.json"))
 var checked:=0;var largest:=0
 var cases:Array=[]
 for skill in catalog:
  cases.append({"skill":skill,"shape":"","effect":""})
  var resource=load("res://data/skill_system/skills/"+skill+".tres")
  for file in DirAccess.get_files_at("res://data/skill_system/gems"):
   if not file.ends_with(".tres"):continue
   var gem=load("res://data/skill_system/gems/"+file)
   if not load("res://data/skill_system/scripts/build_calc.gd").can_equip(resource,gem,gem.slot).is_empty():continue
   var row={"skill":skill,"shape":"","effect":""};row[gem.slot]=gem.id;cases.append(row)
 for case in cases:
  var skill:String=case.skill
  var manager=preload("res://server/rooms/manager.gd").new()
  var profile=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
  var choices:Array=[skill]
  for entry in catalog:
   if choices.size()<4 and entry not in choices:choices.append(entry)
  for i in 4:profile.skill_build.skills[i]={"skill":choices[i],"shape":"","effect":""}
  profile.skill_build.skills[0]=case.duplicate(true)
  assert(manager.create("ownerskilltest",28,[{"id":1,"profile":profile.to_dict()}]).ok)
  var room=manager.rooms["ownerskilltest"].room
  room.sim._ai.clear()
  for target in room.sim.fighters:
   if target!=1:room.sim.fighters[target].hp=100000;room.sim.fighters[target].stats.HP=100000
  var copy=preload("res://logic/game_sim.gd").new(room.sim.world,room.sim.combat,RandomNumberGenerator.new())
  copy.add_player(1,Vector3.ZERO)
  var state:=State.capture(room.sim,1)
  if state.is_empty():print("EMPTY SKILL STATE ",skill);quit(2);return
  assert(State.restore(copy,1,state))
  for tick in range(1,121):
   var frame=preload("res://logic/sim_input.gd").new();frame.aim=Vector2.RIGHT;frame.aim_distance=3
   if tick==2:frame.skill_slot=0
   room.input(1,room.clock_tick+1,frame.encode());room.tick()
   copy.tick_count=room.sim.tick_count-1;Step.advance(copy,1,frame)
   var a=room.sim.fighters[1];var b=copy.fighters[1]
   var same:bool=room.sim.bodies[1].position.distance_to(copy.bodies[1].position)<.00001 and a.skill_view.get("pose",{}).get("skill","")==b.skill_view.get("pose",{}).get("skill","") and a.skill_view.get("casting",false)==b.skill_view.get("casting",false) and absf(a.energy-b.energy)<.00001
   if not same:
    print("OWNER SKILL DIFFERENCE ",skill," tick=",tick," pos=",room.sim.bodies[1].position,"/",copy.bodies[1].position," energy=",a.energy,"/",b.energy," pose=",a.skill_view.get("pose"),"/",b.skill_view.get("pose"));quit(3);return
   if tick==20 or tick==40:
    var snapshot:=State.capture(room.sim,1);largest=maxi(largest,snapshot.size())
    if snapshot.is_empty() or not State.restore(copy,1,snapshot):print("RESTORE FAIL ",skill," tick",tick);quit(4);return
  checked+=1
 print("OWNER SKILL CONTRACT PASS: ",checked," production skill/Gem cases x120ticks, own phase/cast/position/stamina and midcast restore; max bytes=",largest,". Static combat context only; Real-room acceptance separate.")
 quit()
