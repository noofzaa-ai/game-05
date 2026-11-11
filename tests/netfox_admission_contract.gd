extends SceneTree
func _initialize()->void:
 var gate=preload("res://server/rooms/netfox/admission.gd").new()
 var ticket={"v":2,"room":"0123456789abcdef0123456789abcdef","ticket":"a".repeat(64)}
 assert(gate.begin(20,100))
 assert(not gate.begin(20,100))
 var request:Dictionary=gate.request(20,JSON.stringify(ticket).to_utf8_buffer())
 assert(request.op=="redeem" and gate.request(20,JSON.stringify(ticket).to_utf8_buffer()).is_empty())
 assert(gate.route(20).is_empty())
 var result={"ok":true,"room":ticket.room,"slot":1,"capacity":4,"fence":"server-fence","profile":{"v":1}}
 var bad:Dictionary=result.duplicate();bad.room="f".repeat(32)
 assert(gate.complete(20,bad).is_empty() and gate.route(20).is_empty())
 assert(gate.complete(20,result).slot==1)
 assert(not gate.admitted[20].has("ticket") and not gate.admitted[20].has("profile"))
 assert(gate.begin(21,200));gate.request(21,JSON.stringify(ticket).to_utf8_buffer())
 assert(gate.complete(21,result).replaced_peer==20)
 gate.drop(20);assert(gate.slots[str(ticket.room)+":1"]==21)
 assert(gate.begin(22,200));assert(gate.expired(3200).has(22))
 assert(gate.request(22,PackedByteArray()).is_empty())
 var injected:Dictionary=ticket.duplicate();injected.slot=4
 assert(gate.request(22,JSON.stringify(injected).to_utf8_buffer()).is_empty())
 assert(load("res://server/rooms/netfox/endpoint.gd").can_instantiate())
 print("NETFOX ADMISSION PASS: one attempt, pending has no route, server-only slot/fence, wrong-room rejection, replacement cleanup, expiry, bounded schema, no retained credentials")
 quit()
