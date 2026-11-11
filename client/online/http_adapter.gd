extends NakamaHTTPAdapter
## SDK transport with bounded requests, no redirects/retries and no credential logging.
## Kept outside the unmodified vendored SDK.
var _requests := {}
var _last := 0


func send_async(method: String, uri: String, headers: Dictionary, body: PackedByteArray):
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.max_redirects = 0
	req.body_size_limit = 1048576
	req.use_threads = OS.get_name() != "Web"
	add_child(req)
	_last += 1
	var ticket := _last
	_requests[ticket] = req
	var request_headers := PackedStringArray(["Accept: application/json"])
	if not OS.has_feature("web"):
		request_headers.append("User-Agent: zorx-game/1.0")
	for key in headers:
		request_headers.append("%s: %s" % [key, headers[key]])
	var methods := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE, "HEAD": HTTPClient.METHOD_HEAD}
	var method_id: int = methods.get(method, HTTPClient.METHOD_GET)
	var error := req.request(uri, request_headers, method_id, body.get_string_from_utf8())
	if error != OK:
		_requests.erase(ticket)
		req.queue_free()
		await get_tree().process_frame
		return NakamaException.new("transport_unavailable", -1)
	var reply: Array = await req.request_completed
	_requests.erase(ticket)
	req.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS:
		print("online transport: result=", int(reply[0]), " HTTP=", int(reply[1]))
		return NakamaException.new("transport_unavailable", -1)
	var parser := JSON.new()
	if parser.parse(reply[3].get_string_from_utf8()) != OK or not (parser.data is Dictionary):
		return NakamaException.new("invalid_response", int(reply[1]))
	if int(reply[1]) != 200:
		print("online transport: HTTP=", int(reply[1]))
		return NakamaException.new("request_rejected", int(reply[1]))
	return parser.data


func get_last_token():
	return _last


func cancel_request(ticket):
	if _requests.has(ticket):
		var req: HTTPRequest = _requests[ticket]
		req.cancel_request()
		req.call_deferred("emit_signal", "request_completed", HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func cancel_all() -> void:
	for ticket in _requests.keys():
		cancel_request(ticket)
