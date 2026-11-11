extends SceneTree
const Wire=preload("res://logic/net_wire.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var trace=preload("res://client/session/input_trace.gd").new()
 var input=preload("res://logic/sim_input.gd").new()
 trace.capture(60,1,100,110)
 trace.sent(Wire.inputs(1,0,0,60,[input.encode()],1),120)
 trace.sent(Wire.inputs(2,0,0,61,[input.encode(),input.encode()],1),125)
 var state={"meta":{"input_trace":{"epoch":1,"emitted_ms":950,"rows":[{"input_tick":60,"received_ms":900,"used_ms":920,"outcome":"applied"}]}}}
 trace.observed(state,180)
 var row:Dictionary=trace.snapshot("test",1).rows[0]
 assert(row.capture_to_send_ms==20 and row.create_to_send_ms==10 and row.send_count==2)
 assert(row.send_to_applied_observation_ms==60 and row.worker_queue_ms==20 and row.worker_snapshot_wait_ms==30)
 state.meta.input_trace.emitted_ms=1500;trace.observed(state,900)
 assert(trace.rows[60].worker_snapshot_wait_ms==30)
 for i in range(1,100):trace.capture(i*60,1,100,110)
 assert(trace.rows.size()==32)
 trace.capture(60,2,100,110);assert(trace.rows.size()==1)
 var manager=preload("res://server/rooms/manager.gd").new();var rng=RandomNumberGenerator.new()
 var profile=preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
 assert(manager.create("traceinput123",55,[{"id":1,"profile":profile.to_dict()}],true,1).ok)
 var room=manager.rooms["traceinput123"].room
 for i in 59:room.tick()
 assert(room.input(1,60,input.encode()));room.tick()
 var rows:Array=room.trace_snapshot(1).rows
 assert(rows.size()==1 and rows[0].outcome=="applied" and rows[0].used_world_tick==60)
 assert(not room.input(1,60,input.encode()));assert(room.trace_snapshot(1).rows[0].outcome=="applied")
 for i in 61:room.tick()
 assert(not room.input(1,120,input.encode()));assert(room.trace_snapshot(1).rows.back().outcome=="late_rejected")
 assert(not Wire.encode(room.public_state(1),262144).is_empty())
 print("INPUT TRACE PASS: stable epoch/tick refs,dedupfirstsend,retransmitcount,same-clockdurations,no cross-clock subtraction,applied/late outcomes,bounds,Wire")
 quit()
