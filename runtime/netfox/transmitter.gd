extends _RollbackHistoryTransmitter
## Harden the single input-property boundary; no arbitrary actor/state commands enter here.
var _rate_at:=0
var _rate:=0
var rejected_inputs:=0
var rejection_reasons:Dictionary={}
var last_input_delta:=0
var last_input_shape:Array=[]
func _reject(reason:String)->void:
 rejected_inputs+=1;rejection_reasons[reason]=int(rejection_reasons.get(reason,0))+1
@rpc("any_peer","unreliable","call_remote")
func _submit_input(tick:int,data:Array)->void:
 if not multiplayer.is_server():return
 var sender:=multiplayer.get_remote_sender_id()
 if _input_property_config==null or _input_property_config.get_properties_owned_by(sender).is_empty():return
 var now:=Time.get_ticks_msec()
 if now-_rate_at>=1000:_rate_at=now;_rate=0
 _rate+=1
 for entry in data:
  if entry is PackedByteArray:root.input_payload_bytes+=entry.size()
 last_input_delta=tick-NetworkTime.tick
 last_input_shape=[data.size(),typeof(data.back()) if not data.is_empty() else -1]
 if _rate>120:_reject("rate");return
 if tick<NetworkTime.tick-64:_reject("past_history");return
 if tick>NetworkTime.tick+24:_reject("future_window");return
 if data.is_empty() or data.size()>9:_reject("shape");return
 if typeof(data.back())!=TYPE_INT or int(data.back())<0 or int(data.back())>255:_reject("version");return
 for i in data.size()-1:
  if not data[i] is PackedByteArray or (not data[i].is_empty() and preload("res://runtime/netfox/input_frame.gd").decode(data[i]).is_empty()):_reject("frame");return
 if tick%12==0:root.diagnostic.record("wire_receive",{"input_tick":tick,"epoch":root.epoch,"worker_tick":NetworkTime.tick,"redundant_frames":data.size()-1})
 super._submit_input(tick,data)

# History retains immutable uncompressed values. Compress only on the wire, never
# once per local replay tick. Library state encoder/authority checks stay in use.
func _send_full_state(tick:int,peer:int=0)->void:
 if peer==0:
  for target in multiplayer.get_peers():
   if _peer_open(target):_send_full_state(tick,target)
  return
 if not _peer_open(peer):return
 var data:Array=_full_state_encoder.encode(tick,_get_owned_state_props())
 if data.size()!=2 or not data[0] is PackedByteArray:return
 data[0]=preload("res://logic/net/compressed_blob.gd").pack(data[0])
 _submit_full_state.rpc_id(peer,data,tick)
@rpc("any_peer","unreliable_ordered","call_remote")
func _submit_full_state(data:Array,tick:int)->void:
 if multiplayer.is_server() or multiplayer.get_remote_sender_id()!=1:return
 if data.size()!=2 or not data[0] is PackedByteArray or typeof(data[1])!=TYPE_INT:return
 var decode_start:=Time.get_ticks_usec()
 var raw:=preload("res://logic/net/compressed_blob.gd").unpack(data[0])
 if raw.is_empty():return
 var decoded:Array=[raw,data[1]]
 super._submit_full_state(decoded,tick)
 root.state_decode_us+=Time.get_ticks_usec()-decode_start;root.state_packets+=1;root.state_payload_bytes+=data[0].size()
 if tick%12==0:root.diagnostic.record("authority_state",{"network_tick":tick,"payload_bytes":data[0].size(),"client_tick":NetworkTime.tick})

func _peer_open(peer:int)->bool:
 if peer<=0:return true
 if peer not in multiplayer.get_peers():return false
 var transport=multiplayer.multiplayer_peer
 if transport is WebSocketMultiplayerPeer:
  var socket=transport.get_peer(peer)
  return socket!=null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN and socket.get_current_outbound_buffered_amount()<65536
 return true

func transmit_input(tick:int)->void:
 super.transmit_input(tick)
 if not multiplayer.is_server():root.input_send_calls+=1
 if not multiplayer.is_server() and tick%12==0:
  root.diagnostic.record("wire_send",{"input_tick":tick+NetworkRollback.input_delay,"epoch":root.epoch})
