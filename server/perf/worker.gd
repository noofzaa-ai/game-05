extends SceneTree
## Isolated synthetic diagnostic WS. No credentials, account routes, DB or production room access.
const Scenario=preload("res://data/perf/scenario.gd")
const Wire=preload("res://logic/net_wire.gd")
const States=preload("res://logic/net_state.gd")
var tcp:=TCPServer.new()
var peers: Array=[]
func _initialize():
 Engine.max_fps=60
 if tcp.listen(8060,"0.0.0.0")!=OK:quit(1)
 print("PERF synthetic websocket ready")
func _process(delta):
 while tcp.is_connection_available():
  var stream=tcp.take_connection()
  if peers.size()>=2:stream.disconnect_from_host();continue
  var ws:=WebSocketPeer.new();ws.inbound_buffer_size=262144;ws.outbound_buffer_size=1048576;ws.accept_stream(stream)
  peers.append({"ws":ws,"age":0.0,"sim":null,"backlog":0.0,"seq":0,"state_seq":0,"before":{},"events":[],"received_inputs":0,"encode_us":0,"send_bytes":0,"queued":{},"input_driven":false,"used_inputs":0,"accepted_casts":0})
 for peer in peers.duplicate():
  peer.age+=delta;peer.ws.poll()
  if peer.age>600 or peer.ws.get_ready_state()==WebSocketPeer.STATE_CLOSED:peer.ws.close();peers.erase(peer);continue
  if peer.ws.get_ready_state()!=WebSocketPeer.STATE_OPEN:continue
  var read:=0
  while peer.ws.get_available_packet_count()>0 and read<120:
   var bytes: PackedByteArray=peer.ws.get_packet();read+=1
   if bytes.size()>65536:peer.ws.close(1009);break
   if peer.ws.was_string_packet():
    if bytes.size()>64:peer.ws.close(1009);break
    var command=JSON.parse_string(bytes.get_string_from_utf8())
    if command is Dictionary and command.get("start",false) and peer.sim==null:
     peer.input_driven=bool(command.get("input",false));peer.queued={};peer.used_inputs=0;peer.accepted_casts=0;peer.encode_us=0;peer.send_bytes=0;peer.received_inputs=0
     peer.sim=Scenario.new();peer.backlog=0;peer.before={};peer.seq=0;peer.state_seq=0;peer.events=[]
    elif command is Dictionary and command.get("reset",false):
     peer.sim=null;peer.before={};peer.events=[]
   else:
    var packet:=Wire.parse(bytes)
    if packet.get("kind",0)==Wire.INPUT:
     var input:=Wire.read_inputs(packet.body)
     if not input.is_empty() and peer.sim!=null:
      peer.received_inputs+=1
      for index in input.frames.size():
       var tick: int=input.tick-index
       if tick>peer.sim.sim.tick_count and tick<=peer.sim.sim.tick_count+24 and not peer.queued.has(tick):peer.queued[tick]=input.frames[index]
  if peer.sim==null:continue
  peer.backlog+=minf(delta,.25)
  var steps:=0
  while peer.backlog>=1.0/60 and steps<8 and peer.sim.sim.tick_count<720:
   peer.backlog-=1.0/60;steps+=1
   var frame=null
   if peer.input_driven:
    var tick: int=peer.sim.sim.tick_count+1
    frame=preload("res://logic/sim_input.gd").decode(peer.queued[tick]) if peer.queued.has(tick) else preload("res://logic/sim_input.gd").new()
    if peer.queued.has(tick):peer.used_inputs+=1;peer.queued.erase(tick)
   peer.sim.advance(frame)
   for event in peer.sim.sim.events:
    if event.get("type","")=="skill_cast":peer.accepted_casts+=1
   peer.events.append_array(peer.sim.sim.events.duplicate(true))
   if peer.sim.sim.tick_count%3==0:
    var started:=Time.get_ticks_usec();var state: Dictionary=peer.sim.state();var patch:=States.difference(state,peer.before,peer.state_seq,peer.sim.sim.tick_count);peer.seq+=1
    var packet:=Wire.packet(Wire.STATE,peer.seq,patch)
    if not packet.is_empty():peer.ws.put_packet(packet);peer.send_bytes+=packet.size()
    else:push_error("PERF state encode failed")
    peer.state_seq=peer.seq
    peer.before=state.duplicate(true)
    if not peer.events.is_empty():
     peer.seq+=1;var events:=[]
     for i in peer.events.size():events.append({"sequence":peer.sim.sim.tick_count*100+i,"tick":peer.sim.sim.tick_count,"event":peer.events[i]})
     var event_packet:=Wire.packet(Wire.EVENTS,peer.seq,{"events":events})
     if not event_packet.is_empty():peer.ws.put_packet(event_packet)
     peer.events=[]
    peer.encode_us+=Time.get_ticks_usec()-started
  if peer.sim.sim.tick_count>=720:
   var timings: Array=peer.sim.tick_us;timings.sort()
   peer.ws.send_text(JSON.stringify({"done":true,"ticks":720,"tick_p50_ms":timings[timings.size()/2]/1000.0,"tick_p95_ms":timings[int(timings.size()*.95)]/1000.0,"tick_max_ms":timings[-1]/1000.0,"encode_total_ms":peer.encode_us/1000.0,"received_inputs":peer.received_inputs,"bytes":peer.send_bytes,"input_driven":peer.input_driven,"used_input_ticks":peer.used_inputs,"skill_casts":peer.accepted_casts,"worker_version":2}))
   peer.sim=null
 return false
