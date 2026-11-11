extends SceneTree
## LOCALHOST protocol/adapter contract, never evidence of Internet gameplay latency.
var server:=false
var actor
var arena:Node
var connected_at:=0
var start_ms:=0
var done:=false
func _initialize()->void:call_deferred("_run")
func _run()->void:
 server="--server" in OS.get_cmdline_user_args();start_ms=Time.get_ticks_msec()
 var peer=WebSocketMultiplayerPeer.new()
 arena=Node.new();arena.name="Arena";root.add_child(arena)
 if server:
  if peer.create_server(19477,"127.0.0.1")!=OK:quit(2);return
 else:
  if peer.create_client("ws://127.0.0.1:19477")!=OK:quit(3);return
 root.multiplayer.multiplayer_peer=peer
 if server:
  root.multiplayer.peer_connected.connect(func(id:int):_make_actor(id))
  root.get_node("NetworkTime").start()
 else:
  root.multiplayer.connected_to_server.connect(func():
   _make_actor(root.multiplayer.get_unique_id())
   root.get_node("NetworkTime").start()
  )
func _make_actor(owner:int)->void:
 connected_at=Time.get_ticks_msec()
 var sim=preload("res://logic/game_sim.gd").new(preload("res://logic/sim_world.gd").new(),preload("res://logic/combat_data_loader.gd").load_default(),RandomNumberGenerator.new())
 sim.world.half_width=100;sim.world.half_depth=100
 sim.add_player(1,Vector3.ZERO)
 actor=load("res://actor_bridge.gd").new();actor.name="Player"
 actor.configure(sim,1,owner)
 var frame=preload("res://logic/sim_input.gd").new()
 if not server:frame.move=Vector2.RIGHT
 actor.get_node("Input").payload=frame.encode()
 arena.add_child(actor)
func _process(_dt:float)->bool:
 if done:return false
 if Time.get_ticks_msec()-start_ms>12000:done=true;printerr("PEER CONTRACT TIMEOUT");quit(4);return false
 if actor!=null and Time.get_ticks_msec()-connected_at>4000:
  done=true
  var frame=preload("res://logic/sim_input.gd").decode(actor.get_node("Input").payload)
  var received_state_tick:int=actor.get_node("Rollback")._history_transmitter.get_latest_state_tick()
  var ok:bool=actor.rollback_calls>30 and actor.simulation.bodies[1].position.x>0.1 and frame!=null and frame.move==Vector2.RIGHT and (server or received_state_tick>60)
  print("NETFOX PEER CONTRACT ","server" if server else "client"," ok=",ok," actor_x=",actor.simulation.bodies[1].position.x," rollback_calls=",actor.rollback_calls," received_state_tick=",received_state_tick)
  # Do not conflate matching APIs/local transport with Web/co-op/security acceptance.
  quit(0 if ok else 5)
 return false
