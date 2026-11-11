extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var trace=preload("res://client/session/input_trace.gd").new()
 var wire=preload("res://logic/net_wire.gd")
 var input=preload("res://logic/sim_input.gd").new()
 trace.controls(100);trace.capture(17,1,100,100)
 trace.controls(150);trace.controls(151);trace.capture(18,1,150,150)
 trace.sent(wire.inputs(23,0,0,18,[input.encode()],1),151)
 var room=preload("res://server/rooms/room.gd").new();room.connected[1]=true;room.clock_tick=22
 room.observe_input_packet(1,18,9010,23)
 room.observe_input_packet(1,18,9011,23)
 var report:Dictionary=room.trace_snapshot(1)
 assert(report.late_packets.size()==1 and report.late_packets[0].margin_ticks==-4)
 trace.observed({"meta":{"input_trace":report}},210)
 var result:Dictionary=trace.snapshot("test",1).late_packets[0]
 assert(result.client_found and result.client.controls_gap_ms==1 and result.client.controls_burst_gap_ms==50 and result.client.controls_batch==2 and result.client.create_to_send_ms==1)
 assert(result.worker.packet_sequence==23 and result.send_to_observation_ms==59)
 trace.observed({"meta":{"input_trace":report}},250);assert(trace.late_matches.size()==1)
 for i in range(19,650):
  trace.capture(i,1,300,300);trace.sent(wire.inputs(i+30,0,0,i,[input.encode()],1),301)
 assert(trace.captures.size()==512 and trace.packets.size()==512)
 room.epoch=2;room.observe_input_packet(1,20,9020,25)
 assert(room.trace_snapshot(1).late_packets.size()==1)
 trace.capture(1,2,400,400);assert(trace.packets.is_empty() and trace.late_matches.is_empty())
 assert(not wire.encode(report,262144).is_empty())
 print("LATE PACKET TRACE PASS: unsampled tick matched by packet sequence, callback gap, same-clock duration, duplicate/epoch/bounds/Wire")
 quit()
