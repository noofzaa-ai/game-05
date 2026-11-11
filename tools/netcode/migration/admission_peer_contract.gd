extends SceneTree
## Local authentication protocol contract; fixture backend, no account/login/persistence claims.
var server:=false
var endpoint
var api:SceneMultiplayer
var connected:=false
var started:=0
var auth_ok:=false
func _initialize()->void:call_deferred("_run")
func _run()->void:
 server="--server" in OS.get_cmdline_user_args();started=Time.get_ticks_msec()
 if server:
  endpoint=load("res://server/rooms/netfox/endpoint.gd").new();endpoint.name="Endpoint";root.add_child(endpoint)
  endpoint.redeem=func(request:Dictionary)->Dictionary:
   await create_timer(.05).timeout
   return {"ok":request.ticket=="a".repeat(64),"room":request.room,"slot":1,"capacity":1,"profile":{"v":1},"fence":"serverfixture"}
  endpoint.member_admitted.connect(func(_id,binding,_result):auth_ok=binding.slot==1)
  assert(endpoint.listen(19478,"127.0.0.1")==OK)
 else:
  var node=Node.new();node.name="Endpoint";root.add_child(node)
  api=SceneMultiplayer.new();api.auth_timeout=3.0;api.allow_object_decoding=false
  var peer=WebSocketMultiplayerPeer.new();assert(peer.create_client("ws://127.0.0.1:19478")==OK)
  api.peer_authenticating.connect(func(id:int):api.send_auth(id,JSON.stringify({"v":2,"room":"0123456789abcdef0123456789abcdef","ticket":"a".repeat(64)}).to_utf8_buffer()))
  api.auth_callback=func(id:int,bytes:PackedByteArray):
   var value=JSON.parse_string(bytes.get_string_from_utf8())
   auth_ok=value is Dictionary and value.get("slot")==1 and value.size()==5
   if auth_ok:api.complete_auth(id)
  api.connected_to_server.connect(func():connected=true)
  api.multiplayer_peer=peer;set_multiplayer(api,node.get_path())
func _process(_dt:float)->bool:
 if Time.get_ticks_msec()-started>9000:quit(4);return false
 if server and auth_ok and not endpoint.api.get_peers().is_empty():
  print("NETFOX AUTH SERVER PASS: trusted redemption precedes peer admission");quit();return false
 if not server and connected and auth_ok:
  print("NETFOX AUTH CLIENT PASS: scoped SceneMultiplayer handshake; no profile or fence in reply");quit();return false
 return false
