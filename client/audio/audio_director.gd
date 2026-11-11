extends Node
## Autoload "Audio": plays every sound in the game from data/audio/audio.json.
##
##   Audio.handle_events(sim.events, sim, local_id)  # call once per simulation tick (also does footsteps)
##   Audio.play_ui("equip")                         # a UI action (see "ui" in the data)
##   Audio.play("hit_heavy", position)              # any cue directly
##   Audio.play_music("stage") / Audio.play_ambience("shrine") / Audio.stop_music()
##   Audio.set_bus_volume("Music", 0.5)             # settings sliders (linear 0..1)
##
## By itself it also: starts the music and ambience named for the current scene ("scenes" in the
## data), and gives every Button a click/hover sound and every TabBar a tab sound ("auto_ui").
## A specific play_ui() in the same frame replaces the generic click, so a screen can say "equip"
## instead of "click" without double sounds. Set node meta "audio_ui" to another ui action, or to
## "" for silence.
##
## Mixing: players are pooled per bus (no node is made while playing); each cue has a voice limit
## (the oldest copy is cut), a cooldown, a priority (the lowest-priority oldest voice is stolen when
## the pool is full), random pitch/volume variation, and gets quieter with distance from the local
## player. Buses: Master, Music, SFX, UI, Ambience (default_bus_layout.tres).
## Web: browsers block sound until the first click/touch/key; music waits for it.

const AudioData := preload("res://client/audio/audio_data.gd")
const AudioRules := preload("res://client/audio/audio_rules.gd")

signal cue_played(cue: String)  ## for tests and debugging

var data: Dictionary = {}
var errors: Array = []
var muted_until_input := false  ## true on the web until the player first touches the page

var _streams: Dictionary = {}  ## file path -> AudioStream
var _pools: Dictionary = {}  ## bus -> Array[AudioStreamPlayer]
var _voices: Dictionary = {}  ## AudioStreamPlayer -> {"cue", "priority", "started"}
var _last_played: Dictionary = {}  ## cue -> msec
var _last_file: Dictionary = {}  ## cue -> index of the file played last time
var _rng := RandomNumberGenerator.new()
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id := ""
var _music_base_db := 0.0
var _ambience_players: Array[AudioStreamPlayer] = []
var _ambience_active := 0
var _ambience_id := ""
var _music_tween: Tween
var _ambience_tween: Tween
var _duck_tween: Tween
var _scene: Node
var _pending_auto_click := ""
var _specific_ui_this_frame := false
var _step_clock := 0.0
var _listener = null  ## Vector3 or null: where the local player is (for distance)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus pause the stage; their sounds must still play
	_rng.randomize()
	data = AudioData.load_default()
	errors = data.get("errors", [])
	for line in errors:
		push_warning("audio data: " + str(line))
	_ensure_buses()
	var pools: Dictionary = data.get("pools", {"SFX": 24, "UI": 6, "Music": 2})
	for bus in pools:
		var list: Array[AudioStreamPlayer] = []
		for i in int(pools[bus]):
			list.append(_new_player(str(bus), "%s_%d" % [bus, i]))
		_pools[str(bus)] = list
	for i in 2:
		_music_players.append(_new_player("Music", "music_%d" % i))
		_ambience_players.append(_new_player("Ambience", "ambience_%d" % i))
	_preload_cues()
	muted_until_input = OS.has_feature("web")
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	release_all()


## Closing the game: stop everything and let go of the sounds, or the engine reports the streams
## (and their playbacks) as leaked at exit. The audio thread lets go of a stopped playback a moment
## later, so this runs when the window is asked to close (and again on the way out).
func release_all() -> void:
	stop_all()
	for player in _music_players + _ambience_players:
		player.stream = null
	for bus in _pools:
		for player in _pools[bus]:
			player.stream = null
	_streams.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		release_all()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_apply_scene(scene)
	if not _pending_auto_click.is_empty():
		if not _specific_ui_this_frame:
			_play_ui_now(_pending_auto_click)
		_pending_auto_click = ""
	_specific_ui_this_frame = false


func _input(event: InputEvent) -> void:
	if muted_until_input and (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		muted_until_input = false
		var music := _music_id
		var ambience := _ambience_id
		_music_id = ""
		_ambience_id = ""
		if not music.is_empty():
			play_music(music)
		if not ambience.is_empty():
			play_ambience(ambience)


# ================================================================== game events

## Plays the sounds for one tick of simulation events. `sim` (GameSim) gives who is a monster,
## which weapon they hold and where they are; without it only data-free rules can match.
func handle_events(events: Array, sim = null, local_id: int = 1) -> void:
	_listener = null
	if sim != null and sim.bodies.has(local_id):
		_listener = sim.bodies[local_id].position
	var rules: Dictionary = data.get("events", {})
	for event in events:
		if event is Dictionary and event.get("type") in ["skill_cast","skill_hit"] and sim != null:
			var owner_id := int(event.get("player",event.get("attacker",-1)))
			if sim.fighters.has(owner_id) and sim.bodies.has(owner_id):
				var cue := ("skill_cast_" if event.type=="skill_cast" else "skill_impact_") + str(sim.fighters[owner_id].style)
				play(cue,sim.bodies[owner_id].position)
			continue
		if not (event is Dictionary) or not rules.has(str(event.get("type", ""))):
			continue
		var facts := AudioRules.facts(event, sim, local_id)
		for entry in AudioRules.pick(rules[str(event["type"])], facts):
			play(entry["cue"], facts.get("position"), 1.0 + float(entry["pitch"]), AudioRules.friend_gain_db(facts))
	_footsteps(sim, local_id)


## Footsteps of the local player, timed by how fast it moves (there is no footstep event).
func _footsteps(sim, local_id: int) -> void:
	if sim == null or not sim.bodies.has(local_id):
		return
	var settings: Dictionary = data.get("footsteps", {})
	var body = sim.bodies[local_id]
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var running := false
	if sim.fighters.has(local_id):
		running = bool(sim.fighters[local_id].running)
		if int(sim.fighters[local_id].dodge_left) > 0:
			speed = 0.0  # a dodge slide has its own sound
	if not body.grounded or speed < float(settings.get("min_speed", 0.6)):
		_step_clock = 0.0
		return
	var interval := float(settings.get("run_interval" if running else "walk_interval", 0.35))
	var was := _step_clock
	_step_clock += 1.0 / float(Engine.physics_ticks_per_second)
	if was == 0.0 or _step_clock >= interval:
		_step_clock = 0.0001
		play(str(settings.get("run_cue" if running else "walk_cue", "footstep")), null)


# ================================================================== UI

## A UI action ("click", "equip", "error", ... see "ui" in the data).
func play_ui(action: String) -> void:
	_specific_ui_this_frame = true
	_play_ui_now(action)


func _play_ui_now(action: String) -> void:
	var cue := str(data.get("ui", {}).get(action, ""))
	if not cue.is_empty():
		play(cue, null)


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton or node is TabBar) or node.has_meta("_audio_hooked"):
		return  # (a node moved to a new parent is "added" again)
	node.set_meta("_audio_hooked", true)
	var auto: Dictionary = data.get("auto_ui", {})
	if node is BaseButton:
		var button := node as BaseButton
		if auto.has("button_pressed"):
			button.pressed.connect(_on_auto_button.bind(button, str(auto["button_pressed"])))
		if auto.has("button_hover"):
			button.mouse_entered.connect(_on_auto_hover.bind(button, str(auto["button_hover"])))
	elif node is TabBar and auto.has("tab_clicked"):
		(node as TabBar).tab_clicked.connect(func(_tab: int) -> void: _on_auto_button(node, str(auto["tab_clicked"])))


func _on_auto_button(node: Node, action: String) -> void:
	if node.has_meta("audio_ui"):
		action = str(node.get_meta("audio_ui"))
	if not action.is_empty():
		_pending_auto_click = action  # played at the end of the frame unless a specific play_ui() came


func _on_auto_hover(button: BaseButton, action: String) -> void:
	if not button.disabled and not (button.has_meta("audio_ui") and str(button.get_meta("audio_ui")).is_empty()):
		_play_ui_now(action)


# ================================================================== playing a cue

## Plays a cue. `at` (Vector3) makes it quieter the farther it is from the local player.
## Returns the player used, or null if nothing played (unknown cue, cooldown, too far, muted).
func play(cue: String, at = null, pitch_scale: float = 1.0, volume_offset_db: float = 0.0) -> AudioStreamPlayer:
	if muted_until_input:
		return null
	var settings := AudioData.cue_settings(data, cue)
	var files: Array = settings.get("files", [])
	if not data.get("cues", {}).has(cue) or files.is_empty():
		return null
	var now := Time.get_ticks_msec()
	var cooldown := int(settings.get("cooldown_ms", 0))
	if _last_played.has(cue) and now - int(_last_played[cue]) < cooldown:
		return null
	var volume := float(settings.get("volume_db", 0.0)) + volume_offset_db
	if bool(settings.get("positional", true)) and at is Vector3 and _listener is Vector3:
		var distance: float = (at as Vector3).distance_to(_listener)
		var falloff: Dictionary = data.get("distance", {})
		if distance > float(falloff.get("cull", 40.0)):
			return null
		volume += distance_db(distance, falloff)
	var stream := _stream_for(cue, files)
	if stream == null:
		return null
	var bus := str(settings.get("bus", "SFX"))
	var player := _voice_for(cue, bus, int(settings.get("max_voices", 3)), int(settings.get("priority", 5)))
	if player == null:
		return null
	var jitter := float(settings.get("volume_jitter_db", 0.0))
	var pitch: Array = settings.get("pitch", [1.0, 1.0])
	player.stream = stream
	player.volume_db = volume + _rng.randf_range(-jitter, jitter)
	player.pitch_scale = maxf(0.05, _rng.randf_range(float(pitch[0]), float(pitch[1])) * pitch_scale)
	player.play()
	_voices[player] = {"cue": cue, "priority": int(settings.get("priority", 5)), "started": now}
	_last_played[cue] = now
	if settings.has("duck_music_db"):
		_duck_music(float(settings["duck_music_db"]), float(settings.get("duck_seconds", 3.0)))
	cue_played.emit(cue)
	return player


## Gain (dB, <= 0) for a sound `distance` metres from the local player.
static func distance_db(distance: float, falloff: Dictionary) -> float:
	var near := float(falloff.get("near", 7.0))
	var far := float(falloff.get("far", 28.0))
	if distance <= near:
		return 0.0
	var t := clampf((distance - near) / maxf(far - near, 0.01), 0.0, 1.0)
	return float(falloff.get("far_db", -14.0)) * t


func _stream_for(cue: String, files: Array) -> AudioStream:
	var index := 0
	if files.size() > 1:
		index = _rng.randi_range(0, files.size() - 2)
		if index >= int(_last_file.get(cue, -1)):
			index += 1  # never the same file twice in a row
	_last_file[cue] = index
	return _load(str(files[index]))


func _load(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## A free player on the bus. If this cue already has max_voices playing, its oldest is reused;
## if the pool is full, the lowest-priority (then oldest) voice is stolen, unless all are more important.
func _voice_for(cue: String, bus: String, max_voices: int, priority: int) -> AudioStreamPlayer:
	var pool: Array = _pools.get(bus, _pools.get("SFX", []))
	var same: Array[AudioStreamPlayer] = []
	var free: AudioStreamPlayer = null
	for player in pool:
		if player.playing and _voices.has(player):
			if _voices[player]["cue"] == cue:
				same.append(player)
		elif free == null:
			free = player
	if same.size() >= max_voices:
		same.sort_custom(func(a, b) -> bool: return _voices[a]["started"] < _voices[b]["started"])
		same[0].stop()
		return same[0]
	if free != null:
		return free
	var victim: AudioStreamPlayer = null
	for player in pool:
		var info: Dictionary = _voices.get(player, {"priority": 0, "started": 0})
		if victim == null:
			victim = player
			continue
		var best: Dictionary = _voices.get(victim, {"priority": 0, "started": 0})
		if info["priority"] < best["priority"] or (info["priority"] == best["priority"] and info["started"] < best["started"]):
			victim = player
	if victim == null or int(_voices.get(victim, {"priority": 0})["priority"]) > priority:
		return null
	victim.stop()
	return victim


## Silences everything at once (music and ambience too), e.g. before quitting.
func stop_all() -> void:
	for tween in [_music_tween, _ambience_tween, _duck_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	for player in _music_players + _ambience_players:
		player.stop()
	for bus in _pools:
		for player in _pools[bus]:
			player.stop()
	_voices.clear()
	_music_id = ""
	_ambience_id = ""


## How many voices are sounding now (all buses, music excluded).
func active_voices() -> int:
	var count := 0
	for bus in _pools:
		for player in _pools[bus]:
			if player.playing:
				count += 1
	return count


# ================================================================== music and ambience

func play_music(id: String, fade: float = -1.0) -> void:
	if id == _music_id:
		return
	_music_id = id
	var entry = data.get("music", {}).get(id, null)
	_music_base_db = float(entry.get("volume_db", 0.0)) if entry is Dictionary else 0.0
	if muted_until_input:
		return
	_music_tween = _crossfade(_music_players, _music_active, entry, fade, _music_tween)
	_music_active = 1 - _music_active


func stop_music(fade: float = -1.0) -> void:
	play_music("", fade)


func play_ambience(id: String, fade: float = -1.0) -> void:
	if id == _ambience_id:
		return
	_ambience_id = id
	if muted_until_input:
		return
	var entry = data.get("ambience", {}).get(id, null)
	_ambience_tween = _crossfade(_ambience_players, _ambience_active, entry, fade, _ambience_tween)
	_ambience_active = 1 - _ambience_active


func current_music() -> String:
	return _music_id


func current_ambience() -> String:
	return _ambience_id


func _crossfade(players: Array[AudioStreamPlayer], active: int, entry, fade: float, old_tween: Tween) -> Tween:
	if fade < 0.0:
		fade = float(data.get("fade_seconds", 1.5))
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var outgoing := players[active]
	var incoming := players[1 - active]
	var tween := create_tween().set_parallel(true)
	if outgoing.playing:
		tween.tween_property(outgoing, "volume_db", -60.0, maxf(fade, 0.01))
		tween.chain().tween_callback(outgoing.stop)
	if entry is Dictionary:
		var stream := _load(str(entry.get("file", "")))
		if stream != null:
			if "loop" in stream:
				stream.set("loop", bool(entry.get("loop", true)))
			incoming.stream = stream
			incoming.volume_db = -60.0
			incoming.play()
			tween.tween_property(incoming, "volume_db", float(entry.get("volume_db", 0.0)), maxf(fade, 0.01))
	return tween


## Dips the music (for a stinger), then brings it back.
func _duck_music(db: float, seconds: float) -> void:
	var player := _music_players[_music_active]  # the one playing now
	if not player.playing:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(player, "volume_db", _music_base_db + db, 0.25)
	_duck_tween.tween_interval(maxf(seconds - 1.25, 0.0))
	_duck_tween.tween_property(player, "volume_db", _music_base_db, 1.0)


func _apply_scene(scene: Node) -> void:
	if scene == null:
		return
	var entry = data.get("scenes", {}).get(scene.scene_file_path, null)
	if not (entry is Dictionary):
		return
	if entry.has("music"):
		play_music(str(entry["music"]))
	var ambience := str(entry.get("ambience", ""))
	var by_map: Dictionary = entry.get("ambience_by_map", {})
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null and by_map.has(str(game_state.get("selected_map_id"))):
		ambience = str(by_map[str(game_state.get("selected_map_id"))])
	if not ambience.is_empty():
		play_ambience(ambience)


# ================================================================== buses and settings

## Linear 0..1 volume for a bus (for settings sliders).
func set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)) if linear > 0.0 else -80.0)
		AudioServer.set_bus_mute(index, linear <= 0.0)


func get_bus_volume(bus: String) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0)


## The bus layout file sets up all five buses; this only adds any that are missing (a broken or
## replaced layout) so sound still routes somewhere sensible.
func _ensure_buses() -> void:
	for bus in AudioData.BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
			push_warning("audio bus %s was missing from default_bus_layout.tres; added it" % bus)


func _new_player(bus: String, label: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label
	player.bus = bus
	add_child(player)
	return player


func _preload_cues() -> void:
	var cues: Dictionary = data.get("cues", {})
	for cue in cues:
		if cues[cue] is Dictionary:
			for file in cues[cue].get("files", []):
				_load(str(file))
