extends Node
## Downloads a list of content packs (all in parallel, 3 tries each), un-gzips them, writes them to the
## in-memory /tmp and mounts them with ProjectSettings.load_resource_pack in list order (the manifest order).
## Used twice on the split web build (docs/tech/web_hosting.md, "Boot flow"):
##   - by the boot scene (client/pack_loader.gd) for the "boot" packs the card screen needs;
##   - as the persistent /root/BattlePacks node for the "battle" packs, which download in the background
##     while the player is on the card screen. FIGHT waits for it (battle_ready / battle_fraction).
## Desktop, editor and tests never create one: there everything loads from the project folder, so
## battle_ready() is true when the node does not exist.

const PackLayout := preload("res://client/pack_layout.gd")
const BATTLE_NODE := "BattlePacks"
const RETRIES := 3

signal finished
signal failed(message: String)

enum State { IDLE, LOADING, READY, FAILED }

var state := State.IDLE
var error := ""
var _packs: Array = []
var _base := ""
var _requests: Dictionary = {}  # name -> HTTPRequest
var _data: Dictionary = {}  # name -> PackedByteArray
var _tries: Dictionary = {}


## True when the battle packs are mounted, or when this build has none to wait for (desktop, tests).
static func battle_ready(tree: SceneTree) -> bool:
	var node := _battle_node(tree)
	return node == null or node.state == State.READY


## 0..1 of the battle packs downloaded (1 when there is nothing to wait for).
static func battle_fraction(tree: SceneTree) -> float:
	var node := _battle_node(tree)
	return 1.0 if node == null else node.fraction()


## The background battle download, or null (not the split web build).
static func _battle_node(tree: SceneTree) -> Node:
	return null if tree == null else tree.root.get_node_or_null(BATTLE_NODE)


func start(packs: Array, base: String) -> void:
	_packs = packs
	_base = base
	_data.clear()
	_tries.clear()
	error = ""
	state = State.LOADING
	if _packs.is_empty():
		_ready_now.call_deferred()
		return
	for p in _packs:
		_start(p)


## A failed download starts again (FIGHT pressed after a network error).
func retry() -> void:
	if state == State.FAILED:
		start(_packs, _base)


func total_bytes() -> int:
	var total := 0
	for p in _packs:
		total += int(p.get("bytes", 0))
	return total


func done_bytes() -> int:
	if state == State.READY:
		return total_bytes()
	var done := 0
	for p in _packs:
		var size := int(p.get("bytes", 0))
		if _data.has(p.name):
			done += size
		elif _requests.has(p.name):
			done += mini(size, _requests[p.name].get_downloaded_bytes())
	return done


func fraction() -> float:
	if state == State.READY:
		return 1.0
	return float(done_bytes()) / float(maxi(total_bytes(), 1))


func _start(p: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.accept_gzip = true
	req.timeout = 180.0
	add_child(req)
	_requests[p.name] = req
	_tries[p.name] = int(_tries.get(p.name, 0)) + 1
	req.request_completed.connect(_on_done.bind(p, req))
	var err := req.request(PackLayout.pack_url(_base, str(p.file)))
	if err != OK:
		_on_done(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), p, req)


func _on_done(result: int, code: int, _headers, body: PackedByteArray, p: Dictionary, req: HTTPRequest) -> void:
	_requests.erase(p.name)
	req.queue_free()
	if state != State.LOADING:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if int(_tries.get(p.name, 0)) < RETRIES:
			push_warning("pack %s: result %d HTTP %d, retrying" % [p.file, result, code])
			_start(p)
		else:
			_fail("could not download %s (result %d, HTTP %d)" % [p.file, result, code])
		return
	var bytes := PackLayout.unwrap(body)
	if bytes.is_empty():
		_fail("pack %s is empty or not a valid gzip" % p.file)
		return
	_data[p.name] = bytes
	if _data.size() == _packs.size():
		_mount_all()


func _mount_all() -> void:
	for p in _packs:  # mounted in manifest order, whatever order the downloads finished in
		var path := _write_pack(str(p.file), _data[p.name])
		if path == "" or not ProjectSettings.load_resource_pack(path):
			_fail("could not open pack %s" % p.file)
			return
		_data.erase(p.name)
	_ready_now()


func _ready_now() -> void:
	state = State.READY
	finished.emit()


## Packs go to the in-memory /tmp (not user://, which the web build mirrors into IndexedDB).
static func _write_pack(file: String, bytes: PackedByteArray) -> String:
	for dir in ["/tmp/zorx_packs", "user://packs"]:
		DirAccess.make_dir_recursive_absolute(dir)
		var path: String = dir.path_join(file.get_file())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(bytes)
		f.close()
		return path
	return ""


func _fail(message: String) -> void:
	state = State.FAILED
	error = message
	for req in _requests.values():
		req.cancel_request()
		req.queue_free()
	_requests.clear()
	_data.clear()
	push_error("pack loader: " + message)
	failed.emit(message)
