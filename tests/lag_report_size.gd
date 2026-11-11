extends SceneTree
func _initialize():
 var reporter = load("res://client/lag_report.gd")
 var small = "[NETFOX ROOM REPORT v1]\n" + JSON.stringify({"diagnostic":{"ping_ms":123}})
 assert(reporter.fit_message(small) == small)
 var data = {"diagnostic":{"ping_ms":177,"netfox":{"network_tick":900,"reference_tick":901},"history":["x".repeat(9000)]},"input_clock":{"accepted_inputs":88},"input_trace":{"events":["x".repeat(10000)]},"seconds_oldest_first":[[1,2,3]],"map":"goblin_base_gate"}
 var body = reporter.fit_message("[NETFOX ROOM REPORT v1]\n"+JSON.stringify(data))
 assert(body.to_utf16_buffer().size()/2 <= 2000)
 var decoded = JSON.parse_string(body.substr(body.find("\n")+1))
 assert(decoded.diagnostic.ping_ms == 177)
 assert(decoded.input_clock.accepted_inputs == 88)
 assert(decoded.diagnostic.netfox.network_tick == 900)
 data.diagnostic["huge"] = {"text":"ก😀".repeat(9000)}
 body = reporter.fit_message("[NETFOX ROOM REPORT v1]\n"+JSON.stringify(data))
 assert(body.to_utf16_buffer().size()/2 <= 2000)
 assert(JSON.parse_string(body.substr(body.find("\n")+1)))
 print("LAG REPORT SIZE PASS")
 quit()
