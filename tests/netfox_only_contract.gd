extends SceneTree
func _initialize():call_deferred("run")
func run():
 var session=load("res://client/session/netfox_session.gd").new()
 assert(session.get_script().get_base_script().resource_path=="res://client/session/online_session.gd")
 assert(session.debug_metrics().mode=="netfox_authoritative_room")
 assert(not session.get_script().get_base_script().has_method("_accept_state"))
 for p in ["client/session/remote_session.gd","client/session/control_clock.gd","client/session/prediction_history.gd","client/session/remote_interpolation.gd","server/rooms/transport.gd"]:
  assert(not FileAccess.file_exists("res://"+p),p)
 var source=FileAccess.get_file_as_string("res://client/game_state.gd")
 assert(source.contains('var session_script = load("res://client/session/netfox_session.gd")'))
 assert(not source.contains("new URLSearchParams"))
 var emitted=[0]
 session.party_left.connect(func():emitted[0]+=1)
 session._leave_requested=true
 session._pending_commands[77]={"request":{"type":"party_leave"},"epoch":1,"sent":0}
 var wire=load("res://logic/net_wire.gd")
 session._receive(wire.packet(wire.CONTROL,1,{"id":77,"result":{"ok":true,"left":true}}),0)
 assert(session.saved and emitted[0]==1)
 session._finish_leave(true)
 assert(emitted[0]==1)
 var terminal=load("res://client/session/netfox_session.gd").new()
 terminal._handle_reconnect_result({"ok":false,"error":"room_expired"})
 assert(terminal.can_return_to_hub() and not terminal.saved)
 print("NETFOX ONLY CUTOVER + SETTLEMENT RECEIPT PASS")
 quit()
