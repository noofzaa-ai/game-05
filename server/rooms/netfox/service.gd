extends Node
## Netfox gameplay transport + existing trusted Room/Nakama lifecycle. Sole online gameplay transport.
var endpoint
var lease
var manager
var bus
var groups:Dictionary={}
var accepted:Dictionary={}
var _control_rates:Dictionary={}
var _diagnostic_requests:Dictionary={}
var _capture_at:Dictionary={}
var _probes:Dictionary={}
var _last_process_ms:=-1
var _recorders:Dictionary={}
var base_transport
func configure(tree:SceneTree,room_manager,existing_transport)->void:
 manager=room_manager;base_transport=existing_transport
 endpoint=preload("res://server/rooms/netfox/endpoint.gd").new();endpoint.name="Endpoint";endpoint.scope_root=false;add_child(endpoint)
 endpoint.redeem=existing_transport.backend
 endpoint.member_admitted.connect(_admitted);endpoint.member_left.connect(_left)
 bus=preload("res://runtime/netfox/bus.gd").new();bus.name="Bus";add_child(bus)
 bus.on_control=_control;bus.on_ready=_replica_ready
 lease=preload("res://server/rooms/netfox/lease.gd").new(tree,room_manager)
 lease.backend_delegate=existing_transport.backend;lease.state_delegate=_snapshot
func start(port:int,address:String="0.0.0.0")->Error:
 var result:Error=endpoint.listen(port,address)
 if result!=OK:return result
 # Netfox singletons use the process multiplayer API; all rooms are isolated by peer visibility.
 get_node("/root/NetworkTime").on_tick.connect(_tick)
 get_node("/root/NetworkTime").start()
 return OK
func _admitted(id:int,_binding:Dictionary,result:Dictionary)->void:
 var proxy=preload("res://server/rooms/netfox/socket_proxy.gd").new();proxy.peer_id=id;proxy.endpoint=endpoint;proxy.bus=bus
 lease.peers[id]={"ws":proxy,"room":"","slot":0,"out_seq":0,"in_seq":0,"baseline":0,"states":{},"state_times":{},"event_ack":0,"last_send":0,"leaving":false}
 lease.bind_redeemed(id,result)
func _left(id:int,_binding:Dictionary)->void:
 accepted.erase(id);_control_rates.erase(id);_diagnostic_requests.erase(id);_capture_at.erase(id);_probes.erase(id);_recorders.erase(id)
 if lease.peers.has(id):lease._drop(id,Time.get_ticks_msec())
func _process(_delta:float)->void:
 var process_now:=Time.get_ticks_msec()
 var process_gap:=process_now-_last_process_ms if _last_process_ms>=0 else 0;_last_process_ms=process_now
 for group in groups.values():
  for actor in group.actors.values():
   if process_gap>100:actor.diagnostic.record("worker_schedule_gap",{"gap_ms":process_gap});actor.diagnostic.trigger("worker_schedule_gap",{"gap_ms":process_gap})
   actor.diagnostic.advance(process_now)
 if lease!=null:
  endpoint.gate.maintenance=base_transport.maintenance if base_transport.get("maintenance")!=null else false
  lease.poll(Time.get_ticks_msec())
  for room_id in groups.keys():
   if not manager.rooms.has(room_id):groups[room_id].node.queue_free();groups.erase(room_id)
func _room_group(room):
 var id:String=""
 for key in manager.rooms:
  if manager.rooms[key].room==room:id=key;break
 if id.is_empty():return null
 if groups.has(id) and groups[id].epoch==room.epoch:return groups[id]
 if groups.has(id):
  for actor in groups[id].actors.values():actor.retire()
  for entity in groups[id].entities.values():entity.synchronizer.suspended=true
  get_tree().create_timer(2).timeout.connect(groups[id].node.queue_free)
  groups.erase(id)
 var node=Node.new();node.name="R"+id+"E"+str(room.epoch);add_child(node)
 var group={"node":node,"epoch":room.epoch,"base_tick":get_node("/root/NetworkTime").tick-room.clock_tick,"actors":{},"entities":{},"started":false}
 groups[id]=group
 return group
func _sync_nodes(room,group)->void:
 var peers:Array=[]
 for id in lease.peers:
  if lease.peers[id].room in lease.bindings and lease.bindings[lease.peers[id].room].room_obj==room:peers.append(id)
 for id in room.sim.bodies:
  if not group.entities.has(id):
   var entity=preload("res://runtime/netfox/entity.gd").new();entity.name="Entity"+str(id);group.node.add_child(entity)
   entity.configure(room.sim.bodies[id].position,[]);group.entities[id]=entity
   for peer in peers:
    if accepted.get(peer,0)==room.epoch:entity.synchronizer.visibility_filter.set_visibility_for(peer,true)
   entity.synchronizer.visibility_filter.update_visibility()
 for peer in peers:
  var slot:int=lease.peers[peer].slot
  if not group.actors.has(slot) or group.actors[slot].get_node("Input").get_multiplayer_authority()!=peer:
   if group.actors.has(slot):group.actors[slot].free()
   var actor=preload("res://runtime/netfox/actor.gd").new();actor.name="Actor"+str(slot);group.node.add_child(actor)
   actor.configure(room.sim,slot,room.epoch,peer,room);group.actors[slot]=actor
   if not _recorders.has(peer):_recorders[peer]=actor.diagnostic
   actor.diagnostic=_recorders[peer]
   actor.diagnostic.record("scene_epoch",{"epoch":room.epoch,"world_tick":room.clock_tick})
   actor.sync.visibility_filter.set_visibility_for(peer,false)
 for actor in group.actors.values():actor.authority_room=room;actor.simulation=room.sim
func _tick(_dt:float,tick:int)->void:
 var now:=Time.get_ticks_msec()
 for id in lease.bindings:
  var binding:Dictionary=lease.bindings[id]
  if not binding.started or binding.saved or binding.room_obj==null:continue
  var room=binding.room_obj
  var group=_room_group(room)
  if group==null:continue
  _sync_nodes(room,group)
  if room.scene_loading():group.base_tick=tick-room.clock_tick
  if not room.scene_loading() and room.status!="finished":
   for actor_id in group.actors:
    var actor=group.actors[actor_id]
    actor.collect_input(tick,now)
    var repeat_input:bool=actor.inbox._consumed_tick==actor.inbox.latest_tick
    var consumed:Dictionary=actor.inbox.consume(now)
    if tick%12==0 or int(consumed.get("action_tick",-1))>=0:
     actor.set_meta("diag_used",consumed.input_tick)
     actor.diagnostic.record("input_used",{"input_tick":consumed.input_tick,"action_tick":consumed.get("action_tick",-1),"world_tick":room.clock_tick+1,"network_tick":tick,"epoch":room.epoch,"receipt_to_use_ms":maxi(0,now-actor.inbox.last_received_at) if actor.inbox.last_received_at>=0 else null,"held":repeat_input})
    room.input(actor_id,room.clock_tick+1,consumed.frame.encode(),int(consumed.view))
   var step_start:=Time.get_ticks_usec()
   room.tick()
   var step_ms:float=(Time.get_ticks_usec()-step_start)/1000.0
   for actor in group.actors.values():
    actor.diagnostic.sample({"worker_step_ms":step_ms,"network_tick":tick,"world_tick":room.clock_tick,"epoch":room.epoch,"entities":room.sim.bodies.size(),"projectiles":room.sim.projectiles.size(),"areas":room.sim.areas.size(),"input_edge_queue":actor.inbox.actions.size(),"input_age_ms":maxi(0,now-actor.inbox.last_received_at) if actor.inbox.last_received_at>=0 else null})
    if step_ms>25:actor.diagnostic.trigger("worker_step",{"ms":step_ms})
  for entity_id in group.entities:
   if room.sim.bodies.has(entity_id):group.entities[entity_id].position=room.sim.bodies[entity_id].position
  preload("res://runtime/netfox/entity_prune.gd").prune(group.entities,room.sim.bodies)
 for peer in _probes.keys():
  if peer in endpoint.api.get_peers():
   var probe:Dictionary=_probes[peer]
   var echo=preload("res://logic/net_wire.gd").packet(6,1,{"nonce":probe.nonce,"echo_stage":"after_tick","worker_wait_ms":maxi(0,Time.get_ticks_msec()-int(probe.at)),"worker_tick":tick})
   bus.reply.rpc_id(peer,echo)
  _probes.erase(peer)
func _snapshot(peer:int,room)->void:
 if peer not in endpoint.api.get_peers() or not lease.peers.has(peer) or lease.peers[peer].ws.get_ready_state()!=WebSocketPeer.STATE_OPEN:return
 # Keep room-control metadata from building an unbounded reliable backlog.
 # Skipped snapshots are replaced by the next current authoritative snapshot.
 var socket:WebSocketPeer=endpoint.peer.get_peer(peer)
 if socket==null or socket.get_current_outbound_buffered_amount()>=65536:return
 var group=_room_group(room)
 if group==null:return
 _sync_nodes(room,group)
 var slot:int=lease.peers[peer].slot
 var metadata_start:=Time.get_ticks_usec()
 var state:Dictionary=room.public_state(slot)
 # `state` is this peer's own fresh deep copy (room.public_state() duplicates it per call),
 # so mutating it here is safe and affects nobody else. See runtime/netfox/profile_diff.gd.
 preload("res://runtime/netfox/profile_diff.gd").send_only_on_change(state.meta.profiles,slot,lease.peers[peer])
 var actor=group.actors.get(slot)
 if actor!=null:
  state.meta["input_clock"]={"mode":"netfox_receipt_inbox","source_input_tick":actor.inbox.latest_tick,"accepted_inputs":actor.inbox.accepted,"held_ticks":actor.inbox.repeated,"queued_actions":actor.inbox.actions.size(),"consumed_actions":actor.inbox.consumed_actions,"rejected_input_packets":actor.sync._history_transmitter.rejected_inputs,"rejection_reasons":actor.sync._history_transmitter.rejection_reasons.duplicate(),"input_delta":actor.sync._history_transmitter.last_input_delta,"input_shape":actor.sync._history_transmitter.last_input_shape}
 if state.meta.has("input_clock"):
  state.meta.input_clock["event_batches"]=int(lease.peers[peer].get("event_batches",0))
  state.meta.input_clock["event_records"]=int(lease.peers[peer].get("event_records",0))
 # protocol 4: entity rows carry skill_net/race_net (logic/net/skill_net.gd, wire v3).
 # protocol 3: meta.profiles[own slot] may be {"v":0} meaning "unchanged, reuse your last
 # copy" instead of a full profile. Bumped so a stale cached client (old build) cleanly
 # ignores snapshots via the existing protocol check instead of silently failing to decode
 # a sentinel it doesn't understand.
 state["netfox"]={"protocol":4,"peer":peer,"base_tick":group.base_tick,"group":str(group.node.name),"worker_release":OS.get_environment("ZORX_WORKER_RELEASE"),"network_tick":get_node("/root/NetworkTime").tick,"reference_tick":get_node("/root/NetworkTime").seconds_to_ticks(get_node("/root/NetworkTimeSynchronizer").get_time())}
 if accepted.get(peer,0)!=room.epoch:
  state.netfox["continuation"]=preload("res://logic/net/actor_continuation.gd").capture(room.sim,slot)
 var packed:=preload("res://logic/net/compressed_blob.gd").pack(var_to_bytes(state))
 bus.snapshot.rpc_id(peer,packed)
 if actor!=null and Time.get_ticks_msec()-actor.last_diag_snapshot_ms>=250:
  actor.last_diag_snapshot_ms=Time.get_ticks_msec()
  actor.diagnostic.record("snapshot_send",{"input_tick":actor.inbox.latest_tick,"world_tick":room.clock_tick,"epoch":room.epoch,"network_tick":get_node("/root/NetworkTime").tick,"bytes":packed.size(),"outbound_bytes":socket.get_current_outbound_buffered_amount(),"encode_us":Time.get_ticks_usec()-metadata_start})
 if _diagnostic_requests.has(peer):
  var request:Dictionary=_diagnostic_requests[peer];_diagnostic_requests.erase(peer)
  var capture:Dictionary=actor.diagnostic.export_data() if actor!=null else {"availability":"actor_unavailable"}
  capture["reference"]={"room":str(lease.peers[peer].room),"player":slot,"epoch":room.epoch}
  capture["release"]=OS.get_environment("ZORX_WORKER_RELEASE")
  var encoded:=preload("res://runtime/diagnostics/report_codec.gd").encode({"worker":capture})
  var raw:=var_to_bytes({"diagnostic_capture":{"id":request.id,"capture":encoded}})
  if raw.size()<=262144:bus.snapshot.rpc_id(peer,preload("res://logic/net/compressed_blob.gd").pack(raw))
 preload("res://server/rooms/netfox/event_delivery.gd").flush(lease.peers[peer],room.events,slot,
  func(packet:PackedByteArray)->bool:
   if peer not in endpoint.api.get_peers() or socket.get_ready_state()!=WebSocketPeer.STATE_OPEN:return false
   bus.reply.rpc_id(peer,packet);return true,
  func()->bool:return peer in endpoint.api.get_peers() and socket.get_ready_state()==WebSocketPeer.STATE_OPEN and socket.get_current_outbound_buffered_amount()<65536)
func _replica_ready(peer:int,epoch:int)->void:
 var route:Dictionary=endpoint.gate.route(peer)
 if route.is_empty() or not lease.bindings.has(route.room):return
 var room=lease.bindings[route.room].room_obj
 if room==null or room.epoch!=epoch:return
 var group=_room_group(room)
 accepted[peer]=epoch
 group.actors[route.slot].sync.visibility_filter.set_visibility_for(peer,true);group.actors[route.slot].sync.visibility_filter.update_visibility()
 for entity in group.entities.values():entity.synchronizer.visibility_filter.set_visibility_for(peer,true);entity.synchronizer.visibility_filter.update_visibility()
func _control(peer:int,value:Dictionary)->void:
 if endpoint.gate.route(peer).is_empty() or not lease.peers.has(peer):return
 var now:=Time.get_ticks_msec()
 var budget:Dictionary=_control_rates.get(peer,{"at":now,"count":0})
 if now-budget.at>=1000:budget={"at":now,"count":0}
 budget.count+=1;_control_rates[peer]=budget
 if budget.count>60:endpoint.api.disconnect_peer(peer);return
 if value.size()==2 and value.get("netfox_ping")==true and value.get("nonce") is int:
  _probes[peer]={"nonce":value.nonce,"at":now}
  var echo=preload("res://logic/net_wire.gd").packet(6,1,{"nonce":value.nonce,"echo_stage":"receipt","worker_tick":get_node("/root/NetworkTime").tick})
  bus.reply.rpc_id(peer,echo);return
 if value.size()==1 and value.get("diagnostic_capture") is String:
  var id:String=value.diagnostic_capture
  if RegEx.create_from_string("^[a-f0-9]{32}$").search(id)!=null and now-int(_capture_at.get(peer,-5000))>=5000:
   _capture_at[peer]=now;_diagnostic_requests[peer]={"id":id}
  return
 if value.size()==1 and value.get("event_ack") is int and value.event_ack>=0:
  var room=lease._room(lease.peers[peer].room)
  if room!=null:lease.peers[peer].event_ack=mini(value.event_ack,room.event_sequence)
  return
 var sequence:int=lease.peers[peer].in_seq+1
 var wire=preload("res://logic/net_wire.gd")
 var packet:PackedByteArray=wire.packet(wire.CONTROL,sequence,value)
 if not packet.is_empty():lease._receive(peer,packet,Time.get_ticks_msec())
