extends Node3D
## The camp hub (Boss 2026-10-13, after Lost Castle 2's camp): a walkable forest clearing at night.
## The player walks around the campfire (the stage's movement code, input and camera, no combat) and
## talks to the camp's people: walking near one shows "E  talk" (tap the prompt on a phone).
##   Tailor -> the Look screen; Storage and the campfire -> the camp screens; Blacksmith -> Repair;
##   Merchant, Quests -> "coming soon"; the warp gate (north) -> client/warp_gate_screen.gd, which picks
##   Journey / Farm / PvP (until that file exists: this hub's own menu with the same buttons).
## The Menu button (top left, or Esc) keeps every older hub action one tap away.
## A new player makes their character first (character_creator.gd).
## The scenery, spots and colliders: client/hub_world.gd (art from tools/blender/build_camp_hub.py).

const CameraRig := preload("res://client/camera_rig.gd")
const CampScreen := preload("res://client/camp_screen.gd")
const CharacterCreator := preload("res://client/character_creator.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const HubNpc := preload("res://client/hub_npc.gd")
const HubMenuCard := preload("res://client/hub_menu_card.gd")
const HubTouch := preload("res://client/hub_touch.gd")
const HubWorld := preload("res://client/hub_world.gd")
const InkUi := preload("res://client/ink_ui.gd")
const InputReader := preload("res://client/input_reader.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const Movement := preload("res://logic/movement.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

const WARP_GATE_SCREEN := "res://client/world_map_screen.gd"  ## the ux-ui designer's gate screen (loaded only if it exists)
const PLAYER_ID := 1
const TALK_RADIUS := 2.3  ## how near an NPC (feet to feet) the talk prompt shows
const FIRE_RADIUS := 2.7  ## ... and the campfire (its stones are a collider of ~1.15 m)
const GATE_RADIUS := 1.35  ## stepping this far into the gate's ring opens the gate screen
const GATE_REARM := 2.2  ## leave the ring this far before it opens again
const CAMERA_MARGIN := Vector2(8.0, 3.0)  ## the camera stops this far inside the clearing's edges (x, z)
const LOOK_TAB := 1  ## the camp screen's tabs: 0 Inventory/stash, 1 Look, 2 Repair, 3 Camp
const REPAIR_TAB := 2

## The camp's people: role (spot npc_<role> in the glb), name, bubble icon, and what talking does
## ("camp" = the camp screens on `tab`, "soon" = says `line`).
const NPCS := [
	{"role":"relic_master","name":"Relic Master","icon":"trinket","action":"relics"},
	{"role": "bs_refine", "name": "Refine", "icon": "repair", "action": "refine"},
	{"role": "bs_upgrade", "name": "Upgrade", "icon": "upgrade", "action": "upgrade"},
	{"role": "merchant", "name": "Merchant", "icon": "gold", "action": "merchant"},
	{"role": "tailor", "name": "Tailor", "icon": "look", "action": "camp", "tab": LOOK_TAB},
	{"role": "storage", "name": "Storage", "icon": "stash", "action": "storage"},
	{"role": "quest", "name": "Quests", "icon": "journey", "action": "soon", "line": "No notices on the board yet.\nQuests are coming soon!"},
]

## Every word the hub shows (one place, for translation). Button words are also how the tests find them.
const TEXT := {
	"title": "ZORX", "subtitle": "Campfire",
	"farm": "PvE  -  Farm", "journey": "PvE  -  Journey (12 stages)", "pvp": "PvP",
	"camp": "Camp  -  Gear, Stash, Repair", "customize": "Customize  -  Face, Hair, Skin",
	"choose_stage": "Choose a stage", "pvp_arenas": "PvP arenas", "empty": "Nothing here yet.", "back": "Back",
	"close": "Close", "menu": "Menu",
	"talk": "E    Talk  -  %s", "fire": "E    Campfire  -  Gear, Stash, Repair",
}

var world  ## HubWorld: scenery, spots, colliders
var _adventurer
var _relic_panel
var npcs: Array = []  ## HubNpc nodes (their `role` and `action` data is in NPCS)
var _sim: GameSim
var _training
var _training_view:Node3D
var _rig: Node
var _touch: Control
var _facing := Vector2(0.0, -1.0)
var _style := "fists"
var _near := {}  ## what the prompt is for: {} or {"kind": "npc"/"fire", "index": n}
var _gate_armed := true
var _menu_holder: VBoxContainer
var _menu_header_texture: Texture2D
var _menu_heading: HBoxContainer
var _menu_title: Label
var _menu_emblem: TextureRect
var _section_headers: Array = []
var _play_grid: GridContainer
var _management_grid: GridContainer
var _system_grid: GridContainer
var _menu_cards: Array = []
var _main_menu: VBoxContainer
var _stage_menu: VBoxContainer
var _first_button: Button
var _menu_root: Control  ## the menu and the hub's buttons, scaled to the screen
var _menu_margin: MarginContainer
var _menu_scroll: ScrollContainer
var _menu_layout_in := 0.0
var _menu_fit_key := ""
var _menu_panel: PanelContainer
var _feedback_button: Button
var _feedback_panel: Control
var _menu_pair: BoxContainer
var _graphics_side: PanelContainer
var _storage_screen: CanvasLayer
var _player_info: CanvasLayer
var _controls_button: Button
var _skill_button: Button
var _bag_button: Button
var _shortcut_root: Control
var shortcut_css_override := Vector2.ZERO  ## native visual review only
var _info_button: Button
var _menu_button: Button
var _prompt: Button
var _camp_screen: CanvasLayer  ## the camp screens while they are open
var _creator: CanvasLayer  ## the character creator while it is open
var _warp_screen: Node  ## the warp gate screen while it is open
var _combat  ## CombatData (the weapon's stance)
var _foot_name: Label3D
var _character  ## the player's CharacterModel (null if the model is missing)
var density_override := 0.0  ## > 0: lay the menu out for this screen density and the logical size (screenshots)


func _ready() -> void:
	InputReader.setup_actions()
	world = HubWorld.new()
	add_child(world)
	_build_simulation()
	_build_character()
	_build_npcs()
	_build_camera()
	_build_menu()
	_adventurer = preload("res://client/companions/camp_adventurer.gd").new()
	_adventurer.hub = self
	add_child(_adventurer)
	var invitations=preload("res://client/online/character_invitation.gd").new()
	invitations.hub=self
	add_child(invitations)
	_training_view=preload("res://client/training_arena.gd").new();add_child(_training_view)
	_training_view.setup(_training,_training_looks())
	if not GameState.local_perf_test:
		var plaza := preload("res://client/online/plaza_client.gd").new()
		plaza.hub = self
		add_child(plaza)
	if GameState.account_session != null:
		GameState.account_session.ownership_changed.connect(refresh_character)
	if GameState.ensure_profile() and not GameState.profile.created:
		_open_creator()

func _exit_tree()->void:
	if _training!=null:_training.dispose()


func _process(delta: float) -> void:
	_menu_layout_in -= delta
	if _menu_layout_in <= 0.0:
		_menu_layout_in = 0.5
		_fit_menu()
	if not GameState.online_error.is_empty() and _prompt != null:
		_prompt.text = GameState.online_error
		_prompt.show()
	if _character != null:
		_character.apply_pose(delta)


func _physics_process(_delta: float) -> void:
	var input := SimInput.new()
	if can_walk():
		var read: SimInput = InputReader.read(get_viewport())
		input.move = _touch.vector if _touch != null and _touch.vector != Vector2.ZERO else read.move
		input.move = _rig.movement_from_screen(input.move)
		input.run = read.run
		if _training.enabled:
			input=read
			input.move=_rig.movement_from_screen(read.move)
			_aim_training(input)
	elif _touch != null:
		_touch.release()
	_training.step(input)
	if _touch!=null:
		_touch.enabled=not _training.enabled
		if _training.enabled:_touch.release()
	if is_instance_valid(_training_view):
		_training_view.update()
		_character.visible=not _training.enabled
		_rig.target=_training_view.player if _training.enabled else _character
		_shortcut_root.visible=not _training.enabled
	_show_player()
	_update_near()
	_check_gate()


## The player may walk: no menu or screen is open.
func can_walk() -> bool:
	if get_viewport().gui_get_focus_owner() is LineEdit: return false
	return not has_open_panel()


var _farm_panel: CanvasLayer

func has_open_panel() -> bool:
	if is_instance_valid(_relic_panel): return true
	var invitations=get_meta("character_invitation") if has_meta("character_invitation") else null
	if is_instance_valid(invitations) and invitations.has_open_panel(): return true
	if is_instance_valid(_adventurer) and is_instance_valid(_adventurer.panel): return true
	if is_instance_valid(_farm_panel): return true
	return is_instance_valid(_storage_screen) or is_instance_valid(_player_info) or is_instance_valid(_feedback_panel) or _camp_screen != null or _creator != null or _warp_screen != null or (_menu_panel != null and _menu_panel.visible)


## Where the player's feet are now.
func player_position() -> Vector3:
	return _sim.bodies[PLAYER_ID].position

func training_combat_active()->bool:
	return _training!=null and _training.enabled and can_walk()

func _training_looks()->Dictionary:
	var looks:=ItemAssets.looks(GameState.profile.loadout,GameState.item_rules.catalog,_style)
	looks["appearance"]=ItemAssets.appearance(GameState.profile.appearance)
	looks["relics"]=preload("res://logic/relics.gd").equipped_types(GameState.profile.relics)
	return looks

func _aim_training(input)->void:
	var origin:Vector3=player_position()
	var camera:=get_viewport().get_camera_3d()
	var mobile:bool=is_instance_valid(GameState.mobile_controls) and GameState.mobile_controls.enabled
	if not mobile and camera!=null and get_viewport().gui_get_hovered_control()==null:
		var mouse:=get_viewport().get_mouse_position()
		var point=Plane(Vector3.UP,origin.y).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
		if point is Vector3:
			var delta:=Vector2(point.x-origin.x,point.z-origin.z)
			input.aim=delta.normalized();input.aim_distance=minf(25.5,delta.length());return
	var nearest:=INF
	for id in preload("res://logic/training_ground.gd").DUMMY_IDS:
		var delta:Vector3=_sim.bodies[id].position-origin
		if delta.length()<nearest:
			nearest=delta.length();input.aim=Vector2(delta.x,delta.z).normalized();input.aim_distance=nearest


## Moves the player (tests and screenshots).
func place_player(at: Vector3) -> void:
	_sim.bodies[PLAYER_ID].position = at
	_sim.bodies[PLAYER_ID].velocity = Vector3.ZERO
	_show_player()
	_update_near()


# --- the world ----------------------------------------------------------------------------------------

## The stage's walking rules on the camp's floor, bounds and colliders (logic/movement.gd, no combat).
func _build_simulation() -> void:
	var sim_world := SimWorld.new()
	sim_world.half_width = world.half_extents.x
	sim_world.half_depth = world.half_extents.y
	sim_world.add_solid(AABB(Vector3(-60.0, -1.0, -60.0), Vector3(120.0, 1.0, 120.0)))  # the ground
	for box in world.farm_boundaries(): sim_world.add_solid(box)
	for box in world.solids:
		sim_world.add_solid(box)
	_sim = GameSim.new(sim_world)
	_combat=CombatDataLoader.load_default()
	_training=preload("res://logic/training_ground.gd").new(sim_world,_combat,world.spot("spawn",Vector3(0,0,3.6)))
	_sim=_training.sim
	_sim.bodies[PLAYER_ID].grounded = true


## The player's own character, wearing their gear and looks (refresh_character()).
func _build_character() -> void:
	_combat = CombatDataLoader.load_default()
	var model := CharacterModel.new()
	add_child(model)
	if not model.load_model():
		model.queue_free()
		return
	_character = model
	_foot_name = preload("res://client/character_foot_name.gd").new()
	_character.add_child(_foot_name)
	CharacterLight.light_scene(self, world.environment, 0.35, 0.9)  # (the night is dark: let the player see their look)
	refresh_character()
	_show_player()


## Puts the profile's gear and looks on the character.
func refresh_character() -> void:
	if is_instance_valid(world):
		world.refresh_facilities()
		if _sim != null:
			_sim.world.half_width = world.half_extents.x
			_sim.world.solids.clear()
			_sim.world.add_solid(AABB(Vector3(-60, -1, -60), Vector3(120, 1, 120)))
			for box in world.solids: _sim.world.add_solid(box)
			for box in world.farm_boundaries(): _sim.world.add_solid(box)
		if is_instance_valid(_rig):
			_rig.max_x = maxf(0.0, world.half_extents.x - CAMERA_MARGIN.x)
			_rig.min_x=-25
	if _character == null or not GameState.ensure_profile():
		return
	var loadout = GameState.profile.loadout
	if _sim != null and _sim.fighters.has(PLAYER_ID):
		_sim.fighters[PLAYER_ID].stats = _combat.full_stats(preload("res://logic/stats.gd").totals(GameState.item_rules,loadout.items()))
	_style = loadout.weapon_style(_combat.styles.keys())
	_training.configure(preload("res://logic/stats.gd").totals(GameState.item_rules,loadout.items()),_style,GameState.profile.skill_build,GameState.profile.relics)
	var looks := ItemAssets.looks(loadout, GameState.item_rules.catalog, _style)
	looks["appearance"] = ItemAssets.appearance(GameState.profile.appearance)
	looks["relics"]=preload("res://logic/relics.gd").equipped_types(GameState.profile.relics)
	_character.dress(looks)
	if is_instance_valid(_training_view):_training_view.refresh(looks)
	if _foot_name != null:
		_foot_name.text = GameState.profile.name
	_show_player()


func _show_player() -> void:
	if _character == null:
		return
	var body = _sim.bodies[PLAYER_ID]
	_character.position = body.position
	var flat := Vector2(body.velocity.x, body.velocity.z)
	if flat.length() > 0.05:
		_facing = flat.normalized()
	var speed := flat.length() / Movement.SPEED
	var kind := "idle"
	if speed > 0.1:
		kind = "run" if speed > 1.2 else "walk"
	_character.set_pose(kind, 0.0, speed, body.grounded, _facing, false, "", "", _style)


func _build_npcs() -> void:
	var fire: Vector3 = world.spot("campfire")
	for entry in NPCS:
		var at: Vector3 = world.spot("npc_" + str(entry["role"]), Vector3(-4.5,0,-6.0) if entry.role=="relic_master" else Vector3.INF)
		if at == Vector3.INF:
			continue
		var npc = preload("res://client/workshop_npc.gd").new() if str(entry["role"]).begins_with("bs_") else HubNpc.new()
		if str(entry["role"]).begins_with("bs_"): npc.workshop_type = str(entry["action"])
		npc.role = entry["role"]
		npc.display_name = entry["name"]
		if npc is HubNpc: npc.icon_name = entry["icon"]
		npc.position = at
		add_child(npc)
		var to_fire := Vector2(fire.x - at.x, fire.z - at.z).normalized()
		npc.face(to_fire.lerp(Vector2(0.0, 1.0), 0.45))
		npcs.append(npc)


func _build_camera() -> void:
	_rig = CameraRig.new()
	_rig.input_allowed = can_walk
	_rig.target = _character if _character != null else self
	_rig.follow_depth = true
	_rig.min_x = -maxf(0.0, world.half_extents.x - CAMERA_MARGIN.x)
	_rig.max_x = -_rig.min_x
	_rig.min_x=-25
	_rig.min_z = -maxf(0.0, world.half_extents.y - CAMERA_MARGIN.y - 1.5)
	_rig.max_z = maxf(0.0, world.half_extents.y - CAMERA_MARGIN.y)
	add_child(_rig)


# --- talking, the campfire and the gate --------------------------------------------------------------

## Finds what the player stands near (the nearest NPC in reach, else the campfire) and shows the prompt.
func _update_near() -> void:
	if _training.enabled:
		_near={}
		if _prompt!=null:_prompt.hide()
		return
	var at := player_position()
	var best := {}
	var best_distance := INF
	for i in npcs.size():
		var d := _flat_distance(at, npcs[i].position)
		if d <= TALK_RADIUS and d < best_distance:
			best_distance = d
			best = {"kind": "npc", "index": i}
	if best.is_empty() and _flat_distance(at, world.spot("campfire")) <= FIRE_RADIUS:
		best = {"kind": "fire"}
	if preload("res://logic/farm.gd").unlocked(GameState.profile):
		for i in range(4):
			if _flat_distance(at,world.farm_plot_position(i)) <= 2.3: best={"kind":"farm","index":i}
	_near = best if can_walk() else {}
	if _prompt == null:
		return
	_prompt.visible = not _near.is_empty()
	if _near.get("kind", "") == "npc":
		_prompt.text = TEXT["talk"] % npcs[_near["index"]].display_name
	elif _near.get("kind", "") == "farm":
		_prompt.text = "[E] จัดการแปลง %d" % (int(_near.index)+1)
	elif _near.get("kind", "") == "fire":
		_prompt.text = TEXT["fire"]


## What standing here and pressing E (or tapping the prompt) does: {} = nothing.
func near_target() -> Dictionary:
	return _near


## Talks to the NPC (or uses the campfire) the player stands near.
func interact() -> void:
	if _near.is_empty() or not can_walk():
		return
	if _near["kind"] == "farm":
		_farm_panel=preload("res://client/farm_panel.gd").new()
		add_child(_farm_panel)
		_farm_panel.setup(GameState.profile,GameState.get_session(),int(_near.index))
		return
	if _near["kind"] == "fire":
		_open_camp(3)
		return
	var npc = npcs[_near["index"]]
	var entry: Dictionary = _npc_entry(npc.role)
	match str(entry.get("action", "")):
		"relics":
			_relic_panel=preload("res://client/relic_panel.gd").new()
			add_child(_relic_panel)
			_relic_panel.setup(GameState.profile,GameState.get_session())
		"storage":
			_open_storage()
		"merchant":
			_open_camp(0, false, true)
		"refine", "upgrade":
			npc.set_talking(true)
			_open_camp(0, true, false, false, str(entry["action"]))
			if _camp_screen != null: _camp_screen.closed.connect(func(): if is_instance_valid(npc): npc.set_talking(false))
		"camp":
			_open_camp(int(entry.get("tab", 0)))
		"soon":
			npc.say(str(entry.get("line", "")))
			Audio.play_ui("open")


func _npc_entry(role: String) -> Dictionary:
	for entry in NPCS:
		if entry["role"] == role:
			return entry
	return {}


func npc(role: String):
	for each in npcs:
		if each.role == role:
			return each
	return null


## Stepping into the gate's ring opens the gate screen once; it opens again after the player leaves.
func _check_gate() -> void:
	var d := _flat_distance(player_position(), world.spot("warp_gate", Vector3.INF))
	if d > GATE_REARM:
		_gate_armed = true
	elif d <= GATE_RADIUS and _gate_armed and can_walk():
		_gate_armed = false
		open_warp_gate()


## The warp gate's screen (Journey / Farm / PvP). Until the gate screen exists, this hub's own menu.
func open_warp_gate() -> void:
	if ResourceLoader.exists(WARP_GATE_SCREEN):
		var script := load(WARP_GATE_SCREEN) as Script
		if script != null and script.can_instantiate():
			_warp_screen = script.new()
			_warp_screen.skill_requested.connect(func() -> void: _open_camp(4))
			add_child(_warp_screen)
			if _warp_screen.has_signal("closed"):
				_warp_screen.closed.connect(func() -> void: _warp_screen = null)
			Audio.play_ui("open")
			return
	open_menu()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if is_instance_valid(_storage_screen) or is_instance_valid(_player_info) or _camp_screen != null or _creator != null or _warp_screen != null:
		return  # (those screens have the keyboard)
	var key := key_event.physical_keycode
	if key == KEY_ESCAPE:
		if _menu_panel.visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif key == KEY_E and can_walk():
		interact()
		get_viewport().set_input_as_handled()
	elif CameraRig.PRESETS.has(key) and can_walk():
		_rig.choose(CameraRig.PRESETS[key])


# --- the menu and the hub's buttons ------------------------------------------------------------------

## Stages come from map data: adding a map file (and listing it in data/maps/index.json) adds a button.
func _stages_for(mode: GameState.Mode) -> Array:
	var stages: Array = []
	for map in MapLoader.list_for_mode(GameState.mode_key(mode)):
		stages.append({"name": map.display_name, "id": map.id})
	return stages


## The hub's screen layer: the Menu button (top left), the talk prompt (bottom), the touch stick, and
## the menu (a brass-framed window on the left; a bottom sheet on an upright phone), hidden until opened.
func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_touch = HubTouch.new()
	layer.add_child(_touch)
	_menu_root = Control.new()
	_menu_root.theme = InkUi.make_theme(InkUi.FONT_SECTION)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_menu_root)
	_shortcut_root = Control.new()
	_shortcut_root.theme = _menu_root.theme
	_shortcut_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_shortcut_root)

	_menu_button = preload("res://client/hub_shortcut_button.gd").new()
	_menu_button.caption = TEXT["menu"]
	_menu_button.symbol = "menu_bold"
	_menu_button.position = Vector2(InkUi.EDGE_WIDE, InkUi.EDGE_WIDE)
	_menu_button.pressed.connect(open_menu)
	_shortcut_root.add_child(_menu_button)
	_info_button = preload("res://client/hub_shortcut_button.gd").new()
	_info_button.caption = "Player Info"
	_info_button.symbol = "player_info"
	_info_button.pressed.connect(_open_player_info)
	_shortcut_root.add_child(_info_button)
	_bag_button = preload("res://client/hub_shortcut_button.gd").new()
	_bag_button.caption = "Bag"
	_bag_button.symbol = "bag"
	_bag_button.pressed.connect(_open_backpack)
	_shortcut_root.add_child(_bag_button)
	_skill_button = Button.new()
	preload("res://client/skill_menu_icon.gd").apply(_skill_button)
	_skill_button.pressed.connect(_open_camp.bind(4))
	_shortcut_root.add_child(_skill_button)
	_controls_button = preload("res://client/hub_shortcut_button.gd").new()
	_controls_button.caption = "Controls"
	_controls_button.custom_texture = preload("res://assets/ui/hub_shortcuts/keyboard.png")
	_controls_button.pressed.connect(func():
		if OS.has_feature("web"):
			JavaScriptBridge.eval("if (window.zorxShowControls) window.zorxShowControls();"))
	_shortcut_root.add_child(_controls_button)
	_skill_button.visible = preload("res://logic/skill_build.gd").enabled()
	_controls_button.visible = _desktop_controls_available()

	_feedback_button = Button.new()
	_feedback_button.text = "Feedback"
	_feedback_button.custom_minimum_size = Vector2(132, 44)
	_feedback_button.pressed.connect(_open_feedback)
	_menu_root.add_child(_feedback_button)

	_prompt = Button.new()
	_prompt.name = "TalkPrompt"
	InkUi.make_primary(_prompt)
	_prompt.custom_minimum_size = Vector2(360.0, 60.0)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -InkUi.EDGE_HUB
	_prompt.focus_mode = Control.FOCUS_NONE
	_prompt.visible = false
	_prompt.pressed.connect(interact)
	_menu_root.add_child(_prompt)

	_menu_margin = MarginContainer.new()
	_menu_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(_menu_margin)
	_menu_pair = BoxContainer.new()
	InkUi.gap(_menu_pair, InkUi.GAP_M)
	_menu_margin.add_child(_menu_pair)
	_menu_panel = PanelContainer.new()
	InkUi.panel(_menu_panel, InkUi.camp_menu_window_style())
	_menu_pair.add_child(_menu_panel)
	var holder := VBoxContainer.new()
	_menu_holder = holder
	InkUi.gap(holder, InkUi.GAP_M)
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.follow_focus = true
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_panel.add_child(_menu_scroll)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(holder)

	var heading := HBoxContainer.new()
	_menu_heading = heading
	_menu_header_texture = load("res://assets/ui/camp_menu/farm-v1.png")
	heading.draw.connect(_draw_menu_header)
	InkUi.gap(heading, InkUi.GAP_M)
	holder.add_child(heading)
	var emblem := TextureRect.new()
	_menu_emblem = emblem
	emblem.texture = InkUi.icon("menu_fire", 64)
	emblem.custom_minimum_size = Vector2(48, 48)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(emblem)
	var title := InkUi.label(TEXT["subtitle"], InkUi.GOLD, InkUi.FONT_DISPLAY)
	_menu_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(title)
	InkUi.add_close(heading, close_menu)

	_main_menu = VBoxContainer.new()
	InkUi.gap(_main_menu, InkUi.GAP_M)
	holder.add_child(_main_menu)
	_menu_section("Play Modes")
	_play_grid = _menu_grid(_main_menu, 2)
	_first_button = _menu_card(_play_grid, "PvE - Farm", "", "menu_farm", _open_stage_menu.bind(GameState.Mode.PVE), true)
	_menu_card(_play_grid, "PvE - Journey", "12 stages", "journey", func() -> void: GameState.start_journey(), true)
	_menu_card(_play_grid, "เล่นออนไลน์", "", "online", _open_online_room, true)
	_menu_card(_play_grid, "PvP", "", "menu_pvp", _open_stage_menu.bind(GameState.Mode.PVP), true)
	_menu_section("Management")
	_management_grid = _menu_grid(_main_menu, 3)
	_menu_card(_management_grid, "Camp", "Gear, Stash, Repair", "menu_camp", _open_camp)
	_menu_card(_management_grid, "Customize", "Face, Hair, Skin", "menu_customize", _open_camp.bind(LOOK_TAB))
	if preload("res://logic/skill_build.gd").enabled():
		_menu_card(_management_grid, "Skill", "สกิล · Gem · Passive", "upgrade", _open_camp.bind(4))
	_menu_card(_management_grid, "Feedback", "แจ้งปัญหา", "feedback", _open_feedback)
	_menu_section("System")
	_system_grid = _menu_grid(_main_menu, 2 if OS.has_feature("web") else 1)
	if OS.has_feature("web"):
		_menu_card(_system_grid, "Logout", "", "logout", _logout)


	_stage_menu = VBoxContainer.new()
	InkUi.gap(_stage_menu, InkUi.GAP_S)
	_stage_menu.visible = false
	holder.add_child(_stage_menu)
	_menu_panel.visible = false
	_graphics_side = PanelContainer.new()
	InkUi.panel(_graphics_side, InkUi.camp_menu_window_style())
	_graphics_side.custom_minimum_size.x = 620
	_menu_pair.add_child(_graphics_side)
	var graphics_box := VBoxContainer.new()
	InkUi.gap(graphics_box, InkUi.GAP_M)
	_graphics_side.add_child(graphics_box)
	var graphics_heading := HubMenuCard.Section.new()
	graphics_heading.title = "Graphics"
	_section_headers.append(graphics_heading)
	graphics_box.add_child(graphics_heading)
	var settings := preload("res://client/graphics_panel.gd").contents(true)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_box.add_child(settings)
	for control in settings.find_children("*", "CheckButton", true, false):
		control.add_theme_stylebox_override("normal", InkUi.plate(InkUi.INK, InkUi.GOLD, 0.6))
		control.add_theme_stylebox_override("pressed", InkUi.plate(InkUi.INK, InkUi.GOLD, 1.0))
	_menu_pair.visible = false

	get_viewport().size_changed.connect(_fit_menu)
	_fit_menu()


## Opens the hub menu (Farm, Journey, PvP, Camp, Customize).
func open_menu() -> void:
	if is_instance_valid(_storage_screen) or is_instance_valid(_player_info) or _camp_screen != null or _creator != null:
		return
	_stage_menu.visible = false
	_main_menu.visible = true
	_menu_panel.visible = true
	_menu_pair.visible = true
	_menu_button.visible = false
	_info_button.visible = false
	_bag_button.visible = false
	_skill_button.visible = false
	_controls_button.visible = false
	_prompt.visible = false
	_menu_fit_key = ""
	_fit_menu()
	_first_button.grab_focus()


func close_menu() -> void:
	_menu_panel.visible = false
	_menu_pair.visible = false
	_menu_button.visible = true
	_info_button.visible = true
	_bag_button.visible = true
	_skill_button.visible = preload("res://logic/skill_build.gd").enabled()
	_controls_button.visible = _desktop_controls_available()
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()


## Scales the menu to the screen; upright phones get it as a full-width sheet at the bottom.
func _fit_menu() -> void:
	if _menu_root == null or not is_inside_tree():
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	var density := DisplayServer.screen_get_scale()
	if density_override > 0.0:
		window = logical * density_override
		density = density_override
	var layout := InkUi.layout_for(window, logical, density)
	var css := window / maxf(density, 0.01)
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("JSON.stringify((() => { const c = document.getElementById('canvas'); if (!c) return []; const r = c.getBoundingClientRect(); return [r.width, r.height]; })())", true)
		var parsed = JSON.parse_string(str(raw))
		if parsed is Array and parsed.size() == 2 and float(parsed[1]) > 0.0:
			css = Vector2(float(parsed[0]), float(parsed[1]))
	if shortcut_css_override.x > 0 and shortcut_css_override.y > 0: css = shortcut_css_override
	var fit_key := "%s|%s|%s" % [logical, css, density]
	if fit_key == _menu_fit_key:
		return
	_menu_fit_key = fit_key
	var compact := css.y < 600.0 or css.x < 600.0
	if compact:
		layout["mode"] = InkUi.PORTRAIT if css.x < css.y * 0.9 else InkUi.COMPACT
		layout["scale"] = logical.y / maxf(css.y, 1.0) * 0.85
		layout["size"] = logical / float(layout["scale"])
	_menu_root.scale = Vector2.ONE * float(layout["scale"])
	_menu_root.size = layout["size"]
	var upright: bool = layout["mode"] == InkUi.PORTRAIT
	var edge: int = InkUi.EDGE_PORTRAIT if upright else (InkUi.EDGE_HUB if layout["mode"] == InkUi.WIDE else InkUi.EDGE_COMPACT)
	InkUi.margins(_menu_margin, edge)
	_menu_pair.vertical = upright
	_menu_pair.size_flags_horizontal = Control.SIZE_FILL if upright else Control.SIZE_SHRINK_BEGIN
	_menu_pair.size_flags_vertical = Control.SIZE_SHRINK_END if upright else Control.SIZE_SHRINK_CENTER
	_graphics_side.custom_minimum_size = Vector2(620.0, 0.0)
	_menu_panel.size_flags_horizontal = Control.SIZE_FILL if upright else Control.SIZE_SHRINK_BEGIN
	_menu_panel.size_flags_vertical = Control.SIZE_SHRINK_END if upright else Control.SIZE_SHRINK_CENTER
	_menu_panel.custom_minimum_size.x = minf(500.0 if compact else 720.0, maxf(0.0, _menu_root.size.x - edge * 2.0))
	_menu_panel.custom_minimum_size.y = 0.0
	_menu_emblem.custom_minimum_size = Vector2.ONE * (36.0 if compact else 64.0)
	_menu_heading.custom_minimum_size.y = 40.0 if compact else 96.0
	InkUi.text_size(_menu_title, InkUi.FONT_TITLE if compact else roundi(InkUi.FONT_DISPLAY * 1.5))
	InkUi.gap(_menu_holder, InkUi.GAP_XXS if compact else InkUi.GAP_M)
	InkUi.gap(_main_menu, InkUi.GAP_XXS if compact else InkUi.GAP_M)
	for grid in [_play_grid, _management_grid, _system_grid]:
		InkUi.gap(grid, InkUi.GAP_S if compact else InkUi.GAP_M, InkUi.GAP_S if compact else InkUi.GAP_M)
	for section in _section_headers:
		InkUi.camp_menu_section_text(section.label, InkUi.FONT_SMALL if compact else InkUi.FONT_HEADING)
		section.custom_minimum_size.y = section.label.get_minimum_size().y + 4.0
	for card in _menu_cards:
		var scenic: bool = card.scenic
		var management: bool = card.get_parent() == _management_grid
		card.custom_minimum_size = Vector2(0.0, (80.0 if compact else 180.0) if scenic else ((62.0 if compact else 96.0) if management else (44.0 if compact else 56.0)))
		if card._title != null:
			InkUi.camp_menu_card_text(card._title, (InkUi.FONT_LABEL if management else InkUi.FONT_BODY) if compact else (InkUi.FONT_TITLE if scenic else InkUi.FONT_HEADING))
			InkUi.text_size(card._caption, InkUi.FONT_TINY if compact else InkUi.FONT_CAPTION)
	for child in _stage_menu.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(260.0 if compact else 300.0, 44.0 if compact else 56.0)
			InkUi.text_size(child, InkUi.FONT_BODY if compact else InkUi.FONT_SECTION)

	# Shortcuts keep a 60×60 CSS-pixel hit box; menu-content fitting never shrinks them.
	var shortcut_scale := logical.y / maxf(css.y, 1.0)
	_shortcut_root.scale = Vector2.ONE * shortcut_scale
	_shortcut_root.size = logical / shortcut_scale
	_menu_button.position = Vector2(14, 14)
	_info_button.position = Vector2(14, 78)
	_bag_button.position = Vector2(14, 142)
	_skill_button.position = Vector2(14, 206)
	_controls_button.position = Vector2(14, 270)
	_feedback_button.position = Vector2(_menu_root.size.x - edge - 132, edge)
	_feedback_button.visible = false
	_prompt.offset_bottom = -(InkUi.EDGE_HUB if layout["mode"] == InkUi.WIDE else InkUi.EDGE_WIDE)
	_fit_menu_contents.call_deferred()
	# NPC names keep one size on screen: the menu's scale, larger on phones (read at arm's length).
	var label_scale := float(layout["scale"]) * (1.0 if layout["mode"] == InkUi.WIDE else 2.4)
	for person in npcs:
		person.set_screen_scale(label_scale)


## Scale the complete laid-out content, including fonts, borders and every row.
## Never substitute a scrolling viewport for fitting the menu on the screen.
func _fit_menu_contents() -> void:
	if not is_inside_tree() or _menu_panel == null:
		return
	var logical := get_viewport().get_visible_rect().size
	var minimum := _menu_pair.get_combined_minimum_size()
	var horizontal := float(_menu_margin.get_theme_constant("margin_left") + _menu_margin.get_theme_constant("margin_right"))
	var vertical := float(_menu_margin.get_theme_constant("margin_top") + _menu_margin.get_theme_constant("margin_bottom")) + 16.0
	var fit := minf(_menu_root.scale.x, minf(logical.x / maxf(1.0, minimum.x + horizontal), logical.y / maxf(1.0, minimum.y + vertical)))
	_menu_root.scale = Vector2.ONE * fit
	_menu_root.size = logical / fit
	_menu_scroll.scroll_vertical = 0


## Opens the camp screens (on tab `tab`): what the player wears and owns, their looks, repairs and
## camp upgrades.
func _open_camp(tab: int = 0, smith: bool = false, merchant: bool = false, backpack: bool = false, smith_role: String = "") -> void:
	if not GameState.ensure_profile() or _camp_screen != null or _creator != null:
		return
	close_menu()
	_prompt.visible = false
	_camp_screen = CampScreen.new()
	_camp_screen.skill_mode = tab == 4 and not smith and not merchant and not backpack
	_camp_screen.backpack_mode = backpack
	_camp_screen.blacksmith_mode = smith
	_camp_screen.smith_role = smith_role
	_camp_screen.merchant_mode = merchant
	add_child(_camp_screen)
	_camp_screen.setup(GameState.profile, GameState.camp_data, GameState.item_rules, _combat, null, "", null, GameState.get_session())
	_camp_screen.show_tab(tab)
	_camp_screen.closed.connect(func() -> void:
		_camp_screen = null
		refresh_character())


## A new player makes their character first.
func _open_creator() -> void:
	close_menu()
	_creator = CharacterCreator.new()
	add_child(_creator)
	_creator.setup(GameState.profile, GameState.item_rules, _combat, GameState.get_session())
	_creator.look.changed.connect(refresh_character)
	_creator.created.connect(func() -> void:
		_creator = null
		refresh_character())



func _draw_menu_header() -> void:
	var area := _menu_heading.size
	var art := Rect2(Vector2(area.x * 0.46, 0.0), Vector2(area.x * 0.54, area.y - 4.0))
	if _menu_header_texture != null and art.size.y > 0.0:
		var tint := InkUi.PAPER
		tint.a = 0.42
		_menu_heading.draw_texture_rect_region(_menu_header_texture, art, HubMenuCard.cover_region(_menu_header_texture, art.size), tint)
	var y := area.y - 1.0
	_menu_heading.draw_line(Vector2(0,y),Vector2(area.x*0.45,y),InkUi.BORDER,0.9,true)
	_menu_heading.draw_line(Vector2(area.x*0.55,y),Vector2(area.x,y),InkUi.BORDER,0.9,true)
	var at := Vector2(area.x*0.5,y)
	_menu_heading.draw_polyline(PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0),at+Vector2(0,-4)]),InkUi.GOLD,1.0,true)


func _menu_section(title: String) -> void:
	var section := HubMenuCard.Section.new()
	section.title = title
	_section_headers.append(section)
	_main_menu.add_child(section)


func _menu_grid(parent: Control, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(grid, InkUi.GAP_M, InkUi.GAP_M)
	parent.add_child(grid)
	return grid


func _menu_card(parent: Control, title: String, caption: String, symbol: String, callback: Callable, scenic: bool = false) -> Button:
	var card := HubMenuCard.new()
	# Retain the established semantic labels while the card renders title/caption separately.
	var labels := {"PvE - Farm": TEXT["farm"], "PvE - Journey": TEXT["journey"], "Camp": TEXT["camp"], "Customize": TEXT["customize"], "Feedback": "Feedback / แจ้งปัญหา", "Logout": "ออกจากระบบ / Logout"}
	card.text = str(labels.get(title, title))
	card.clip_text = true
	card.card_title = title
	card.caption = caption
	card.symbol = symbol
	card.scenic = scenic
	card.scenery_seed = _menu_cards.size()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(callback)
	_menu_cards.append(card)
	parent.add_child(card)
	return card


func _add_button(parent: Control, text: String, callback: Callable, icon_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(300.0, 56.0)
	if icon_name != "":
		InkUi.icon_button(button, icon_name, 26)
	if callback.is_valid():
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _open_stage_menu(mode: GameState.Mode) -> void:
	for child in _stage_menu.get_children():
		_stage_menu.remove_child(child)
		child.queue_free()
	_stage_menu.add_child(InkUi.brush_title(TEXT["choose_stage"] if mode == GameState.Mode.PVE else TEXT["pvp_arenas"]))

	var stages := _stages_for(mode)
	if stages.is_empty():
		_stage_menu.add_child(InkUi.label(TEXT["empty"], InkUi.MUTED))
	var focus_target: Button = null
	for stage in stages:
		var stage_button := _add_button(_stage_menu, stage["name"], GameState.start_stage.bind(mode, stage["id"]), "pve" if mode == GameState.Mode.PVE else "pvp")
		if focus_target == null:
			focus_target = stage_button
	var back := _add_button(_stage_menu, TEXT["back"], _close_stage_menu, "back_arrow")
	if focus_target == null:
		focus_target = back

	_main_menu.visible = false
	_stage_menu.visible = true
	_menu_fit_key = ""
	_fit_menu()
	focus_target.grab_focus()


func _close_stage_menu() -> void:
	_stage_menu.visible = false
	_main_menu.visible = true
	_menu_fit_key = ""
	_fit_menu()
	_first_button.grab_focus()


func _logout() -> void:
	var online := get_node_or_null("/root/Online")
	if online != null:
		online.logout_to_website()


func _open_online_room() -> void:
	if GameState.local_perf_test: return
	close_menu()
	var panel = preload("res://client/online/room_panel.gd").new()
	panel.closed.connect(open_menu)
	add_child(panel)

func _open_feedback() -> void:
	if is_instance_valid(_feedback_panel): return
	_feedback_panel = preload("res://client/feedback_panel.gd").new()
	_menu_root.add_child(_feedback_panel)


func _open_player_info() -> void:
	if not GameState.ensure_profile() or is_instance_valid(_player_info) or _camp_screen != null or _creator != null: return
	close_menu()
	_prompt.visible = false
	_menu_button.visible = false
	_info_button.visible = false
	_bag_button.visible = false
	_skill_button.visible = false
	_controls_button.visible = false
	_player_info = preload("res://client/player_info_panel.gd").new()
	add_child(_player_info)
	_player_info.setup(GameState.profile, GameState.item_rules, GameState.get_session())
	_player_info.closed.connect(func():
		_player_info = null
		_menu_button.visible = true
		_info_button.visible = true
		_bag_button.visible = true
		_skill_button.visible = preload("res://logic/skill_build.gd").enabled()
		_controls_button.visible = _desktop_controls_available()
		_info_button.grab_focus())


func _open_storage() -> void:
	if not GameState.ensure_profile() or is_instance_valid(_storage_screen) or _camp_screen != null or _creator != null or is_instance_valid(_player_info): return
	close_menu()
	_prompt.visible = false
	_menu_button.visible = false
	_info_button.visible = false
	_bag_button.visible = false
	_skill_button.visible = false
	_controls_button.visible = false
	_storage_screen = preload("res://client/storage_panel.gd").new()
	add_child(_storage_screen)
	_storage_screen.setup(GameState.profile, GameState.item_rules, GameState.camp_data, GameState.get_session())
	_storage_screen.closed.connect(func():
		_storage_screen = null
		_menu_button.visible = true
		_info_button.visible = true
		_bag_button.visible = true
		_skill_button.visible = preload("res://logic/skill_build.gd").enabled()
		_controls_button.visible = _desktop_controls_available()
		refresh_character())


func _open_backpack() -> void:
	_open_camp(0, false, false, true)

func _desktop_controls_available() -> bool:
	if not OS.has_feature("web"): return false
	return not bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0 || window.matchMedia('(any-pointer: coarse)').matches"))

func _unhandled_input(event: InputEvent) -> void:
	if not can_walk() or not preload("res://logic/farm.gd").unlocked(GameState.profile): return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: point=event.position
	elif event is InputEventScreenTouch and event.pressed: point=event.position
	else: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var hit = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
	if hit == null: return
	for i in range(4):
		if Vector3(hit).distance_to(world.farm_plot_position(i)) < 1.8 and _flat_distance(player_position(),world.farm_plot_position(i)) < 2.3:
			_near={"kind":"farm","index":i};interact();get_viewport().set_input_as_handled();return
