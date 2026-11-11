extends Node
## Autoload: remembers what the player picked at the campfire and switches between scenes.
## This is app/client state (menus and navigation), not game rules.
## It also holds the player's profile (stash, worn gear, camp level) for this session. Until the
## server saves players, a new profile is made when the game starts and is lost when it closes.

const MobileControls := preload("res://client/mobile_controls.gd")
var mobile_controls: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile_controls = MobileControls.new()
	add_child(mobile_controls)


enum Mode { PVE, PVP }

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const LootDataLoader := preload("res://logic/loot_data_loader.gd")
const LocalSession := preload("res://client/session/local_session.gd")
var session
## Auto-battler (Boss 2026-11-10): in a fight the squad fights by itself; no manual move/attack input.
var auto_battle := true
## How each squad member looks and fights (Boss 2026-11-10: the classes of test05/studio): class file
## (data/classes), hair file letter and Silver Silk. Fighter 1 first. Env ZORX_SQUAD overrides the classes
## (comma list, e.g. "greatsword,longbow,magic").
## The squad of the next fight, from the player's class cards (logic/card_deck.gd): one look per fighter.
func squad_looks() -> Array:
	var deck: Dictionary = profile.card_deck if profile != null else preload("res://logic/card_deck.gd").initial()
	return preload("res://logic/card_deck.gd").squad_looks(deck)
var squad_size := 3  ## fighters per round in the auto-battler (Boss 2026-11-10): the player plus guests 2..N
var remote_session
var party_invite := ""
var account_session
var online_error := ""
var _solo_connecting := false
var _solo_generation := 0
var _solo_started_at := 0
var solo_phase := ""
var last_room_open_failure:Dictionary={}
var _refreshing_account := false
# Read-only compatibility for already compiled camp UI; cannot activate retired modes.
var local_perf_test: bool:
	get: return false
var real_room_probe: bool:
	get: return false
var replay_probe: bool:
	get: return false
var _exiting_diagnostic := false
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const MapLoader := preload("res://logic/map_loader.gd")

const HUB_SCENE := "res://scenes/hub.tscn"
const CARD_DECK_SCENE := "res://scenes/card_deck_screen.tscn"
const STAGE_SCENE := "res://scenes/stage.tscn"
const JOURNEY_SCENE := "res://scenes/journey.tscn"
const DEFAULT_JOURNEY := "ink_road"
const WAVE_JOURNEY := "goblin_waves"  ## what the default journey becomes in the auto-battler: one fight, 12 waves
const DEFAULT_MAP := "goblin_base_gate"

var mode: Mode = Mode.PVE
var selected_map_id := DEFAULT_MAP

var item_rules  ## the equipment rules (data/items/rules.json)
var camp_data  ## the camp rules (data/camp/camp.json)
var loot_data  ## the monster drop tables (data/loot/loot.json)
var profile  ## the player's stash, worn gear and camp (null until ensure_profile())
var last_trip := {}  ## what the last trip brought back to camp (for the camp screen)
var journey  ## the PvE journey being played (logic/journey.gd), null when none


## The mode's name as written in map files ("pve" / "pvp").
func mode_key(of_mode: Mode = mode) -> String:
	return "pve" if of_mode == Mode.PVE else "pvp"


## Loads the rule data and makes the player's profile if there is none yet. Returns false (and
## leaves `profile` null) if the data is broken.
func ensure_profile() -> bool:
	if profile != null:
		return true
	item_rules = ItemRulesLoader.load_default()
	if not item_rules.is_valid():
		push_error("item rules are invalid: %s" % [item_rules.errors])
		return false
	camp_data = CampDataLoader.load_default(item_rules.tiers.size())
	loot_data = LootDataLoader.load_default(camp_data.materials.keys(), item_rules.tiers.size())
	if not camp_data.is_valid() or not loot_data.is_valid():
		push_error("camp or loot data are invalid: %s %s" % [camp_data.errors, loot_data.errors])
		return false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	session = LocalSession.new(null, item_rules, camp_data, loot_data)
	session.create_profile(rng, TEST_KIT)
	profile = session.profile
	return true


func start_stage(new_mode: Mode, map_id: String) -> void:
	if account_session != null:
		if new_mode == Mode.PVE and not _solo_connecting:
			_solo_connecting = true
			_start_solo.call_deferred(map_id)
		else: online_error = "PvP ยังไม่เปิดให้บริการ"
		return
	mode = new_mode
	selected_map_id = map_id
	get_tree().change_scene_to_file(STAGE_SCENE)


func go_hub() -> void:
	if remote_session != null and remote_session.admission.get("diagnostic",false):
		if not _exiting_diagnostic: _exit_diagnostic.call_deferred()
		return
	if remote_session != null:
		if not remote_session.can_return_to_hub(): return
		stop_online_room()
	if session != null:
		session.enter_camp()
	get_tree().change_scene_to_file(HUB_SCENE)


## The home screen since the auto-battler (Boss 2026-11-11): the Class Card screen. The campfire hub
## (go_hub, scenes/hub.tscn) is kept but no longer reached from the game flow.
func go_card_deck() -> void:
	if remote_session != null and remote_session.admission.get("diagnostic",false):
		if not _exiting_diagnostic: _exit_diagnostic.call_deferred()
		return
	if remote_session != null:
		if not remote_session.can_return_to_hub(): return
		stop_online_room()
	if session != null:
		session.enter_camp()
	get_tree().change_scene_to_file(CARD_DECK_SCENE)


## Starts a 12-stage journey (data/journeys/<id>.json) with a fresh run bag and opens the path screen.
## `seed` 0 = a random journey. Returns false if the data is broken.
func start_journey(journey_id: String = DEFAULT_JOURNEY, seed: int = 0) -> bool:
	if account_session != null:
		if journey_id != DEFAULT_JOURNEY or _solo_connecting: return false
		_solo_connecting = true
		_start_solo.call_deferred()
		return true
	if not ensure_profile():
		return false
	if auto_battle and journey_id == DEFAULT_JOURNEY:
		journey_id = WAVE_JOURNEY
	var combat = CombatDataLoader.load_default()
	var data = JourneyData.load_by_id(journey_id, combat.enemies.keys())
	if not data.is_valid():
		push_error("journey data is invalid: %s" % [data.errors])
		return false
	if seed == 0:
		seed = randi()
	mode = Mode.PVE
	var guests := {}
	if auto_battle:
		for guest_id in range(2, mini(squad_size, squad_looks().size()) + 1):
			var squad_rng := RandomNumberGenerator.new()
			squad_rng.seed = seed + guest_id
			guests[guest_id] = preload("res://logic/profile.gd").new_player(item_rules, camp_data, squad_rng)
	elif OS.get_cmdline_user_args().has("--coop-debug=2"):
		var guest_rng := RandomNumberGenerator.new()
		guest_rng.seed = seed + 2
		guests[2] = preload("res://logic/profile.gd").new_player(item_rules, camp_data, guest_rng)
	var fight_session = get_session()
	if "squad_classes" in fight_session:  # only the local session runs the auto-battler
		fight_session.squad_classes = squad_looks().map(func(slot): return str(slot.get("class", ""))) if auto_battle else []
	fight_session.start_journey(data, combat.weapon_ids, seed, guests)
	journey = session.journey
	# Stage 1 is always one plain fight: go straight in (the route screen had a single button there).
	# Between stages the exit portals choose; the route screen stays for the end summary and as a fallback.
	var first: Array = journey.choices()
	if first.size() == 1 and ["combat", "challenge", "boss"].has(str(first[0]["kind"])):
		enter_journey_choice(0)
	else:
		go_journey()
	return true


func go_journey() -> void:
	get_tree().change_scene_to_file(JOURNEY_SCENE)


## Plays the journey's chosen fight on its map (or a camp on its rest map).
func play_journey_stage() -> void:
	start_stage(Mode.PVE, journey_map_id(journey.current))


## Takes upcoming choice `index` of the journey (an exit portal or the route screen) and goes there:
## a fight or a camp loads its map; a treasure opens where the player stands (the caller shows it).
## Returns the chosen node ({} if the pick was not allowed).
func enter_journey_choice(index: int) -> Dictionary:
	if remote_session != null:
		remote_session.command({"type": "journey_choose", "index": index})
		return {}
	if journey == null:
		return {}
	var node: Dictionary = get_session().command({"type": "journey_choose", "index": index}).get("result", {})
	if node.is_empty():
		return {}
	if journey.state == Journey.IN_STAGE or journey.is_at_camp():
		play_journey_stage()
	return node


## The map a journey node is played on. A missing or broken map falls back: a camp to the first fight
## map (the stage shows it without monsters), a fight to the first valid map of the journey's lists.
func journey_map_id(node: Dictionary) -> String:
	var wanted := str(node.get("map", ""))
	if not wanted.is_empty() and MapLoader.load_by_id(wanted).is_valid():
		return wanted
	var fallbacks: Array = []
	if journey != null:
		fallbacks.append_array(journey.data.combat_maps)
		fallbacks.append(journey.data.boss_map)
	for map_id in fallbacks:
		if MapLoader.load_by_id(str(map_id)).is_valid():
			return str(map_id)
	return wanted


## Ends the journey and goes back to the campfire. A won journey brings the bag home.
func end_journey() -> void:
	if remote_session != null:
		if not remote_session.can_return_to_hub(): return
		stop_online_room()
		go_card_deck()
		return
	if journey != null and journey.state == Journey.WON:
		last_trip = get_session().command({"type": "journey_finish"}).get("result", {})
	journey = null
	go_card_deck()


## Boss test kit (2026-10-06, every armor / clothing piece too since 2026-10-15): one of every
## catalog item (everything that has a model) waits in the camp stash, to try every outfit; the
## stash grows to fit it (client/test_kit.gd). The weapon swap key is gone; equip from the stash
## instead. TURN OFF BEFORE RELEASE.
const TEST_KIT := true


## Reuse the authority across hub, creator, camp and each stage of the Journey.
func get_session():
	if remote_session != null and remote_session.ready: return remote_session
	if account_session != null: return account_session
	if not ensure_profile():
		return null
	if session == null or session.profile != profile or session.rules != item_rules or session.camp != camp_data:
		session = LocalSession.new(profile, item_rules, camp_data, loot_data)
	session.journey = journey
	if journey != null:
		session.run = journey.run
	return session


func _physics_process(_delta: float) -> void:
	if remote_session!=null:
		remote_session.physics_begin()
		if remote_session.ready:
			profile=remote_session.profile;journey=remote_session.journey

func _process(delta: float) -> void:
	if remote_session!=null and not remote_session.ready and remote_session._terminal:
		online_error=preload("res://client/online/online_text.gd").message(remote_session.error)
		cancel_pending_solo(false)
	if _solo_started_at>0 and Time.get_ticks_msec()-_solo_started_at>15000 and (_solo_connecting or (remote_session!=null and not remote_session.ready)):
		online_error="เปิดห้องไม่สำเร็จภายใน 15 วินาที กดออกเดินทางเพื่อลองใหม่"
		cancel_pending_solo(false)
	if remote_session != null:
		remote_session.poll(delta)
		if remote_session.ready:
			profile = remote_session.profile
			journey = remote_session.journey

func attach_online_room(service, ticket: Dictionary):
	if not ensure_profile(): return null
	if account_session == null: return null
	var session_script = load("res://client/session/netfox_session.gd")
	remote_session = session_script.new(null, item_rules, camp_data, loot_data)
	remote_session.party_left.connect(_online_party_left)
	remote_session.state_ready.connect(_online_stage_ready)
	remote_session.stage_changed.connect(_online_stage_ready)
	if not remote_session.connect_room(service, ticket):
		remote_session = null; return null
	return remote_session

func _online_stage_ready() -> void:
	if remote_session == null: return
	profile = remote_session.profile; session = remote_session; journey = remote_session.journey
	selected_map_id = str(remote_session.server_state.meta.map); mode = Mode.PVE
	get_tree().call_deferred("change_scene_to_file", STAGE_SCENE)

func stop_online_room() -> void:
	if remote_session == null: return
	remote_session.enter_camp()
	remote_session = null; journey = null; party_invite = ""
	profile = account_session.profile if account_session != null else null
	session = account_session
	_refresh_account.call_deferred()

func _online_party_left() -> void:
	stop_online_room()
	get_tree().call_deferred("change_scene_to_file", HUB_SCENE)


## Title entry loads the sole account profile. No local inventory is uploaded.
func connect_account_profile() -> bool:
	var account = get_node("/root/Online")
	if account.status != account.Status.AUTHENTICATED:
		await account.connect_account()
	if account.status != account.Status.AUTHENTICATED:
		online_error = "ต้องเชื่อมต่ออินเทอร์เน็ตเพื่อเข้าเกม"
		return false
	item_rules = ItemRulesLoader.load_default()
	camp_data = CampDataLoader.load_default(item_rules.tiers.size())
	loot_data = LootDataLoader.load_default(camp_data.materials.keys(), item_rules.tiers.size())
	var candidate = preload("res://client/session/account_session.gd").new(null, item_rules, camp_data, loot_data)
	candidate.account = account
	var result: Dictionary = await candidate.refresh_account()
	if not result.get("ok", false):
		online_error = "โหลดตัวละครจากเซิร์ฟเวอร์ไม่ได้ กรุณาลองใหม่"
		return false
	account_session = candidate
	session = candidate; profile = candidate.profile; journey = null
	online_error = ""
	return true

func _refresh_account() -> void:
	if account_session == null or _refreshing_account: return
	_refreshing_account = true
	var result: Dictionary = await account_session.refresh_account()
	_refreshing_account = false
	if result.get("ok", false): profile = account_session.profile
	else: online_error = "ยังโหลดข้อมูลล่าสุดไม่ได้ กรุณาเชื่อมต่อใหม่"

func _start_solo(farm_map: String = "") -> void:
	if account_session != null and not preload("res://logic/skill_build.gd").ready_for_run(account_session.profile):
		_solo_connecting=false;_solo_started_at=0;solo_phase=""
		online_error=preload("res://client/online/online_text.gd").message("skill_build_required")
		return
	_solo_generation+=1
	var request_generation:=_solo_generation
	_solo_started_at=Time.get_ticks_msec()
	solo_phase="ขอเปิดห้อง"
	_solo_connecting = true
	online_error = ""
	var account = get_node("/root/Online")
	var rooms = preload("res://client/online/room_client.gd").new()
	var result: Dictionary = await rooms.create(account, 1, false, farm_map, false)
	if not _solo_current(request_generation,result,account):return
	if result.get("error")=="in_match":
		solo_phase="ปลดห้องทดลองเก่า"
		var released:Dictionary=await rooms.cancel_diagnostic(account)
		if request_generation!=_solo_generation:return
		if released.get("ok",false):
			solo_phase="ขอเปิดห้องใหม่"
			result=await rooms.create(account,1,false,farm_map,false)
			if not _solo_current(request_generation,result,account):return
	if not result.get("ok", false) and result.get("error") == "in_match":
		result = await rooms.resume(account)
		if not _solo_current(request_generation,result,account):return
	if not result.get("ok", false):
		online_error = "เริ่ม Journey ไม่ได้: " + str(result.get("error", "unavailable"))
	elif attach_online_room(account, result) == null:
		online_error = "เชื่อมต่อห้องไม่ได้ กรุณาลองกลับห้องเดิม"
	_solo_connecting = false
	solo_phase="รอสถานะเริ่มต้นจาก Room Worker" if remote_session!=null and not remote_session.ready else ""
	if remote_session==null:_solo_started_at=0


## Private stage preview uses authenticated server admission, never a local-only stage.
func can_preview_mummy() -> bool:
	var account = get_node_or_null("/root/Online")
	return account_session != null and account != null and account.session != null and account.session.user_id == "76f7165a-18c4-4300-9c0d-9996173c6ae9"

func start_mummy_preview() -> void:
	if not can_preview_mummy() or _solo_connecting: return
	_solo_connecting = true
	_start_solo.call_deferred("mummy_ascent")


func _exit_diagnostic() -> void:
	if remote_session==null or not remote_session.admission.get("diagnostic",false):return
	_exiting_diagnostic=true
	var rooms=preload("res://client/online/room_client.gd").new()
	var result:Dictionary=await rooms.cancel(get_node("/root/Online"),remote_session.admission.room)
	_exiting_diagnostic=false
	if not result.get("ok",false):
		online_error="ปิดห้องทดลองไม่สำเร็จ ลองกดออกอีกครั้ง"
		return
	stop_online_room()
	get_tree().change_scene_to_file(HUB_SCENE)


func _solo_current(generation: int,result: Dictionary,account) -> bool:
	if generation==_solo_generation:return true
	if result.get("ok",false) and result.has("room"):_cancel_stale_room.call_deferred(account,str(result.room))
	return false

func _cancel_stale_room(account,room: String) -> void:
	await preload("res://client/online/room_client.gd").new().cancel(account,room)

func cancel_pending_solo(show_message: bool = true) -> void:
	_solo_generation+=1;_solo_connecting=false;_solo_started_at=0;solo_phase=""
	if remote_session!=null and not remote_session.ready:
		var old=remote_session
		last_room_open_failure={"session":old.debug_metrics(),"close_history":old.close_history.duplicate(true)}
		remote_session=null;old.enter_camp()
		if old.admission.get("diagnostic",false):_cancel_stale_room.call_deferred(old.account,str(old.admission.room))
		session=account_session
	if show_message:online_error="ยกเลิกการเปิดห้องแล้ว กดออกเดินทางเพื่อลองใหม่"

