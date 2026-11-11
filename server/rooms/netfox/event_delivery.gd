extends RefCounted
## Reliable event stream: queue each event once per connection, not once per snapshot.
const Wire=preload("res://logic/net_wire.gd")
static func next_batch(events:Array, after:int, slot:int)->Dictionary:
 var records:Array=[]
 var through:=after
 for event in events:
  if int(event.sequence)<=after:continue
  if event.event.get("type") in ["loot","bag_lost","bag_saved","gear_worn"] and event.event.get("player",slot)!=slot:
   through=int(event.sequence);continue
  var candidate:Array=records.duplicate();candidate.append(event)
  var packet:=Wire.packet(Wire.EVENTS,1,{"events":candidate})
  if packet.is_empty():break
  records=candidate;through=int(event.sequence)
  if records.size()>=32:break
 return {"through":through,"records":records}
static func flush(entry:Dictionary,events:Array,slot:int,send:Callable,can_send:Callable)->void:
 var after:int=maxi(int(entry.get("sent_event_sequence",0)),int(entry.get("event_ack",0)))
 # Bounded work and outbound queue. Remaining records resume next snapshot.
 for _batch in range(4):
  if not can_send.call():return
  var batch:=next_batch(events,after,slot)
  if batch.through<=after:return
  if not batch.records.is_empty():
   var packet:=Wire.packet(Wire.EVENTS,batch.through,{"events":batch.records})
   if packet.is_empty() or not send.call(packet):return
   entry["event_batches"]=int(entry.get("event_batches",0))+1
   entry["event_records"]=int(entry.get("event_records",0))+batch.records.size()
  after=batch.through;entry["sent_event_sequence"]=after
