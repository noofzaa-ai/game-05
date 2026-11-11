extends Node
## RPC surface is identical on both ends; server/client handlers are injected locally.
var on_control:Callable
var on_ready:Callable
var on_state:Callable
var on_reply:Callable
@rpc("any_peer","call_remote","reliable")
func control(value:Dictionary)->void:
 if not multiplayer.is_server() or not on_control.is_valid() or var_to_bytes(value).size()>65536:return
 on_control.call(multiplayer.get_remote_sender_id(),value)
@rpc("any_peer","call_remote","reliable")
func replica_ready(epoch:int)->void:
 if multiplayer.is_server() and on_ready.is_valid():on_ready.call(multiplayer.get_remote_sender_id(),epoch)
@rpc("authority","call_remote","reliable")
func snapshot(bytes:PackedByteArray)->void:
 if not multiplayer.is_server() and on_state.is_valid() and bytes.size()<=524288:on_state.call(bytes)
@rpc("authority","call_remote","reliable")
func reply(bytes:PackedByteArray)->void:
 if not multiplayer.is_server() and on_reply.is_valid() and bytes.size()<=65536:on_reply.call(bytes)
