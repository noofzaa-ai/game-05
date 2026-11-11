extends RefCounted
## Only legacy command receipts use Wire here; gameplay inputs/state use Godot multiplayer.
var peer_id:int
var endpoint
var bus
var outbound_buffer_size:=524288
func get_ready_state()->int:
 if not endpoint.gate.admitted.has(peer_id) or peer_id not in endpoint.api.get_peers():return WebSocketPeer.STATE_CLOSED
 var socket:WebSocketPeer=endpoint.peer.get_peer(peer_id)
 return socket.get_ready_state() if socket!=null else WebSocketPeer.STATE_CLOSED
func get_current_outbound_buffered_amount()->int:return 0
func send_text(_text:String)->Error:return OK # SceneMultiplayer authentication already sent admission.
func put_packet(bytes:PackedByteArray)->Error:
 if get_ready_state()!=WebSocketPeer.STATE_OPEN:return ERR_CONNECTION_ERROR
 bus.reply.rpc_id(peer_id,bytes);return OK
func close(_code:int=1000,_reason:String="")->void:endpoint.api.disconnect_peer(peer_id)
