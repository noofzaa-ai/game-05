extends Node3D
## Camp resident using the main character renderer. Combat starts only in a trusted Room.
const Roster := preload("res://logic/companions/roster.gd")
const Character := preload("res://client/characters/studio05_character_model.gd")
const Body := preload("res://logic/sim_body.gd")
const Movement := preload("res://logic/movement.gd")
const Ink := preload("res://client/ink_ui.gd")
var hub
var model
var body := Body.new()
var navigation := preload("res://logic/companions/navigation.gd").new()
var entry := Roster.get_entry("arun")
var waypoint := 0
const REST_MIN_TICKS := 45 * 60
const REST_MAX_TICKS := 90 * 60
const MOVE_TICKS := 2 * 60
const CAMP_WALK_SCALE := 0.35
var rest_ticks := 60 * 60
var move_ticks := 0
var rest_rng := RandomNumberGenerator.new()
var button: Button
var panel
var facing := Vector2.DOWN
var style := "blade"
var label: Label3D
var offer_ready := false
var fetching := false
var offer_seed := ""

func _ready() -> void:
	if hub == null or entry.is_empty(): return
	var profile = Roster.make_profile("arun", GameState.item_rules, GameState.camp_data)
	if profile == null: return
	body.position = Vector3(float(entry.camp_route[0][0]), 0.05, float(entry.camp_route[0][1]))
	model = Character.new()
	add_child(model)
	if not model.load_model(): return
	var looks := preload("res://client/item_assets.gd").looks(profile.loadout, GameState.item_rules.catalog, "blade")
	looks.appearance = preload("res://client/item_assets.gd").appearance(profile.appearance)
	model.dress(looks)
	label = Label3D.new()
	label.text = str(entry.name)
	label.font = Ink.font()
	label.font_size = 48
	label.pixel_size = 0.006
	label.position.y = 1.65
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Ink.GOLD
	model.add_child(label)
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	button = Button.new()
	button.theme = Ink.make_theme()
	button.text = "ชวน " + str(entry.name) + " ร่วมเดินทาง"
	button.custom_minimum_size = Vector2(240, 48)
	button.pressed.connect(_invite)
	layer.add_child(button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	model.hide()
	button.hide()
	var service = get_node_or_null("/root/Online")
	if service != null: service.changed.connect(_fetch_offer)
	_fetch_offer.call_deferred()

func _layout() -> void:
	if button == null: return
	var size := get_viewport().get_visible_rect().size
	button.size = Vector2(minf(300, size.x-24), 48)
	button.position = Vector2((size.x-button.size.x)*0.5, size.y-112)

func _physics_process(_dt: float) -> void:
	if hub == null or model == null: return
	var near: bool = hub.player_position().distance_to(body.position) < 2.8
	button.visible = false # Character selection owns the shared invite menu for humans and companions.
	var frame = _camp_frame(near,is_instance_valid(panel))
	if near: facing = Vector2(hub.player_position().x-body.position.x,hub.player_position().z-body.position.z).normalized()
	var events: Array[Dictionary] = []
	Movement.step(4, body, frame, hub._sim.world, events)
	model.position = body.position
	if frame.move.length_squared() > 0.01: facing = frame.move
	model.set_pose("walk" if frame.move.length_squared()>0.01 else "idle", 0.0, frame.move.length(), body.grounded, facing, false, "", "", style)

func _camp_frame(near: bool, panel_open: bool):
	var frame := preload("res://logic/sim_input.gd").new()
	if near or panel_open: return frame
	if rest_ticks > 0:
		rest_ticks -= 1
		return frame
	if move_ticks <= 0: move_ticks = MOVE_TICKS
	var point: Array = entry.camp_route[waypoint]
	var goal := Vector3(float(point[0]),body.position.y,float(point[1]))
	if Vector2(body.position.x-goal.x,body.position.z-goal.z).length() < 0.55:
		waypoint=(waypoint+1)%entry.camp_route.size()
		move_ticks=0
		rest_ticks=rest_rng.randi_range(REST_MIN_TICKS,REST_MAX_TICKS)
		return frame
	frame.move=navigation.direction(hub._sim.world,body.position,goal)*CAMP_WALK_SCALE
	move_ticks-=1
	if move_ticks==0:rest_ticks=rest_rng.randi_range(REST_MIN_TICKS,REST_MAX_TICKS)
	return frame

func _process(delta: float) -> void:
	if model != null: model.apply_pose(delta)

func _invite() -> void:
	if not offer_ready or is_instance_valid(panel) or not hub.can_walk(): return
	panel = preload("res://client/online/room_panel.gd").new()
	panel.invite_target = "companion:" + offer_seed
	add_child(panel)
	button.hide()

func _fetch_offer() -> void:
	if fetching or offer_ready or model == null: return
	if GameState.local_perf_test:
		_apply_offer(43017)
		return
	var service = get_node_or_null("/root/Online")
	if service == null or service.session == null: return
	fetching = true
	var response = await service.client.rpc_async(service.session,"zorx_companion_v1",'{"v":1}')
	fetching = false
	if not is_inside_tree() or response == null or response.is_exception(): return
	var value = JSON.parse_string(response.payload)
	if not value is Dictionary or not value.get("ok",false) or not value.get("seed") is String: return
	if RegEx.create_from_string("^[a-f0-9]{13}$").search(value.seed)==null: return
	offer_seed = value.seed
	_apply_offer(str(value.seed).hex_to_int())

func _apply_offer(seed_value: int) -> void:
	var profile = Roster.make_profile("arun",GameState.item_rules,GameState.camp_data,seed_value)
	if profile == null: return
	rest_rng.seed=seed_value
	rest_ticks=rest_rng.randi_range(REST_MIN_TICKS,REST_MAX_TICKS)
	move_ticks=0
	style = profile.loadout.weapon_style(hub._combat.styles.keys())
	var looks := preload("res://client/item_assets.gd").looks(profile.loadout,GameState.item_rules.catalog,style)
	looks.appearance = preload("res://client/item_assets.gd").appearance(profile.appearance)
	model.dress(looks)
	entry.name = profile.name
	label.text = profile.name
	button.text = "ชวน " + profile.name + " ร่วมเดินทาง"
	offer_ready = true
	model.show()
