extends Node3D
## Plays a stage on this machine: loads the map, runs the simulation, draws it, reads input,
## drives the camera, effects and HUD. Everything that decides what happens is in logic/;
## this script only feeds it input and draws the result.

const Combat := preload("res://logic/combat.gd")
const TELEGRAPH_SHADER := preload("res://client/vfx/attack_telegraph.gdshader")
const TELEGRAPH_LIFT := 0.05  ## the ground warning floats this much above the floor (no flicker)
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const CameraRig := preload("res://client/camera_rig.gd")
const CameraTrigger := preload("res://client/camera_trigger.gd")
const Effects := preload("res://client/effects.gd")
const ClassSkillData := preload("res://logic/class_skills/skill_data.gd")
const ExitPortal := preload("res://client/exit_portal.gd")
const TreasureChest := preload("res://client/treasure_chest.gd")
const EnemyBars := preload("res://client/enemy_bars.gd")
const ProjectileView := preload("res://client/projectile_view.gd")
const PerfOverlay := preload("res://client/perf_overlay.gd")
const Fighter := preload("res://logic/fighter.gd")
const Hud := preload("res://client/hud.gd")
const InputReader := preload("res://client/input_reader.gd")
const Journey := preload("res://logic/journey.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const MapData := preload("res://logic/map_data.gd")
const InkStyle := preload("res://client/ink_style.gd")
const StageProps := preload("res://client/stage_props.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")

var _local_player_id := 1
const FIRST_ENEMY_ID := 100
## Test camera fired with E (PvE only): a low dramatic angle that locks the player's choice.
const EVENT_CAMERA := {"name": "Event: dramatic", "offset": Vector3(-5.0, 1.0, 7.0), "look_y": 2.0, "fov": 40.0}
const EVENT_DURATION := 4.0
## Popups at one spot within this many ticks stack upward (see _popup).
const POPUP_STACK_TICKS := 12
## How map materials look. A map may name any key; unknown names use "default".
const MATERIAL_COLORS := {
	"default": Color(0.6, 0.6, 0.6),
	"dirt": Color(0.5, 0.36, 0.22),
	"stone": Color(0.55, 0.55, 0.5),
	"ink": Color(0.30, 0.34, 0.29),
}
const PLAYER_MODEL := "res://art/characters/studio05/split/body_sword_shield.glb"  # (the model team's chibi; earlier: chibi/chibi_painted.glb, base/base_character.glb)
const InkUi := preload("res://client/ink_ui.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const PLAYER_COLOR := Color(0.85, 0.85, 0.95)
const DEFAULT_WEAPON_COLOR := Color(1.0, 0.5, 0.1)
const RUN_DUST_TICKS := 8  ## a puff of dust under a sprinting fighter this often
## The keyboard help lines. %s are filled from client/input_reader.gd so they always name the real keys.
const HELP_TEXT := "Move WASD   Light %s   Heavy %s   Guard hold %s   Dodge %s   Run hold %s   Jump %s   Skill %s   Ultimate %s\nRun/Jump + attack = special attack   Camera 6-9   %s   F3 hit boxes   F1 hide help"
## The keys for leaving: a free stage has rest points, retry and the way home; a journey stage is
## fought to the end (Q, R and Esc do nothing there) and rests at its camp rooms.
const HELP_STAGE_KEYS := "R retry   Esc cards"
const HELP_JOURNEY_KEYS := "Clear the stage, then stand in a light to pick the next stage"
## Journey exits (Boss 2026-10-13): after a clear the portals rise this long after the last monster falls.
const PORTAL_DELAY := 1.2
const PORTAL_SPACING := 4.5  ## metres between neighbouring fallback portals
const CAMPFIRE_RADIUS := 2.2  ## standing this close to a rest camp's fire offers "E rest"
const PORTAL_HINT := "Stand in a light to choose the next stage    Esc = route list"
const CHEST_PROMPT := "E  open"  ## by the treasure chest (also a button: tap it on a phone)
const CHEST_AHEAD := 2.6  ## metres in front of the player the treasure chest drops

var _boss_id := -1  ## the journey boss fighter (-1: none), for the HUD boss bar
var _enemy_bars  ## client/enemy_bars.gd: the data-driven enemy health-bar styles for this map
var _map_id := ""  ## the current map's id and atmosphere, to resolve each enemy bar's look
var _map_atmosphere := "golden"
var _session
var _popup_stacks := {}  ## spot key -> {frame, count} of the latest popups there (see _popup)
var _combat_numbers: Node2D
var _loot_popups: Node2D
var _heal_samples := {}
var _combat_data
var _vfx  ## what every action looks like (client/vfx/vfx_library.gd, from data/combat/vfx.json)
var _fighter_colors: Dictionary = {}  ## fighter id -> its own color (a monster's 'weapon' color in the effect data)
var _views: Dictionary = {}  ## fighter id -> fighter_view node
var _hitbox_views: Dictionary = {}  ## fighter id -> translucent box shown while a move is active (F3)
var _telegraph_views: Dictionary = {}  ## fighter id -> red ground warning while a telegraphed move winds up
var _rig: Node
var _effects: Node3D
var _ranged: ProjectileView
var _class_vfx  ## client/skills/class_skill_vfx.gd: the 16 class skill effects (class_skill/<id>)
var _hud: CanvasLayer
var _event_trigger: Node
var _party_hud
var _party_camera
var _zone_triggers: Array[Node] = []
var _is_pve := true
var _show_hitboxes := false
var _result := ""  ## "", "cleared" or "defeated"
var _run  ## this trip: the run bag and gear (logic/run.gd)
var _banked := false  ## the bag has been brought back to camp
var _ink_style := false  ## the map is an "ink" stage: outlines and a painted ground
var _dust_clock := 0
var _perf: CanvasLayer  ## frame timing readout (F2)
var _journey  ## the journey this stage belongs to (logic/journey.gd), null for a single stage
var _camp_mode := false  ## a journey camp: the safe rest map (no monsters, a campfire, portals at once)
var _map  ## the loaded map (for portal and campfire spots)
var _portals: Array = []  ## client/exit_portal.gd nodes, one per upcoming choice
var _portal_delay := -1.0  ## seconds until the portals rise (-1: not waiting)
var _built_scene_epoch := 0
var _scene_build_started_us := 0
var _scene_presented := false
var _scene_loading_label: Label
var _leaving := false  ## a portal was taken: the next stage is loading
var _clear_banner_left := 0.0  ## the STAGE CLEAR banner shows this long, then the portal hint
var _chest: Node3D  ## client/treasure_chest.gd while a taken treasure waits to be opened (or just opened)
var _near_chest := false
var _chest_button: Button  ## the "E  open" prompt as a button (tap on a phone)


func _ready() -> void:
	_scene_build_started_us=Time.get_ticks_usec()
	var numbers_layer := CanvasLayer.new()
	numbers_layer.layer = 8
	add_child(numbers_layer)
	_combat_numbers = preload("res://client/combat_numbers.gd").new()
	_combat_numbers.z_index = 1
	numbers_layer.add_child(_combat_numbers)
	_loot_popups = preload("res://client/loot_popups.gd").new()
	numbers_layer.add_child(_loot_popups)
	if GameState.remote_session != null: _built_scene_epoch = GameState.remote_session.scene_epoch()
	if GameState.remote_session != null: _local_player_id = GameState.remote_session.player_id()
	_is_pve = GameState.mode == GameState.Mode.PVE
	InputReader.setup_actions()
	InputReader.setup_secondary()
	if not GameState.ensure_profile():
		_build_error_hud(["the equipment, camp or loot data could not be loaded (see the output for details)"])
		return

	if _is_pve and GameState.journey != null and (GameState.remote_session != null or GameState.journey.state == Journey.IN_STAGE or GameState.journey.is_at_camp()):
		_journey = GameState.journey
		_camp_mode = _journey.is_at_camp()
	var map := MapLoader.load_by_id(GameState.selected_map_id)
	_map = map
	_combat_data = CombatDataLoader.load_default()
	var errors: Array[String] = []
	errors.append_array(map.errors)
	errors.append_array(_combat_data.errors)
	_vfx = VfxLibrary.load_default()
	errors.append_array(_vfx.errors)
	_enemy_bars = EnemyBars.new().load_default()
	errors.append_array(_enemy_bars.errors)
	_map_id = map.id
	_map_atmosphere = map.atmosphere
	if not errors.is_empty():
		_build_error_hud(errors)
		return

	_ink_style = map.atmosphere == "ink"
	_build_atmosphere(map.atmosphere)
	_build_stage(map)
	if not _build_session(map): return
	_build_camera(map)
	_build_effects_and_hud()
	if _camp_mode:
		if not (_session.has_method("is_lobby") and _session.is_lobby()): _spawn_portals()
		_hud.show_skill_banner("Rest camp")
	var loading_layer := CanvasLayer.new()
	loading_layer.layer = 30
	add_child(loading_layer)
	_scene_loading_label = Label.new()
	_scene_loading_label.text = "กำลังเตรียมฉาก…"
	_scene_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scene_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_layer.add_child(_scene_loading_label)
	if GameState.remote_session != null: GameState.remote_session.lag_scene_build_us=Time.get_ticks_usec()-_scene_build_started_us
	_confirm_scene_presented.call_deferred()


func _confirm_scene_presented() -> void:
	var remote = GameState.remote_session
	var scene_epoch: int = _built_scene_epoch
	for frame in range(2):
		if DisplayServer.get_name() == "headless": await get_tree().process_frame
		else: await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
	if remote != null: remote.lag_scene_present_us=Time.get_ticks_usec()-_scene_build_started_us
	_scene_presented = true
	if remote != null and remote == GameState.remote_session: remote.scene_presented(scene_epoch)


func _process(_delta:float)->void:
	if not _scene_presented or _session==null or not _session.has_method("presentation_position"):return
	for id in _views:
		if _session.bodies.has(id):_views[id].position=_session.presentation_position(id)

func _work_mark(label:String,start_us:int)->int:
	var end_us:=Time.get_ticks_usec()
	if _session!=null and _session.has_method("is_remote"):_session.input_trace.work.record(label,start_us,end_us)
	return end_us

func _physics_process(_delta: float) -> void:
	var start_us:=Time.get_ticks_usec()
	_physics_frame(_delta)
	_work_mark("stage_physics_total",start_us)

func _physics_frame(_delta: float) -> void:
	var work_started:=Time.get_ticks_usec()
	if _session!=null and _session.has_method("physics_begin"):_session.physics_begin()
	if not _scene_presented or _session == null:
		return  # (no stage yet, or paused at a rest point)
	if _scene_loading_label != null:
		var loading: bool = _session.has_method("is_remote") and _session.server_state.get("meta", {}).get("scene_loading", false)
		_scene_loading_label.visible = loading
		_scene_loading_label.text = "รอผู้เล่นโหลดฉากพร้อม…"
	var auto_fight: bool = _is_auto_fight()
	if auto_fight and _session.is_coop():
		for other_id in _session.fighters:  # every other fighter of our squad is also brain-driven
			if other_id != _local_player_id and _session.fighters[other_id].team == _session.fighters[_local_player_id].team:
				_session.set_input(other_id, _session.auto_input(other_id))
	elif _session.is_coop() and not _session.has_method("is_remote"):
		var secondary = InputReader.read_secondary()
		secondary.move = _rig.movement_from_screen(secondary.move)
		_session.set_input(2, secondary)
	var frame = _session.auto_input(_local_player_id) if auto_fight else InputReader.read(get_viewport())
	if auto_fight:
		frame = _auto_journey_input(frame)
	if _party_hud != null and _party_hud.revive_held: frame = preload("res://logic/sim_input.gd").new()
	if _session.has_method("is_lobby") and _session.is_lobby():
		var walking = preload("res://logic/sim_input.gd").new(); walking.move = frame.move; walking.run = frame.run; frame = walking
	if not auto_fight:
		frame.move = _rig.movement_from_screen(frame.move)
	if not auto_fight and (frame.skill_slot >= 0 or (_session.fighters.get(_local_player_id)!=null and _session.fighters[_local_player_id].style=="bow" and (frame.light or frame.heavy))): _aim_skill(frame)
	work_started=_work_mark("input_read_aim_reconcile",work_started)
	if _session.has_method("advance_controls"):_session.advance_controls(frame,_delta)
	else:_session.step(frame)
	work_started=_work_mark("controls_predict",work_started)
	if _session.has_method("is_remote"): _update_remote_views()
	_update_heal_numbers()
	_handle_events()
	work_started=_work_mark("remote_views_events",work_started)
	_ranged.handle_events(_session.events, _color_of)
	_class_vfx.handle_events(_session.events)
	_ranged.show_state(_session)
	Audio.handle_events(_session.events, _session, _local_player_id)
	work_started=_work_mark("projectiles_audio",work_started)
	_update_popup_keep_out()
	if _squad_panel != null:
		for squad_id in _views:
			if _views[squad_id].looks.has("class"):
				_squad_panel.classes[squad_id] = _views[squad_id].looks["class"]
		_squad_panel.update_from(_session.fighters, _local_player_id, _combat_data)
	for id in _views:
		_views[id].show_state(_session.bodies[id], _session.fighters[id], _combat_data)
		if _session.has_method("presentation_position"):
			_views[id].position=_session.presentation_position(id)
		if _views[id].has_node("PartyStatus"):
			var f = _session.fighters[id]
			var status: Label3D = _views[id].get_node("PartyStatus")
			status.text = "%s  %.0f / %.0f" % [_session.player_name(id) if _session.has_method("player_name") else "P%d" % id, f.hp, f.max_hp()]
			if f.state == Fighter.State.DOWNED: status.text = "P%d DOWN %.1fs\nRevive %d%%" % [id, f.bleedout_left / 60.0, 100 * f.revive_progress / int(_combat_data.coop.revive_ticks)]
			elif f.eliminated: status.text = "P%d OUT" % id
	work_started=_work_mark("fighter_visuals",work_started)
	if _rig != null and _rig.arena:
		_rig.action_points = _action_points()
	_update_hitbox_views()
	for trigger in _zone_triggers:
		trigger.update(_views[_local_player_id].position)

	var player: Fighter = _session.fighters[_local_player_id]
	if _session.local_defeated() and _result.is_empty():
		_result = "defeated"
	if _session.is_coop():
		var follow_id := _local_player_id
		if _focus_id >= 0 and _views.has(_focus_id) and _session.fighters[_focus_id].is_alive():
			follow_id = _focus_id  # the squad card the player picked (squad_panel.gd): the camera closes on that fighter
		elif player.eliminated:
			for id in _journey.player_ids():
				if _session.fighters[id].is_alive():
					follow_id = id
					break
		_rig.target = _views[follow_id]
	if _party_camera != null:
		var own_ultimate: bool = player.state == Fighter.State.ATTACK and _combat_data.styles.get(player.style, {}).get("ultimate", "") == player.move_id
		_party_camera.update(_session, _views, own_ultimate)
	_running_dust()
	if _journey != null:
		_update_journey_exits(player, 1.0 / float(Engine.physics_ticks_per_second))
	_hud.update_from(player, _combat_data, _session.living_enemy_count(), _camera_text(), _bag_text())
	_show_boss_bar()
	_work_mark("camera_hud_exits",work_started)
	if _session.has_method("is_remote") and not _session.connected:
		_hud.set_prompt("ห้องปิดหรือเชื่อมต่อไม่ได้ กดกลับเพื่อไปแคมป์หลัก" if _session.can_return_to_hub() else "กำลังเชื่อมต่อห้องอีกครั้ง…")
	if _journey != null and not _result.is_empty():
		if _result == "defeated":
			_hud.set_banner("พ่ายแพ้ — ของในเป้ถูกส่งกลับคลังแล้ว\nEnter = ไปต่อ")
		elif _journey.state == Journey.WON:
			_hud.set_banner("JOURNEY COMPLETE\nEnter = continue")
		else:
			_hud.set_banner("STAGE CLEAR" if _clear_banner_left > 0.0 else "")
		return
	match _result:
		"cleared":
			_hud.set_banner("STAGE CLEAR\nEsc = back to the campfire    R = play again")
		"defeated":
			_hud.set_banner("พ่ายแพ้ — ของในเป้ถูกส่งกลับคลังแล้ว\nR = ลองใหม่    Esc = กลับแคมป์")


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key := key_event.physical_keycode
	if key == KEY_ESCAPE and _session != null and _session.has_method("is_remote") and _session.can_return_to_hub():
		GameState.go_card_deck()
		return
	if key == KEY_ESCAPE and _session != null and _session.has_method("is_lobby") and _session.is_lobby():
		var response: Dictionary = _session.command({"type": "party_leave"})
		_hud.set_prompt("กำลังออกจากปาร์ตี้ กลับแคมป์หลัก…" if response.get("pending", false) else preload("res://client/online/online_text.gd").message(str(response.get("error", "unavailable"))))
		return
	if _journey != null:
		if _leaving:
			return
		if _journey.is_over() and not _result.is_empty() and (key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_ESCAPE or key == KEY_SPACE):
			GameState.go_journey()  # (the summary)
			return
		if key == KEY_ESCAPE and (_camp_mode or _result == "cleared"):
			GameState.go_journey()  # between stages the route screen is the fallback (and the way to leave)
			return
		if key == KEY_E and _near_chest:
			open_chest()
			return
		if key == KEY_ESCAPE or key == KEY_R or key == KEY_Q:
			return  # a journey stage is fought to the end (go home from a camp)
	if key == KEY_ESCAPE:
		_bank_loot()  # (until the stage has rest points, leaving early brings the loot home)
		GameState.go_card_deck()
	elif _rig == null:
		return
	elif key == KEY_R:
		_bank_loot()
		get_tree().reload_current_scene()
	elif key == KEY_F3:
		_show_hitboxes = not _show_hitboxes
	elif key == KEY_F2:
		_perf.visible = not _perf.visible
	elif key == KEY_F1:
		_hud.toggle_help()
	elif CameraRig.PRESETS.has(key):
		_rig.choose(CameraRig.PRESETS[key])
	elif key == KEY_E:
		_event_trigger.activate()


func _build_atmosphere(style: String = "golden") -> void:
	var atmosphere := Node3D.new()
	atmosphere.set_script(load("res://client/atmosphere.gd"))
	atmosphere.set("style", style)
	add_child(atmosphere)


func _build_stage(map) -> void:
	StageProps.build(self, map.props, _ink_style)  # (a map's art_scene arrives as a prop, see stage_props.gd)
	var GoblinGround := preload("res://client/goblin_ground.gd")
	for solid in ([] if GoblinGround.dressed(map) else map.solids):  # (dressed maps: the art covers every solid)
		var box: AABB = solid["box"]
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = box.size
		var material: StandardMaterial3D
		if _ink_style and solid["material"] == "ink":
			material = InkStyle.ground_material()  # soft washes of grey-green
		else:
			material = StandardMaterial3D.new()
			material.albedo_color = MATERIAL_COLORS.get(solid["material"], MATERIAL_COLORS["default"])
		box_mesh.material = material
		mesh.mesh = box_mesh
		mesh.position = box.get_center()
		add_child(mesh)
	GoblinGround.apply(self,map)
	if map.camera_style == "arena":
		var arena_props := preload("res://client/arena_props.gd")
		arena_props.hide_ground_plane(self)
		if GoblinGround.dressed(map):  # a goblin camp: the kit of its own art scene, re-placed around a dirt yard
			arena_props.hide_scene(self)  # (hidden, not freed: the kit meshes are read from it)
			arena_props.build_camp(self, self, map, str(map.id))
		else:
			arena_props.hide_scene(self)
			arena_props.add_island(self, map)
		arena_props.set_sky(self)


func _build_session(map) -> bool:
	_session = GameState.get_session()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var started: Dictionary = _session.begin_stage(map, _combat_data, _journey, _local_player_id, FIRST_ENEMY_ID, rng)
	if started.has("error"):
		_build_error_hud([str(started.error)])
		_session = null
		return false
	_run = _session.run
	if _session.has_method("is_remote"):
		_session.command_completed.connect(_remote_command_completed)
		_session.ownership_changed.connect(_remote_looks_changed)
	for id in _session.fighters:
		_add_fighter_view(id, started["enemy_types"].get(id, ""), started["bosses"].has(id))
	return true


## Builds the view of one fighter (player or monster) and starts showing it.
func _add_fighter_view(id: int, enemy_type: String, is_boss: bool) -> void:
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	var is_player: bool = _session.fighters[id].team == "player"
	view.ink_outline = _ink_style
	view.base_color = PLAYER_COLOR if is_player else _combat_data.enemies[enemy_type]["color"]
	_fighter_colors[id] = view.base_color
	if is_player:
		view.model_path = PLAYER_MODEL
		view.looks = _player_looks(id)
	else:
		view.show_health_bar = true
		var tier: String = _enemy_bars.tier_for(enemy_type, is_boss)
		view.bar_style = _enemy_bars.resolve(_map_id, _map_atmosphere, tier)
		var definition: Dictionary = _combat_data.enemies[enemy_type]
		view.monster_model_path = definition["model"]  # "" = capsule
		view.monster_model_height = definition["model_height"]
		view.monster_run_clip_speed = float(definition.get("run_clip_speed", 0.0))
		view.monster_animations_path = definition["animations"]
		view.monster_clips = definition["clips"]
		view.monster_tint = definition["model_tint"]
		view.monster_standin_clips = definition["standin_clips"]
		view.monster_nock_mesh = definition["nock_mesh"]
	add_child(view)
	_views[id] = view
	if is_player and party_status_shown(_session.is_coop(), _is_auto_fight()):
		var status := Label3D.new()
		status.name = "PartyStatus"
		status.position.y = 2.1
		status.font_size = 28
		status.pixel_size = .004
		status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		view.add_child(status)
	if is_boss:
		_add_boss_label(view)
		_boss_id = id
	view.show_state(_session.bodies[id], _session.fighters[id], _combat_data)


## Whether our squad fighters get the overhead "name  HP / max" tag. In a local auto-battle the squad
## panel (squad_panel.gd) already shows each member's name and HP, and the auto camera zooms in so far
## the small tag only blurs into a smudge; it stays for online/co-op play outside auto-battle.
static func party_status_shown(coop: bool, auto_fight: bool) -> bool:
	return coop and not auto_fight


## A local auto-battle (no remote room, not the lobby): the squad's brains drive every fighter.
func _is_auto_fight() -> bool:
	return GameState.auto_battle and not _session.has_method("is_remote") and not (_session.has_method("is_lobby") and _session.is_lobby())


## The HUD's boss bar follows the journey boss while it lives.
func _show_boss_bar() -> void:
	var boss: Fighter = _session.fighters.get(_boss_id) if _boss_id >= 0 else null
	if boss == null or not boss.is_alive():
		_hud.set_boss("", 0.0)
		return
	_hud.set_boss(str(_journey.data.boss.get("label", "BOSS")), clampf(boss.hp / boss.max_hp(), 0.0, 1.0))


## A "BOSS" name tag over a journey boss (its label comes from the journey data).
func _add_boss_label(view: Node3D) -> void:
	var label := Label3D.new()
	label.text = str(_journey.data.boss.get("label", "BOSS"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	label.font_size = 56
	label.outline_size = 12
	label.modulate = Color(1.0, 0.35, 0.25)
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.5, 0.0)
	view.add_child(label)


## What the player's character wears now (models of the worn items) and their own looks.
func _player_looks(id: int = -1) -> Dictionary:
	if id < 0: id = _local_player_id
	var owner = _session.profile_for(id)
	var trip = _session.run_for(id)
	var own: Dictionary = {} if owner == null else owner.appearance
	var looks: Dictionary
	if trip == null:
		looks = {"appearance": ItemAssets.appearance(own)}
	else:
		var loadout = trip.loadout()
		looks = ItemAssets.looks(loadout, GameState.item_rules.catalog, loadout.weapon_style(_combat_data.styles.keys()))
		looks["appearance"] = ItemAssets.appearance(own)
	if GameState.auto_battle and not _session.has_method("is_remote"):
		var slots: Array = GameState.squad_looks()
		var env := OS.get_environment("ZORX_SQUAD")
		var slot: Dictionary = slots[(id - 1) % slots.size()].duplicate()
		if not env.is_empty():
			var classes := env.split(",")
			slot["class"] = classes[(id - 1) % classes.size()]
		looks["class"] = slot["class"]
		looks["appearance"] = ItemAssets.card_appearance(slot, looks["appearance"])
	return looks


func _on_gear_changed() -> void:
	if _views.has(_local_player_id):
		_views[_local_player_id].set_looks(_player_looks())


## Brings what is in the run bag back to camp (once). A dead player's bag is already empty.
func _bank_loot() -> void:
	if _run == null or _banked or _journey != null:  # (a journey brings its bag home at the end)
		return
	_banked = true
	GameState.last_trip = _session.command({"type": "return_to_camp"}).get("result", {})


## "Bag 3/12  Gold 40" for the info line.
func _bag_text() -> String:
	if _run == null:
		return ""
	var bag := "Bag %d/%d" % [_run.bag.slots_used(), _run.bag.capacity]
	if _journey != null and _journey.data.wave_mode:
		bag = "Wave %d/%d    %s" % [mini(_wave_now, _journey.wave_total()), _journey.wave_total(), bag]
	elif _journey != null:
		bag = "%s    %s" % [_journey.progress_text() if _result.is_empty() else "Stage %d/%d" % [_journey.completed, _journey.data.stage_count], bag]
	if _run.bag.free_slots() <= 0:
		bag += " FULL"  # an empty/low-resource state the player must notice: new loot is lost
	return "%s    Gold %d" % [bag, _run.bag.gold]


## Floating text for what a kill dropped: gold, materials and equipment (colored by tier).
func _show_loot(event: Dictionary) -> void:
	var at: Vector3 = _session.bodies[event["enemy"]].position
	var line := 0
	if int(event["gold"]) > 0:
		_loot_line(at, line, "+%d" % int(event["gold"]), InkUi.LOOT_GOLD, InkUi.icon("gold",24,InkUi.LOOT_GOLD))
		line += 1
	for id in event["materials"]:
		var material: Dictionary = GameState.camp_data.materials[id]
		_loot_line(at, line, "+%d" % int(event["materials"][id]), Color("fff3db"), InkUi.icon(str(id),24))
		line += 1
	for item in event["items"]:
		var tier: Dictionary = GameState.item_rules.tiers[int(item["tier"])]
		var label := str(item["weapon_type"]) if item["slot"] == "weapon" and not str(item["weapon_type"]).is_empty() else str(item["slot"])
		label = str(GameState.item_rules.catalog.entry(str(item.get("item_id", ""))).get("name", label.capitalize()))
		var color: Color = InkUi.rarity_color(tier["color"], true)
		_loot_line(at, line, "%s ×1" % label, color, ItemAssets.icon_for_id(str(item.get("item_id", "")), GameState.item_rules.catalog))
		line += 1
	for relic in event.get("relics",[]):
		var definition: Dictionary=load("res://logic/relics.gd").catalog().get(relic.relic,{})
		var icon_path: String=str(definition.get("icon",""))
		var icon: Texture2D=load(icon_path) if not icon_path.is_empty() else null
		_loot_line(at,line,"%s ×1"%str(definition.get("name",relic.relic)),InkUi.GOLD,icon)
		line+=1
	# Pickups use A-style floating icons only; do not duplicate them in a boxed feed.
	if int(event["lost_items"]) > 0 or not event["lost_materials"].is_empty():
		_hud.add_loot("BAG FULL: some loot was left behind", InkUi.LOOT_PROBLEM)
	if int(event["lost_items"]) > 0 or not event["lost_materials"].is_empty():
		_loot_line(at, line, "BAG FULL", InkUi.LOOT_PROBLEM)


func _loot_line(at: Vector3, line: int, text: String, color: Color, icon: Texture2D = null) -> void:
	_loot_popups.show_pickup(at,text,color,icon,line)


func _build_camera(map) -> void:
	_rig = CameraRig.new()
	_rig.input_allowed = func() -> bool: return _scene_presented
	_rig.target = _views[_local_player_id]
	_rig.min_x = -map.half_width + 6.0
	_rig.max_x = map.half_width - 6.0
	if map.camera_style == "arena":
		_rig.arena = true
		_rig.min_x = -map.half_width
		_rig.max_x = map.half_width
		_rig.min_z = -map.half_depth
		_rig.max_z = map.half_depth
	elif map.camera_style == "top_down":
		_rig.follow_depth = true
		_rig.min_z = -map.half_depth + 3.0
		_rig.max_z = map.half_depth - 3.0  # (the starting angle stays the default, 8; the player can still pick 6-9)
	_rig.special_enabled = _is_pve  # PvP: no special cameras
	add_child(_rig)

	for zone in map.camera_zones:
		var trigger := CameraTrigger.new()
		trigger.rig = _rig
		trigger.box = zone["box"]
		trigger.preset = zone["camera"]
		trigger.lock_choice = zone["lock"]
		add_child(trigger)
		_zone_triggers.append(trigger)

	_event_trigger = CameraTrigger.new()
	_event_trigger.rig = _rig
	_event_trigger.preset = EVENT_CAMERA
	_event_trigger.mode = CameraTrigger.Mode.MANUAL
	_event_trigger.lock_choice = true
	_event_trigger.max_duration = EVENT_DURATION
	add_child(_event_trigger)



func _build_effects_and_hud() -> void:
	_effects = Effects.new()
	_effects.library = _vfx
	add_child(_effects)
	_ranged = ProjectileView.new()  # arrows, bolts and ground circles (logic/projectiles.gd)
	_ranged.effects = _effects
	add_child(_ranged)
	_class_vfx = preload("res://client/skills/class_skill_vfx.gd").new()
	_class_vfx.session = _session
	_class_vfx.views = _views
	add_child(_class_vfx)
	_prewarm_effects()
	_effects.rig = _rig
	_hud = Hud.new()
	add_child(_hud)
	if GameState.auto_battle and not _session.has_method("is_remote"):
		_hud.auto_battle = true
		_squad_panel = preload("res://client/squad_panel.gd").new()
		add_child(_squad_panel)
		_squad_panel.selected.connect(func(id: int) -> void: _focus_id = id)
	if _boss_id >= 0:  # style the boss bar to the map once (the Chief's bar matches its floating goblin bar)
		_hud.set_boss_style(_enemy_bars.resolve(_map_id, _map_atmosphere, "boss"))
	_hud.set_help(help_text(_journey != null))
	_effects.screen_flash.connect(_hud.flash)
	if _session.has_method("is_remote"):
		_party_hud = preload("res://client/party_hud.gd").new(); _party_hud.session = _session; add_child(_party_hud)
		_party_hud.request.connect(func(command): _session.command(command))
		_party_hud.invite_requested.connect(_party_invite)
		_party_camera = preload("res://client/party_camera.gd").new(); _party_camera.rig = _rig; add_child(_party_camera)
	if GameState.remote_session != null:
		var network_status = preload("res://client/network_status.gd").new()
		network_status.session = _session
		network_status.hud = _hud
		add_child(network_status)
	_perf = PerfOverlay.new()
	add_child(_perf)


## Compiles every effect in data/combat/vfx.json (and the damage number font) during loading instead
## of on its first use (the web build has no shader cache, so each first use froze the game).
## Drawn under the floor, where nobody sees it.
func _prewarm_effects() -> void:
	var hidden: Vector3 = _session.bodies[_local_player_id].position - Vector3(0.0, 4.0, 0.0)
	_effects.prewarm(hidden)
	_ranged.prewarm(hidden)
	_class_vfx.prewarm(_class_vfx.skills_on_field(_session).keys(), hidden, _class_vfx.skills_on_field(_session))  # GLB effects: built and drawn once now
	# The weapon swing trail's material compiles on its first draw (a hitch on the web): draw one now.
	var trail := preload("res://client/vfx/blade_trail.gd").new()
	add_child(trail)
	trail.sample(hidden, hidden + Vector3.UP)
	trail.sample(hidden + Vector3.RIGHT * 0.2, hidden + Vector3(0.2, 1.0, 0.0))
	trail.glint(hidden)
	get_tree().create_timer(0.5).timeout.connect(trail.queue_free)
	# The monster wind-up warning (attack_telegraph.gdshader) too: else the first telegraphed attack froze the web.
	var warning := MeshInstance3D.new()
	warning.mesh = PlaneMesh.new()
	var warning_material := ShaderMaterial.new()
	warning_material.shader = TELEGRAPH_SHADER
	warning.material_override = warning_material
	warning.position = hidden
	add_child(warning)
	get_tree().create_timer(0.5).timeout.connect(warning.queue_free)
	_popup(hidden, "0123456789! BLOCK +-", Color(1.0, 1.0, 1.0, 0.01), 0.01)
	(get_child(get_child_count() - 1) as Label3D).outline_modulate = Color(0.0, 0.0, 0.0, 0.01)


func _build_error_hud(errors: Array[String]) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(16.0, 12.0)
	label.text = "This stage could not be loaded (Esc = back to campfire):\n- " + "\n- ".join(errors)
	layer.add_child(label)


static func help_text(in_journey: bool = false) -> String:
	if true:  # skill slots replace the old special/ultimate keys
		return "Move WASD   Light LMB   Heavy RMB   Guard F   Dodge C   Run Shift   Jump Space   Skills 1 2 3 4\nBow: grounded shots only · no run/jump attacks   Camera 6–9   F2 FPS   F1 hide help"
	var keys: Array = []
	for action in ["light", "heavy", "guard", "dodge", "run", "jump", "special", "ultimate"]:
		keys.append(InputReader.key_label(action, "?"))
	keys.append(HELP_JOURNEY_KEYS if in_journey else HELP_STAGE_KEYS)
	return HELP_TEXT % keys


func _camera_text() -> String:
	var text := "Camera %s" % _rig.chosen["name"]
	if _rig.is_choice_locked():
		text += " [locked]"
	if _rig.has_override():
		text += "   Active: %s" % _rig.override_name()
	return text if _is_pve else text + "   PvP: no special cameras"


## Turns simulation events into effects and sounds-to-be. Which effect plays is looked up in
## data/combat/vfx.json by action key (see client/vfx/vfx_library.gd).
func _handle_events() -> void:
	var skill_impact := {"tier": 0, "crit": false}  # strongest skill blow this frame that involves us
	for event in _session.events:
		if event.get("type") == "party_ping":
			_popup(event.pos, preload("res://client/party_hud.gd").TEXT.get(event.kind, ""), Color(0.9, 0.75, 0.3), 0.012)
		match event["type"]:
			"skill_visual":
				_play_skill_burst(event)
			"skill_cast":
				if bool(event.get("class_skill", false)):
					_announce_cast(int(event.player), str(event.skill))  # class skills v2: name callout only, no VFX yet
					continue
				# Buff-only effect gems have no hit to ride on: mark them on the caster as the cast lands.
				if str(event.get("effect","")) in ["thorns", "regen"]:
					_play_at_fighter("skill_gem/" + str(event.effect), int(event.player))
				_play_at_fighter("skill_cast/" + str(event.skill), int(event.player), _vfx.skill_color(str(event.skill), DEFAULT_WEAPON_COLOR))
				_announce_cast(int(event.player), str(event.skill))
			"skill_hit":
				if _views.has(event.target):
					_views[event.target].flash()
					_spawn_damage_number(_session.bodies[event.target].position, int(ceilf(event.damage)), bool(event.get("crit",false)), false, int(event.target)==_local_player_id)
					skill_impact = _play_skill_hit(event, skill_impact)
			"skill_dot":
				if _session.bodies.has(event.target):
					_spawn_damage_number(_session.bodies[event.target].position, int(ceilf(event.damage)), false, false, int(event.target)==_local_player_id)
					_play_skill_hit(event, skill_impact)
			"attack_started":
				_announce_skill(int(event["player"]), str(event["move"]))
				_play_move(_vfx.windup_key(str(event["move"])), int(event["player"]))
			"attack_active":
				_play_move(_vfx.swing_key(str(event["move"])), int(event["player"]))
			"hit":
				var target_id: int = event["target"]
				_views[target_id].flash()
				_play_hit(event)
				_spawn_damage_number(_session.bodies[target_id].position, event["damage"], event["crit"], false, target_id==_local_player_id)
			"blocked":
				var guard_id: int = event["target"]
				_views[guard_id].flash()
				var guard_feet: Vector3 = _session.bodies[guard_id].position
				_effects.play("block", _fighter_context(guard_id, Effects.context(event["pos"], guard_feet, -Vector2(event["dir"]), _vfx.palette.get("block", Color.SKY_BLUE))))
				_spawn_damage_number(guard_feet, event["damage"], false, true, guard_id==_local_player_id)
			"effect_applied":
				var applied: Dictionary = _combat_data.effects[event["effect"]]
				var applied_at: Vector3 = _session.bodies[event["target"]].position
				_popup(applied_at, ("+" if applied["kind"] == "buff" else "") + str(applied["name"]).to_upper(), applied["color"], 0.011)
				_play_at_fighter(_vfx.status_key(str(applied.get("control", "")), str(applied["kind"])), int(event["target"]), applied["color"])
				if event["target"] == _local_player_id and applied["kind"] == "debuff":
					_hud.flash(Color(applied["color"].r, applied["color"].g, applied["color"].b, 0.22), 0.2)
			"effect_resisted":
				_popup(_session.bodies[event["target"]].position, "RESIST", InkUi.POPUP_RESIST, 0.009)
			"dot":
				_spawn_damage_number(_session.bodies[event["target"]].position, int(ceilf(event["damage"])), false, false, int(event["target"])==_local_player_id)
			"out_of_stamina":
				if event["player"] == _local_player_id:
					_hud.flash_stamina()
			"guard_broken":
				var broken_id: int = event["target"]
				_play_at_fighter("guard_break", broken_id)
				if broken_id == _local_player_id:
					_hud.flash(Color(1.0, 0.2, 0.2, 0.35), 0.2)
			"poise_broken":
				_play_at_fighter("poise_break", int(event["target"]))
			"dodge_started":
				var dodger: int = event["player"]
				var slide: Vector2 = _session.bodies[dodger].knockback
				var heading := slide if slide.length() > 0.01 else Vector2(_session.fighters[dodger].direction)
				var dodge_feet: Vector3 = _session.bodies[dodger].position
				_effects.play("dodge", _fighter_context(dodger, Effects.context(dodge_feet + Vector3(0.0, 1.0, 0.0), dodge_feet, heading, _color_of(dodger))))
			"landed":
				var lander_id: int = event["player"]
				var lander: Fighter = _session.fighters[lander_id]
				var dive_key := ""
				if lander.state == Fighter.State.ATTACK and not lander.move_id.is_empty():
					dive_key = _vfx.land_key(lander.move_id)
				if dive_key.is_empty():
					_play_at_fighter("land", lander_id)
				else:
					_play_move(dive_key, lander_id)
			"knocked_down":
				_play_at_fighter("knockdown", int(event["player"]))
			"got_up":
				_play_at_fighter("getup", int(event["player"]))
			"killed":
				var dead_id: int = event["target"]
				_play_at_fighter("death", dead_id)
				if dead_id != _local_player_id and _views.has(dead_id):
					var dead_view: Node3D = _views[dead_id]
					# (a bound method, not a lambda: the connection drops by itself if the view is freed first)
					get_tree().create_timer(2.4).timeout.connect(dead_view.hide)
			"downed":
				_popup(_session.bodies[event["player"]].position, "P%d DOWN - stand nearby to revive" % event["player"], Color.MEDIUM_PURPLE, .01)
			"revived":
				_popup(_session.bodies[event["player"]].position, "REVIVED", Color.PALE_GREEN, .012)
			"eliminated":
				_popup(_session.bodies[event["player"]].position, "OUT", Color.INDIAN_RED, .012)
			"team_wiped":
				_result = "defeated"
			"wave_arrived":
				var boss_wave := false
				for new_id in event["enemies"]:
					var arrived_type: String = _session.fighters[int(new_id)].enemy_type
					var boss_here: bool = _journey != null and _journey.data.wave_mode and _journey.data.stages[-1]["enemies"].any(func(e): return bool(e.get("boss", false)) and str(e["type"]) == arrived_type)
					boss_wave = boss_wave or boss_here
					_add_fighter_view(int(new_id), arrived_type, boss_here)
				if _journey != null and _journey.data.wave_mode:
					_wave_now = int(event["wave"])
					GameState.run_loot["wave"] = _wave_now
					_hud.show_skill_banner("BOSS WAVE" if boss_wave else "Wave %d" % _wave_now)
				else:
					_hud.show_skill_banner("Reinforcements!")
			"stage_cleared":
				_result = "cleared"
				if _journey != null:
					_clear_banner_left = PORTAL_DELAY + 1.5
					if not _journey.is_over():
						_portal_delay = PORTAL_DELAY  # the exits rise once the last monster has fallen
				else:
					_bank_loot()
			"loot":
				if _journey != null and _is_our_team(int(event["player"])):  # the summary lists the whole squad's pick-ups
					GameState.note_run_loot(int(event["gold"]), event["materials"], event["items"])
				if event["player"] == _local_player_id:
					_show_loot(event)
					_play_loot(event)
			"bag_saved":
				if event["player"] == _local_player_id:
					_hud.flash(Color(0.6, 0.0, 0.0, 0.4), 0.3)
					_popup(_session.bodies[_local_player_id].position, "เก็บของกลับคลังแล้ว", InkUi.GOLD, 0.014)
	# Camera kick once per frame (an AoE striking eight monsters is one blow, not eight).
	var impact_ctx := Effects.context(Vector3.ZERO, Vector3.ZERO, Vector2.RIGHT, Color.WHITE)
	for key in _vfx.skill_impact_keys(int(skill_impact.tier), bool(skill_impact.crit)):
		_effects.play(key, impact_ctx)


## A skill-tree blow landing (or a burn/bleed tick): sparks in the skill's color on the target,
## the effect gem's mark (data: skill_gem/<gem id>), and — only when the local player cast it or took it — a camera kick
## remembered in `impact` (played once at the end of the frame). Returns the updated `impact`.
func _play_skill_hit(event: Dictionary, impact: Dictionary) -> Dictionary:
	var target_id := int(event.target)
	if not _session.bodies.has(target_id):
		return impact
	var attacker_id := int(event.get("attacker", 0))
	var skill_id := str(event.get("move", "")).trim_prefix("skill:")
	var fallback: Color = _color_of(attacker_id) if _session.fighters.has(attacker_id) else DEFAULT_WEAPON_COLOR
	var feet: Vector3 = _session.bodies[target_id].position
	var at: Vector3 = feet + Vector3(0.0, Effects.CHEST_HEIGHT, 0.0)
	var ctx := _fighter_context(target_id, Effects.context(at, feet, Vector2.RIGHT, _vfx.skill_color(skill_id, fallback), {"scale": _vfx.hit_scale(float(event.damage) * 4.0)}))
	if event.type == "skill_dot":
		_effects.play("skill_dot", ctx)
		return impact
	if is_class_skill(skill_id) or skill_id == "intercept_link":
		return impact  # class skills v2: no VFX until the VFX tool fills class_skill/<id> (class-skills.md 6); the number still shows
	var tier := int(event.get("impact", 1))
	var crit := bool(event.get("crit", false))
	var periodic := bool(event.get("periodic", false))
	for key in _vfx.skill_hit_keys(tier, crit, periodic):
		_effects.play(key, ctx)
	if not periodic:
		_effects.play("skill_struck/" + skill_id, ctx)  # (only skills whose own look does not land on the target have one)
	for gem in event.get("gems", []):  # the effect gem's own mark at the moment it lands
		if _vfx.has("skill_gem/" + str(gem)) and not str(gem) in ["thorns", "regen"]:
			_effects.play("skill_gem/" + str(gem), ctx)
	if not periodic and (attacker_id == _local_player_id or target_id == _local_player_id):
		impact.tier = maxi(int(impact.tier), tier)
		impact.crit = bool(impact.crit) or crit
	return impact


## Damage numbers and loot pickups keep off the HUD (trip line, banners, boss bar) and the squad cards.
func _update_popup_keep_out() -> void:
	var keep: Array[Rect2] = []
	if _hud != null and _hud.has_method("keep_out_rects"):
		keep.append_array(_hud.keep_out_rects())
	if _squad_panel != null:
		keep.append_array(_squad_panel.keep_out_rects())
	_combat_numbers.keep_out = keep
	_loot_popups.keep_out = keep


## A skill's own visual landed (logic/skills: a burst at a point, or a beam from `position` to `end`): its
## 'skill_burst/<skill>' look from data/combat/vfx.json on top of the presenter's art (so every skill reads
## even where the authored art is faint at the board camera's distance).
func _play_skill_burst(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	if not kind in ["burst", "beam"]:
		return
	var skill := str(event.get("skill", ""))
	var feet: Vector3 = event["position"]
	var color: Color = _vfx.skill_color(skill, DEFAULT_WEAPON_COLOR)
	var extra := {}
	var at := feet
	if kind == "beam":  # body to body, at chest height
		at = feet + Vector3(0.0, Effects.CHEST_HEIGHT, 0.0)
		extra["end"] = Vector3(event["end"]) + Vector3(0.0, Effects.CHEST_HEIGHT, 0.0)
	_effects.play("skill_burst/" + skill, Effects.context(at, feet, Vector2.RIGHT, color, extra))


## Every skill-tree cast of our squad: the skill's name shows on the caster's squad card (one callout per
## card, so casts on the same tick never pile up on one banner); a lone fighter gets the HUD banner.
func _announce_cast(id: int, skill: String) -> void:
	if not _session.fighters.has(id) or _session.fighters[id].team != _session.fighters.get(_local_player_id, _session.fighters[id]).team:
		return
	var name := skill_display_name(skill)
	if _squad_panel != null:
		_squad_panel.callout(id, name, _vfx.skill_color(skill, DEFAULT_WEAPON_COLOR))
	elif id == _local_player_id:
		_hud.show_skill_banner(name)


## True for the local player and the fighters on its team (the auto-battle squad).
func _is_our_team(id: int) -> bool:
	if id == _local_player_id:
		return true
	var me = _session.fighters.get(_local_player_id)
	var them = _session.fighters.get(id)
	return me != null and them != null and str(me.team) == str(them.team)


static var _skill_names: Dictionary = {}
## A skill's player-facing name (data/class_skills/class_skills.json name), cached.
static func skill_display_name(skill: String) -> String:
	if not _skill_names.has(skill) and is_class_skill(skill):
		_skill_names[skill] = str(ClassSkillData.load_default().skill(skill).get("name", skill.capitalize()))
	if not _skill_names.has(skill):
		_skill_names[skill] = skill.capitalize()
	return _skill_names[skill]


## True for a class skill v2 id (data/class_skills/class_skills.json).
static func is_class_skill(skill: String) -> bool:
	return not ClassSkillData.load_default().skill(skill).is_empty()


## A special skill or ultimate of the local player: its name appears in a brush-stroke banner.
func _announce_skill(id: int, move_id: String) -> void:
	if id != _local_player_id:
		return
	for kind in ["special", "ultimate"]:
		if move_id.ends_with("_" + kind):
			var weapon: Dictionary = _combat_data.weapons.get(_session.fighters[id].style, {})
			_hud.show_skill_banner(str(weapon.get("skill_names", {}).get(kind, kind.capitalize())))


## 'weapon' in the effect data: the player's weapon color, a monster's own color.
func _color_of(id: int) -> Color:
	var fighter: Fighter = _session.fighters[id]
	if fighter.team == "player":
		return _combat_data.weapons.get(fighter.style, {}).get("color", DEFAULT_WEAPON_COLOR)
	return _fighter_colors.get(id, DEFAULT_WEAPON_COLOR)


## Adds the fighter's view to an effect context (afterimages trace it).
func _fighter_context(id: int, ctx: Dictionary) -> Dictionary:
	ctx["follow"] = _views.get(id)
	return ctx


## Plays a move's effect key (a swing, a wind-up, a dive landing) from fighter `id`, facing its way.
func _play_move(key: String, id: int) -> void:
	if key.is_empty():
		return
	var fighter: Fighter = _session.fighters[id]
	var body = _session.bodies[id]
	var hitbox: Vector3 = body.position + Vector3(0.0, 1.0, 0.0)
	if not fighter.move_id.is_empty() and _combat_data.moves.has(fighter.move_id):
		hitbox = Combat.hitbox_world(body, fighter, _combat_data).get_center()
	_effects.play(key, _fighter_context(id, Effects.context(hitbox, body.position, Vector2(fighter.direction), _color_of(id), {"hitbox": hitbox})))


## Plays an effect key centered on fighter `id` (at = its chest). `color` replaces its own color.
func _play_at_fighter(key: String, id: int, color = null) -> void:
	if key.is_empty() or not _session.bodies.has(id):
		return
	var feet: Vector3 = _session.bodies[id].position
	var tint: Color = color if color is Color else _color_of(id)
	_effects.play(key, _fighter_context(id, Effects.context(feet + Vector3(0.0, Effects.CHEST_HEIGHT, 0.0), feet, Vector2(_session.fighters[id].direction), tint)))


## A landed blow: the base hit plus heavy / crit / launch / knockback / armored / the move's own extra.
func _play_hit(event: Dictionary) -> void:
	var target_id: int = event["target"]
	var move_id := str(event["move"])
	var knockback := float(_combat_data.moves[move_id]["knockback"]) if _combat_data.moves.has(move_id) else 0.0
	var ctx := Effects.context(event["pos"], _session.bodies[target_id].position, event["dir"], _color_of(int(event["attacker"])), {"scale": _vfx.hit_scale(float(event["damage"]))})
	_fighter_context(target_id, ctx)
	for key in _vfx.hit_keys(move_id, float(event["power"]), bool(event["crit"]), bool(event["launched"]), bool(event["armored"]), knockback):
		_effects.play(key, ctx)


## A kill dropped something: a beam of light in the color of the best item (gold if only gold).
func _play_loot(event: Dictionary) -> void:
	if int(event["gold"]) <= 0 and event["items"].is_empty() and event["materials"].is_empty():
		return
	var color: Color = _vfx.palette.get("gold", Color(1.0, 0.8, 0.2))
	var best := -1
	for item in event["items"]:
		if int(item["tier"]) > best:
			best = int(item["tier"])
			color = InkUi.RARITY_WORLD.get(GameState.item_rules.tiers[best]["color"], color)
	var feet: Vector3 = _session.bodies[event["enemy"]].position
	_effects.play("loot", Effects.context(feet, feet, Vector2.RIGHT, color))


## Puffs of dust under every sprinting fighter.
func _running_dust() -> void:
	_dust_clock += 1
	if _dust_clock % RUN_DUST_TICKS != 0:
		return
	for id in _session.fighters:
		var fighter: Fighter = _session.fighters[id]
		if fighter.running and fighter.is_alive() and _session.bodies[id].grounded:
			_play_at_fighter("run_dust", id)


## Presentation palette: normal white, critical orange. Damage magnitude never changes colour.
static func damage_style(damage: int, crit: bool, blocked: bool) -> Dictionary:
	var size := 0.010 + clampf(float(damage) / 600.0, 0.0, 1.0) * 0.013 + (0.004 if crit else 0.0)
	var color := InkUi.DAMAGE
	if blocked:
		color = InkUi.DAMAGE_BLOCKED
	elif crit:
		color = Color("ff8b18")
	else:
		color = Color.WHITE
	return {"pixel_size": size, "color": color}


func _spawn_damage_number(at: Vector3, damage: int, crit: bool, blocked: bool, incoming: bool = false) -> void:
	if blocked:
		_popup(at, "BLOCK", InkUi.DAMAGE_BLOCKED, 0.009)
	_combat_numbers.show_amount(at, damage, 3 if incoming else (1 if crit and not blocked else 0))


## Observe actual HP increases (including server snapshots); do not invent healing or change HP.
## Aggregate small regen ticks so they do not create a number every physics tick.
func _update_heal_numbers() -> void:
	var now := Time.get_ticks_msec()
	for id in _heal_samples.keys():
		if not _session.fighters.has(id): _heal_samples.erase(id)
	for id in _session.fighters:
		var fighter = _session.fighters[id]
		if not _session.bodies.has(id): continue
		var hp: float=fighter.hp
		var maximum: float=fighter.max_hp()
		if not _heal_samples.has(id):
			_heal_samples[id]={"hp":hp,"max":maximum,"amount":0.0,"at":now}
			continue
		var sample: Dictionary=_heal_samples[id]
		if not is_equal_approx(float(sample.max),maximum) or hp<=0:
			sample.amount=0.0;sample.at=now
		elif hp>float(sample.hp): sample.amount+=hp-float(sample.hp)
		if now-int(sample.at)>=450:
			if sample.amount>=1.0: _combat_numbers.show_amount(_session.bodies[id].position,int(roundf(sample.amount)),2);sample.amount=0.0
			sample.at=now
		sample.hp=hp;sample.max=maximum;_heal_samples[id]=sample


## Text that floats up from a fighter and fades (damage numbers, status effects).
func _popup(at: Vector3, text: String, color: Color, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = pixel_size
	label.font_size = 56
	label.outline_size = 12
	label.no_depth_test = true
	label.modulate = color
	# Popups from the same spot within a few ticks (a hit plus its "+RAGE") stack upward instead of
	# printing on top of each other; all start above the 3D health bar (SimBody.HEIGHT + 0.4).
	var key := "%d,%d" % [roundi(at.x * 2.0), roundi(at.z * 2.0)]
	var frame := Engine.get_physics_frames()
	var stack: Dictionary = _popup_stacks.get(key, {"frame": -100, "count": -1})
	stack["count"] = stack["count"] + 1 if frame - int(stack["frame"]) <= POPUP_STACK_TICKS else 0
	stack["frame"] = frame
	_popup_stacks[key] = stack
	label.position = at + Vector3(randf_range(-0.4, 0.4), 2.6 + 0.5 * stack["count"], 0.2)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.1, 0.75).set_ease(Tween.EASE_OUT)
	# The outline goes first: a half-faded outline shows through the fill and turns the number into a dark blob.
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.15).set_delay(0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


## Draws the danger markers: a warning area on the ground for the monster moves that are winding
## up (always), and with F3 every active attack's hit box so ranges and timing can be judged.
func _update_hitbox_views() -> void:
	var clock := float(Time.get_ticks_msec()) / 1000.0
	for id in _telegraph_views:
		if not _session.fighters.has(id):
			_telegraph_views[id].visible = false
	for id in _hitbox_views:
		if not _session.fighters.has(id):
			_hitbox_views[id].visible = false
	for id in _session.fighters:
		var fighter: Fighter = _session.fighters[id]
		var shape := Combat.telegraph_shape(id, _session.fighters, _session.bodies, _combat_data)
		_show_telegraph(id, shape, clock)
		# F3: the real hit box of every active attack (the warning above covers the wind-ups).
		var active := _show_hitboxes and Combat.is_attack_active(fighter, _combat_data)
		if not _hitbox_views.has(id):
			if not active:
				continue
			var box := MeshInstance3D.new()
			box.mesh = BoxMesh.new()
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			box.mesh.material = material
			box.visible = false
			add_child(box)
			_hitbox_views[id] = box
		var view: MeshInstance3D = _hitbox_views[id]
		view.visible = active
		if active:
			var world_box := Combat.hitbox_world(_session.bodies[id], fighter, _combat_data)
			var turned := fighter.direction.x != 0 and fighter.direction.y != 0
			var move_size: Vector3 = _combat_data.moves[fighter.move_id]["hit_size"]
			view.mesh.size = move_size if turned else world_box.size  # a diagonal swing shows its real turned box
			view.rotation.y = atan2(-float(fighter.direction.y), float(fighter.direction.x)) if turned else 0.0
			view.position = world_box.get_center()


## The red ground warning of a move winding up (attack_telegraph.gdshader): laid along the attack's
## real direction, its gauge reaching the far end at the moment the attack lands. One flat quad per
## fighter, built once; each frame only moves it and sets shader uniforms.
func _show_telegraph(id: int, shape: Dictionary, clock: float) -> void:
	var quad: MeshInstance3D = _telegraph_views.get(id)
	if shape.is_empty():
		if quad != null:
			quad.visible = false
		return
	if quad == null:
		quad = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		quad.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = TELEGRAPH_SHADER
		quad.material_override = material
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		_telegraph_views[id] = quad
	var material: ShaderMaterial = quad.material_override
	var progress := float(shape["progress"])
	quad.visible = true
	if shape["kind"] == "circle":
		var diameter := float(shape["radius"]) * 2.0
		quad.position = Vector3(shape["center"]) + Vector3(0.0, TELEGRAPH_LIFT, 0.0)
		quad.rotation = Vector3.ZERO
		quad.scale = Vector3(diameter, 1.0, diameter)
		material.set_shader_parameter("shape", 1)
		material.set_shader_parameter("size_m", Vector2(diameter, diameter))
	else:
		var dir: Vector2 = shape["dir"]
		var length := float(shape["length"])
		var widest := maxf(float(shape["width"]), float(shape["far_width"]))
		quad.position = Vector3(shape["origin"]) + Vector3(dir.x, 0.0, dir.y) * length * 0.5 + Vector3(0.0, TELEGRAPH_LIFT, 0.0)
		quad.rotation = Vector3(0.0, atan2(-dir.y, dir.x), 0.0)
		quad.scale = Vector3(length, 1.0, widest)
		material.set_shader_parameter("shape", 0)
		material.set_shader_parameter("size_m", Vector2(length, widest))
		material.set_shader_parameter("near_width", float(shape["width"]) / widest)
		material.set_shader_parameter("far_width", float(shape["far_width"]) / widest)
	material.set_shader_parameter("progress", progress)
	material.set_shader_parameter("time", clock)
	material.set_shader_parameter("opacity", clampf(progress * 8.0, 0.0, 1.0))


# ---------------------------------------------------------------- journey exits and rest camps
# (Boss 2026-10-13, after Lost Castle 2) A cleared journey stage raises one portal per next choice; the
# player stands in one to take it. A camp choice loads a safe rest map with a campfire ("E rest").
# The rules (what the choices are, what taking one does) stay in logic/journey.gd.

## Counts down to the portals, fills the one the player stands in, and keeps the prompts current.
var _squad_panel: CanvasLayer
var _focus_id := -1  ## auto-battle: the fighter the camera follows when zoomed in (-1 = the local player)
var _wave_now := 1  ## wave-mode journeys: the wave on the field (arrivals come as "wave_arrived" events)

## Between fights the auto-battler walks the squad on by itself: open a waiting chest, rest once at a camp's
## fire, then take the best portal (combat, challenge, boss first; a camp only when hurt; a chest last).
func _auto_journey_input(frame):
	var me: Fighter = _session.fighters.get(_local_player_id)
	if me == null or not me.is_alive() or _journey == null or _leaving:
		return frame
	var at: Vector3 = _session.bodies[_local_player_id].position
	var goal = null
	if _journey.is_over() and _clear_banner_left <= 0.0:  # the last wave is down: on to the summary
		_leaving = true
		GameState.go_journey()
		return frame
	if _chest != null and not _chest.is_open:
		goal = _chest.global_position
		if _near_chest:
			open_chest()
	elif not _portals.is_empty() and _clear_banner_left <= 0.0:
		var hurt: bool = me.hp < me.max_hp() * 0.6
		var ranks := {"boss": 0, "combat": 1, "challenge": 2, "camp": 0 if hurt else 3, "treasure": 4}
		var best_rank := 99
		for portal in _portals:
			var rank: int = ranks.get(portal.kind, 5)
			if rank < best_rank:
				best_rank = rank
				goal = portal.position
	if goal == null:
		return frame
	var off := Vector2(goal.x - at.x, goal.z - at.z)
	if off.length() > 0.3:
		frame.move = off.normalized()
		frame.run = off.length() > 6.0
	return frame


func _update_journey_exits(player: Fighter, delta: float) -> void:
	if _session.has_method("is_lobby") and _session.is_lobby(): return
	_clear_banner_left = maxf(0.0, _clear_banner_left - delta)
	if _portal_delay > 0.0:
		_portal_delay -= delta
		if _portal_delay <= 0.0:
			_spawn_portals()
	if _leaving:
		return
	var exit_id := _local_player_id
	if _session.is_coop() and player.eliminated:
		for id in _journey.player_ids():
			if _session.fighters[id].is_alive():
				exit_id = id
				player = _session.fighters[id]
				break
	var at: Vector3 = _session.bodies[exit_id].position
	var prompt := ""
	_near_chest = _chest != null and player.is_alive() and _chest.in_reach(at)
	if _chest_button != null:
		_chest_button.visible = _near_chest
	if _chest != null and not _chest.is_open:
		_hud.set_prompt("" if _near_chest else "Open the treasure chest")
		return
	if not _portals.is_empty() and _clear_banner_left <= 0.0:
		prompt = PORTAL_HINT
	for portal in _portals:
		var inside: bool = player.is_alive() and portal.contains(at)
		if inside:
			prompt = "Entering  %s  -  Stage %d ..." % [ExitPortal.NAMES.get(portal.kind, portal.kind), portal.stage]
		if portal.update_hold(inside, delta):
			_take_portal(portal)
			return
	if _result.is_empty() or _result == "cleared":
		_hud.set_prompt(prompt)


## One portal per upcoming choice of the journey (none once it is over).
func _spawn_portals() -> void:
	_portal_delay = -1.0
	for portal in _portals:
		portal.queue_free()
	_portals.clear()
	if _journey == null or _journey.is_over() or _journey.treasure_pending:
		return
	var options: Array = _journey.upcoming_choices()
	var spots := portal_spots(_map, options.size(), null)
	for index in options.size():
		var portal := ExitPortal.new()
		portal.setup(options[index], index)
		portal.position = spots[index]
		add_child(portal)
		_portals.append(portal)
	if not _portals.is_empty():
		Audio.play_ui("open")


## Where the portals stand: the map's own exit_portals spots (level data) first; any more choices (and
## maps that did not place any) in a row north of the centre (of the campfire on a rest map), moved off
## walls and pillars. Sorted left to right, so choice 0 is the leftmost light.
static func portal_spots(map, count: int, anchor = null) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var authored: Array = []
	var listed = map.get("exit_portals") if map != null else null
	if listed is Array and not listed.is_empty() and not _is_default_spots(map, listed):
		authored = listed
	for entry in authored:
		var point = _point_of(entry)
		if point is Vector3 and spots.size() < count:
			spots.append(point)
	var half_width: float = map.half_width if map != null else 10.0
	var half_depth: float = map.half_depth if map != null else 10.0
	var centre: Vector3 = anchor if anchor is Vector3 else Vector3.ZERO
	var row_z := centre.z - (5.0 if anchor is Vector3 else minf(6.0, half_depth * 0.45))
	if not spots.is_empty():  # (extra choices join the authored row, between and beside its spots)
		centre.x = spots.reduce(func(sum, p): return sum + p.x, 0.0) / float(spots.size())
		row_z = spots.reduce(func(sum, p): return sum + p.z, 0.0) / float(spots.size())
	row_z = clampf(row_z, -half_depth + 1.5, half_depth - 1.5)
	var missing := count - spots.size()
	for i in missing:
		var x := centre.x + (float(i) - float(missing - 1) * 0.5) * PORTAL_SPACING
		var spot := Vector3(clampf(x, -half_width + 1.5, half_width - 1.5), 0.05, row_z)
		for attempt in 10:  # step aside from walls, pillars and the other portals (floor slabs do not count)
			if not _blocked(map, spot, spots):
				break
			spot.x = clampf(spot.x + (1.0 if attempt % 2 == 0 else -1.0) * 1.5 * float(attempt + 1), -half_width + 1.5, half_width - 1.5)
			if attempt == 6:
				spot.z = clampf(spot.z + 2.5, -half_depth + 1.5, half_depth - 1.5)
		spots.append(spot)
	spots.sort_custom(func(a, b): return a.x < b.x)
	return spots


## The map loader fills exit_portals with two spots from the bounds when a map gives none: those are not
## placed by hand (they may stand in a pillar), so the portal row is worked out here instead.
static func _is_default_spots(map, listed: Array) -> bool:
	var defaults: Array = MapLoader.default_exit_portals(map) if map is MapData else []
	return listed == defaults


static func _blocked(map, spot: Vector3, taken: Array[Vector3]) -> bool:
	for other in taken:
		if Vector2(other.x - spot.x, other.z - spot.z).length() < ExitPortal.RADIUS * 2.5:
			return true
	if map == null:
		return false
	for solid in map.solids:
		var box: AABB = solid["box"]
		if box.end.y <= 0.3:
			continue
		var grown := box.grow(ExitPortal.RADIUS + 0.3)
		if spot.x > grown.position.x and spot.x < grown.end.x and spot.z > grown.position.z and spot.z < grown.end.z:
			return true
	return false


## A spot written in map data: [x, y, z], {"position": [x, y, z]} or a Vector3. null if unreadable.
static func _point_of(entry):
	if entry is Vector3:
		return entry
	if entry is Dictionary:
		return _point_of(entry.get("position", null))
	if entry is Array and entry.size() == 3:
		return Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
	return null


## The player stepped into a portal and held still: a flash in its color, then the journey takes it.
func _take_portal(portal: Node3D) -> void:
	_leaving = true
	_hud.set_prompt("")
	_hud.flash(Color(portal.color.r, portal.color.g, portal.color.b, 0.45), 0.3)
	Audio.play_ui("select")
	var index := int(portal.index)
	if _journey != null and _session != null and _session.fighters.has(_local_player_id):
		_session.capture_gauge()  # the ultimate gauge goes on to the next stage
	for other in _portals:  # (the lights go out as the player steps through)
		other.queue_free()
	_portals.clear()
	get_tree().create_timer(0.35).timeout.connect(_enter_choice.bind(index))


func _enter_choice(index: int) -> void:
	if not is_inside_tree():
		return
	var node: Dictionary = GameState.enter_journey_choice(index)
	if node.is_empty():  # (not allowed after all: show the choices again)
		_leaving = false
		_spawn_portals()
		return
	if str(node.get("kind", "")) != "treasure":
		return  # a fight or a camp: the next map is loading
	# A treasure (Boss 2026-10-13): a chest drops in here; opening it gives the piece, then the next
	# stage's portals rise in its place.
	_leaving = false
	_spawn_chest()


## Drops the treasure chest at a clear spot in front of the player (or the map centre).
func _spawn_chest() -> void:
	_portal_delay = -1.0
	for portal in _portals:
		portal.queue_free()
	_portals.clear()
	if _chest != null:
		_chest.queue_free()
	var body = _session.bodies[_local_player_id]
	_chest = TreasureChest.new()
	add_child(_chest)
	var next_spots := portal_spots(_map, _journey.upcoming_choices().size(), null)  # (keep clear of the portals to come)
	_chest.position = chest_spot(_map, body.position, Vector2(_session.fighters[_local_player_id].direction), next_spots)
	if _session.has_method("is_remote") and _session.is_remote():
		var wave_meta: Dictionary = _session.server_state.get("meta", {}).get("goblin_wave", {})
		var coords: Array = wave_meta.get("chest_position", [])
		if wave_meta.get("phase") == "chest" and coords.size() == 3:
			_chest.position = Vector3(float(coords[0]), float(coords[1]), float(coords[2]))
	_chest.landed.connect(_on_chest_landed)
	_chest.opened.connect(_on_chest_opened)
	_chest.drop_in()
	_hud.show_skill_banner("Treasure!")
	if _chest_button == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_chest_button = Button.new()
		_chest_button.name = "ChestPrompt"
		_chest_button.text = CHEST_PROMPT
		InkUi.make_primary(_chest_button)
		_chest_button.custom_minimum_size = Vector2(260.0, 60.0)
		_chest_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_chest_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_chest_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_chest_button.offset_bottom = -InkUi.EDGE_HUB - 70.0
		_chest_button.focus_mode = Control.FOCUS_NONE
		_chest_button.pressed.connect(open_chest)
		layer.add_child(_chest_button)
	_chest_button.visible = false


## Where the treasure chest lands: CHEST_AHEAD in front of the player if that spot is inside the map and
## clear of walls, pillars and the `avoid` spots (the next portals), else beside them, else the map centre.
static func chest_spot(map, from: Vector3, facing: Vector2, avoid: Array[Vector3] = []) -> Vector3:
	var ahead := facing.normalized() if facing.length() > 0.01 else Vector2(0.0, -1.0)
	var half_width: float = map.half_width if map != null else 10.0
	var half_depth: float = map.half_depth if map != null else 10.0
	for direction in [ahead, ahead.rotated(PI * 0.5), ahead.rotated(-PI * 0.5), -ahead]:
		var spot := Vector3(from.x + direction.x * CHEST_AHEAD, 0.0, from.z + direction.y * CHEST_AHEAD)
		var crowded := avoid.any(func(p): return Vector2(p.x - spot.x, p.z - spot.z).length() < ExitPortal.RADIUS + 2.0)
		if absf(spot.x) < half_width - 1.5 and absf(spot.z) < half_depth - 1.5 and not crowded and not _blocked(map, spot, []):
			return spot
	return Vector3.ZERO


func _on_chest_landed() -> void:
	if not is_inside_tree() or _chest == null:
		return
	var at: Vector3 = _chest.global_position
	_effects.play("land", Effects.context(at + Vector3(0.0, 0.3, 0.0), at, Vector2.RIGHT, Color(0.8, 0.7, 0.5)))
	_rig.shake(0.08, 0.15)


## Opens the treasure chest the player stands at (E, or the prompt button). Public: also for touch.
func open_chest() -> void:
	if _chest == null or not _near_chest or _chest.is_open:
		return
	if _chest.open():
		_hud.set_prompt("")
		_chest_button.visible = false
		Audio.play_ui("open")


## The lid is up: the journey hands over the piece (once), the reveal plays, the next portals rise.
func _on_chest_opened() -> void:
	if not is_inside_tree() or _journey == null:
		return
	var reward: Dictionary = _session.command({"type": "journey_treasure"}).get("result", {})
	GameState.note_run_loot(int(reward.get("gold", 0)), reward.get("materials", {}), reward.get("items", []))
	var at: Vector3 = _chest.loot_position()
	_effects.play("loot", Effects.context(at, at, Vector2.RIGHT, ExitPortal.COLORS["treasure"]))
	_hud.flash(Color(1.0, 0.85, 0.35, 0.25), 0.25)
	var loot_line := 0
	for item in reward.get("items", []):  # (Item objects, logic/item.gd)
		var tier: Dictionary = GameState.item_rules.tiers[int(item.tier)]
		var label := str(GameState.item_rules.catalog.entry(str(item.item_id)).get("name", str(item.slot).capitalize()))
		var color: Color = InkUi.rarity_color(tier["color"], true)
		_loot_line(at,loot_line,"%s ×1" % label,color,ItemAssets.icon_for_id(str(item.item_id),GameState.item_rules.catalog))
		loot_line += 1
	if not reward.get("lost_items", []).is_empty():
		_hud.add_loot("BAG FULL: the treasure was left behind", InkUi.LOOT_PROBLEM)
	if not (_session.has_method("is_remote") and _session.is_remote() and not _session.server_state.get("meta", {}).get("goblin_wave", {}).is_empty()):
		_portal_delay = PORTAL_DELAY


## Stores the journey bag in the stash now (camp_banks_bag; Journey.bank_bag(), safe from a later death)
## and shows it. Public: the camp window's "Store the bag in the stash" button does the same banking
## itself and reports through its bag_banked signal (-> _on_bag_banked). Returns what moved ({} = not allowed).
func bank_bag_at_camp() -> Dictionary:
	if _journey == null or not _journey.can_bank_bag():
		return {}
	var moved: Dictionary = _session.command({"type": "bank_bag"}).get("result", {})
	_on_bag_banked(moved)
	Audio.play_ui("select")  # (the camp window plays its own)
	return moved


## The bag went into the stash (here or from the camp window): remember it for the summary and say so.
func _on_bag_banked(moved: Dictionary) -> void:
	GameState.last_trip = moved
	_popup(_session.bodies[_local_player_id].position, "BAG STORED", InkUi.LOOT_GOLD, 0.012)
	_hud.add_loot("Stored in the stash: %d gold, %d items" % [int(moved.get("gold", 0)), int(moved.get("items", 0))], InkUi.LOOT_GOLD)


func _update_remote_views() -> void:
	_run = _session.run
	_journey = _session.journey
	var wave_meta: Dictionary = _session.server_state.get("meta", {}).get("goblin_wave", {})
	if not wave_meta.is_empty() and wave_meta.get("phase") != "chest" and _chest != null:
		_chest.queue_free()
		_chest = null
		if _chest_button != null: _chest_button.visible = false
	for id in _session.fighters:
		if not _views.has(id): _add_fighter_view(id, _session.fighters[id].enemy_type, str(_session.fighters[id].enemy_type).contains("chief"))
	for id in _views.keys():
		if not _session.fighters.has(id): _views[id].queue_free(); _views.erase(id)
	if _journey.state == Journey.CHOOSING and _result.is_empty():
		_result = "cleared"; _portal_delay = PORTAL_DELAY; _clear_banner_left = PORTAL_DELAY
	if _journey.treasure_pending:
		if _chest == null: _spawn_chest()
		elif not _portals.is_empty(): _spawn_portals()
	elif str(_journey.current.get("kind", "")) == "treasure" and _journey.state == Journey.AT_NODE and _portals.is_empty() and _portal_delay < 0.0:
		if _chest != null: _chest.is_open = true
		_portal_delay = PORTAL_DELAY
	if not _session.connected: _hud.set_prompt("กำลังเชื่อมต่อห้องอีกครั้ง…")


func _remote_command_completed(_id: int, result: Dictionary) -> void:
	if _party_hud != null: _party_hud.show_result(result)
	if not result.get("ok", false):
		if _journey.treasure_pending and _chest != null and _chest.is_open: _spawn_chest()
		_hud.set_prompt("รอหัวหน้าปาร์ตี้เลือกเส้นทาง" if result.get("error") == "leader_only" else "คำสั่งไม่สำเร็จ กรุณาลองใหม่")
	_on_gear_changed()

func _remote_looks_changed() -> void:
	for id in _views:
		if _session.fighters.has(id) and _session.fighters[id].team == "player":
			var next_looks := _player_looks(id)
			if _views[id].looks != next_looks: _views[id].set_looks(next_looks)

func _party_invite() -> void:
	var panel = preload("res://client/online/social_panel.gd").new()
	panel.account = _session.account; panel.room = _session.admission.room; panel.invite = GameState.party_invite
	add_child(panel)

func _aim_skill(frame) -> void:
	if not _session.bodies.has(_local_player_id):return
	var origin: Vector3=_session.bodies[_local_player_id].position
	var camera:=get_viewport().get_camera_3d()
	var mobile := false
	if not mobile and camera!=null and get_viewport().gui_get_hovered_control()==null:
		var mouse:=get_viewport().get_mouse_position()
		var point=Plane(Vector3.UP,origin.y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point is Vector3:
			var delta:=Vector2(point.x-origin.x,point.z-origin.z)
			frame.aim=delta.normalized();frame.aim_distance=minf(25.5,delta.length());return
	var nearest:=12.0
	var direction:=Vector2.ZERO
	for id in _session.fighters:
		if _session.fighters[id].team==_session.fighters[_local_player_id].team or not _session.fighters[id].is_alive():continue
		var delta: Vector3=_session.bodies[id].position-origin
		if delta.length()<nearest:
			nearest=delta.length();direction=Vector2(delta.x,delta.z)
	if direction!=Vector2.ZERO:frame.aim=direction.normalized();frame.aim_distance=nearest


## Auto-battle camera framing: the living enemies and the squad members fighting near them (a shooter far
## behind is left out so the camera can close in); everyone alive when no enemy is left.
const ACTION_NEAR := 4.5
func _action_points() -> Array[Vector3]:
	var enemies: Array[Vector3] = []
	var squad: Array[Vector3] = []
	for id in _views:
		if not _session.fighters[id].is_alive():
			continue
		if _session.fighters[id].team == "enemy":
			enemies.append(_views[id].position)
		else:
			squad.append(_views[id].position)
	if enemies.is_empty():
		return squad
	var points: Array[Vector3] = enemies.duplicate()
	for member in squad:
		for enemy in enemies:
			if member.distance_to(enemy) <= ACTION_NEAR:
				points.append(member)
				break
	return points

