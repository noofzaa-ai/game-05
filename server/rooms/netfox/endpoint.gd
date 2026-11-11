extends Node
## Standard Godot multiplayer endpoint. Not enabled by the live worker until Room integration.
signal member_admitted(peer:int,binding:Dictionary,trusted_result:Dictionary)
signal member_left(peer:int,binding:Dictionary)
var gate=preload("res://server/rooms/netfox/admission.gd").new()
var peer:=WebSocketMultiplayerPeer.new()
var api:=SceneMultiplayer.new()
var redeem:Callable
var active:=false
var scope_root:=true
func listen(port:int,address:String="127.0.0.1")->Error:
 if active or not redeem.is_valid() or not is_inside_tree():return ERR_UNCONFIGURED
 peer.inbound_buffer_size=1048576;peer.outbound_buffer_size=1048576
 var error:=peer.create_server(port,address)
 if error!=OK:return error
 api.allow_object_decoding=false
 api.auth_timeout=3.0
 api.auth_callback=_authenticate
 api.peer_authenticating.connect(_begin)
 api.peer_authentication_failed.connect(_failed)
 api.peer_disconnected.connect(_left)
 api.multiplayer_peer=peer
 # All replicated nodes for this endpoint must live under this scoped root.
 get_tree().set_multiplayer(api,get_path() if scope_root else NodePath(""))
 active=true
 return OK
func _process(_delta:float)->void:
 if not active:return
 # SceneTree polls its registered SceneMultiplayer once per frame.
 for id in gate.expired(Time.get_ticks_msec()):
  api.disconnect_peer(id);gate.drop(id)
func _begin(id:int)->void:
 if not gate.begin(id,Time.get_ticks_msec()):api.disconnect_peer(id)
func _authenticate(id:int,bytes:PackedByteArray)->void:
 var request:Dictionary=gate.request(id,bytes)
 if request.is_empty():api.disconnect_peer(id);gate.drop(id);return
 var result:Dictionary=await redeem.call(request)
 for attempt in 2:
  if result.get("error")!="conflict":break
  result=await redeem.call(request)
 var binding:Dictionary=gate.complete(id,result)
 if binding.is_empty():
  api.disconnect_peer(id);gate.drop(id);return
 var previous:int=binding.replaced_peer
 if previous>1 and previous!=id:api.disconnect_peer(previous);gate.drop(previous)
 # Trusted result remains local. Auth reply has no inventory, ticket, secret or backend fence.
 var reply={"v":2,"ok":true,"room":binding.room,"slot":binding.slot,"peer":id}
 api.send_auth(id,JSON.stringify(reply).to_utf8_buffer())
 var error:=api.complete_auth(id)
 if error!=OK:api.disconnect_peer(id);gate.drop(id);return
 member_admitted.emit(id,binding,result)
func _failed(id:int)->void:gate.drop(id)
func _left(id:int)->void:
 var binding:Dictionary=gate.route(id)
 gate.drop(id)
 if not binding.is_empty():member_left.emit(id,binding)
func _exit_tree()->void:
 active=false
 peer.close()
