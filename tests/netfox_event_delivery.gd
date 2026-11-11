extends SceneTree
func _initialize():
 var delivery=load("res://server/rooms/netfox/event_delivery.gd")
 var wire=load("res://logic/net_wire.gd")
 var events:Array=[]
 for i in range(1,101):events.append({"sequence":i,"tick":i,"event":{"type":"hit","player":1}})
 events.append({"sequence":101,"tick":101,"event":{"type":"loot","player":2}})
 var row={"event_ack":0};var packets:Array=[]
 var send=func(p):packets.append(p);return true
 delivery.flush(row,events,1,send,func():return true)
 assert(row.sent_event_sequence==101 and packets.size()==4)
 var seen:Array=[]
 for p in packets:
  var v=wire.decode(wire.parse(p).body).value
  for e in v.events:seen.append(e.sequence)
 assert(seen==range(1,101))
 delivery.flush(row,events,1,send,func():return true)
 assert(packets.size()==4) # No ACK yet; reliable stream must not resend.
 var reconnect={"event_ack":0};delivery.flush(reconnect,events,1,send,func():return false)
 assert(not reconnect.has("sent_event_sequence"))
 delivery.flush(reconnect,events,1,func(_p):return false,func():return true)
 assert(not reconnect.has("sent_event_sequence"))
 delivery.flush(reconnect,events,1,send,func():return true)
 assert(reconnect.sent_event_sequence==101 and packets.size()==8)
 print("RELIABLE EVENT BATCH/DEDUP/RECONNECT/BACKPRESSURE PASS")
 quit()
