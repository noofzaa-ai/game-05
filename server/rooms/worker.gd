extends "res://server/shared/private_http.gd"
## Separate one-CPU room process. Control stays private; gameplay transport is M4-2/3.
var manager := preload("res://server/rooms/manager.gd").new()
var _last_usec := 0
var maintenance := OS.get_environment("ZORX_MAINTENANCE") == "true"
var transport
var netfox_service

func _initialize() -> void:
	super._initialize()
	transport = preload("res://server/rooms/lifecycle.gd").new(self, manager)
	transport.maintenance = maintenance
	if not transport.start():
		printerr("room worker: invalid transport configuration")
		quit(2)
	_start_netfox.call_deferred()
	_last_usec = Time.get_ticks_usec()

func _configuration_ready() -> bool:
	return manager.ready()

func _routes() -> Array:
	return ["/rooms", "/metrics", "/maintenance"]

func _dispatch(path: String, data: Variant) -> Dictionary:
	if path == "/metrics":
		if not data is Dictionary or data.size() != 1 or data.get("v") != 1: return manager.failure("invalid_payload")
		var result := manager.metrics()
		result["maintenance"] = maintenance
		result["runtime"] = "netfox-1.35.3"
		result["peers"] = netfox_service.endpoint.api.get_peers().size() if netfox_service != null else 0
		return result
	if path == "/maintenance":
		if not data is Dictionary or data.size() != 2 or data.get("v") != 1 or not data.get("enabled") is bool: return manager.failure("invalid_payload")
		maintenance = data.enabled
		if transport != null: transport.maintenance = maintenance
		return {"v": 1, "ok": true, "maintenance": maintenance}
	if maintenance and data is Dictionary and data.get("op") == "create": return manager.failure("maintenance")
	return manager.control(data)

func _process(delta: float) -> bool:
	# Drain inputs already waiting before advancing their world ticks.
	var now := Time.get_ticks_usec()
	manager.advance(float(now - _last_usec) / 1000000.0)
	_last_usec = now
	# Publish the state produced by those ticks, not the preceding frame.
	return super._process(delta)

func _start_netfox()->void:
	netfox_service=load("res://server/rooms/netfox/service.gd").new()
	netfox_service.name="NetRuntime";root.add_child(netfox_service)
	netfox_service.configure(self,manager,transport)
	var listening:int=netfox_service.start(8061,"0.0.0.0")
	if listening!=OK:
		printerr("room worker: netfox endpoint failed ",listening);quit(2)
