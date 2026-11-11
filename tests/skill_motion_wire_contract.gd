extends SceneTree
const Wire=preload("res://logic/net_wire.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_system/catalog.json"))
 var count:=0;var largest:=0
 for skill in catalog:
  var manager=preload("res://server/rooms/manager.gd").new()
  var rng=RandomNumberGenerator.new();rng.seed=55
  var p=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
  var selected:Array=[skill]
  for id in catalog:
   if selected.size()<4 and id not in selected:selected.append(id)
  for i in range(4):p.skill_build.skills[i]={"skill":selected[i],"shape":"","effect":""}
  assert(manager.create("wiremotion123",55,[{"id":1,"profile":p.to_dict()}]).ok)
  var room=manager.rooms["wiremotion123"].room
  for tick in range(90):
   var frame=preload("res://logic/sim_input.gd").new();frame.aim=Vector2.RIGHT;frame.aim_distance=3
   if tick==1:frame.skill_slot=0
   room.sim.fighters[1].hp=room.sim.fighters[1].max_hp();room.sim.fighters[1].energy=1000
   room.input(1,room.clock_tick+1,frame.encode());room.tick()
   if tick%3==0:
    var state:Dictionary=room.public_state(1)
    var payload=preload("res://logic/net_state.gd").difference(state,{},0,room.acknowledged[1])
    var body=Wire.encode(payload,262144)
    if body.is_empty():print("WIRE FAIL skill=",skill," ",Wire.last_encode_error);quit(2);return
    largest=maxi(largest,body.size())
  count+=1
 print("SKILL MOTION WIRE PASS:",count," skill configs x90ticks;motion capsule/input_clock fit existing codec;max full frame bytes=",largest)
 quit()
