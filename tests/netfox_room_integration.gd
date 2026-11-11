extends SceneTree
## Native correctness gate for actual production Room service/session. Not Web acceptance.
class FixtureBackend:
 extends RefCounted
 var maintenance:=false
 var profile:Dictionary
 var began:=Time.get_ticks_msec()
 var companion_joined:=false
 func backend(request:Dictionary)->Dictionary:
  if "--companion-delay" in OS.get_cmdline_user_args():
   if request.op=="redeem":return {"ok":true,"room":request.room,"slot":1,"capacity":2,"profile":profile,"fence":"fixturefence","member_fence":"fixturemember","seed":"0000000000000042","camp":true,"companions":[],"pending_companion":{"id":"arun","slot":2,"seed":"0000000000042","accept_at":10000}}
   if request.op=="companion_accept":
    if Time.get_ticks_msec()-began<10000:return {"ok":false,"error":"request_expired"}
    companion_joined=true;return {"ok":true,"companion":{"id":"arun","slot":2,"seed":"0000000000042"}}
   if request.op=="start" and not companion_joined:return {"ok":false,"error":"party_not_ready"}
  if request.op=="redeem" and ("--companion" in OS.get_cmdline_user_args() or "--companion-delay" in OS.get_cmdline_user_args()):
   return {"ok":true,"room":request.room,"slot":1,"capacity":2,"profile":profile,"fence":"fixturefence","member_fence":"fixturemember","seed":"0000000000000042","camp":true,"companions":[{"id":"arun","slot":2}]}
  if request.op=="redeem":return {"ok":true,"room":request.room,"slot":2 if request.ticket.begins_with("b") else 1,"capacity":2 if "--coop" in OS.get_cmdline_user_args() else 1,"profile":profile,"fence":"fixturefence","member_fence":"fixturemember","seed":"0000000000000042","diagnostic":true,"farm_map":"" if "--coop" in OS.get_cmdline_user_args() else ("practice_field" if ("--quiet-states" in OS.get_cmdline_user_args() or "--pause" in OS.get_cmdline_user_args()) else "goblin_arena_a")}
  return {"ok":true}
var service
var session
var started:=0
var activated:=0
var first:=Vector3.ZERO
var fixture
var server:=false
var slot:=1
var actor_tick:=0
var reconnected:=false
var forced_epoch:=false
var last_occupied_at:=0
var epoch_seen:=0
var remote_moved:=false
var initial_remote:=Vector3.ZERO
var quiet_started:=false
var quiet_finished:=false
var stalled_once:=false
var companion_ready_sent:=false
var companion_depart_sent:=false
var companion_first:=Vector3.ZERO
var diagnostic_started:=false
var diagnostic_done:=false
var worker_stalled:=false
var diagnostic_desync:=false
func _initialize()->void:call_deferred("_run")
func _run()->void:
 print("INTEGRATION RUN");started=Time.get_ticks_msec();server="--server" in OS.get_cmdline_user_args()
 print("INTEGRATION manager");var manager=preload("res://server/rooms/manager.gd").new()
 if "--slot2" in OS.get_cmdline_user_args():slot=2
 print("INTEGRATION constructed");if server:
  fixture=FixtureBackend.new()
  fixture.profile=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new()).to_dict()
  service=load("res://server/rooms/netfox/service.gd").new();service.name="NetRuntime";root.add_child(service);service.configure(self,manager,fixture)
  print("INTEGRATION service configured");var listening:int=service.start(8061,OS.get_environment("ZORX_TEST_BIND") if not OS.get_environment("ZORX_TEST_BIND").is_empty() else "127.0.0.1");print("INTEGRATION listening ",listening);assert(listening==OK)
 else:
  session=load("res://client/session/netfox_session.gd").new(null,manager.rules,manager.camp,manager.loot)
  session.state_ready.connect(func():session.scene_presented(session.scene_epoch()))
  session.stage_changed.connect(func():session.scene_presented(session.scene_epoch()))
  assert(session.connect_room(null,{"room":"0123456789abcdef0123456789abcdef","ticket":("a" if slot==1 else "b").repeat(64),"player_id":slot,"url":OS.get_environment("ZORX_TEST_ROOM_URL") if not OS.get_environment("ZORX_TEST_ROOM_URL").is_empty() else "ws://127.0.0.1:8060"}))
func _process(dt:float)->bool:
 if started==0:return false
 var age:=Time.get_ticks_msec()-started
 if age>180000:printerr("NETFOX REAL ROOM TIMEOUT");quit(4);return false
 if not server and "--diagnostics" in OS.get_cmdline_user_args() and session!=null and session.own_actor!=null and session.ready and age>4500 and not diagnostic_desync:
  diagnostic_desync=true
  session.own_actor.simulation.bodies[slot].position+=Vector3(.8,0,0)
  session.own_actor.state_bytes=preload("res://logic/net/actor_continuation.gd").capture(session.own_actor.simulation,slot)
 if server:
  if "--diagnostics" in OS.get_cmdline_user_args() and age>3500 and not worker_stalled and not service.groups.is_empty():
   worker_stalled=true;OS.delay_msec(140)
  if "--epoch" in OS.get_cmdline_user_args() and not forced_epoch and age>5500:
   for binding in service.lease.bindings.values():
    if binding.room_obj!=null and not binding.room_obj.scene_loading():binding.room_obj.epoch+=1;binding.room_obj.require_scene_ready();forced_epoch=true
  if "--quiet-states" in OS.get_cmdline_user_args():
   for group in service.groups.values():
    for actor in group.actors.values():
     if age>2500 and age<4500:
      actor.sync._published_tick=1000000000;quiet_started=true
     elif age>=4500 and quiet_started and not quiet_finished:
      actor.sync._published_tick=-100
   if age>=4500 and quiet_started:quiet_finished=true
  if not service.endpoint.gate.admitted.is_empty():last_occupied_at=Time.get_ticks_msec()
  var completed:=false
  for binding in service.lease.bindings.values():
   if binding.room_obj!=null and (binding.room_obj.clock_tick>(1800 if ("--companion" in OS.get_cmdline_user_args() or "--companion-delay" in OS.get_cmdline_user_args()) else (1200 if "--diagnostics" in OS.get_cmdline_user_args() else 480)) or (binding.room_obj.clock_tick>120 and last_occupied_at>0 and Time.get_ticks_msec()-last_occupied_at>8000)):completed=true
  if completed:
   for binding in service.lease.bindings.values():
    var room=binding.room_obj
    if room!=null:print("NETFOX ROOM SERVER world_ticks=",room.clock_tick," inputs=",room.acknowledged)
   quit()
 elif session!=null:
  session.poll(dt)
  if session.ready and not session.server_state.meta.get("scene_loading",true):
   if ("--companion" in OS.get_cmdline_user_args() or "--companion-delay" in OS.get_cmdline_user_args()) and session.server_state.meta.get("party",{}).get("lobby",false):
    session.advance_controls(preload("res://logic/sim_input.gd").new(),dt)
    if session.server_state.meta.party.members.size()<2:return false
    if not companion_ready_sent:
     companion_ready_sent=true;session.command({"type":"party_ready","ready":true})
    elif not companion_depart_sent and session.server_state.meta.party.members.all(func(m):return m.ready):
     companion_depart_sent=true;session.command({"type":"party_depart"})
    return false
   if activated==0:
    activated=Time.get_ticks_msec();first=session.presentation_position(slot)
    if ("--companion" in OS.get_cmdline_user_args() or "--companion-delay" in OS.get_cmdline_user_args()):companion_first=session.presentation_position(2)
   var input=preload("res://logic/sim_input.gd").new();input.move=Vector2.RIGHT if slot==1 else Vector2.LEFT
   epoch_seen=maxi(epoch_seen,session.scene_epoch())
   if "--reconnect" in OS.get_cmdline_user_args() and not reconnected and Time.get_ticks_msec()-activated>2500:
    reconnected=true
    session.admission.ticket=("a" if slot==1 else "b").repeat(64)
    session._open_socket()
    return false
   if "--pause" in OS.get_cmdline_user_args() and not stalled_once and Time.get_ticks_msec()-activated>2000:
    stalled_once=true;OS.delay_msec(1400)
   actor_tick+=1
   if actor_tick%60==0:input.skill_slot=(actor_tick/60)%4
   session.advance_controls(input,dt)
   if Time.get_ticks_msec()-activated>7000:
    var distance:float=session.presentation_position(slot).distance_to(first)
    if "--diagnostics" in OS.get_cmdline_user_args() and not diagnostic_done:
     if not diagnostic_started:diagnostic_started=true;_diagnostic_roundtrip.call_deferred()
     return false
    print("NETFOX ROOM CLIENT distance=",distance," tick=",session.own_actor.last_prediction_tick," state_tick=",session.server_state.tick," net=",session.netfox_metrics()," inbox=",session.server_state.meta.input_clock," connected=",session.connected)
    var okay:bool=distance>.1 and session.own_actor.last_prediction_tick>100 and session.own_actor.sync.get_last_known_state()>100 and session.connected and (epoch_seen>=2 if "--epoch" in OS.get_cmdline_user_args() else true)
    if ("--companion" in OS.get_cmdline_user_args() or "--companion-delay" in OS.get_cmdline_user_args()):
     okay=okay and companion_depart_sent and session.server_state.meta.players.has(2) and not session.profile_for(2).name.is_empty() and session.presentation_position(2).distance_to(companion_first)>0.1
     print("COMPANION NETFOX remote_moved=",session.presentation_position(2).distance_to(companion_first)," named=",session.profile_for(2).name)
    if "--quiet-states" in OS.get_cmdline_user_args():
     # Two seconds with no authority publication must not replay the unchanged
     # owner history on every client frame. Fresh authority must resume normally.
     okay=okay and session.own_actor.sync.redundant_replay_ticks_avoided>100 and session.own_actor.prediction_ticks<1500
    if "--pause" in OS.get_cmdline_user_args():
     var net=session.netfox_metrics()
     var reasons:Dictionary=session.server_state.meta.input_clock.rejection_reasons
     okay=okay and stalled_once and absi(net.network_tick-net.reference_tick)<=4 and int(reasons.get("future_window",0))==0 and int(reasons.get("past_history",0))==0
    session.enter_camp();quit(0 if okay else 5)
 return false

func _diagnostic_roundtrip()->void:
 OS.delay_msec(160)
 await process_frame
 var report:Dictionary=await session.diagnostic_report()
 assert(report.reference.room==session.admission.room)
 assert(report.worker_capture_status=="received")
 assert(report.worker.reference.player==session.player_id())
 assert(not report.client.live.samples.is_empty() and not report.worker.live.samples.is_empty())
 var client_kinds:Array=[];var worker_kinds:Array=[]
 for e in report.client.live.events:client_kinds.append(e.kind)
 for e in report.worker.live.events:worker_kinds.append(e.kind)
 var injected_correction:=false
 for e in report.client.live.events:
  if e.kind=="correction" and float(e.value.get("distance_m",0))>.25:injected_correction=true
 assert(injected_correction)
 assert("capture" in client_kinds and "wire_send" in client_kinds and "metadata" in client_kinds)
 assert("wire_receive" in worker_kinds and "input_used" in worker_kinds and "snapshot_send" in worker_kinds)
 var stages:Array=[]
 for e in report.client.live.events:
  if e.kind=="app_echo":stages.append(e.value.stage)
 assert("receipt" in stages and "after_tick" in stages)
 var encoded=preload("res://runtime/diagnostics/report_codec.gd").encode(report)
 assert(encoded.ok and not preload("res://runtime/diagnostics/report_codec.gd").decode(encoded).is_empty())
 var output=OS.get_environment("ZORX_DIAGNOSTIC_REPORT_FILE")
 if not output.is_empty():
  var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
 print("DIAGNOSTIC REAL ROOM CAPTURE PASS compressed_chars=",encoded.data.length()," worker_rows=",report.worker.live.samples.size()," client_rows=",report.client.live.samples.size())
 diagnostic_done=true
