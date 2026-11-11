extends RefCounted
## Client collector: measures local scheduling separately from application RTT.
var recorder=preload("res://runtime/diagnostics/flight_recorder.gd").new()
var session
var _last_poll:=-1
var _last_sample:=0
var _last_correction:=0
var _last_trigger:=""
var worker:Dictionary={}
var worker_capture_id:=""
var worker_capture_at:=-1
var capture_pending:=false
var _next_request:=0
var _context:Dictionary={}
func configure(owner)->void:session=owner
func poll()->void:
 var now:=Time.get_ticks_msec()
 if _last_poll>=0 and now-_last_poll>100:_trigger("client_schedule_gap",{"gap_ms":now-_last_poll},now)
 var frame_ms:=now-_last_poll if _last_poll>=0 else -1;_last_poll=now
 var actor=session.own_actor
 if actor!=null and actor.correction_count>_last_correction:
  _last_correction=actor.correction_count
  recorder.record("correction",{"input_tick":actor.correction_tick,"distance_m":actor.correction_last_m,"state":actor.correction_state},now)
  if actor.correction_last_m>.25:_trigger("correction",{"distance_m":actor.correction_last_m},now)
 var socket:WebSocketPeer=session.net_peer.get_peer(1) if session.connected and session.net_peer!=null else null
 var outbound:int=socket.get_current_outbound_buffered_amount() if socket!=null else 0
 if outbound>65536:_trigger("outbound_queue",{"bytes":outbound},now)
 var age:int=maxi(0,now-session._received_at)
 if session.ready and not session.server_state.get("meta",{}).get("scene_loading",false) and age>500:_trigger("snapshot_gap",{"age_ms":age},now)
 if now-_last_sample>=250:
  _last_sample=now
  var net:Dictionary=session.netfox_metrics()
  var remote_age:=-1.0;var remote_gap:=-1.0
  for entity in session.net_entities.values():
   var sync=entity.synchronizer
   if sync._latest_seen>=0:
    remote_age=maxf(remote_age,float(net.network_tick-sync._latest_seen)*1000.0/60.0)
    remote_gap=maxf(remote_gap,maxf(0.0,float(net.network_tick)+float(NetworkTime.tick_factor)-sync._delay-float(sync._latest_seen))*1000.0/60.0)
  var values={"frame_ms":frame_ms,"snapshot_age_ms":age,"outbound_bytes":outbound,"network_tick":net.network_tick,"reference_tick":net.reference_tick,"authority_tick":net.authoritative_tick,"snapshot_world_tick":session.server_state.get("tick",0),"entities":session.net_entities.size(),"projectiles":session.server_state.get("projectiles",[]).size(),"areas":session.server_state.get("areas",[]).size()}
  if session._last_pong>=0:values["app_rtt_ms"]=session.rtt_ms
  if remote_age>=0:values["remote_snapshot_age_ms"]=remote_age;values["interpolation_starvation_ms"]=remote_gap
  if remote_gap>300 and session.ready and not session.saved and not session.server_state.get("meta",{}).get("scene_loading",false):_trigger("interpolation_starvation",{"gap_ms":remote_gap},now)
  if actor!=null:values["input_edge_queue"]=actor.get_node("Input").edges.size()
  recorder.sample(values,{"prediction_us":actor.prediction_us if actor!=null else 0,"restore_us":actor.restore_us if actor!=null else 0,"metadata_decode_us":session.lag_decode_us,"metadata_apply_us":session.metadata_apply_us,"metadata_bytes":session._metadata_bytes,"authority_payload_bytes":actor.state_payload_bytes if actor!=null else 0,"authority_packets":actor.state_packets if actor!=null else 0,"authority_decode_us":actor.state_decode_us if actor!=null else 0,"input_rpc_calls":actor.input_send_calls if actor!=null else 0},now)
  _context={"map":session.server_state.get("meta",{}).get("map",""),"epoch":session.scene_epoch(),"mode":"netfox_authoritative_room","worker_release":net.worker_release,"scene_loading":session.server_state.get("meta",{}).get("scene_loading",false),"saved":session.saved}
  if OS.has_feature("web"):
   var raw=JavaScriptBridge.eval("JSON.stringify({visibility:document.visibilityState,focused:document.hasFocus(),longtask_supported:!!(window.zorxInputWork&&window.zorxInputWork.supported),tasks:window.zorxInputWork?window.zorxInputWork.tasks:[]})",true)
   var browser=JSON.parse_string(str(raw))
   if browser is Dictionary:_context["browser"]=browser
 if recorder.advance(now):request_worker_capture()
func _trigger(reason:String,values:Dictionary,now:int)->void:
 if recorder.trigger(reason,values,now):
  _last_trigger=reason
  if reason=="client_schedule_gap":recorder.record("stall_scopes",session.input_trace.work.gap(_last_poll*1000,now*1000))
func request_worker_capture()->bool:
 var now:=Time.get_ticks_msec()
 if capture_pending or not session.connected or now<_next_request:return false
 worker_capture_id=Crypto.new().generate_random_bytes(16).hex_encode();capture_pending=true;_next_request=now+5000
 session.net_bus.control.rpc_id(1,{"diagnostic_capture":worker_capture_id})
 return true
func accept_worker(value:Dictionary)->void:
 if value.get("id")!=worker_capture_id:return
 var decoded=preload("res://runtime/diagnostics/report_codec.gd").decode(value.get("capture",{}))
 if not decoded.has("worker"):capture_pending=false;return
 worker=decoded.worker;worker_capture_at=Time.get_ticks_msec();capture_pending=false
func report()->Dictionary:
 var begin:=Time.get_ticks_msec()
 request_worker_capture()
 while capture_pending and Time.get_ticks_msec()-begin<3500:
  await Engine.get_main_loop().process_frame
 if capture_pending:capture_pending=false
 var build={}
 if FileAccess.file_exists("res://data/ui/build_info.json"):build=JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/build_info.json"))
 if OS.has_feature("web"):
  build["content_build"]=JavaScriptBridge.eval("window.zorxBoot && window.zorxBoot.manifest ? window.zorxBoot.manifest.build : null",true)
 var runtime=Engine.get_main_loop().get_root()
 var client=recorder.export_data()
 client["context"]=_context.duplicate(true)
 if session.profile!=null:client["context"]["skill_build"]=session.profile.skill_build.duplicate(true)
 client["graphics"]=preload("res://client/graphics_options.gd").snapshot()
 client["render"]={"viewport":[runtime.size.x,runtime.size.y],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
 var ref={"room":str(session.admission.get("room","")),"player":session.player_id(),"epoch":session.scene_epoch(),"key":"room/player/epoch/input_tick"}
 return {"v":2,"reference":ref,"build":build,"client":client,"worker":worker.duplicate(true),"worker_capture_age_ms":Time.get_ticks_msec()-worker_capture_at if worker_capture_at>=0 else null,"worker_capture_status":"received" if worker_capture_at>=begin else "cached" if worker_capture_at>=0 else "unavailable","clock_contract":"timestamps are independent per process; never subtract client and worker timestamps; app RTT includes scheduling, receipt and after_tick RTT are measured on client","last_trigger":_last_trigger,"thresholds":{"client_gap_ms":100,"worker_gap_ms":100,"snapshot_gap_ms":500,"correction_m":.25,"outbound_bytes":65536,"interpolation_starvation_ms":300,"worker_step_ms":25},"sampling":{"values_ms":250,"held_input_ticks":12,"action_inputs":"all","scope":"30s or explicit bounded ring cap; oldest details may be removed with marker when encoding"}}
