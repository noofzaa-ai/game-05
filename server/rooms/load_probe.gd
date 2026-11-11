extends SceneTree
## Isolated synthetic profiles never touch Nakama/production storage. Real GameSim/legal bot input.
const Manager := preload("res://server/rooms/manager.gd")
var failed := false
func _initialize() -> void:
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size()>0 else 8
	var ticks := int(args[1]) if args.size()>1 else 3600
	if count<1 or count>8 or ticks<60 or ticks>216000: quit(2);return
	var manager := Manager.new()
	var profiles := []
	for id in range(1,5):
		var rng := RandomNumberGenerator.new();rng.seed=id
		var profile = preload("res://logic/profile.gd").new_player(manager.rules,manager.camp,rng)
		profiles.append({"id":id,"profile":profile.to_dict()})
	for index in count:
		if not manager.create("load-room-%d"%index,77+index,profiles).ok: quit(2);return
	var started := Time.get_ticks_usec()
	var total_snapshot_bytes := 0
	var delta_bytes := 0
	var baselines := {}
	var scheduler_max := 0
	var simulation_max := 0
	var paced := args.size() > 2 and args[2] == "paced"
	for tick in ticks:
		var before := Time.get_ticks_usec()
		for key in manager.rooms.keys():
			if manager.rooms[key].room.status == "finished":
				manager.rooms.erase(key); manager.create(key,77+tick,profiles)
		for entry in manager.rooms.values():
			for id in entry.room.connected:
				var frame = preload("res://logic/sim_input.gd").new()
				frame.move = Vector2.from_angle(float(tick+id)/120.0)
				frame.light = tick%30==id;frame.special=tick%180==id;frame.run=true
				entry.room.input(id,entry.room.clock_tick+1,frame.encode())
		manager.advance(1.0/60)
		simulation_max = maxi(simulation_max,Time.get_ticks_usec()-before)
		# Encode actual full room state at 20 Hz: conservative upload budget, not a delta guess.
		if tick%3==0:
			var alive := {}
			for entry in manager.rooms.values():
				for id in entry.room.connected:
					var key := str(entry.room.get_instance_id())+":"+str(id)
					alive[key] = true
					var state: Dictionary = entry.room.public_state(id, true)
					var patch := preload("res://logic/net_state.gd").difference(state,baselines.get(key,{}),1 if baselines.has(key) else 0,tick,entry.room.entity_delta_cache)
					var payload: PackedByteArray = preload("res://logic/net_wire.gd").encode(patch,262144,entry.room.entity_wire_cache)
					if not baselines.has(key): total_snapshot_bytes += payload.size()
					delta_bytes += payload.size()
					baselines[key] = state
			for key in baselines.keys():
				if not alive.has(key): baselines.erase(key)
		scheduler_max=maxi(scheduler_max,Time.get_ticks_usec()-before)
		if paced:
			var remaining := started + int((tick+1)*1000000.0/60.0) - Time.get_ticks_usec()
			if remaining > 0: OS.delay_usec(remaining)
	var result := manager.metrics()
	result.merge({"requested_rooms":count,"simulation_seconds":ticks/60.0,"wall_seconds":(Time.get_ticks_usec()-started)/1000000.0,"simulation_batch_max_ms":simulation_max/1000.0,"paced":paced,"scheduler_max_ms":scheduler_max/1000.0,"delta_payload_bytes_per_second":delta_bytes/(ticks/60.0),"initial_full_snapshot_bytes":total_snapshot_bytes,"kind":"isolated_simulation_no_database_no_real_network"})
	print("LOAD_RESULT="+JSON.stringify(result))
	quit(0 if result.tick_max_ms<=16 and result.simulation_batch_max_ms<=16 and manager.closed.is_empty() and (not paced or result.wall_seconds <= ticks/60.0*1.10+0.1) else 1)
