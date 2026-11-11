extends RefCounted
## Local authority implementing the future Session boundary. UI receives read views;
## gameplay/ownership writes go through step(), command() or lifecycle methods here.
const Commands := preload("res://logic/commands.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const PartyJourney := preload("res://logic/coop_journey.gd")
const Journey := preload("res://logic/journey.gd")
const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const Cosmetics := preload("res://logic/cosmetic_options.gd")
const TestKit := preload("res://logic/test_kit.gd")
const Camp := preload("res://logic/camp.gd")

var profile
var rules
var camp
var loot
var journey
var run
var _sim: GameSim
var squad_classes: Array = []  ## auto-battler: class id of squad member 1, 2, 3 (fighter id - 1); the class picks the fighting style
var _auto_memory: Dictionary = {}
const AutoPilot := preload("res://logic/auto_pilot.gd")
var _map
var _player_id := 1
var _menu_open := false
var _point_id := ""
var _location := "camp"
var _command_rng := RandomNumberGenerator.new()
var cosmetics

# These are borrowed read views, not mutation APIs. RemoteSession will provide equivalent views.
var bodies: Dictionary:
	get: return _sim.bodies if _sim != null else {}
var fighters: Dictionary:
	get: return _sim.fighters if _sim != null else {}
var events: Array:
	get: return _sim.events if _sim != null else []
var projectiles: Array:
	get: return _sim.projectiles if _sim != null else []
var areas: Array:
	get: return _sim.areas if _sim != null else []
var combat:
	get: return _sim.combat if _sim != null else null
var tick_count: int:
	get: return _sim.tick_count if _sim != null else 0

func _init(player = null, item_rules = null, camp_data = null, loot_data = null, options = null) -> void:
	profile = player
	rules = item_rules
	camp = camp_data
	loot = loot_data
	cosmetics = options if options != null else Cosmetics.load_default()
	_command_rng.randomize()


## For isolated panels/tools/tests. Actual gameplay passes its existing shared session.
static func for_menu(player, item_rules, camp_data = null, trip = null, trip_journey = null):
	var data = camp_data if camp_data != null else CampDataLoader.load_default(item_rules.tiers.size())
	var session = load("res://client/session/local_session.gd").new(player, item_rules, data)
	session.run = trip
	session.journey = trip_journey
	session._location = "camp" if trip == null else "rest"
	return session


func create_profile(random: RandomNumberGenerator, test_kit: bool = false) -> void:
	profile = Profile.new_player(rules, camp, random)
	if test_kit:
		TestKit.fill(profile, rules, camp, random)
	Camp.refresh(profile, camp)


func start_journey(data, weapons: Array, seed_value: int, party_profiles: Dictionary = {}) -> void:
	run = Run.start(profile, camp)
	if party_profiles.is_empty():
		journey = Journey.start(data, run, rules, loot, weapons, seed_value)
	else:
		var trips := {_player_id: run}
		for id in party_profiles:
			if id != _player_id: trips[id] = Run.start(party_profiles[id], camp)
		journey = PartyJourney.start_party(data, trips, rules, loot, weapons, seed_value, _player_id)

func is_coop() -> bool:
	return journey is PartyJourney

func profile_for(id: int):
	return journey.runs_by_player[id].profile if is_coop() and journey.runs_by_player.has(id) else profile

func run_for(id: int):
	return journey.runs_by_player.get(id) if is_coop() else run

func local_defeated() -> bool:
	return bool(_sim._coop["wiped"]) if is_coop() else fighters[_player_id].state == preload("res://logic/fighter.gd").State.DEAD


func begin_stage(map, combat_data, trip_journey = null, player_id: int = 1, first_enemy_id: int = 100, random: RandomNumberGenerator = null) -> Dictionary:
	_map = map
	_player_id = player_id
	_menu_open = false
	_point_id = ""
	_location = "stage"
	journey = trip_journey
	var world := SimWorld.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid["box"])
	_sim = GameSim.new(world, combat_data, random)
	_sim.add_player(player_id, map.spawn)
	run = Run.start(profile, camp) if journey == null else journey.run
	_sim.attach_run(player_id, run, rules, loot)
	var bosses: Array = []
	var enemy_types := {}
	if is_coop():
		bosses = journey.populate(_sim, map, player_id, first_enemy_id)
		if not _sim.coop_enabled:
			_sim = null
			return {"error": "Party setup failed: co-op configuration or safe spawn positions unavailable"}
		if journey.is_at_camp(): mark_camp_rest("journey_camp_%d" % journey.stage_number())
	elif journey != null and journey.is_at_camp():
		var me = fighters[player_id]
		me.hp = minf(me.max_hp(), me.max_hp() * journey.hp_fraction)
		me.gauge = journey.gauge
		mark_camp_rest("journey_camp_%d" % journey.stage_number())
	elif journey != null:
		bosses = journey.populate(_sim, map, player_id, first_enemy_id)
	else:
		var next_id := first_enemy_id
		for spawn in map.enemy_spawns:
			if combat_data.enemies.has(spawn["type"]):
				_sim.add_enemy(next_id, spawn["position"], spawn["type"], spawn["level"])
				next_id += 1
	for id in fighters:
		if fighters[id].team == "enemy":
			enemy_types[id] = fighters[id].enemy_type
		elif not squad_classes.is_empty():
			var class_weapon := str(preload("res://logic/card_deck.gd").class_data(str(squad_classes[(id - 1) % squad_classes.size()])).get("weapon", ""))
			_sim.set_class_style(id, class_weapon)
	return {"bosses": bosses, "enemy_types": enemy_types}


## The auto-battle brain's input for fighter `id` this tick (logic/auto_pilot.gd). Each fighter keeps its own memory.
func auto_input(id: int) -> SimInput:
	if _sim == null or not _sim.fighters.has(id):
		return SimInput.new()
	if not _auto_memory.has(id):
		_auto_memory[id] = AutoPilot.new_memory(id * 7919 + 1)
	return AutoPilot.decide(_sim, _sim.combat, id, _auto_memory[id], _sim.tick_count)


func set_input(id: int, input: SimInput) -> void:
	if _sim != null and not _menu_open:
		# Always use exactly the wire values, including offline play and local prediction.
		_sim.set_input(id, SimInput.decode(input.encode()))


func step(input: SimInput) -> void:
	set_input(_player_id, input)
	tick()


func tick() -> void:
	if _sim == null or _menu_open:
		return
	_sim.tick()
	if journey == null:
		return
	if is_coop():
		journey.capture_party(_sim)
		if _sim._coop["wiped"]:
			journey.died()
			return
	for event in events:
		if event["type"] == "stage_cleared":
			var me = fighters[_player_id]
			journey.stage_cleared(me.hp / me.max_hp())
			capture_gauge()
	# Preserve the existing stage result priority: a reported clear wins over a later/same-tick death.
	if not is_coop() and fighters.has(_player_id) and not fighters[_player_id].is_alive() and not journey.is_over() and not _sim._clear_reported:
		journey.died()


func snapshot() -> Dictionary:
	if _sim == null:
		return {}
	var state := _sim.snapshot()
	if journey != null:
		state["journey"] = journey.to_dict()
	return state


func living_enemy_count() -> int:
	return _sim.living_enemy_count() if _sim != null else 0


func capture_gauge() -> void:
	if is_coop():
		journey.capture_party(_sim)
	elif journey != null and fighters.has(_player_id):
		journey.gauge = fighters[_player_id].gauge


func mark_camp_rest(point: String) -> void:
	command({"type": "journey_camp_rest", "point": point})


## The UI can request a menu, but actual world state decides whether it is a rest point.
func open_rest(point: String) -> bool:
	if _sim == null or not fighters[_player_id].is_alive():
		return false
	var at: Vector3 = bodies[_player_id].position
	var allowed := false
	if journey != null and journey.is_at_camp():
		var fire: Vector3 = _map.campfire if _map.has_campfire else _map.spawn + Vector3(3.0, 0.0, -3.0)
		allowed = point == "journey_camp_%d" % journey.stage_number() and Vector2(at.x - fire.x, at.z - fire.z).length() <= 2.2
	elif journey == null:
		for candidate in _map.rest_points:
			if candidate["id"] == point and Vector2(at.x - candidate["position"].x, at.z - candidate["position"].z).length() <= float(candidate["radius"]):
				allowed = true
	if not allowed:
		return false
	_menu_open = true
	_point_id = point
	_location = "rest"
	return true


func close_menu() -> void:
	_menu_open = false
	_point_id = ""
	_location = "stage" if _sim != null else ("rest" if run != null else "camp")


func enter_camp() -> void:
	_sim = null
	_map = null
	run = null
	journey = null
	_menu_open = false
	_location = "camp"


func command(request: Dictionary) -> Dictionary:
	var result := Commands.apply({"now":int(Time.get_unix_time_from_system()),"profile": profile, "rules": rules, "camp": camp,
		"run": run, "journey": journey, "location": _location, "cosmetics": cosmetics}, request, _command_rng)
	if result["ok"] and _sim != null and request["type"] in ["equip", "unequip", "repair", "repair_all", "upgrade_camp", "upgrade_facility"]:
		_sim.gear_changed(_player_id)
	# Present local Item views to the existing treasure renderer; the command itself returns JSON data.
	if result["ok"] and request["type"] == "journey_treasure" and not result["result"].is_empty():
		result["result"] = journey.last_reward
	return result


func use_rest() -> bool:
	return _sim != null and _menu_open and _sim.use_rest(_player_id, _point_id)


## Route-list fallback is already at the camp node; it has no world-space prompt.
func open_route_camp(point: String) -> bool:
	if journey == null or not journey.is_at_camp() or point != "journey_camp_%d" % journey.stage_number():
		return false
	run = journey.run
	mark_camp_rest(point)
	_menu_open = true
	_location = "rest"
	_point_id = point
	return true
