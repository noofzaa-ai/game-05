extends SceneTree
var cache:Dictionary={}
const Wire=preload("res://logic/net_wire.gd")
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var raw=JSON.parse_string(FileAccess.get_file_as_string("/tmp/zorx-ff-codec-profile.json"))
 assert(raw is Dictionary)
 var manager=preload("res://server/rooms/manager.gd").new()
 var fixture=JSON.parse_string(FileAccess.get_file_as_string("/tmp/zorx-ff-codec-room.json"))
 var result=manager.create("12345678abcd",str(fixture.seed).hex_to_int(),[{"id":1,"profile":raw}])
 if not result.get("ok",false):
  print("ROOM CREATE FAILED ",result)
  var profile=preload("res://logic/profile.gd").from_dict(raw,manager.rules,manager.camp)
  var weapon=profile.loadout.item_at("weapon",0) if profile!=null else null
  print("BUILD CHECK ",{"profile_valid":profile!=null,"weapon_present":weapon!=null,"weapon_destroyed":weapon.destroyed if weapon!=null else null,"weapon_family":weapon.weapon_type if weapon!=null else "", "build_error":preload("res://logic/skill_build.gd").validate(profile.skill_build) if profile!=null else "invalid_profile", "build_start":profile.skill_build.get("start","") if profile!=null else ""})
  quit(2);return
 var room=manager.rooms["12345678abcd"].room
 for id in room.sim.bodies:
  if id!=1:room.sim.bodies[id].position=room.sim.bodies[1].position+Vector3(0,0,-1.5)
 var previous:Dictionary={}
 for tick in range(600):
  var input=preload("res://logic/sim_input.gd").new();input.move=Vector2.ZERO;input.aim=Vector2(0,-1);input.aim_distance=3.0
  input.light=false;input.skill_slot=(tick/120)%4
  room.sim.fighters[1].energy=1000;room.sim.fighters[1].hp=room.sim.fighters[1].max_hp()
  room.input(1,room.clock_tick+1,input.encode())
  room.tick()
  for event in room.sim.events:
   if event.get("type")=="skill_cast":print("CAST tick=",tick)
  if tick%3!=0:continue
  cache.clear()
  var state:Dictionary=room.public_state(1,true)
  var patch=preload("res://logic/net_state.gd").difference(state,{},0,0)
  if not check(patch,262144,"FULL_STATE",tick):quit(2);return
  var delta=preload("res://logic/net_state.gd").difference(state,previous,1,0)
  if not check(delta,262144,"DELTA_STATE",tick):quit(2);return
  previous=state.duplicate(true)
  var events:Array=[]
  for event in room.events:
   events.append(event)
   if events.size()>=32:break
  if not events.is_empty() and not check({"events":events},Wire.MAX_FRAME-12,"EVENTS",tick):quit(2);return
 print("REAL PROFILE CODEC PASS600ticks")
 quit()
func check(value:Dictionary,limit:int,kind:String,tick:int)->bool:
 var codec=Wire.ValueCodec.new();codec.limit=limit;codec.budget=32768 if limit>Wire.MAX_FRAME else 8192
 codec.shared_entities=cache
 codec.write(value,0)
 if codec.failed or codec.stream.get_size()>limit:
  print("CODEC FAILURE kind=",kind," tick=",tick," bytes=",codec.stream.get_size()," budgetleft=",codec.budget)
  inspect(value,"",0)
  return false
 return true
func inspect(value,path:String,depth:int)->void:
 if depth>12:print("DEPTH EXCEEDED ",path," depth=",depth);return
 if value is Dictionary:
  if value.size()>512:print("DICT TOO LARGE ",path)
  for key in value:inspect(value[key],path+"/"+str(key),depth+1)
 elif value is Array:
  if value.size()>1024:print("ARRAY TOO LARGE ",path)
  for i in value.size():inspect(value[i],path+"/"+str(i),depth+1)
 elif value is String:
  if value.to_utf8_buffer().size()>8192:print("STRING TOO LARGE ",path)
 elif not typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_VECTOR3]:print("UNSUPPORTED ",path," type=",typeof(value))
