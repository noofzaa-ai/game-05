extends RefCounted
## One trusted, in-memory Journey/GameSim authority. No client scene or database access.
const Sim := preload("res://logic/game_sim.gd")
const World := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const Journey := preload("res://logic/journey.gd")
const Party := preload("res://logic/coop_journey.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const AutoPilot := preload("res://logic/auto_pilot.gd")
## Online squads (design/gdd/online-squads.md): the room fields each player's cards, the server auto-pilot plays them.
var squads := false
var owner_by_fighter := {}  ## squad rooms: fighter id -> player slot (a player's first card has fighter id = its slot)
var _auto_memory := {}  ## squad rooms: fighter id -> AutoPilot memory (seed fid * 7919 + 1, as LocalSession.auto_input)
var _idle_since := -1  ## squad rooms: clock tick the room stopped fighting (route/camp/treasure), for the automatic flow
var _idle_epoch := -1
const CLEAR_DELAY_TICKS := 150  ## let death events and corpse animations reach peers before a chest or route moves on
var party = preload("res://logic/party_state.gd").new()
var companion_slots := {} # Trusted server-authored slot -> input brain; never an account.
var lobby := false
var boss_intro := {}
var _config := {}
var _ping_ticks := {}
var entity_delta_cache := {}
var entity_wire_cache := {}
var _snapshot_tick := -1
var _snapshot_epoch := -1
var _snapshot_entities := {}
var _snapshot_profiles := {}
var _snapshot_redacted := {}
var _snapshot_owned := {}
var _ownership_cache := preload("res://server/rooms/snapshot_cache.gd").new()
var sim
var journey
var status := "active"
var error := ""
var connected := {}
var queued := {}
var acknowledged := {}
const HELD_INPUT_LIMIT:=24 #400ms maximum; authority remains one simulation tick per world tick.
var held_inputs:Dictionary={}
var held_tick:Dictionary={}
var input_applied:Dictionary={}
var input_audit:Dictionary={}
var input_repeated:Dictionary={}
var input_delivery:Dictionary={}
var input_traces:Dictionary={}
var trace_epoch:=-1
var late_packet_traces:Dictionary={}
var transport_poll_gap_ms:=0
var transport_poll_gap_max_ms:=0
const MELEE_REWIND_LIMIT:=36
var viewed_inputs:Dictionary={}
var held_views:Dictionary={}
var melee_history:Dictionary={}
var melee_history_epoch:=-1
var melee_rewinds:=0
var melee_view_rejected:=0
var input_missing:Dictionary={}
var input_last_missing:Dictionary={}
var input_missing_epoch:Dictionary={}
var clock_tick := 0
var epoch := 1
var settled := false
var cloud_saved := false
var command_receipts := {}
var command_watermark := {}
var event_sequence := 0
var events: Array = []
var _rules
var _camp
var _loot
var _combat
var _seed := 0
var _map_id := ""
var _scene_gate := false
var _scene_waiting := {}
var goblin_waves
var _goblin_next_id := 10000
var _goblin_clear_at := -1
var _goblin_chest_position := Vector3.ZERO

func require_scene_ready() -> void:
	held_inputs.clear();held_tick.clear();held_views.clear()
	_scene_gate = true
	_scene_waiting.clear()
	for id in connected:
		if not companion_slots.has(id): _scene_waiting[id] = true
	_snapshot_tick = -1

func scene_loading() -> bool:
	return _scene_gate and not _scene_waiting.is_empty()

func scene_ready(player: int, scene_epoch: int) -> bool:
	if not _scene_gate or scene_epoch != epoch or not connected.get(player, false): return false
	_scene_waiting.erase(player)
	_snapshot_tick = -1
	return true


static func create(raw_players: Array, seed_value: int, config: Dictionary):
	var room = load("res://server/rooms/room.gd").new()
	room._config = config
	room._rules = config.rules
	room._camp = config.camp
	room._loot = config.loot
	room._combat = config.combat
	room._seed = seed_value
	if raw_players.size() < 1 or raw_players.size() > 4: return null
	room.squads = bool(config.get("squads", false))
	var trips := {}
	var profiles := {}
	for raw in raw_players:
		if not raw is Dictionary or not raw.has_all(["id", "profile"]) or raw.size() != 2 or not (raw.id is int or raw.id is float) or raw.id != floorf(raw.id) or raw.id < 1 or raw.id > 4 or trips.has(int(raw.id)) or not raw.profile is Dictionary:
			return null
		if not raw.profile.has_all(["v", "stash", "loadout", "camp_level", "facility_levels", "appearance", "name", "created"]): return null
		var p = Profile.from_dict(raw.profile.duplicate(true), config.rules, config.camp)
		if p == null: return null
		if room.squads and not squad_profile_problem(raw.profile, p, cards_per_player(raw_players.size(), config.combat)).is_empty(): return null
		profiles[int(raw.id)] = p
		trips[int(raw.id)] = Run.start(p, config.camp)
		room.connected[int(raw.id)] = true
		room.party.join(int(raw.id))
		room.queued[int(raw.id)] = {}
		room.acknowledged[int(raw.id)] = 0
	var ids := trips.keys()
	ids.sort()
	if room.squads:
		trips = room._squad_trips(profiles, config)
		if trips.is_empty(): return null
		room.journey = Party.start_party(config.journey, trips, config.rules, config.loot, config.combat.weapon_ids, seed_value, ids[0], room.owner_by_fighter) if trips.size() > 1 else Journey.start(config.journey, trips[ids[0]], config.rules, config.loot, config.combat.weapon_ids, seed_value)
	else:
		room.journey = Party.start_party(config.journey, trips, config.rules, config.loot, config.combat.weapon_ids, seed_value, ids[0]) if trips.size() > 1 else Journey.start(config.journey, trips[ids[0]], config.rules, config.loot, config.combat.weapon_ids, seed_value)
	if room.journey != null and not config.get("fixed_maps", []).is_empty():
		room.journey.nodes.clear()
		for index in config.fixed_maps.size():
			room.journey.nodes.append([{"stage":index+1,"kind":"combat","map":config.fixed_maps[index]}])
	if room.journey == null or room.journey.choose(0).is_empty() or not room._start_stage(): return null
	return room

## GDD online-squads 3.1 / 4.1: cards each player brings, k(n) = min(SQUAD_MAX, floor(room_card_cap / n)).
static func cards_per_player(players: int, combat) -> int:
	var cap := int(combat.coop.get("room_card_cap", combat.coop.get("max_fighters", 6))) if combat != null and not combat.coop.is_empty() else 6
	return mini(CardDeck.SQUAD_MAX, cap / maxi(1, players))

## GDD 3.8: "" when the raw profile (as received) may field its first `k` squad cards, else the reason. Profile.from_dict
## repairs a deck quietly (bad squad -> starter squad, bad tree -> refunded), so anything the repair changed is a tamper.
static func squad_profile_problem(raw: Dictionary, p, k: int) -> String:
	if k < 1: return "too_many_players"
	var deck = raw.get("card_deck")
	if not deck is Dictionary or not deck.get("squad") is Array or not deck.get("cards") is Dictionary: return "bad_deck"
	if (deck.squad as Array).is_empty() or Array(deck.squad).map(func(c): return str(c)) != p.card_deck.squad: return "bad_squad"
	var gear = raw.get("card_gear")
	for card in p.card_deck.squad.slice(0, k):
		if not gear is Dictionary or not gear.has(card) or not p.card_gear.has(card): return "missing_card_gear"
		var saved_card = deck.cards.get(card)
		var tree = saved_card.get("skill_tree") if saved_card is Dictionary else null
		if tree == null: continue
		var kept: Dictionary = p.card_deck.cards[card].get("skill_tree", {})
		if not tree is Dictionary: return "bad_tree"
		for branch in ["class", "race", "combo"]:
			if not tree.get(branch, []) is Array or Array(tree.get(branch, [])).map(func(id): return str(id)) != Array(kept.get(branch, [])): return "bad_tree"
	return ""

## Squad rooms: every player's first k cards as SquadMembers of that player's own trip. Fighter ids: a player's first
## card takes the player's slot id (slot-keyed presence/ping/actor paths keep pointing at a real fighter), the other
## cards take the lowest free ids in player order (1 player = ids 1..3, as solo). 4 players x 1 card share one room
## synergy group (GDD 3.2). Fills owner_by_fighter; returns {} when a squad is empty.
func _squad_trips(profiles: Dictionary, config: Dictionary) -> Dictionary:
	var slots := profiles.keys()
	slots.sort()
	var k := cards_per_player(slots.size(), config.combat)
	var picked := {}
	var races: Array = []
	for slot in slots:
		var cards: Array = profiles[slot].card_deck.squad.slice(0, k)
		if cards.is_empty(): return {}
		picked[slot] = cards
		for card in cards: races.append(CardDeck.race_of(profiles[slot].card_deck, str(card)))
	var room_group := k == 1 and slots.size() > 1
	var override: Dictionary = preload("res://logic/race_data.gd").load_default().synergy_for(races) if room_group else {}
	var used := {}
	var ids := {}
	for slot in slots:
		ids[slot] = [slot]
		used[slot] = true
	var next := 1
	for slot in slots:
		for i in range(1, picked[slot].size()):
			while used.has(next): next += 1
			ids[slot].append(next)
			used[next] = true
	var trips := {}
	owner_by_fighter.clear()
	for slot in slots:
		var members: Array = SquadMember.make_squad(Run.start(profiles[slot], config.camp), picked[slot], override, "room" if room_group else "")
		for i in members.size():
			trips[ids[slot][i]] = members[i]
			owner_by_fighter[ids[slot][i]] = slot
	return trips

## Every friendly fighter of the journey (squad rooms: all cards; legacy: one per player slot), sorted.
func fighter_ids() -> Array:
	var ids: Array = journey.player_ids() if journey is Party else connected.keys()
	ids = ids.duplicate()
	ids.sort()
	return ids

## The fighter ids owned by player slot `player`.
func fighters_of(player: int) -> Array:
	if not squads: return [player]
	return fighter_ids().filter(func(id): return int(owner_by_fighter.get(id, id)) == player)

func _start_stage() -> bool:
	if _scene_gate: require_scene_ready()
	_snapshot_tick = -1; entity_delta_cache.clear(); entity_wire_cache.clear()
	var map = preload("res://logic/map_loader.gd").load_by_id(str(journey.current.get("map", "")))
	if not map.is_valid():
		for fallback in journey.data.combat_maps:
			map = preload("res://logic/map_loader.gd").load_by_id(str(fallback))
			if map.is_valid(): break
	if not map.is_valid(): return false
	_map_id = map.id
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids: world.add_solid(solid.box)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + journey.stage_number() * 997
	sim = Sim.new(world, _combat, rng)
	var ids := connected.keys()
	ids.sort()
	if ids.size() == 1:
		sim.add_player(ids[0], map.spawn)
		sim.attach_run(ids[0], journey.run, _rules, _loot)
	if not lobby or journey is Party: journey.populate(sim, map, ids[0], 100)
	if squads: _squad_styles()
	if bool(_config.get("enable_goblin_wave_lab", true)) and not lobby and journey.data.id == "ink_road" and journey.stage_number() == 1 and _config.get("fixed_maps", []).is_empty():
		_start_goblin_waves(map)
	if journey.current.get("kind") == "boss":
		for actor in sim.fighters:
			if str(sim.fighters[actor].enemy_type).contains("chief"):
				boss_intro = {"epoch": epoch, "tick": clock_tick, "duration": 90, "boss": actor}
	return sim.fighters.has(ids[0]) and (ids.size() == 1 or sim.coop_enabled)

## Squad rooms: each card fights in its class style (data/classes/<class>.json weapon), as LocalSession.begin_stage.
func _squad_styles() -> void:
	_auto_memory.clear()
	for id in fighter_ids():
		var trip = journey.runs_by_player.get(id) if journey is Party else journey.run
		if sim.fighters.has(id) and trip is SquadMember:
			sim.set_class_style(id, str(CardDeck.class_data(trip.card_id).get("weapon", "")))

func _start_goblin_waves(map) -> void:
	goblin_waves = preload("res://logic/goblin_wave_progress.gd").new()
	for id in sim.fighters.keys():
		if sim.fighters[id].team == "enemy": sim.remove_player(id)
	sim._waves.clear()
	sim._clear_reported = true
	_spawn_goblin_wave(map)

func _spawn_goblin_wave(map) -> bool:
	var roster = preload("res://logic/goblin_wave_roster.gd").build(journey.data, goblin_waves.wave)
	sim.reward_wave = goblin_waves.wave  # race gear drop shares by wave (logic/race_drops.gd)
	var scale := float(sim.combat.coop["hp_multiplier"][fighter_ids().size() - 1]) if sim.coop_enabled else 1.0
	var ids: Array = preload("res://logic/goblin_wave_roster.gd").spawn(sim, map, roster, _goblin_next_id, scale)
	if ids.is_empty(): return false
	_goblin_next_id += ids.size()
	_goblin_clear_at = -1
	return true

func _tick_goblin_waves() -> void:
	if goblin_waves == null or goblin_waves.phase != "fighting" or sim.living_enemy_count() > 0:
		return
	if _goblin_clear_at < 0:
		_goblin_clear_at = clock_tick + 150 # let death events and corpse animations reach peers
		return
	if clock_tick < _goblin_clear_at: return
	for id in sim.fighters.keys():
		if sim.fighters[id].team == "enemy" and not sim.fighters[id].is_alive(): sim.remove_player(id)
	var cleared: int = goblin_waves.wave
	if not goblin_waves.finish_wave(cleared): return
	if goblin_waves.phase == "chest":
		var leader := party.leader()
		_goblin_chest_position = sim.bodies[leader].position if sim.bodies.has(leader) else Vector3.ZERO
		journey.treasure_pending = true
		status = "treasure"
		if squads: _open_goblin_chest(-1)  # GDD online-squads 3.7: the chest opens itself after the clear delay
	elif goblin_waves.phase == "rest":
		journey.completed = 10
		journey.nodes[10] = [{"stage": 11, "kind": "camp", "map": journey.data.camp_map}]
		journey.state = Journey.CHOOSING
		journey.choose(0)
		epoch += 1
		for slot in queued: queued[slot].clear()
		if not _start_stage(): error = "invalid_camp_map"; status = "finished"; return
		status = "camp"
	else:
		var map = preload("res://logic/map_loader.gd").load_by_id(_map_id)
		if not _spawn_goblin_wave(map): error = "invalid_wave"; status = "finished"

func _open_goblin_chest(id: int) -> bool:
	if goblin_waves == null or goblin_waves.phase != "chest": return false
	if not squads:  # squad rooms open it from the server (id -1); a player walks to it otherwise
		if not sim.bodies.has(id) or not sim.fighters[id].is_alive(): return false
		var offset: Vector3 = sim.bodies[id].position - _goblin_chest_position
		if Vector2(offset.x, offset.z).length() > 2.0: return false
	var wave: int = goblin_waves.wave
	if not goblin_waves.open_chest(): return false
	for player in connected:
		var trip = trip_for(player)
		if not trip.died:
			var reward_rng = journey._rng_for("goblin-chest-%d" % player, wave)
			var item = journey.treasure_item(reward_rng)
			item.id = "wave-chest-%d-%d-%d" % [_seed, wave, player]
			var RaceDrops = load("res://logic/race_drops.gd")  # race gear share of the chest (design/gdd/race-gear-sets.md 3.12)
			item = RaceDrops.convert_piece(journey.item_rules, item, RaceDrops.picks_for(trip), RaceDrops.CHEST, wave)
			trip.loot_into_bag({"gold": 0, "materials": {}, "items": [item]})
	journey.treasure_pending = false
	status = "active"
	var map = preload("res://logic/map_loader.gd").load_by_id(_map_id)
	if not _spawn_goblin_wave(map): error = "invalid_wave"; status = "finished"
	return true

func _audit_input(player:int,entry:Dictionary)->void:
	entry["epoch"]=epoch
	if not input_audit.has(player):input_audit[player]=[]
	input_audit[player].append(entry)
	while input_audit[player].size()>32:input_audit[player].pop_front()

## One observation per validated packet's newest tick, never its redundant history frames.
func observe_input_packet(player:int,newest_tick:int,now_ms:int=-1,packet_sequence:int=-1)->void:
	if scene_loading() or not connected.get(player,false) or newest_tick>clock_tick+24:return
	if now_ms<0:now_ms=Time.get_ticks_msec()
	var row:Dictionary=input_delivery.get(player,{})
	if row.get("epoch",-1)!=epoch:row={"epoch":epoch,"samples":[],"gaps":[],"late_total":0,"sequence":0,"newest":-1,"last_ms":-1}
	if newest_tick<=int(row.newest):return
	var margin:=newest_tick-clock_tick
	row.sequence+=1;row.newest=newest_tick
	if margin<=0:
		row.late_total+=1
		if trace_epoch!=epoch:input_traces.clear();late_packet_traces.clear();trace_epoch=epoch
		if not late_packet_traces.has(player):late_packet_traces[player]=[]
		late_packet_traces[player].append({"packet_sequence":packet_sequence,"input_tick":newest_tick,"received_ms":now_ms,"world_tick":clock_tick,"margin_ticks":margin,"arrival_gap_ms":maxi(0,now_ms-int(row.last_ms)) if int(row.last_ms)>=0 else 0,"poll_gap_ms":transport_poll_gap_ms,"worker_release":OS.get_environment("ZORX_WORKER_RELEASE")})
		while late_packet_traces[player].size()>8:late_packet_traces[player].pop_front()
	row.samples.append([now_ms,margin])
	if int(row.last_ms)>=0:row.gaps.append([now_ms,maxi(0,now_ms-int(row.last_ms))])
	row.last_ms=now_ms
	for key in ["samples","gaps"]:
		while not row[key].is_empty() and (row[key].size()>128 or now_ms-int(row[key][0][0])>1000):row[key].pop_front()
	input_delivery[player]=row

func delivery_metrics(player:int)->Dictionary:
	var row:Dictionary=input_delivery.get(player,{})
	if row.is_empty() or int(row.get("epoch",-1))!=epoch:return {}
	var margins:Array=[];var recent:Array=[];var gaps:Array=[];var now_ms:=Time.get_ticks_msec()
	for sample in row.samples:
		if now_ms-int(sample[0])<=1000:margins.append(sample[1])
		if now_ms-int(sample[0])<=200:recent.append(sample[1])
	for sample in row.gaps:
		if now_ms-int(sample[0])<=1000:gaps.append(sample[1])
	margins.sort();recent.sort();gaps.sort()
	return {"worker_poll_gap_ms":transport_poll_gap_ms,"worker_poll_gap_max_ms":transport_poll_gap_max_ms,"epoch":epoch,"sequence":row.sequence,"samples":margins.size(),"margin_latest":int(row.samples.back()[1]) if not row.samples.is_empty() else 0,"margin_recent":recent[int((recent.size()-1)*.50)] if not recent.is_empty() else 2,"margin_recent_samples":recent.size(),"margin_low":margins[int((margins.size()-1)*.10)] if not margins.is_empty() else 0,"late_total":row.late_total,"measurement_age_ms":maxi(0,now_ms-int(row.last_ms)),"packet_gap_p50_ms":gaps[int((gaps.size()-1)*.50)] if not gaps.is_empty() else 0,"packet_gap_p95_ms":gaps[int((gaps.size()-1)*.95)] if not gaps.is_empty() else 0,"packet_gap_max_ms":gaps.back() if not gaps.is_empty() else 0}

func trace_input(player:int,tick:int)->Dictionary:
	if trace_epoch!=epoch:input_traces.clear();late_packet_traces.clear();trace_epoch=epoch
	if tick%60!=0:return {}
	if not input_traces.has(player):input_traces[player]={}
	var rows:Dictionary=input_traces[player]
	if not rows.has(tick):
		rows[tick]={"worker_release":OS.get_environment("ZORX_WORKER_RELEASE"),"input_tick":tick,"received_ms":Time.get_ticks_msec(),"received_world_tick":clock_tick,"margin_ticks":tick-clock_tick,"outcome":"received"}
	while rows.size()>4:rows.erase(rows.keys()[0])
	return rows[tick]

func trace_snapshot(player:int)->Dictionary:
	return {"late_packets":late_packet_traces.get(player,[]).duplicate(true) if trace_epoch==epoch else [],"epoch":epoch,"emitted_ms":Time.get_ticks_msec(),"sample_period_ticks":60,"rows":input_traces.get(player,{}).values().duplicate(true) if trace_epoch==epoch else []}

func input(player: int, tick: int, bytes: PackedByteArray,view_tick:int=-1) -> bool:
	if companion_slots.has(player) or scene_loading() or status=="finished" or not connected.get(player,false) or SimInput.decode(bytes)==null:return false
	if squads and not lobby:return false # GDD online-squads 3.3: the server auto-pilot plays every card; client combat input is ignored
	var trace:Dictionary=trace_input(player,tick)
	if tick<=clock_tick:
		if not trace.is_empty() and trace.outcome=="received":trace.outcome="late_rejected"
		if input_applied.get(player,{}).get(tick,false)!=true:_audit_input(player,{"kind":"late_unapplied","tick":tick,"server_tick":clock_tick})
		return false
	if tick>clock_tick+24:
		if not trace.is_empty():trace.outcome="future_rejected"
		_audit_input(player,{"kind":"too_far_future","tick":tick,"server_tick":clock_tick});return false
	if queued[player].has(tick):return queued[player][tick]==bytes
	if not trace.is_empty():trace.outcome="queued"
	queued[player][tick]=bytes.duplicate()
	if not viewed_inputs.has(player):viewed_inputs[player]={}
	var valid_view:bool=view_tick>=0 and view_tick<=clock_tick and clock_tick-view_tick<=MELEE_REWIND_LIMIT
	if view_tick>=0 and not valid_view:melee_view_rejected+=1
	viewed_inputs[player][tick]=view_tick if valid_view else -1
	return true

func presence(player: int, online: bool) -> bool:
	if companion_slots.has(player): return false
	_snapshot_tick = -1; entity_delta_cache.clear(); entity_wire_cache.clear()
	if not connected.has(player): return false
	if _scene_gate and online and not connected[player] and not sim.fighters[player].eliminated:
		_scene_waiting[player] = true
	connected[player] = online
	party.presence(player, online)
	queued[player].clear();held_inputs.erase(player);held_tick.erase(player);viewed_inputs.erase(player);held_views.erase(player)
	return true

func tick() -> void:
	entity_delta_cache.clear(); entity_wire_cache.clear()
	if status == "finished" or scene_loading(): return
	if melee_history_epoch!=epoch:
		melee_history.clear();viewed_inputs.clear();held_views.clear();melee_history_epoch=epoch
	var boxes:Dictionary={}
	for target in sim.fighters:
		if sim.fighters[target].team=="enemy":boxes[target]=sim.bodies[target].aabb()
	melee_history[clock_tick]=boxes
	while melee_history.size()>MELEE_REWIND_LIMIT+2:melee_history.erase(melee_history.keys()[0])
	sim.melee_target_boxes.clear()
	clock_tick += 1
	var next_tick: int = clock_tick
	if squads and not lobby: _auto_inputs()
	for id in (connected if not (squads and not lobby) else {}):
		var bytes: PackedByteArray = queued[id].get(next_tick, PackedByteArray())
		queued[id].erase(next_tick)
		var frame = SimInput.decode(bytes) if connected[id] and bytes.size() == SimInput.wire_size() else SimInput.new()
		if companion_slots.has(id):
			var leader := party.leader()
			companion_slots[id].leader_id = leader
			frame = companion_slots[id].think(sim, id)
			bytes = frame.encode()
		var genuine:bool=connected[id] and bytes.size()==SimInput.wire_size()
		var seen_tick:int=viewed_inputs.get(id,{}).get(next_tick,-1)
		if viewed_inputs.has(id):viewed_inputs[id].erase(next_tick)
		if genuine:
			if seen_tick>=0:held_views[id]=seen_tick
			else:held_views.erase(id)
		else:seen_tick=int(held_views.get(id,-1))
		if seen_tick>=0:
			if next_tick-seen_tick<=MELEE_REWIND_LIMIT and melee_history.has(seen_tick):
				sim.melee_target_boxes[id]=melee_history[seen_tick];melee_rewinds+=1
			else:melee_view_rejected+=1
		var repeated:=false
		if genuine:
			var trace:Dictionary=input_traces.get(id,{}).get(next_tick,{}) if trace_epoch==epoch else {}
			if not trace.is_empty():trace.outcome="applied";trace["used_ms"]=Time.get_ticks_msec();trace["used_world_tick"]=next_tick
			held_inputs[id]=frame.held_controls().encode();held_tick[id]=next_tick
		elif connected[id] and held_inputs.has(id) and next_tick-int(held_tick.get(id,0))<=HELD_INPUT_LIMIT:
			frame=SimInput.decode(held_inputs[id]);repeated=true
			input_repeated[id]=int(input_repeated.get(id,0))+1
		if not input_applied.has(id):input_applied[id]={}
		input_applied[id][next_tick]=genuine
		while input_applied[id].size()>128:input_applied[id].erase(input_applied[id].keys()[0])
		if lobby:
			var walking := SimInput.new(); walking.move = frame.move; walking.run = frame.run; frame = walking
		sim.set_input(id, frame)
		if bytes.size() == SimInput.wire_size() and connected[id]: acknowledged[id] = next_tick
		elif connected[id]:
			input_missing[id]=int(input_missing.get(id,0))+1;input_last_missing[id]=next_tick;input_missing_epoch[id]=epoch
			_audit_input(id,{"kind":"held_fallback" if repeated else "neutral_missing","tick":next_tick,"server_tick":clock_tick,"source_input_tick":int(held_tick.get(id,0))})
	sim.tick()
	if lobby: return
	for event in sim.events:
		event_sequence += 1
		events.append({"sequence": event_sequence, "tick": clock_tick, "event": event.duplicate(true)})
	if events.size() > 256: events = events.slice(-256)
	journey.note_waves(sim)  # card XP counts the waves cleared (design/gdd/skill-tree.md 3.7)
	if journey is Party:
		journey.capture_party(sim)
		if sim._coop.wiped:
			journey.died()
			status = "finished"
	else:
		var id = connected.keys()[0]
		journey.hp_fraction = maxf(0, sim.fighters[id].hp / sim.fighters[id].max_hp())
		journey.gauge = sim.fighters[id].gauge
		if sim.fighters[id].hp <= 0:
			journey.died()
			status = "finished"
	# The empty practice arena is intentionally open-ended; zero enemies is not a victory.
	if squads and status != "finished": _auto_flow()
	if goblin_waves != null and journey.state == Journey.IN_STAGE and status != "finished":
		_tick_goblin_waves()
	elif _map_id != "practice_field" and journey.state == Journey.IN_STAGE and status != "finished" and sim.living_enemy_count() == 0 and sim.pending_wave_count() == 0:
		journey.stage_cleared(journey.hp_fraction)
		status = "finished" if journey.is_over() else "route"

## Squad rooms (GDD online-squads 3.3, chunk 3): every friendly fighter's input this tick comes from the auto-pilot, with
## the same per-fighter memory seed as solo (LocalSession.auto_input), whether its owner is connected or not.
func _auto_inputs() -> void:
	for id in fighter_ids():
		if not sim.fighters.has(id): continue
		if not _auto_memory.has(id): _auto_memory[id] = AutoPilot.new_memory(id * 7919 + 1)
		# Exactly the wire values, as LocalSession.set_input (solo parity, AC 1).
		sim.set_input(id, SimInput.decode(AutoPilot.decide(sim, sim.combat, id, _auto_memory[id], sim.tick_count).encode()))
	for id in connected:
		if connected[id]: acknowledged[id] = clock_tick

## Squad rooms (GDD 3.7): nobody walks to a chest or a portal. A waiting treasure opens after the clear delay; a route or
## camp choice the leader leaves open for coop.auto_continue_seconds takes choice 0. Counted in room ticks (60/s).
func _auto_flow() -> void:
	var waiting: bool = status in ["route", "camp", "treasure"] and journey.state in [Journey.CHOOSING, Journey.AT_NODE]
	if not waiting:
		_idle_since = -1
		return
	if _idle_since < 0 or _idle_epoch != epoch:
		_idle_since = clock_tick; _idle_epoch = epoch
		return
	var waited := clock_tick - _idle_since
	if journey.treasure_pending and goblin_waves == null:
		if waited >= CLEAR_DELAY_TICKS:
			journey.open_treasure()
			status = "route"
			_idle_since = clock_tick
		return
	if waited < int(_combat.coop.get("auto_continue_seconds", 20)) * 60: return
	_idle_since = -1
	if journey.upcoming_choices().is_empty():
		if journey.state == Journey.AT_NODE: journey.leave_node(); status = "finished" if journey.is_over() else "route"
		return
	var node: Dictionary = journey.choose_next(0)
	if node.is_empty(): return
	status = "treasure" if node.kind == "treasure" else ("camp" if node.kind == "camp" else "active")
	if node.kind == "treasure": return
	if goblin_waves != null and goblin_waves.phase == "rest":
		goblin_waves.leave_rest(); goblin_waves = null
	epoch += 1
	for slot in queued: queued[slot].clear()
	if not _start_stage(): error = "invalid_state"; status = "finished"; return
	if journey.is_at_camp(): status = "camp"

func summary() -> Dictionary:
	return {"status": status, "tick": clock_tick, "players": connected.keys(), "map": _map_id, "stage": journey.stage_number(), "enemy_count": sim.living_enemy_count(), "acknowledged": acknowledged.duplicate(), "event_sequence": event_sequence}


## Player slot `id`'s trip (squad rooms: the player's first card, which shares that player's run, bag and profile).
func trip_for(id: int):
	return journey.runs_by_player.get(id) if journey is Party else journey.run

## The trip of fighter `id` (a card in squad rooms).
func trip_of_fighter(id: int):
	return journey.runs_by_player.get(id) if journey is Party else journey.run

func command(id: int, request_id: int, request: Dictionary, expected_epoch: int = -1) -> Dictionary:
	_snapshot_tick = -1; entity_delta_cache.clear(); entity_wire_cache.clear()
	if not connected.get(id, false): return {"ok": false, "error": "not_connected"}
	_ready_companions()
	var key := "%d:%d" % [id, request_id]
	var hash_value := JSON.stringify(request).sha256_text()
	if command_receipts.has(key):
		return command_receipts[key].result if command_receipts[key].hash == hash_value else {"ok": false, "error": "request_id_reused"}
	if request_id < 1 or request_id > 2147483646: return {"ok": false, "error": "invalid_command"}
	if request_id <= int(command_watermark.get(id, 0)): return {"ok": false, "error": "stale_request"}
	if expected_epoch >= 0 and expected_epoch != epoch: return {"ok": false, "error": "stale_epoch"}
	command_watermark[id] = request_id
	var kind = request.get("type")
	var leader = party.leader()
	var result := {"ok": false, "error": "not_available_here"}
	var next_stage := false
	match kind:
		"mall_buy":
			if lobby:
				var trip = trip_for(id)
				result = preload("res://logic/commands.gd").apply({"profile":trip.profile,"rules":_rules,"camp":_camp,"location":"camp","cosmetics":_config.get("cosmetics",preload("res://logic/cosmetic_options.gd").load_default())},request,sim.rng)
		"party_ready":
			if lobby and request.size() == 2 and request.get("ready") is bool and party.set_ready(id, request.ready): result = {"ok": true}
		"party_depart":
			if not lobby: result.error = "already_started"
			elif id != leader: result.error = "leader_only"
			elif not party.can_depart(id): result.error = "party_not_ready"
			elif request.size() == 1:
				party.departing = true  # (the old skill-build check is gone with that system)
				result = {"ok": true, "action": "depart"}
		"party_leave":
			if lobby and not party.departing and request.size() == 1: result = {"ok": true, "action": "leave"}
		"party_ping":
			if request.size() != 2 or request.get("kind") not in ["here", "danger", "help", "yes"]: result.error = "invalid_command"
			elif clock_tick - int(_ping_ticks.get(id, -120)) < 120: result.error = "rate_limited"
			else:
				_ping_ticks[id] = clock_tick
				event_sequence += 1
				events.append({"sequence": event_sequence, "tick": clock_tick, "event": {"type": "party_ping", "player": id, "kind": request.kind, "pos": sim.bodies[id].position}})
				if events.size() > 256: events.pop_front()
				result = {"ok": true}
		"journey_choose":
			if id != leader: result.error = "leader_only"
			elif request.size() != 2 or not (request.get("index") is int): result.error = "invalid_command"
			elif not lobby and journey.state in [Journey.CHOOSING, Journey.AT_NODE] and not journey.treasure_pending:
				var node: Dictionary = journey.choose_next(request.index)
				if not node.is_empty():
					result = {"ok": true}
					next_stage = node.kind != "treasure"
					status = "treasure" if node.kind == "treasure" else ("camp" if node.kind == "camp" else "active")
		"journey_leave":
			if not lobby and id == leader and request.size() == 1 and journey.state == Journey.AT_NODE:
				journey.leave_node()
				status = "finished" if journey.is_over() else "route"
				result = {"ok": true}
		"bank_bag":
			if not lobby and request.size() == 1 and journey.is_at_camp():
				var summary: Dictionary = journey.bank_bag_for(id) if journey is Party else journey.run.return_to_camp()
				result = {"ok": true, "result": summary}
		"journey_treasure":
			if not lobby and id == leader and request.size() == 1 and goblin_waves != null and goblin_waves.phase == "chest":
				if _open_goblin_chest(id): result = {"ok": true}
				else: result.error = "chest_out_of_reach"
			elif not lobby and id == leader and request.size() == 1 and journey.treasure_pending:
				journey.open_treasure()
				result = {"ok": true}
		"journey_retreat":
			if not lobby and id == leader and request.size() == 1 and journey.is_at_camp():
				journey.retreat()
				status = "finished"
				settled = true
				result = {"ok": true}
		"journey_abandon":
			if not lobby and id == leader and request.size() == 1 and journey.state != Journey.IN_STAGE and not journey.is_at_camp() and not journey.is_over():
				journey.abandon()
				status = "finished"
				settled = true
				result = {"ok": true}
		"journey_finish":
			if not lobby and id == leader and request.size() == 1 and journey.is_over():
				if not settled:
					if journey.state == Journey.WON:
						if journey is Party: journey.finish_rewards()
						else: journey.run.return_to_camp()
					settled = true
				result = {"ok": true}
		"appearance":
			# Looks change in the lobby only (the mid-stage fashion toggle went with the old fashion, Boss 2026-11-13).
			if lobby:
				var trip = trip_for(id)
				result = preload("res://logic/commands.gd").apply({"now":int(Time.get_unix_time_from_system()),"profile":trip.profile,"rules":_rules,"camp":_camp,"location":"camp","run":null,"cosmetics":_config.get("cosmetics",preload("res://logic/cosmetic_options.gd").load_default())},request,sim.rng)
		_:
			if journey.is_at_camp():
				var trip = trip_for(id)
				result = preload("res://logic/commands.gd").apply({"now":int(Time.get_unix_time_from_system()),"profile": trip.profile, "rules": _rules, "camp": _camp, "location": "camp" if lobby else "rest", "run": null if lobby else trip, "journey": null, "cosmetics": _config.get("cosmetics", preload("res://logic/cosmetic_options.gd").load_default())}, request, sim.rng)
				if result.get("ok", false):
					for fid in fighters_of(id): sim.gear_changed(fid)  # squad rooms: the player's cards share the profile
	if next_stage:
		if goblin_waves != null and goblin_waves.phase == "rest":
			goblin_waves.leave_rest()
			goblin_waves = null
		epoch += 1
		for slot in queued: queued[slot].clear()
		if not _start_stage(): return {"ok": false, "error": "invalid_state"}
		# Camp rest/treasure processing stays in original Journey methods.
		if journey.is_at_camp(): status = "camp"
	command_receipts[key] = {"hash": hash_value, "result": result}
	if command_receipts.size() > 64: command_receipts.erase(command_receipts.keys()[0])
	return result

func eliminate(id: int) -> void:
	_scene_waiting.erase(id)
	presence(id, false)
	if squads and not lobby: return  # GDD online-squads 3.6: an offline player's cards keep fighting under the auto-pilot
	if sim.fighters.has(id) and not sim.fighters[id].eliminated:
		var fighter = sim.fighters[id]
		fighter.hp = 0
		fighter.state = preload("res://logic/fighter.gd").State.DEAD
		fighter.eliminated = true
		sim._finalize_player_death(id)

func public_state(viewer: int, borrowed: bool = false) -> Dictionary:
	# Materialize shared fields once per authority tick, never share mutable output with callers.
	if _snapshot_tick != clock_tick or _snapshot_epoch != epoch:
		_snapshot_tick = clock_tick; _snapshot_epoch = epoch
		_snapshot_entities = {}; _snapshot_profiles = {}; _snapshot_redacted = {}; _snapshot_owned = {}
		_ownership_cache.begin()
		for id in sim.bodies:
			var body := []; var fighter := []
			for field in preload("res://logic/net_wire.gd").BODY_FIELDS: body.append(sim.bodies[id].get(field))
			for field in preload("res://logic/net_wire.gd").FIGHTER_FIELDS: fighter.append(preload("res://logic/net_wire.gd").fighter_value(sim.fighters[id], field))
			_snapshot_entities[id] = [body, fighter]
		_snapshot_entities = _snapshot_entities.duplicate(true)
		for id in connected:
			var full: Dictionary = _ownership_cache.profile(trip_for(id).profile)
			_snapshot_profiles[id] = full
			var hidden := full.duplicate()
			hidden.loadout = full.loadout.duplicate(true)
			hidden.stash = {"v": 1, "capacity": 0, "gold": "0", "materials": {}, "items": []}
			hidden.relics = full.relics.duplicate(true)
			hidden.relics.owned = hidden.relics.owned.filter(func(item):return item.id in hidden.relics.equipped)
			hidden.farm = {}; hidden.facility_levels = {}; hidden.camp_level = 1
			for entry in hidden.loadout.equipped.values(): entry.durability = "0000000000005940"
			_snapshot_redacted[id] = preload("res://server/rooms/snapshot_cache.gd").freeze(hidden)
			_snapshot_owned[id] = _public_run(id)
		_ownership_cache.end()
	var entities: Dictionary = _snapshot_entities
	var visible_profiles := _snapshot_redacted.duplicate()
	visible_profiles[viewer] = _snapshot_profiles[viewer]
	var state := {"tick": clock_tick, "epoch": epoch, "entities": entities, "projectiles": sim.projectiles.duplicate(true), "areas": sim.areas.duplicate(true),
		"meta": {"input_trace":trace_snapshot(viewer),"melee_lag_compensation":{"max_rewind_ticks":MELEE_REWIND_LIMIT,"rewind_ticks":melee_rewinds,"rejected_views":melee_view_rejected},"input_clock":{"mode":"world_tick_bounded_held_on_missing","held_limit_ticks":HELD_INPUT_LIMIT,"repeated_ticks":int(input_repeated.get(viewer,0)),"delivery":delivery_metrics(viewer),"recent":input_audit.get(viewer,[]).slice(maxi(0,input_audit.get(viewer,[]).size()-8)).duplicate(true),"server_tick":clock_tick,"input_ack":int(acknowledged.get(viewer,0)),"missing_count":int(input_missing.get(viewer,0)),"last_missing_epoch":int(input_missing_epoch.get(viewer,0)),"last_missing_tick":int(input_last_missing.get(viewer,0))},"scene_loading": scene_loading(), "scene_waiting": _scene_waiting.keys(), "content_name": journey.data.display_name, "stage_count": journey.data.stage_count, "party": party.view(_names(), lobby), "boss_intro": boss_intro.duplicate(true), "status": status, "end_reason": error, "map": _map_id, "stage": journey.stage_number(), "current": journey.current.duplicate(true), "state": journey.state, "choices": journey.upcoming_choices().duplicate(true), "treasure_pending": journey.treasure_pending, "path": Array(journey.path.duplicate()), "players": connected.keys(), "profiles": visible_profiles, "run": _snapshot_owned[viewer], "connected": connected.duplicate(), "settled": settled, "cloud_saved": cloud_saved, "command_id": command_watermark.get(viewer, 0)}}
	if goblin_waves != null and journey.state == Journey.IN_STAGE and goblin_waves.phase in ["fighting", "chest"]:
		state.meta["goblin_wave"] = {"wave": goblin_waves.wave, "phase": goblin_waves.phase, "chest_position": [_goblin_chest_position.x, _goblin_chest_position.y, _goblin_chest_position.z]}
		state.meta.stage = goblin_waves.wave
	if borrowed: return preload("res://server/rooms/snapshot_cache.gd").freeze(state)
	return state.duplicate(true)


func _public_run(id: int) -> Dictionary:
	var trip = trip_for(id)
	var data := {"v": 1, "bag": _ownership_cache.inventory(trip.bag), "relic_loot":trip.relic_loot.duplicate(true), "died": trip.died, "used_rests": trip.used_rests.duplicate(), "skill_cooldowns":trip.skill_cooldowns.duplicate(true)}
	return data


func finalize(aborted: bool = false) -> Dictionary:
	_snapshot_tick = -1; entity_delta_cache.clear(); entity_wire_cache.clear()
	if aborted and not lobby and not journey.is_over():
		for id in (fighter_ids() if squads else connected.keys()):
			if sim.runs.has(id) and not sim.runs[id].died: sim._finalize_player_death(id)
		journey.died()
		status = "finished"
	if not settled:
		if not lobby and journey.state == Journey.WON:
			if journey is Party: journey.finish_rewards()
			else: journey.run.return_to_camp()
		settled = true
	var profiles := {}
	for id in human_ids(): profiles[str(id)] = trip_for(id).profile.to_dict()
	return profiles


func _names() -> Dictionary:
	var names := {}
	for id in connected: names[id] = trip_for(id).profile.name
	return names

func owned_profiles() -> Array:
	var raw := []
	var ids := connected.keys(); ids.sort()
	for id in ids: raw.append({"id": id, "profile": trip_for(id).profile.to_dict()})
	return raw

func enter_lobby(capacity: int) -> bool:
	lobby = true; party.capacity = capacity; status = "lobby"
	journey.state = Journey.AT_NODE
	journey.current = {"kind": "camp", "map": journey.data.camp_map}
	return _start_stage()

func rebuild_lobby(profiles: Array) -> bool:
	if not lobby or profiles.is_empty(): return false
	var previous_positions := {}
	var old_presence := connected.duplicate()
	for id in sim.bodies:
		if connected.has(id): previous_positions[id] = sim.bodies[id].position
	var fresh = create(profiles, _seed, _config)
	if fresh == null or not fresh.enter_lobby(party.capacity): return false
	journey = fresh.journey; sim = fresh.sim; _map_id = fresh._map_id; owner_by_fighter = fresh.owner_by_fighter; _auto_memory.clear()
	goblin_waves = fresh.goblin_waves; _goblin_next_id = fresh._goblin_next_id
	connected = fresh.connected; queued = fresh.queued; acknowledged = fresh.acknowledged
	party.departing = false
	for id in party.members.keys():
		if not connected.has(id):
			party.leave(id)
			command_watermark.erase(id); _ping_ticks.erase(id)
			for key in command_receipts.keys():
				if str(key).begins_with("%d:" % id): command_receipts.erase(key)
	for id in connected:
		party.join(id)
		if previous_positions.has(id): sim.bodies[id].position = previous_positions[id]
		connected[id] = old_presence.get(id, true)
		party.presence(id, connected[id])
	party.reset_ready()
	_ready_companions()
	epoch += 1
	if _scene_gate: require_scene_ready()
	return true

func depart() -> bool:
	if not lobby or not party.departing: return false
	var fresh = create(owned_profiles(), _seed, _config)
	if fresh == null: return false
	journey = fresh.journey; sim = fresh.sim; _map_id = fresh._map_id; owner_by_fighter = fresh.owner_by_fighter; _auto_memory.clear()
	goblin_waves = fresh.goblin_waves; _goblin_next_id = fresh._goblin_next_id
	lobby = false; status = "active"; epoch += 1
	if _scene_gate: require_scene_ready()
	party.departing = false
	for id in queued: queued[id].clear()
	return true

## Only trusted admission can install these after allocating their real party slots.
func install_companions(descriptors: Array) -> bool:
	if squads: return descriptors.is_empty()  # GDD online-squads 3.6: no companion bots in squad rooms
	var pending := {}
	for entry in descriptors:
		if not entry is Dictionary or entry.size() not in [2,3] or not entry.has_all(["id", "slot"]): return false
		if not entry.id is String or preload("res://logic/companions/roster.gd").get_entry(entry.id).is_empty(): return false
		if typeof(entry.slot) not in [TYPE_INT, TYPE_FLOAT] or entry.slot != int(entry.slot): return false
		var slot := int(entry.slot)
		if slot < 2 or slot > party.capacity or not connected.has(slot) or pending.has(slot): return false
		pending[slot] = preload("res://logic/companions/brain.gd").new()
	companion_slots = pending
	_ready_companions()
	if _scene_gate: require_scene_ready()
	return true

func _ready_companions() -> void:
	for slot in companion_slots:
		if party.members.has(slot): party.set_ready(slot, true)

func human_ids() -> Array:
	return connected.keys().filter(func(id): return not companion_slots.has(id))

func has_connected_humans() -> bool:
	return human_ids().any(func(id): return connected[id])
