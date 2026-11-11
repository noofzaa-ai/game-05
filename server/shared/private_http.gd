extends SceneTree
## Shared private HTTP transport. Derived workers own their routes/configuration.
const BODY_LIMIT := 524288
const HEADER_LIMIT := 4096
const CONNECTION_LIMIT := 32
const DEADLINE_MS := 2500
var _server := TCPServer.new()
var _connections: Array[Dictionary] = []
var _authorization := PackedByteArray()


func _initialize() -> void:
	var token := OS.get_environment("ZORX_WORKER_TOKEN")
	if token.is_empty(): token = OS.get_environment("ZORX_NAMES_TOKEN")
	if not _configuration_ready():
		printerr("authority worker: invalid game configuration")
		quit(2)
		return
	if token.length() < 32:
		printerr("name validator: ZORX_NAMES_TOKEN must have at least32 characters")
		quit(2)
		return
	_authorization = ("Bearer " + token).to_utf8_buffer()
	var port_text := OS.get_environment("ZORX_WORKER_PORT")
	if port_text.is_empty(): port_text = OS.get_environment("ZORX_NAMES_PORT")
	var port := 8051 if port_text.is_empty() else int(port_text)
	var bind_address := OS.get_environment("ZORX_WORKER_BIND")
	if bind_address.is_empty(): bind_address = OS.get_environment("ZORX_NAMES_BIND")
	if bind_address.is_empty():
		bind_address = "0.0.0.0"
	if port < 1 or port > 65535 or _server.listen(port, bind_address) != OK:
		printerr("name validator: cannot listen")
		quit(2)
		return
	Engine.max_fps = 60
	print("name validator: ready")


func _process(_delta: float) -> bool:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _connections.size() >= CONNECTION_LIMIT:
			_reply(peer, 503, {"v": 1, "ok": false, "error": "unavailable"})
			continue
		peer.set_no_delay(true)
		_connections.append({"peer": peer, "deadline": Time.get_ticks_msec() + DEADLINE_MS, "buffer": PackedByteArray()})
	for index in range(_connections.size() - 1, -1, -1):
		var connection := _connections[index]
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_connections.remove_at(index)
			continue
		if Time.get_ticks_msec() > int(connection.deadline):
			_reply(peer, 408, {"v": 1, "ok": false, "error": "invalid_payload"})
			_connections.remove_at(index)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			if connection.buffer.size() + available > HEADER_LIMIT + BODY_LIMIT:
				_reply(peer, 413, {"v": 1, "ok": false, "error": "invalid_payload"})
				_connections.remove_at(index)
				continue
			var data := peer.get_data(available)
			if data[0] != OK:
				peer.disconnect_from_host()
				_connections.remove_at(index)
				continue
			connection.buffer.append_array(data[1])
		if _handle(connection):
			_connections.remove_at(index)
	return false


func _handle(connection: Dictionary) -> bool:
	var bytes: PackedByteArray = connection.buffer
	var separator := -1
	for i in range(maxi(0, bytes.size() - 3)):
		if bytes[i] == 13 and bytes[i + 1] == 10 and bytes[i + 2] == 13 and bytes[i + 3] == 10:
			separator = i
			break
	if separator < 0:
		if bytes.size() > HEADER_LIMIT:
			_reply(connection.peer, 413, {"v": 1, "ok": false, "error": "invalid_payload"})
			return true
		return false
	if separator > HEADER_LIMIT:
		_reply(connection.peer, 413, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	var lines := bytes.slice(0, separator).get_string_from_utf8().split("\r\n")
	var request := lines[0].split(" ")
	if request.size() != 3 or request[2] not in ["HTTP/1.0", "HTTP/1.1"]:
		_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	if request[0] == "GET" and request[1] == "/healthz":
		_reply(connection.peer, 200, {"ok": true})
		return true
	if request[0] != "POST" or request[1] not in _routes():
		_reply(connection.peer, 404, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at <= 0:
			_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
			return true
		var key := lines[i].substr(0, at).to_lower()
		if headers.has(key):
			_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
			return true
		headers[key] = lines[i].substr(at + 1).strip_edges()
	if not _authorized(str(headers.get("authorization", ""))):
		_reply(connection.peer, 401, {"v": 1, "ok": false, "error": "unauthorized"})
		return true
	var length_text := str(headers.get("content-length", ""))
	var decimal := RegEx.create_from_string("^[0-9]+$")
	if headers.has("transfer-encoding") or decimal.search(length_text) == null or str(headers.get("content-type", "")).split(";")[0].to_lower() != "application/json":
		_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	var length := int(length_text)
	if length < 1 or length > BODY_LIMIT:
		_reply(connection.peer, 413, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	var body_start := separator + 4
	if bytes.size() < body_start + length:
		return false
	if bytes.size() != body_start + length:
		_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	var parser := JSON.new()
	if parser.parse(bytes.slice(body_start).get_string_from_utf8()) != OK:
		_reply(connection.peer, 400, {"v": 1, "ok": false, "error": "invalid_payload"})
		return true
	_reply(connection.peer, 200, _dispatch(request[1], parser.data))
	return true


func _authorized(value: String) -> bool:
	var supplied := value.to_utf8_buffer()
	var difference := supplied.size() ^ _authorization.size()
	for index in _authorization.size():
		difference |= _authorization[index] ^ (supplied[index] if index < supplied.size() else 0)
	return difference == 0


func _reply(peer: StreamPeerTCP, code: int, value: Dictionary) -> void:
	var body := JSON.stringify(value).to_utf8_buffer()
	var header := "HTTP/1.1 %d Response\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, body.size()]
	peer.put_data(header.to_utf8_buffer() + body)
	peer.disconnect_from_host()


func _configuration_ready() -> bool:
	return true

func _routes() -> Array:
	return []

func _dispatch(_path: String, _data: Variant) -> Dictionary:
	return {"v": 1, "ok": false, "error": "invalid_payload"}
