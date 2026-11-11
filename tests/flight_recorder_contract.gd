extends SceneTree
func _initialize():call_deferred("run")
func run():
 var script=load("res://runtime/diagnostics/flight_recorder.gd")
 var r=script.new()
 for i in range(240):
  r.sample({"rtt_ms":i,"missing":null},{"decode_us":i*100},i*250)
  r.record("input",{"input_tick":i},i*250)
 assert(r.samples.size()<=121 and r.events.size()<=121)
 var s=r.snapshot(60000)
 assert(s.stats.rtt_ms.n>100 and s.stats.rtt_ms.p95>=230)
 assert(not s.stats.has("missing"))
 assert(r.trigger("network_gap",{},60000))
 assert(not r.trigger("duplicate",{},60001))
 r.record("after",{},61000)
 assert(not r.advance(61999));assert(r.advance(62000))
 assert(r.incidents.size()==1 and r.incidents[0].after.events.back().kind=="after")
 for i in range(1500):r.record("bounded",{},63000)
 assert(r.events.size()<=768)
 r.sample({"value":1},{"decode_us":1},64000)
 assert(not r.samples.back().counter_delta.has("decode_us"))
 var report={"v":2,"reference":{"room":"fixture","player":1,"epoch":1},"client":r.export_data(64000),"worker":{}}
 var codec=load("res://runtime/diagnostics/report_codec.gd")
 var encoded=codec.encode(report)
 assert(encoded.ok and encoded.data.length()<87384)
 var roundtrip=codec.decode(encoded);assert(roundtrip.get("reference",{}).get("room")=="fixture")
 encoded.digest="wrong";assert(codec.decode(encoded).is_empty())
 # Known-cause classification fixtures and frozen evidence are independent from current ring.
 var frozen=JSON.stringify(r.incidents)
 r.record("new",{},98000);assert(JSON.stringify(r.incidents)==frozen)
 var disabled=script.new();disabled.enabled=false;disabled.record("x",{});disabled.sample({"v":1});assert(disabled.events.is_empty() and disabled.samples.is_empty())
 # Local wall-time overhead: compare identical deterministic loop with recorder off/on.
 var timings:Array=[]
 for enabled in [false,true]:
  var probe=script.new();probe.enabled=enabled
  var start=Time.get_ticks_usec()
  for i in range(10000):probe.record("sample",{"input_tick":i},i)
  timings.append(Time.get_ticks_usec()-start)
 print("FLIGHT RECORDER PASS bounds/window/incidents/codec/tamper/reset/null/frozen; overhead10k off/on_us=",timings)
 quit()
