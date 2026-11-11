extends RefCounted
## Ten one-second buckets in memory. No periodic upload or console logging.
var buckets: Array = []
var _last_us := 0
var _poll_us := 0
var _step_us := 0
var _states := 0
var _reconciles := 0
var _corrections := 0
var _decode_us := 0
var _reconcile_us := 0
var _packets := 0
var _replay_ticks := 0

func sample(session) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var second := int(now / 1000000)
		if buckets.is_empty() or buckets.back()[0] != second:
			# second, frames, total frame ms, max frame ms, >50ms frames,
			# poll ms, prediction step ms, decoded states, reconciles, corrections
			buckets.append([second, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		while not buckets.is_empty() and buckets.front()[0] < second - 9: buckets.pop_front()
		var b: Array = buckets.back()
		var frame_ms := maxi(0, roundi(float(now - _last_us) / 1000.0))
		b[1] += 1; b[2] += frame_ms; b[3] = maxi(b[3], frame_ms)
		if frame_ms > 50: b[4] += 1
		b[5] += maxi(0, session.lag_poll_us - _poll_us)
		b[6] += maxi(0, session.lag_step_us - _step_us)
		b[7] += maxi(0, session.lag_states - _states)
		b[8] += maxi(0, session.lag_reconciles - _reconciles)
		b[9] += maxi(0, session.corrections - _corrections)
		b[10]+=maxi(0,session.lag_decode_us-_decode_us)
		b[11]+=maxi(0,session.lag_reconcile_us-_reconcile_us)
		b[12]+=maxi(0,session.lag_packets-_packets)
		b[13]+=maxi(0,session.lag_replay_ticks-_replay_ticks)
	_decode_us=session.lag_decode_us; _reconcile_us=session.lag_reconcile_us
	_packets=session.lag_packets; _replay_ticks=session.lag_replay_ticks
	_last_us = now; _poll_us = session.lag_poll_us; _step_us = session.lag_step_us
	_states = session.lag_states; _reconciles = session.lag_reconciles; _corrections = session.corrections

func message(session, viewport_size: Vector2) -> String:
	var rows: Array = []
	for b in buckets:
		rows.append([b[1], b[2], b[3], b[4], roundi(float(b[5]) / 1000.0), roundi(float(b[6]) / 1000.0), b[7], b[8], b[9],roundi(float(b[10])/1000.0),roundi(float(b[11])/1000.0),b[12],b[13]])
	var metrics: Dictionary = session.debug_metrics()
	return "[NETFOX ROOM REPORT v1]\n"+JSON.stringify({"diagnostic":metrics,"input_clock":session.server_state.get("meta",{}).get("input_clock",{}),"map":session.server_state.get("meta",{}).get("map",""),"seconds_oldest_first":rows.slice(-3)})

## Keep valid JSON under the existing feedback RPC UTF-16 limit. Never slice JSON.
static func fit_message(body: String) -> String:
	if body.to_utf16_buffer().size() / 2 <= 2000: return body
	var split := body.find("\n")
	var header := body.substr(0, split + 1)
	var parsed = JSON.parse_string(body.substr(split + 1))
	if not parsed is Dictionary: return "[LAG REPORT]\n{\"report_error\":\"invalid_json\"}"
	var report: Dictionary = parsed
	report["compacted"] = true
	# Histories can grow without bound; keep aggregate network counters first.
	for key in ["input_trace", "reconciliation", "graphics", "columns", "runtime"]:
		report.erase(key)
	var diagnostic: Dictionary = report.get("diagnostic", {})
	for key in diagnostic.keys():
		if diagnostic[key] is Array: diagnostic.erase(key)
	var result := header + JSON.stringify(report)
	var rows: Array = report.get("seconds_oldest_first", [])
	while result.to_utf16_buffer().size() / 2 > 2000 and not rows.is_empty():
		rows.pop_front()
		result = header + JSON.stringify(report)
	if result.to_utf16_buffer().size() / 2 <= 2000: return result
	# Oversized nested diagnostics: bounded scalar summary, retaining ticks and ACK.
	var minimal := {"compacted": true, "map": str(report.get("map", "")).left(80)}
	if diagnostic.get("netfox") is Dictionary: report["netfox"] = diagnostic["netfox"]
	for section in ["diagnostic", "netfox", "input_clock", "movement_sync"]:
		var source: Dictionary = report.get(section, {})
		var target := {}
		for key in source:
			var value = source[key]
			if value is Dictionary or value is Array: continue
			if value is String: value = value.left(80)
			target[key] = value
			minimal[section] = target
			if (header + JSON.stringify(minimal)).to_utf16_buffer().size() / 2 > 1900:
				target.erase(key)
	return header + JSON.stringify(minimal)
