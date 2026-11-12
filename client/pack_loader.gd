extends Control
## Boot scene (project main scene: scenes/boot.tscn). On the split web build it downloads the
## content packs listed in the manifest, loads them with ProjectSettings.load_resource_pack and only
## then opens the title screen, so nothing touches art before its pack is in. Desktop, editor and the headless
## tests have no manifest: they go straight to the title screen and load from the project folder.
##
## Load order: the engine and the core pack (code, scenes, data, audio) are fetched by play.html
## before the engine starts; then every content pack here, all downloads in parallel, mounted in
## manifest order. Texture packs come in one variant per GPU format (".s3tc" desktop, ".etc2"
## mobile); only the variant this device will read is downloaded.
## The page gives us the manifest as window.zorxBoot = {base: "<absolute pack URL>", manifest: {...}}
## (see tools/web/play_template.html and docs/tech/web_hosting.md).

const PackLayout := preload("res://client/pack_layout.gd")
const NEXT_SCENE := "res://scenes/title.tscn"  ## the title screen (its Start opens the campfire hub)
const RETRIES := 3

var _label: Label
var _bar: ProgressBar
var _packs: Array = []  # [{name, file, bytes, ...}] to load
var _requests: Dictionary = {}  # name -> HTTPRequest
var _data: Dictionary = {}  # name -> PackedByteArray
var _tries: Dictionary = {}
var _base := ""
var _failed := false


func _ready() -> void:
	var boot = _page_boot()
	if boot == null:
		_open_game.call_deferred()
		return
	_build_ui()
	var errors := []
	_base = str(boot.get("base", ""))
	_packs = choose_packs(PackLayout.content_packs(boot.get("manifest"), errors), _supported_formats())
	print("pack loader: GPU formats %s, loading %s" % [_supported_formats(), _packs.map(func(p): return str(p.name))])
	if not errors.is_empty():
		_fail("bad pack manifest: %s" % [errors])
		return
	var selected_bytes := 0
	for p in _packs: selected_bytes += int(p.get("bytes", 0))
	JavaScriptBridge.eval("if (window.zorxBootPlan) window.zorxBootPlan(%d);" % selected_bytes)
	if _packs.is_empty():
		_finish()
		return
	for p in _packs:
		_start(p)


## The content packs this device needs: plain packs plus, for packs with a "format", only the first
## format in the manifest order that the GPU supports. The build lists the formats in the order
## they appear in the exported .import files ("path.s3tc" before "path.etc2"), and Godot's importer
## takes the first supported one in that order, so both pick the same textures.
static func choose_packs(packs: Array, supported: Array) -> Array:
	var order := []
	for p in packs:
		var f := str(p.get("format", ""))
		if f != "" and not order.has(f):
			order.append(f)
	var pick := ""
	for f in order:
		if supported.has(f):
			pick = f
			break
	if pick == "" and not order.is_empty():
		pick = order[0]  # (no known format reported: try the first rather than load nothing)
	return packs.filter(func(p): return str(p.get("format", "")) in ["", pick])


func _supported_formats() -> Array:
	return ["s3tc", "bptc", "etc2", "astc"].filter(func(f): return OS.has_feature(f))


func _page_boot():
	if not OS.has_feature("web"):
		return null
	var text = JavaScriptBridge.eval("JSON.stringify(window.zorxBoot || null)", true)
	if not (text is String):
		return null
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else null


func _start(p: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.accept_gzip = true
	req.timeout = 120.0
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
	if _failed:
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
	_label.text = "Preparing…"
	for p in _packs:  # mounted in manifest order, whatever order the downloads finished in
		var path := _write_pack(str(p.file), _data[p.name])
		if path == "" or not ProjectSettings.load_resource_pack(path):
			_fail("could not open pack %s" % p.file)
			return
		_data.erase(p.name)
	_finish()


## Packs go to the in-memory /tmp (not user://, which the web build mirrors into IndexedDB).
func _write_pack(file: String, bytes: PackedByteArray) -> String:
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


func _process(_delta: float) -> void:
	if _bar == null or _failed or _packs.is_empty():
		return
	var done := 0.0
	var total := 0.0
	for p in _packs:
		var size := float(p.get("bytes", 1))
		total += size
		if _data.has(p.name):
			done += size
		elif _requests.has(p.name):
			done += minf(size, float(_requests[p.name].get_downloaded_bytes()))
	_bar.value = 100.0 * done / maxf(total, 1.0)
	_label.text = "Loading game data %d%%" % int(_bar.value)
	JavaScriptBridge.eval("window.zorxBootProgress && window.zorxBootProgress(%f, %f)" % [done, total], true)


func _finish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.zorxBootDone && window.zorxBootDone()", true)
	_open_game()


## Boss 2026-11-13: no title screen in between; go straight to the class card screen. With an account
## session from the web page (production) it signs in first; otherwise (dev machine, desktop) it plays offline.
## The title screen stays only as a fallback when the online sign-in fails.
func _open_game() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state == null or DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file(NEXT_SCENE)
		return
	var online = get_node_or_null("/root/Online")
	var has_account := OS.has_feature("web") and bool(JavaScriptBridge.eval("window.zorxGoogleSession != null", true))
	if has_account and online != null:
		JavaScriptBridge.eval("window.zorxAutoEnter = false", true)
		online.begin()
		while online.status == online.Status.CONNECTING:
			await online.changed
		if await game_state.connect_account_profile():
			get_tree().change_scene_to_file(game_state.CARD_DECK_SCENE)
			return
		get_tree().change_scene_to_file(NEXT_SCENE)  # sign-in failed: the title screen shows why and can retry
		return
	if online != null:
		online.use_offline()
	game_state.ensure_profile()
	get_tree().change_scene_to_file(game_state.CARD_DECK_SCENE)


func _fail(message: String) -> void:
	_failed = true
	push_error("pack loader: " + message)
	if _label != null:
		_label.text = "Could not load the game data. Please reload the page.\n" + message
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.zorxBootFail && window.zorxBootFail(%s)" % JSON.stringify(message), true)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.082, 0.09, 0.102)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	box.position = -box.custom_minimum_size / 2.0
	add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.text = "Loading game data…"
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(360, 6)
	box.add_child(_bar)
