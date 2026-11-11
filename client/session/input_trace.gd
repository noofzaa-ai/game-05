extends RefCounted
## Bounded sampled trace. Never subtract clocks belonging to different machines.
var work=preload("res://client/session/input_work_trace.gd").new()
var gap_context:Dictionary={}
var gap_context_at:=-1
var rows:Dictionary={}
var epoch:=-1
var captures:Dictionary={}
var packets:Dictionary={}
var late_matches:Dictionary={}
var last_controls_ms:=-1
var controls_gap_ms:=0
var controls_batch:=0
var controls_burst_gap_ms:=0
var last_input_sent_ms:=-1
func controls(now:int)->void:
 work.browser_setup()
 controls_gap_ms=maxi(0,now-last_controls_ms) if last_controls_ms>=0 else 0
 controls_batch=controls_batch+1 if last_controls_ms>=0 and now-last_controls_ms<=2 else 1
 if controls_batch==1:
  controls_burst_gap_ms=controls_gap_ms
  if controls_gap_ms>=40:
   gap_context=work.gap(last_controls_ms*1000,now*1000);gap_context_at=now
  elif gap_context_at>=0 and now-gap_context_at>500:gap_context={}
 last_controls_ms=now
var last_callback_ms:=-1
var callback_gap_max_ms:=0
func capture(tick:int,current_epoch:int,captured:int,now:int,synthetic:bool=false)->void:
 if current_epoch!=epoch:
  rows.clear();captures.clear();packets.clear();late_matches.clear();last_input_sent_ms=-1;epoch=current_epoch
 captures[tick]={"created_ms":now,"captured_ms":captured,"controls_gap_ms":controls_gap_ms,"controls_batch":controls_batch,"controls_burst_gap_ms":controls_burst_gap_ms,"synthetic":synthetic,"work_gap":gap_context,"work_gap_age_ms":now-gap_context_at if not gap_context.is_empty() else -1}
 while captures.size()>512:captures.erase(captures.keys()[0])
 if tick%60!=0:return
 if rows.has(tick):return
 rows[tick]={"input_tick":tick,"epoch":epoch,"captured_ms":captured,"created_ms":now,"synthetic":synthetic}
 while rows.size()>32:rows.erase(rows.keys()[0])
func sent(packet:PackedByteArray,now:int)->void:
 var wire=preload("res://logic/net_wire.gd")
 var message:Dictionary=wire.parse(packet)
 if message.get("kind",-1)!=wire.INPUT:return
 var input:Dictionary=wire.read_inputs(message.body)
 if input.is_empty() or int(input.epoch)!=epoch:return
 var entry:Dictionary=captures.get(int(input.tick),{}).duplicate()
 entry["input_tick"]=int(input.tick);entry["packet_sequence"]=int(message.sequence);entry["sent_ms"]=now
 entry["previous_send_gap_ms"]=maxi(0,now-last_input_sent_ms) if last_input_sent_ms>=0 else 0
 last_input_sent_ms=now
 if entry.has("created_ms"):entry["create_to_send_ms"]=maxi(0,now-int(entry.created_ms))
 packets[int(message.sequence)]=entry
 while packets.size()>512:packets.erase(packets.keys()[0])
 for i in input.frames.size():
  var tick:int=input.tick-i
  if not rows.has(tick):continue
  var row:Dictionary=rows[tick]
  if not row.has("sent_ms"):
   row.sent_ms=now;row.packet_sequence=message.sequence
   row.capture_to_send_ms=maxi(0,now-int(row.captured_ms));row.create_to_send_ms=maxi(0,now-int(row.created_ms))
  row.last_sent_ms=now;row.send_count=int(row.get("send_count",0))+1
func observed(state:Dictionary,now:int)->void:
 var trace:Dictionary=state.get("meta",{}).get("input_trace",{})
 if int(trace.get("epoch",-1))!=epoch:return
 for event in trace.get("late_packets",[]):
  var sequence:int=event.get("packet_sequence",-1)
  if late_matches.has(sequence):continue
  var matched:Dictionary={"worker":event.duplicate(true),"observed_ms":now,"client_found":packets.has(sequence)}
  if packets.has(sequence):
   matched["client"]=packets[sequence].duplicate(true)
   matched["send_to_observation_ms"]=maxi(0,now-int(packets[sequence].sent_ms))
  late_matches[sequence]=matched
  while late_matches.size()>12:late_matches.erase(late_matches.keys()[0])
 for remote in trace.get("rows",[]):
  var tick:int=remote.get("input_tick",-1)
  if not rows.has(tick):continue
  var row:Dictionary=rows[tick]
  if not row.has("response_ms"):
   row.response_ms=now
   if row.has("sent_ms"):row.send_to_observation_ms=maxi(0,now-int(row.sent_ms))
  row.worker=remote.duplicate(true)
  if remote.has("used_ms"):
   row.worker_queue_ms=maxi(0,int(remote.used_ms)-int(remote.received_ms))
   if not row.has("applied_observed_ms"):
    row.worker_snapshot_wait_ms=maxi(0,int(trace.get("emitted_ms",remote.used_ms))-int(remote.used_ms))
    row.applied_observed_ms=now
    if row.has("sent_ms"):row.send_to_applied_observation_ms=maxi(0,now-int(row.sent_ms))
func callback(now:int)->void:
 if last_callback_ms>=0:callback_gap_max_ms=maxi(callback_gap_max_ms,now-last_callback_ms)
 last_callback_ms=now
func snapshot(room:String,player:int)->Dictionary:
 return {"version":2,"late_packets":late_matches.values().duplicate(true),"reference":{"room":room,"player":player,"epoch":epoch,"key":"room/player/epoch/input_tick"},"sample_period_ticks":60,"callback_gap_max_ms":callback_gap_max_ms,"clock_note":"client and worker timestamps have independent origins; only same-clock durations and roundtrip observations are valid; send means WebSocket put_packet accepted, not NIC transmit","rows":rows.values().slice(maxi(0,rows.size()-6)).duplicate(true)}
