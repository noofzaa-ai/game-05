extends "res://client/session/online_session.gd"
## Actual online session: standard Godot multiplayer + netfox. No legacy input clock/history.
const Blob=preload("res://logic/net/compressed_blob.gd")
var net_root:Node
var net_bus
var net_api:SceneMultiplayer
var net_peer:WebSocketMultiplayerPeer
var group:Node
var own_actor
var net_entities:Dictionary={}
var _received_group:=""
var diagnostics=preload("res://runtime/diagnostics/session_probe.gd").new()
var metadata_apply_us:=0
var _last_metadata_record:=-250
var _diagnostic_hooked:=false
var _pending_pings:Dictionary={}
var _metadata_bytes:=0
var _last_metadata_tick:=-1
var _sent_event_ack:=0
var _netfox_generation:=0
func physics_begin()->void:pass
func _open_socket()->bool:
 _connection_generation+=1;_netfox_generation+=1
 _last_metadata_tick=-1;_sent_event_ack=0;_presented_epoch=0;_last_scene_ack=-1000;ready=false
 _dispose_net()
 net_root=Node.new();net_root.name="NetRuntime";Engine.get_main_loop().root.add_child(net_root)
 net_bus=preload("res://runtime/netfox/bus.gd").new();net_bus.name="Bus";net_root.add_child(net_bus)
 net_bus.on_state=_state_bytes;net_bus.on_reply=_bus_reply
 net_peer=WebSocketMultiplayerPeer.new();net_peer.inbound_buffer_size=1048576;net_peer.outbound_buffer_size=1048576
 net_api=SceneMultiplayer.new();net_api.allow_object_decoding=false;net_api.auth_timeout=5.0
 net_api.peer_authenticating.connect(_auth_begin);net_api.auth_callback=_auth_reply
 net_api.connected_to_server.connect(_connected)
 net_api.server_disconnected.connect(_lost);net_api.connection_failed.connect(_lost)
 net_api.peer_authentication_failed.connect(func(_id):_lost())
 var url:String=str(admission.url)
 if url.ends_with("/room"):url=url.trim_suffix("/room")+"/room-v2"
 elif url.ends_with("/room/"):url=url.trim_suffix("/room/")+"/room-v2"
 elif url.ends_with("/room-v2") or url.ends_with("/room-v2/"):pass
 elif url.begins_with("ws://127.0.0.1:"):url=url.replace(":8060",":8061")
 else:error="unsupported_room_url";return false
 connected=false;connecting=true;_terminal=false;_deliberate_close=false
 var result:=net_peer.create_client(url)
 if result!=OK:return false
 net_api.multiplayer_peer=net_peer;Engine.get_main_loop().set_multiplayer(net_api)
 return true
func _auth_begin(id:int)->void:
 net_api.send_auth(id,JSON.stringify({"v":2,"room":admission.room,"ticket":admission.ticket}).to_utf8_buffer())
func _auth_reply(id:int,bytes:PackedByteArray)->void:
 var value=JSON.parse_string(bytes.get_string_from_utf8())
 if not value is Dictionary or not value.get("ok",false) or value.get("room")!=admission.room or value.get("slot")!=_player_id:return
 admission.erase("ticket");net_api.complete_auth(id)
func _connected()->void:
 connected=true;connecting=false;error="";_disconnected_at=0;_reconnecting=false
 diagnostics.recorder.record("connected",{"epoch":_epoch})
 var clock=net_root.get_node("/root/NetworkTime")
 clock.start()
 connection_changed.emit()
func _lost()->void:
 if _deliberate_close:return
 if net_root!=null:net_root.get_node("/root/NetworkTime").stop()
 connected=false;connecting=false;error="reconnecting";disconnect_count+=1
 diagnostics.recorder.record("disconnected",{"epoch":_epoch,"count":disconnect_count})
 if _disconnected_at==0:_disconnected_at=Time.get_ticks_msec()
 connection_changed.emit()
func _dispose_net()->void:
 var tree=Engine.get_main_loop()
 var clock=tree.root.get_node_or_null("NetworkTime")
 if clock!=null and net_root!=null:clock.stop()
 if net_peer!=null:net_peer.close()
 if net_root!=null and is_instance_valid(net_root):net_root.free()
 if net_api!=null:tree.set_multiplayer(SceneMultiplayer.new())
 net_root=null;group=null;own_actor=null;net_entities.clear();_received_group=""
func _state_bytes(bytes:PackedByteArray)->void:
 var decode_start:=Time.get_ticks_usec()
 var raw:=Blob.unpack(bytes)
 if raw.is_empty():return
 var state=bytes_to_var(raw)
 lag_decode_us+=Time.get_ticks_usec()-decode_start
 if state is Dictionary and state.has("diagnostic_capture"):
  diagnostics.accept_worker(state.diagnostic_capture);return
 if not state is Dictionary or not state.has_all(["tick","epoch","entities","meta","netfox"]):return
 if state.netfox.get("protocol")!=4 or state.epoch<_epoch:return
 if state.epoch==_epoch and state.tick<_last_metadata_tick:return
 _metadata_bytes+=bytes.size();_last_metadata_tick=state.tick;lag_states+=1
 var apply_started:=Time.get_ticks_usec()
 _accept_metadata(state)
 metadata_apply_us+=Time.get_ticks_usec()-apply_started
 if Time.get_ticks_msec()-_last_metadata_record>=250:
  _last_metadata_record=Time.get_ticks_msec()
  diagnostics.recorder.record("metadata",{"epoch":state.epoch,"world_tick":state.tick,"authority_network_tick":state.netfox.get("network_tick",0),"input_ack":state.meta.get("input_clock",{}).get("source_input_tick",-1),"bytes":bytes.size()})
func _accept_metadata(state:Dictionary)->void:
 var initial:=not ready
 var changed:bool=state.epoch!=_epoch or _received_group!=str(state.netfox.group)
 if changed:diagnostics.recorder.record("scene_epoch",{"epoch":state.epoch,"world_tick":state.tick,"scene_loading":state.meta.get("scene_loading",false)})
 var previous_meta:Dictionary=server_state.get("meta",{})
 # Restore our own profile block if the authority sent the "unchanged" sentinel instead of
 # resending it; this must happen before `ownership` below, and before server_state=state,
 # so every downstream read (including online_session.gd's profile_for()) sees the real
 # value exactly as if it had been resent. See runtime/netfox/profile_diff.gd.
 if not preload("res://runtime/netfox/profile_diff.gd").restore_cached(state.meta.profiles,_player_id,previous_meta.get("profiles",{})):return
 var ownership:bool=previous_meta.get("profiles",{})!=state.meta.profiles or previous_meta.get("run",{})!=state.meta.run
 server_state=state;_epoch=state.epoch;_received_at=Time.get_ticks_msec()
 var map=_map
 if map==null or str(map.id)!=str(state.meta.map):map=preload("res://logic/map_loader.gd").load_by_id(state.meta.map)
 if not map.is_valid():error="invalid_map";return
 _map=map
 if changed or _sim==null:_sim=make_sim(state,map)
 else:
  # Presentation owns separate values; metadata must never mutate rollback state by alias.
  # Squad rooms (online-squads chunk 5): the server auto-pilots every card, the client only interpolates.
  if own_actor!=null and not spectating():
   _sim.bodies.erase(_player_id);_sim.fighters.erase(_player_id)
  apply_entities(_sim,state)
 var profiles:Dictionary=state.meta.profiles
 if profile==null or ownership:
  var decoded=Profile.from_dict(profiles[_player_id],rules,camp)
  if decoded==null:return
  if profile==null:profile=decoded
  else:copy_fields(decoded,profile,["stash","vault","loadout","camp_level","facility_levels","farm","appearance","name","created","beta_kit_version","diamonds", "mall_owned", "bonus_stash_slots"])
  var trip=Run.from_dict(state.meta.run,rules,camp,profile)
  if trip==null:return
  run=trip
 journey.update(state.meta,run);saved=bool(state.meta.get("cloud_saved",false))
 _command_id=maxi(_command_id,int(state.meta.get("command_id",0)))
 if changed:
  if group!=null:
   own_actor.retire()
   for entity in net_entities.values():entity.synchronizer.suspended=true
   Engine.get_main_loop().create_timer(2).timeout.connect(group.queue_free)
  group=Node.new();group.name=str(state.netfox.group);net_root.add_child(group);net_entities.clear()
  _received_group=str(group.name)
  var predicted=make_sim(state,map)
  own_actor=preload("res://runtime/netfox/actor.gd").new();own_actor.name="Actor"+str(_player_id);group.add_child(own_actor)
  own_actor.configure(predicted,_player_id,_epoch,int(state.netfox.peer))
  own_actor.diagnostic=diagnostics.recorder
  if state.netfox.has("continuation"):own_actor.continuation=state.netfox.continuation
  _ready_replica.call_deferred(_epoch)
 for id in state.entities:
  if not net_entities.has(id):
   var entity=preload("res://runtime/netfox/entity.gd").new();entity.name="Entity"+str(id);group.add_child(entity);entity.configure(_sim.bodies[id].position,[]);net_entities[id]=entity
 preload("res://runtime/netfox/entity_prune.gd").prune(net_entities,state.entities)
 own_actor.base_tick=state.netfox.base_tick;own_actor.paused=bool(state.meta.get("scene_loading",false)) or state.meta.get("status")=="finished" or spectating()
 _project_owner()
 if ownership:ownership_changed.emit()
 if previous_meta.get("state")!=state.meta.state or previous_meta.get("cloud_saved",false)!=saved:route_changed.emit()
 ready=true
 if initial:state_ready.emit()
 elif changed:stage_changed.emit()
func _ready_replica(epoch:int)->void:
 var generation:=_netfox_generation
 var clock=net_root.get_node("/root/NetworkTime")
 if not clock.is_initial_sync_done():await clock.after_sync
 await Engine.get_main_loop().process_frame
 if generation==_netfox_generation and connected and epoch==_epoch:net_bus.replica_ready.rpc_id(1,epoch)
func _project_owner()->void:
 if spectating():return
 if own_actor==null or own_actor.simulation==null or _sim==null:return
 _sim.bodies[_player_id]=own_actor.simulation.bodies[_player_id]
 _sim.fighters[_player_id]=own_actor.simulation.fighters[_player_id]
 _sim.tick_count=own_actor.simulation.tick_count
func advance_controls(input:SimInput,_elapsed:float)->void:
 input_trace.controls(Time.get_ticks_msec())
 if own_actor!=null and connected and not spectating():own_actor.get_node("Input").push(input,_epoch,_viewed_world_tick())
 if _sim!=null:_sim.events.clear();_sim.events.append_array(_pending_events);_pending_events.clear()
 _project_owner()
func poll(delta:float)->void:
 if not _diagnostic_hooked:
  diagnostics.configure(self);_diagnostic_hooked=true
 diagnostics.poll()
 if own_actor!=null:
  lag_step_us=own_actor.prediction_us
  lag_reconcile_us=own_actor.restore_us
 var now:=Time.get_ticks_msec()
 input_trace.callback(now)
 _project_owner()
 if connected:
  if ready and _presented_epoch==_epoch and now-_last_scene_ack>=1000 and server_state.get("meta",{}).get("scene_waiting",[]).has(_player_id):
   _last_scene_ack=now;_send(Wire.CONTROL,{"scene_ready":_epoch})
  if now-_last_ping>=1000:
   _last_ping=now;_ping_nonce=now;_pending_pings[now]=now
   while _pending_pings.size()>16:_pending_pings.erase(_pending_pings.keys()[0])
   net_bus.control.rpc_id(1,{"nonce":now,"netfox_ping":true})
  if event_ack>_sent_event_ack:
   _sent_event_ack=event_ack;net_bus.control.rpc_id(1,{"event_ack":event_ack})
  for id in _pending_commands:
   if now-_pending_commands[id].sent>1000:_pending_commands[id].sent=now;_send(Wire.CONTROL,{"id":id,"epoch":_pending_commands[id].epoch,"request":_pending_commands[id].request})
 elif _disconnected_at>0 and now-_disconnected_at<30000 and not _reconnecting and now>=_retry_at:
  _reconnecting=true;_retry_at=now+1500;_reconnect()
 elif _disconnected_at>0 and now-_disconnected_at>=30000:error="reconnect_expired"
func _send(kind:int,value:Dictionary)->void:
 if connected and kind==Wire.CONTROL:net_bus.control.rpc_id(1,value)
func _queue_packet(_bytes:PackedByteArray,_now:int)->void:pass
func presentation_position(id:int)->Vector3:
 if own_actor!=null and id==_player_id and not spectating():return own_actor.position
 if net_entities.has(id):return _remote_cast_position(id,net_entities[id])
 return _sim.bodies[id].position if _sim!=null and _sim.bodies.has(id) else Vector3.ZERO
func enter_camp()->void:
 _deliberate_close=true;_dispose_net();connected=false
func netfox_metrics()->Dictionary:
 return {"correction_n":own_actor.correction_count if own_actor!=null else 0,"correction_max_m":snappedf(own_actor.correction_max_m,.001) if own_actor!=null else 0,"correction_last_m":snappedf(own_actor.correction_last_m,.001) if own_actor!=null else 0,"correction_tick":own_actor.correction_tick if own_actor!=null else -1,"correction_state":own_actor.correction_state if own_actor!=null else "","snapshot_age_ms":maxi(0,Time.get_ticks_msec()-_received_at),"protocol":4,"runtime":"netfox-1.35.3","worker_release":server_state.get("netfox",{}).get("worker_release",""),"server_network_tick":server_state.get("netfox",{}).get("network_tick",0),"server_reference_tick":server_state.get("netfox",{}).get("reference_tick",0),"network_tick":net_root.get_node("/root/NetworkTime").tick if net_root!=null else 0,"last_prediction_tick":own_actor.last_prediction_tick if own_actor!=null else 0,"reference_tick":net_root.get_node("/root/NetworkTime").seconds_to_ticks(net_root.get_node("/root/NetworkTimeSynchronizer").get_time()) if net_root!=null else 0,"input_authority":own_actor.get_node("Input").get_multiplayer_authority() if own_actor!=null else 0,"peer_id":net_api.get_unique_id() if net_api!=null and connected else 0,"base_tick":own_actor.base_tick if own_actor!=null else 0,"authoritative_tick":own_actor.sync.get_last_known_state() if own_actor!=null else 0,"prediction_ticks":own_actor.prediction_ticks if own_actor!=null else 0,"prediction_us":own_actor.prediction_us if own_actor!=null else 0,"redundant_replay_ticks_avoided":own_actor.sync.redundant_replay_ticks_avoided if own_actor!=null else 0,"restore_count":own_actor.restore_count if own_actor!=null else 0,"restore_us":own_actor.restore_us if own_actor!=null else 0,"metadata_payload_bytes":_metadata_bytes}
func debug_metrics()->Dictionary:
 return {"netfox":netfox_metrics(),"mode":"netfox_authoritative_room","rewards_saved":saved,"connected":connected,"epoch":_epoch,"server_tick":server_state.get("tick",0),"ping_ms":rtt_ms,"ping_age_ms":Time.get_ticks_msec()-_last_pong if _last_pong>=0 else -1,"error":error}

func _finish_leave(confirmed:bool)->void:
 if _left_emitted:return
 _left_emitted=true;_deliberate_close=true;saved=confirmed;connected=false;connecting=false
 _pending_commands.clear();_dispose_net();party_left.emit()

func _viewed_world_tick()->int:
 if own_actor==null:return int(server_state.get("tick",0))
 var clock=net_root.get_node("/root/NetworkTime")
 return maxi(0,floori(clock.tick+clock.tick_factor-6-own_actor.base_tick))

func _bus_reply(bytes:PackedByteArray)->void:
 var packet:=Wire.parse(bytes)
 if packet.get("kind")==Wire.EVENTS:
  var payload:=Wire.decode(packet.body)
  for record in payload.get("value",{}).get("events",[]):
   var event:Dictionary=record.get("event",{})
   diagnostics.recorder.record("authority_event",{"world_tick":record.get("tick"),"sequence":record.get("sequence"),"type":event.get("type"),"player":event.get("player"),"target":event.get("target"),"move":event.get("move")})
 if packet.get("kind")==Wire.PONG:
  var decoded:=Wire.decode(packet.body)
  var value:Dictionary=decoded.get("value",{})
  if _pending_pings.has(value.get("nonce")):
   var rtt:=Time.get_ticks_msec()-int(_pending_pings[value.nonce])
   diagnostics.recorder.record("app_echo",{"nonce":value.nonce,"stage":value.get("echo_stage","receipt"),"rtt_ms":rtt,"worker_wait_ms":value.get("worker_wait_ms"),"worker_tick":value.get("worker_tick")})
 _receive(bytes,Time.get_ticks_msec())
func diagnostic_report()->Dictionary:
 return await diagnostics.report()

## Remote class-skill casts (logic/net/skill_net.gd): the clip clock and the travel follow the SAME world tick the
## remote body is drawn at (RemoteState.rendered_tick - base_tick), so a Shield Rush/Intercept/Crater Leap/Vault Shot
## clip lands where the body lands. Inside the travel frames the body follows the authority's travel line, but never
## more than TRAVEL_SNAP_M from the sampled position (a wall stop or a late snapshot falls back to the samples).
const TRAVEL_SNAP_M:=0.75
func _remote_cast_position(id:int,entity)->Vector3:
 var sampled:Vector3=entity.position
 if _sim==null or not _sim.fighters.has(id) or own_actor==null or entity.synchronizer==null:return sampled
 var clock:float=float(entity.synchronizer.rendered_tick)-float(own_actor.base_tick) if float(entity.synchronizer.rendered_tick)>=0 else -1.0
 return preload("res://logic/net/skill_net.gd").remote_position(_sim.fighters[id].skill_view,sampled,clock,_sim.world.half_width,_sim.world.half_depth,TRAVEL_SNAP_M)
