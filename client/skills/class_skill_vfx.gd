extends Node3D
## Class skills v2 VFX (design/gdd/class-skills.md 3.2-3.5 "VFX:", Boss 2026-11-13: ship the 16 daiyooo-vfx effects).
## Resolves each skill's `vfx` key `class_skill/<id>` (data/class_skills/class_skills.json) to
## res://art/vfx/class_skills/<id>/effect.tscn and plays it from the sim's class skill events:
##   class_skill_start / class_skill_release / class_skill_telegraph / class_skill_veil / class_skill_impact,
## at the caster, the target, the ground point, or along the orb's travel path. Display only: nothing here
## changes the fight. Instances are pooled per skill and built + drawn once under the floor while the stage
## loads (no shader cache on the web), so the first cast does not stutter. An effect goes back to its pool
## when its clip ends (or, for a stance/buff aura, when the sim's class_buffs entry ends).
##
## SPEC per skill: on = the event that starts it; at = caster | target | point | impact; seek = seconds into
## the effect clip to start from (lines the clip's own impact frame up with the game's); delay = seconds to
## wait; face = turn local +Z (the asset's forward) toward the aim; follow = stay on the fighter; buff = the
## class_buffs key that keeps a looping aura alive; back = metres the effect is pulled back from the target
## toward the caster (a shot's flight and burst end on the target); travel = an orb carried along its path.

const ROOT := "res://art/vfx/class_skills/"
const PREFIX := "class_skill/"
const SkillData := preload("res://logic/class_skills/skill_data.gd")
const GraphicsOptions := preload("res://client/graphics_options.gd")
const TICKS := 60.0

const SPEC := {
	"shield_rush": {"on": "start", "at": "caster", "face": true},
	"iron_guard": {"on": "start", "at": "caster", "follow": true, "buff": "stance"},
	"intercept": {"on": "release", "at": "caster", "seek": 0.45},
	"breaker_slam": {"on": "release", "at": "caster", "seek": 0.45, "face": true},
	"reaping_arc": {"on": "release", "at": "caster", "seek": 0.12, "face": true},
	"crater_leap": {"on": "release", "at": "caster", "seek": 0.05, "face": true},
	"hook_sweep": {"on": "start", "at": "caster", "delay": 0.1},
	"battle_trance": {"on": "release", "at": "caster", "follow": true, "buff": "trance"},
	"heartseeker_shot": {"on": "release", "at": "target", "seek": 0.6, "back": 2.6, "face": true},
	"pinning_shot": {"on": "release", "at": "target", "seek": 0.35, "back": 2.0, "face": true},
	"rapid_fire": {"on": "release", "first_only": true, "at": "target", "seek": 0.15, "back": 4.0, "face": true},
	"vault_shot": {"on": "release", "at": "caster", "seek": 0.1, "face": true},
	"arcane_orb": {"on": "release", "at": "caster", "travel": 12.0, "travel_frame": 0.55, "impact_seek": 0.95, "face": true},
	"repulse_nova": {"on": "release", "at": "caster", "seek": 0.5},
	"starfall": {"on": "telegraph", "at": "point", "lead": 0.42},
	"warding_veil": {"on": "veil", "at": "target", "follow": true, "buff": "veil"},
}

var session  ## the stage's session (bodies, fighters, events)
var views: Dictionary = {}  ## fighter id -> fighter_view (shared with stage_view)

var _packed: Dictionary = {}  ## skill -> PackedScene
var _pool: Dictionary = {}  ## skill -> Array of idle instances
var _live: Array = []  ## {node, skill, player, age, length, loop, follow, buff, orb, dir, speed, left}
var _pending: Array = []  ## {skill, wait, args}
var prewarmed: Array = []  ## skills built and drawn during loading (tests)
## Web perf A/B (tech-artist, 2026-11-13): the page URL `?class_vfx=0` turns these effects off; the live count is
## published as window.zorxClassVfxLive for the browser frame-time probe. Debug only, no effect on the fight.
var enabled := true
var _publish_clock := 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		enabled = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('class_vfx')", true)) != "0"


## The scene for a `vfx` key ("class_skill/<id>"), or "" when it is not a class skill effect.
static func scene_path(vfx_key: String) -> String:
	if not vfx_key.begins_with(PREFIX):
		return ""
	var path := ROOT + vfx_key.trim_prefix(PREFIX) + "/effect.tscn"
	return path if ResourceLoader.exists(path) else ""


## Builds `copies` idle instances of each skill and plays every one a few frames at `hidden` (under the floor)
## so its materials compile during loading. `skills` = the class skills the fighters on the field carry.
func prewarm(skills: Array, hidden: Vector3, copies: Dictionary = {}) -> void:
	for skill in skills:
		var key := str(skill)
		if not SPEC.has(key) or prewarmed.has(key):
			continue
		var n := maxi(1, int(copies.get(key, 1)))
		if SPEC[key].has("travel"):
			n += 1  # the flying orb and its burst are two instances
		for i in n:
			var inst := _make(key)
			if inst == null:
				break
			_start(inst, 0.5, hidden, Vector3.FORWARD, false)
			_live.append({"node": inst, "skill": key, "player": -1, "age": 0.0, "length": 0.15, "loop": false, "follow": -1, "buff": "", "orb": false})
		prewarmed.append(key)


## The class skill ids carried by the fighters of `session` (to prewarm only what this fight can cast).
static func skills_on_field(sim_session) -> Dictionary:
	var count := {}
	for id in sim_session.fighters:
		var fighter = sim_session.fighters[id]
		var state = fighter.get("skill_state")
		if state is Dictionary:
			for skill in state.get("skills", []):
				count[str(skill)] = int(count.get(str(skill), 0)) + 1
	return count


func handle_events(events: Array) -> void:
	if not enabled or not GraphicsOptions.enabled("combat_vfx"):
		return
	for event in events:
		var type := str(event.get("type", ""))
		match type:
			"class_skill_start":
				_on("start", str(event.get("skill", "")), event)
			"class_skill_release":
				_on("release", str(event.get("skill", "")), event)
			"class_skill_telegraph":
				_on("telegraph", str(event.get("skill", "")), event)
			"class_skill_veil":
				_on("veil", "warding_veil", event)
			"class_skill_impact":
				_orb_impact(event)
			"class_skill_lost":
				_cancel(int(event.get("player", -1)))


func _on(trigger: String, skill: String, event: Dictionary) -> void:
	var spec: Dictionary = SPEC.get(skill, {})
	if spec.is_empty() or str(spec["on"]) != trigger:
		return
	if bool(spec.get("first_only", false)) and int(event.get("index", 0)) != 0:
		return
	var player := int(event.get("player", -1))
	if session == null or not session.bodies.has(player):
		return
	var caster: Vector3 = _position_of(player)
	var aim: Vector3 = event.get("aim", caster + Vector3.FORWARD) if event.get("aim") is Vector3 else caster + Vector3.FORWARD
	var target := int(event.get("target", -1))
	var dir := Vector3(aim.x - caster.x, 0.0, aim.z - caster.z)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var at := caster
	var follow := -1
	match str(spec["at"]):
		"target":
			if trigger == "veil" and session.bodies.has(target):
				at = _position_of(target)
				follow = target
			else:
				at = Vector3(aim.x, caster.y, aim.z) - dir * float(spec.get("back", 0.0))
		"point":
			at = event.get("pos", aim)
		_:
			if bool(spec.get("follow", false)):
				follow = player
	var wait := float(spec.get("delay", 0.0))
	if spec.has("lead"):  # the clip's strike frame lands when the sim's delayed blow does
		wait = maxf(0.0, float(event.get("ticks", 0)) / TICKS - float(spec["lead"]))
	var args := {"skill": skill, "player": player, "at": at, "dir": dir, "follow": follow if bool(spec.get("follow", false)) else -1}
	if wait > 0.0:
		_pending.append({"wait": wait, "args": args})
	else:
		_spawn(args)


func _spawn(args: Dictionary) -> void:
	var skill := str(args["skill"])
	var spec: Dictionary = SPEC[skill]
	var inst := _take(skill)
	if inst == null:
		return
	var is_orb := spec.has("travel")
	var seek := float(spec.get("travel_frame", 0.0)) if is_orb else float(spec.get("seek", 0.0))
	_start(inst, seek, args["at"], args["dir"] if bool(spec.get("face", false)) else Vector3.ZERO, is_orb)
	var length := _clip_length(inst)
	_live.append({"node": inst, "skill": skill, "player": int(args["player"]), "age": seek, "length": length,
		"loop": spec.has("buff"), "follow": int(args["follow"]), "buff": str(spec.get("buff", "")), "orb": is_orb,
		"dir": args["dir"], "speed": float(spec.get("travel", 0.0)), "left": 14.0, "watch": float(spec.get("delay", 0.0))})


## An orb's job reached something (or its range): its flying effect ends there and the burst plays.
func _orb_impact(event: Dictionary) -> void:
	var player := int(event.get("player", -1))
	var pos: Vector3 = event.get("pos", Vector3.ZERO)
	for i in range(_live.size() - 1, -1, -1):
		var fx: Dictionary = _live[i]
		if bool(fx["orb"]) and int(fx["player"]) == player:
			var skill := str(fx["skill"])
			_release(fx)
			_live.remove_at(i)
			var inst := _take(skill)
			if inst != null:
				var seek := float(SPEC[skill].get("impact_seek", 0.9))
				_start(inst, seek, pos - Vector3(fx["dir"]) * 2.7, fx["dir"], false)
				_live.append({"node": inst, "skill": skill, "player": player, "age": seek, "length": _clip_length(inst), "loop": false, "follow": -1, "buff": "", "orb": false})
			return


func _cancel(player: int) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		if int(_pending[i]["args"]["player"]) == player:
			_pending.remove_at(i)
	for i in range(_live.size() - 1, -1, -1):
		var fx: Dictionary = _live[i]
		if int(fx["player"]) == player and (bool(fx["orb"]) or str(fx["buff"]) == "stance"):
			_release(fx)
			_live.remove_at(i)


func _process(delta: float) -> void:
	if OS.has_feature("web"):
		_publish_clock += delta
		if _publish_clock >= 0.1:
			_publish_clock = 0.0
			var names := ",".join(_live.map(func(fx): return str(fx["skill"])))
			JavaScriptBridge.eval("window.zorxClassVfxLive = %d; window.zorxClassVfxOn = %s; window.zorxClassVfxNames = '%s'" % [_live.size(), "true" if enabled else "false", names], true)
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i]["wait"] = float(_pending[i]["wait"]) - delta
		if float(_pending[i]["wait"]) <= 0.0:
			var args: Dictionary = _pending[i]["args"]
			_pending.remove_at(i)
			_spawn(args)
	for i in range(_live.size() - 1, -1, -1):
		var fx: Dictionary = _live[i]
		fx["age"] = float(fx["age"]) + delta
		var node: Node3D = fx["node"]
		var done := false
		if int(fx["follow"]) >= 0:
			if session != null and session.bodies.has(int(fx["follow"])):
				node.global_position = _position_of(int(fx["follow"]))
			else:
				done = true
		if bool(fx["orb"]):
			var step := float(fx["speed"]) * delta
			node.global_position += Vector3(fx["dir"]) * step
			fx["left"] = float(fx["left"]) - step
			done = done or float(fx["left"]) <= 0.0
		elif bool(fx["loop"]):
			done = done or (float(fx["age"]) > 0.5 and not _buff_on(int(fx["follow"]), str(fx["buff"])))
		else:
			done = done or float(fx["age"]) >= float(fx["length"])
		if done:
			_release(fx)
			_live.remove_at(i)


func _buff_on(id: int, key: String) -> bool:
	if session == null or not session.fighters.has(id):
		return false
	var fighter = session.fighters[id]
	if not fighter.is_alive():
		return false
	var buffs = fighter.skill_view.get("class_buffs", {})
	return buffs is Dictionary and buffs.has(key)


## How many class skill effects are playing now (tests, the performance overlay).
func live_count() -> int:
	return _live.size()


func _position_of(id: int) -> Vector3:
	if views.has(id) and is_instance_valid(views[id]):
		return views[id].global_position
	return session.bodies[id].position


func _make(skill: String) -> Node3D:
	if not _packed.has(skill):
		var path := scene_path(str(SkillData.load_default().skill(skill).get("vfx", PREFIX + skill)))
		if path == "":
			push_warning("class skill VFX missing for " + skill)
			_packed[skill] = null
			return null
		_packed[skill] = load(path)
	var packed: PackedScene = _packed[skill]
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	inst.set("autoplay", false)
	inst.set("free_on_finish", false)
	inst.visible = false
	add_child(inst)
	return inst


func _take(skill: String) -> Node3D:
	var idle: Array = _pool.get(skill, [])
	if not idle.is_empty():
		return idle.pop_back()
	return _make(skill)  # (a cast nobody prewarmed: built now)


func _start(inst: Node3D, seek: float, at: Vector3, dir: Vector3, hold: bool) -> void:
	inst.global_position = at
	if dir.length() > 0.01:
		inst.global_basis = Basis.looking_at(-dir, Vector3.UP)  # the asset's forward is +Z
	else:
		inst.global_basis = Basis.IDENTITY
	inst.visible = true
	var player := _player_of(inst)
	if player == null:
		return
	var clip := _clip_of(player)
	player.play(clip)
	player.seek(seek, true)
	if hold:
		player.pause()  # a flying orb holds one flight frame and the node carries it


func _release(fx: Dictionary) -> void:
	var inst: Node3D = fx["node"]
	if not is_instance_valid(inst):
		return
	var player := _player_of(inst)
	if player != null:
		player.stop()
	inst.visible = false
	var skill := str(fx["skill"])
	if not _pool.has(skill):
		_pool[skill] = []
	_pool[skill].append(inst)


func _player_of(inst: Node) -> AnimationPlayer:
	if inst.has_meta("vfx_player"):
		return inst.get_meta("vfx_player")
	var found := inst.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = found[0] if not found.is_empty() else null
	inst.set_meta("vfx_player", player)
	return player


func _clip_of(player: AnimationPlayer) -> StringName:
	for name in player.get_animation_list():
		if name != &"RESET":
			return name
	return &""


func _clip_length(inst: Node) -> float:
	var player := _player_of(inst)
	if player == null:
		return 0.0
	var clip := _clip_of(player)
	return player.get_animation(clip).length if clip != &"" else 0.0
