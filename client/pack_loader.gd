extends Control
## Boot scene (project main scene: scenes/boot.tscn). On the split web build it downloads the
## content packs the card screen needs ("boot" stage), mounts them, then opens the game. The "battle"
## packs (maps, monsters, skill VFX) start downloading right after, in the background, in the persistent
## /root/BattlePacks node (client/pack_fetcher.gd); FIGHT on the card screen waits for them.
## Desktop, editor and the headless tests have no manifest: they go straight on and load from the project folder.
##
## Load order: the engine and the core pack (code, scenes, data, audio) are fetched by play.html
## before the engine starts; then the boot packs here, all downloads in parallel, mounted in manifest
## order; then the battle packs in the background (Boss 2026-11-13, two-stage loading). Texture packs
## come in one variant per GPU format (".s3tc" desktop, ".etc2" mobile); only the variant this device
## will read is downloaded.
## The page gives us the manifest as window.zorxBoot = {base: "<absolute pack URL>", manifest: {...}}
## (see tools/web/play_template.html and docs/tech/web_hosting.md).

const PackLayout := preload("res://client/pack_layout.gd")
const PackFetcher := preload("res://client/pack_fetcher.gd")
## Where loading ends: the card hub ("MY CARDS"). Boss 2026-11-13: never the title screen, not even when the
## online sign-in fails (the old title scene is unreferenced now; docs/po_defaults.md).
const NEXT_SCENE := "res://scenes/card_deck_screen.tscn"

var _label: Label
var _bar: ProgressBar
var _boot: Node  ## PackFetcher for the boot packs
var _battle_packs: Array = []
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
	var chosen := choose_packs(PackLayout.content_packs(boot.get("manifest"), errors), _supported_formats())
	if not errors.is_empty():
		_fail("bad pack manifest: %s" % [errors])
		return
	var boot_packs := PackLayout.packs_for_stage(chosen, PackLayout.BOOT)
	_battle_packs = PackLayout.packs_for_stage(chosen, PackLayout.BATTLE)
	print("pack loader: GPU formats %s, boot %s, battle %s" % [_supported_formats(), _names(boot_packs), _names(_battle_packs)])
	var boot_bytes := 0
	for p in boot_packs: boot_bytes += int(p.get("bytes", 0))
	JavaScriptBridge.eval("if (window.zorxBootPlan) window.zorxBootPlan(%d);" % boot_bytes)
	_boot = PackFetcher.new()
	_boot.name = "BootPacks"
	add_child(_boot)
	_boot.finished.connect(_on_boot_packs)
	_boot.failed.connect(_fail)
	_boot.start(boot_packs, _base)


static func _names(list: Array) -> Array:
	return list.map(func(p): return str(p.name))


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


func _on_boot_packs() -> void:
	_label.text = "Preparing…"
	start_battle_packs(get_tree(), _battle_packs, _base)
	_finish()


## Starts the background download of the battle packs in the persistent /root/BattlePacks node (once).
static func start_battle_packs(tree: SceneTree, packs: Array, base: String) -> Node:
	var node := tree.root.get_node_or_null(PackFetcher.BATTLE_NODE)
	if node != null:
		return node
	node = PackFetcher.new()
	node.name = PackFetcher.BATTLE_NODE
	tree.root.add_child(node)
	node.start(packs, base)
	return node


func _process(_delta: float) -> void:
	if _bar == null or _failed or _boot == null:
		return
	var done := float(_boot.done_bytes())
	var total := float(_boot.total_bytes())
	_bar.value = 100.0 * done / maxf(total, 1.0)
	_label.text = "Loading game data %d%%" % int(_bar.value)
	JavaScriptBridge.eval("window.zorxBootProgress && window.zorxBootProgress(%f, %f)" % [done, total], true)


func _finish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.zorxBootDone && window.zorxBootDone()", true)
	_open_game()


## Boss 2026-11-13: always straight into the card hub, never the title screen. With an account session from the
## web page (production) it signs in first and opens the hub on the account profile. If that sign-in fails, the hub
## opens offline on a local profile and the Online pill turns into an "Offline · Reconnect" button that retries the
## sign-in in place (client/online/online_account.gd offer_reconnect / reconnect). Otherwise (dev machine, desktop,
## headless tests) it plays offline.
func _open_game() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state == null:
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
			get_tree().change_scene_to_file(NEXT_SCENE)
			return
		push_warning("pack loader: sign-in failed (%s): opening the hub offline" % online.reason)
		online.offer_reconnect(online.reason)
		game_state.ensure_profile()
		get_tree().change_scene_to_file(NEXT_SCENE)
		return
	if online != null:
		online.use_offline()
	game_state.ensure_profile()
	get_tree().change_scene_to_file(NEXT_SCENE)


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
