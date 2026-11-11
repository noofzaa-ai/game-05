extends RefCounted
## Tests the sound system: the data (every cue file exists, every rule plays a real cue, every
## simulation event has sounds), the buses, the rules that turn events into cues, and the Audio
## autoload playing a real fight headless (voice limits, cooldowns, UI clicks, music, ambience).

const AudioData := preload("res://client/audio/audio_data.gd")
const AudioRules := preload("res://client/audio/audio_rules.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimInput := preload("res://logic/sim_input.gd")
const SimWorld := preload("res://logic/sim_world.gd")

## Simulation events that are deliberately silent (something else already sounds for them).
const SILENT_EVENTS := ["effect_ended"]
## The whole shipped audio folder must stay under this (web download size).
const AUDIO_BUDGET_BYTES := 4 * 1024 * 1024

var _played: Array[String] = []


func run(ctx) -> void:
	var combat = CombatDataLoader.load_default()
	var weapons: Array = combat.weapons.keys()
	var data := AudioData.load_default()
	ctx.check("audio data loads without errors %s" % [data.get("errors", [])], data.get("errors", ["?"]).is_empty())
	var weapon_errors := AudioData.validate(data, weapons)
	ctx.check("every {weapon} cue exists for every weapon in weapons.json %s" % [weapon_errors], weapon_errors.is_empty())
	_test_files(ctx, data)
	_test_event_coverage(ctx, data)
	_test_buses(ctx)
	_test_rules(ctx, data, combat)
	_test_validation(ctx)
	var audio: Node = ctx.root.get_node_or_null("Audio")
	ctx.check("the Audio autoload exists", audio != null)
	if audio == null:
		return
	audio.cue_played.connect(_on_played)
	audio.muted_until_input = false
	await _test_fight(ctx, audio, combat)
	await _test_voices(ctx, audio)
	await _test_ui(ctx, audio)
	await _test_music(ctx, audio)
	audio.cue_played.disconnect(_on_played)
	audio.stop_all()
	await ctx.create_timer(0.3).timeout  # let the audio thread let go of the stopped sounds
	ctx.check("stop_all silences every voice", audio.active_voices() == 0)


func _on_played(cue: String) -> void:
	_played.append(cue)


func _test_files(ctx, data: Dictionary) -> void:
	var bad: Array[String] = []
	for cue in data["cues"]:
		for file in data["cues"][cue]["files"]:
			var stream = load(str(file))
			if not (stream is AudioStream) or stream.get_length() <= 0.0:
				bad.append(str(file))
	ctx.check("every cue file loads as a sound with a length %s" % [bad], bad.is_empty())
	for section in ["music", "ambience"]:
		for id in data[section]:
			var stream = load(str(data[section][id]["file"]))
			ctx.check("%s '%s' loads and is a loop of at least 20 s" % [section, id], stream is AudioStream and stream.get_length() >= 20.0)
	var total := 0
	for folder in ["res://audio/sfx", "res://audio/music", "res://audio/ambience"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".ogg") or file.ends_with(".wav"):
				var handle := FileAccess.open(folder + "/" + file, FileAccess.READ)
				if handle != null:
					total += handle.get_length()
	ctx.check("all audio together is under the web budget (%.2f MB of %.0f MB)" % [total / 1048576.0, AUDIO_BUDGET_BYTES / 1048576.0], total > 0 and total < AUDIO_BUDGET_BYTES)
	ctx.check("audio/CREDITS.md exists", FileAccess.file_exists("res://audio/CREDITS.md"))


## Every event type the simulation can produce (found by reading logic/) has sound rules, so a
## new event cannot be added without someone deciding what it sounds like.
func _test_event_coverage(ctx, data: Dictionary) -> void:
	var regex := RegEx.new()
	regex.compile("\"type\":\\s*\"([a-z_]+)\"")
	var types := {}
	for file in DirAccess.get_files_at("res://logic"):
		if file.ends_with(".gd"):
			for found in regex.search_all(FileAccess.get_file_as_string("res://logic/" + file)):
				types[found.get_string(1)] = true
	ctx.check("found the simulation's event types in logic/ (%d)" % types.size(), types.size() >= 15)
	for type in types:
		if type in SILENT_EVENTS:
			continue
		ctx.check("event '%s' has sound rules" % type, data["events"].has(type) and not data["events"][type].is_empty())


func _test_buses(ctx) -> void:
	for bus in AudioData.BUSES:
		var index := AudioServer.get_bus_index(bus)
		ctx.check("bus %s exists" % bus, index >= 0)
		if index > 0:
			ctx.check("bus %s sends to Master" % bus, AudioServer.get_bus_send(index) == &"Master")
	ctx.check("default_bus_layout.tres exists", ResourceLoader.exists("res://default_bus_layout.tres"))


func _test_rules(ctx, data: Dictionary, combat) -> void:
	var sim := _duel(combat, "blade")
	var events: Dictionary = data["events"]
	var hit := AudioRules.facts({"type": "hit", "attacker": 1, "target": 2, "crit": true, "power": 1.0, "launched": false,
		"armored": false, "move": "blade_light_1", "pos": Vector3.ZERO, "attacker_combo": 3}, sim, 1)
	ctx.check("hit facts: weapon, kind, local, target is a monster", hit["weapon"] == "blade" and hit["kind"] == "light_1" and hit["local"] and hit["target_enemy"] and not hit["enemy"])
	var cues := _names(AudioRules.pick(events["hit"], hit))
	ctx.check("a blade crit plays crit + light body + slice + monster hurt %s" % [cues], cues == ["hit_crit", "hit_light", "hit_slice", "enemy_hurt"])
	var pitched := AudioRules.pick(events["hit"], hit)
	ctx.check("combo hits rise slightly in pitch", pitched[1]["pitch"] > 0.0 and pitched[1]["pitch"] <= 0.08)
	hit["power"] = 2.4
	hit["heavy_hit"] = true
	hit["crit"] = false
	ctx.check("a strong hit plays the heavy body", "hit_heavy" in _names(AudioRules.pick(events["hit"], hit)) and not "hit_light" in _names(AudioRules.pick(events["hit"], hit)))

	var swing := AudioRules.facts({"type": "attack_active", "player": 1, "move": "blade_heavy"}, sim, 1)
	ctx.check("a heavy blade swing plays its heavy whoosh", _names(AudioRules.pick(events["attack_active"], swing)) == ["swing_blade_heavy"])
	swing = AudioRules.facts({"type": "attack_active", "player": 1, "move": "blade_light_2"}, sim, 1)
	ctx.check("a light blade swing plays its light whoosh", _names(AudioRules.pick(events["attack_active"], swing)) == ["swing_blade_light"])
	swing = AudioRules.facts({"type": "attack_started", "player": 1, "move": "blade_special"}, sim, 1)
	ctx.check("a blade skill plays its cast sound", _names(AudioRules.pick(events["attack_started"], swing)) == ["skill_cast_blade"])
	var grunt := AudioRules.facts({"type": "attack_active", "player": 2, "move": "fists_light_1"}, sim, 1)
	ctx.check("a monster with fists does not use the player's whoosh", _names(AudioRules.pick(events["attack_active"], grunt)) == ["swing_grunt"])

	var brute := _duel(combat, "fists", "brute")
	var slam := AudioRules.facts({"type": "attack_started", "player": 2, "move": "brute_slam"}, brute, 1)
	ctx.check("the brute's slam wind-up plays the telegraph warning", slam["enemy"] and slam["kind"] == "slam" and _names(AudioRules.pick(events["attack_started"], slam)) == ["enemy_windup"])
	var died := AudioRules.facts({"type": "killed", "target": 1, "by": 2}, brute, 1)
	ctx.check("the local player dying plays the down sound and the defeat stinger", _names(AudioRules.pick(events["killed"], died)) == ["player_down", "stinger_defeat"])
	var monster_died := AudioRules.facts({"type": "killed", "target": 2, "by": 1}, brute, 1)
	ctx.check("a monster dying plays its death cry", _names(AudioRules.pick(events["killed"], monster_died)) == ["enemy_death"])
	var buff := AudioRules.facts({"type": "effect_applied", "target": 1, "effect": "haste", "stacks": 1, "source": 1}, brute, 1)
	ctx.check("a buff plays the buff sound", buff["effect_kind"] == "buff" and _names(AudioRules.pick(events["effect_applied"], buff)) == ["buff_up"])
	var loot := AudioRules.facts({"type": "loot", "player": 1, "enemy": 2, "gold": 12, "materials": {"ink": 2},
		"items": [{"slot": "head", "tier": 3, "weapon_type": ""}], "lost_items": 0, "lost_materials": {}}, brute, 1)
	ctx.check("loot with gold, a gold-tier item and materials plays all four %s" % [_names(AudioRules.pick(events["loot"], loot))],
		_names(AudioRules.pick(events["loot"], loot)) == ["gold", "item_drop", "rare_drop", "material_pickup"])
	var other_loot := loot.duplicate()
	other_loot["local"] = false
	ctx.check("someone else's loot is silent", AudioRules.pick(events["loot"], other_loot).is_empty())
	ctx.check("move kind of a monster move drops the style", AudioRules.move_kind("charger_rush", "charger") == "rush")
	ctx.check("conditions: value, list, range", AudioRules.matches({"a": 1, "b": ["x", "y"], "c": {"min": 2, "max": 4}}, {"a": 1.0, "b": "y", "c": 3})
		and not AudioRules.matches({"c": {"min": 5}}, {"c": 3}) and not AudioRules.matches({"z": true}, {}))


func _test_validation(ctx) -> void:
	var broken := {
		"cues": {"a": {"files": ["res://audio/sfx/nope.ogg"], "bus": "Loud"}},
		"events": {"hit": [{"play": ["b"]}]},
		"ui": {"click": "c"},
	}
	var errors := AudioData.validate(broken)
	ctx.check("validation finds a missing file, a bad bus, an unknown cue and a bad ui cue %s" % [errors], errors.size() >= 4)


## A real fight: the player hits a monster and the director plays swings and hits, with no errors.
func _test_fight(ctx, audio: Node, combat) -> void:
	var sim := _duel(combat, "blade")
	_played.clear()
	var attack := SimInput.new()
	for i in 90:
		attack.light = i % 12 == 0
		sim.set_input(1, attack)
		sim.tick()
		audio.handle_events(sim.events, sim, 1)
	ctx.check("a headless fight plays blade swings %s" % [_played.slice(0, 8)], "swing_blade_light" in _played)
	ctx.check("and hits", "hit_light" in _played or "hit_heavy" in _played)
	ctx.check("and the blade's slice layer", "hit_slice" in _played)
	await ctx.process_frame


func _test_voices(ctx, audio: Node) -> void:
	var limit := int(AudioData.cue_settings(audio.data, "hit_light")["max_voices"])
	for i in 12:
		audio._last_played.erase("hit_light")  # (skip the cooldown to hammer the limit)
		audio.play("hit_light")
	var copies := 0
	for player in audio._voices:
		if player.playing and audio._voices[player]["cue"] == "hit_light":
			copies += 1
	ctx.check("one cue never plays more than its voice limit (%d of %d)" % [copies, limit], copies <= limit)
	_played.clear()
	audio.play("hit_heavy")
	audio.play("hit_heavy")
	ctx.check("a cue re-triggered inside its cooldown plays once", _played.count("hit_heavy") == 1)
	for i in 60:
		audio.play("footstep", null, 1.0, 0.0)
		audio._last_played.clear()
	ctx.check("the voice pool never grows (%d players busy)" % audio.active_voices(), audio.active_voices() <= int(audio.data["pools"]["SFX"]) + int(audio.data["pools"]["UI"]) + 2)
	ctx.check("far sounds are quieter, very near ones are not", audio.distance_db(3.0, audio.data["distance"]) == 0.0 and audio.distance_db(20.0, audio.data["distance"]) < -4.0)
	audio._listener = Vector3.ZERO
	ctx.check("sounds past the cull distance do not play", audio.play("enemy_death", Vector3(500, 0, 0)) == null)
	audio._listener = null
	await ctx.process_frame


func _test_ui(ctx, audio: Node) -> void:
	var button := Button.new()
	ctx.root.add_child(button)
	await ctx.process_frame
	_played.clear()
	button.pressed.emit()
	await ctx.process_frame
	await ctx.process_frame
	ctx.check("any button clicks by itself %s" % [_played], _played.count("ui_click") == 1)
	_played.clear()
	button.pressed.emit()
	audio.play_ui("equip")
	await ctx.process_frame
	await ctx.process_frame
	ctx.check("a specific UI sound in the same frame replaces the generic click %s" % [_played], _played == ["ui_equip"])
	_played.clear()
	button.set_meta("audio_ui", "")
	button.pressed.emit()
	await ctx.process_frame
	await ctx.process_frame
	ctx.check("a button can opt out of the click", _played.is_empty())
	button.queue_free()
	await ctx.process_frame


func _test_music(ctx, audio: Node) -> void:
	audio.play_music("stage", 0.05)
	ctx.check("music switches", audio.current_music() == "stage")
	var playing := 0
	for player in audio._music_players:
		if player.playing:
			playing += 1
			ctx.check("the music stream loops", player.stream.get("loop") == true)
			ctx.check("the music plays on the Music bus", player.bus == &"Music")
	ctx.check("a music player is playing", playing >= 1)
	audio.play_ambience("shrine", 0.05)
	ctx.check("ambience switches and plays on the Ambience bus", audio.current_ambience() == "shrine" and audio._ambience_players[audio._ambience_active].bus == &"Ambience")
	_played.clear()
	audio.play("stinger_stage_clear")
	ctx.check("the stage clear stinger plays", _played == ["stinger_stage_clear"])
	audio.set_bus_volume("Music", 0.5)
	ctx.check("bus volume can be set for a settings slider", absf(audio.get_bus_volume("Music") - 0.5) < 0.01)
	audio.set_bus_volume("Music", db_to_linear(-4.0))
	audio.stop_music(0.01)
	audio.play_ambience("", 0.01)
	await ctx.process_frame


func _duel(combat, style: String, enemy_type: String = "dummy_grunt") -> GameSim:
	var world := SimWorld.new()
	world.half_width = 30.0
	world.half_depth = 3.0
	world.add_solid(AABB(Vector3(-40, -0.4, -5), Vector3(80, 0.4, 10)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sim := GameSim.new(world, combat, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"CRIRATE": 0, "STAMINA": 1000}, style)
	sim.add_enemy(2, Vector3(1.0, 0.05, 0), enemy_type)
	sim._ai.erase(2)
	sim.fighters[2].stats["HP"] = 100000.0
	sim.fighters[2].hp = 100000.0
	for i in 12:
		sim.tick()
	var face := SimInput.new()
	face.move = Vector2(0.01, 0)
	sim.set_input(1, face)
	sim.tick()
	sim.set_input(1, SimInput.new())
	return sim


static func _names(picked: Array) -> Array:
	var out := []
	for entry in picked:
		out.append(entry["cue"])
	return out
