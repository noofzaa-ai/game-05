extends RefCounted
## Compact, versioned wire views of a fighter's class-skill cast and race state (logic/net_wire.gd FIGHTER_FIELDS
## "skill_net" / "race_net"). The authority packs them from Fighter.skill_state / race_state (Fighter getters);
## clients validate and unpack them into the presentation fields the views already read (skill_view.class_cast,
## race_state). Plain values only. The server stays authoritative: nothing here feeds back into rules.
##
## Tick domain: cast ticks are sent RELATIVE to the sim tick the snapshot was taken after (skill_state.now - 1), so a
## client rebuilds them in the snapshot's own clock (state.tick, the room clock). Remote bodies are sampled on that
## same clock (runtime/netfox/remote_state.gd), so the clip window and the travel line up with the body.
##
## skill_net v1: [] or [1, skill, start_rel, end_rel, time_mul_milli, flags, travel_from_rel, travel_to_rel,
##                      from: Vector3, to: Vector3, stance_end_rel, counters_rel: Array (<= 8), target]
##   flags: 1 travel, 2 travel stopped (wall), 4 stance end present.
## race_net v1:  [] or [1, race, class, ult_name, fire_at (-1 none), fire_below_hp, ult_move ("" when not casting)]

const SkillData := preload("res://logic/class_skills/skill_data.gd")
const Wire := preload("res://logic/net_wire.gd")
const VERSION := 1
const SKILL_MAX_BYTES := 128  ## encoded with logic/net_wire.gd; a cast row is ~70 B
const RACE_MAX_BYTES := 128  ## ~50-80 B with the ultimate name
const MAX_REL := 36000  ## +-10 min of ticks around the snapshot
const MAX_COORD := 10000.0
const MAX_COUNTERS := 8
const MAX_TEXT := 48
const LINGER_TICKS := 30  ## > the 18-tick max remote interpolation delay (runtime/netfox/remote_state.gd)

static var rejected := 0  ## client-side validation failures (rate-limited log)
static var _last_log_ms := -100000
static var _classes: Array = []


# ---------------------------------------------------------------- authority: pack

static func pack_skill(fighter) -> Array:
	var s: Dictionary = fighter.skill_state
	var cast: Dictionary = s.get("cast", {})
	if cast.is_empty():
		return []
	var base := int(s.get("now", int(cast.get("start", 0)) + 1)) - 1
	var travel: Dictionary = cast.get("travel", {})
	var stance: Dictionary = s.get("stance", {})
	var flags := 0
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var t0 := 0
	var t1 := 0
	if not travel.is_empty():
		flags |= 1
		if bool(travel.get("stopped", false)):
			flags |= 2
		from = travel["from"]
		to = travel["to"]
		t0 = _rel(int(travel["from_tick"]), base)
		t1 = _rel(int(travel["to_tick"]), base)
	var stance_end := 0
	if not stance.is_empty():
		flags |= 4
		stance_end = _rel(int(stance.get("until", base)), base)
	var counters: Array = []
	for tick in stance.get("counter_ticks", []).slice(-MAX_COUNTERS):
		counters.append(_rel(int(tick), base))
	return [VERSION, str(cast["skill"]), _rel(int(cast["start"]), base), _rel(int(cast["end"]), base),
		clampi(roundi(float(cast.get("cast_time", 1.0)) * 1000.0), 50, 20000), flags, t0, t1, from, to, stance_end, counters,
		clampi(int(cast.get("target", -1)), -1, 1000000)]


static func pack_race(fighter) -> Array:
	var r: Dictionary = fighter.race_state
	if r.is_empty():
		return []
	var gauge: Dictionary = r.get("tree", {}).get("gauge", {})
	var fire_at := float(gauge["fire_at"]) if gauge.has("fire_at") else -1.0
	return [VERSION, str(r.get("race", "")).left(MAX_TEXT), str(r.get("class", "")).left(MAX_TEXT),
		str(r.get("ultimate", {}).get("name", "")).left(MAX_TEXT) if not r.get("ultimate", {}).is_empty() else "",
		snappedf(fire_at, 0.01), snappedf(float(gauge.get("fire_below_hp", 0.0)), 0.001), str(r.get("ult", {}).get("move", "")).left(MAX_TEXT * 2 + 10)]


static func _rel(tick: int, base: int) -> int:
	return clampi(tick - base, -MAX_REL, MAX_REL)


# ---------------------------------------------------------------- client: validate + unpack

## {} when `value` is not a valid skill_net row (never partially applied).
static func read_skill(value) -> Dictionary:
	if not value is Array:
		return _reject("skill_type")
	if value.is_empty():
		return {"empty": true}
	if Wire.encode(value).size() > SKILL_MAX_BYTES or value.size() != 13 or typeof(value[0]) != TYPE_INT or value[0] != VERSION:
		return _reject("skill_shape")
	if not value[1] is String or not SkillData.load_default().skills.has(value[1]):
		return _reject("skill_id")
	for i in [2, 3, 6, 7, 10]:
		if typeof(value[i]) != TYPE_INT or absi(value[i]) > MAX_REL:
			return _reject("skill_tick")
	if typeof(value[4]) != TYPE_INT or value[4] < 50 or value[4] > 20000 or typeof(value[5]) != TYPE_INT or value[5] < 0 or value[5] > 7:
		return _reject("skill_flags")
	if typeof(value[12]) != TYPE_INT or value[12] < -1 or value[12] > 1000000 or value[3] < value[2]:
		return _reject("skill_target")
	for i in [8, 9]:
		if not value[i] is Vector3 or not _coord_ok(value[i]):
			return _reject("skill_vector")
	if not value[11] is Array or value[11].size() > MAX_COUNTERS:
		return _reject("skill_counters")
	for tick in value[11]:
		if typeof(tick) != TYPE_INT or absi(tick) > MAX_REL:
			return _reject("skill_counters")
	if value[5] & 1 and value[7] < value[6]:
		return _reject("skill_travel")
	return {"skill": value[1], "start": value[2], "end": value[3], "time_mul": value[4] / 1000.0, "flags": value[5], "from_tick": value[6],
		"to_tick": value[7], "from": value[8], "to": value[9], "stance_end": value[10], "counters": value[11], "target": value[12]}


static func read_race(value) -> Dictionary:
	if not value is Array:
		return _reject("race_type")
	if value.is_empty():
		return {"empty": true}
	if Wire.encode(value).size() > RACE_MAX_BYTES or value.size() != 7 or typeof(value[0]) != TYPE_INT or value[0] != VERSION:
		return _reject("race_shape")
	for i in [1, 2, 3, 6]:
		if not value[i] is String:
			return _reject("race_text")
	var races: Array = preload("res://logic/race_data.gd").load_default().ids()
	if not (value[1] == "" or races.has(value[1])) or not (value[2] == "" or _class_ids().has(value[2])):
		return _reject("race_id")
	if not (value[6] == "" or value[6] == "%s_%s_ultimate" % [value[1], value[2]]):
		return _reject("race_move")
	for i in [4, 5]:
		if typeof(value[i]) != TYPE_FLOAT or not is_finite(value[i]):
			return _reject("race_number")
	if value[4] > 1000.0 or (value[4] < 0.0 and value[4] != -1.0) or value[5] < 0.0 or value[5] > 1.0:
		return _reject("race_number")
	return {"race": value[1], "class": value[2], "ult_name": value[3], "fire_at": value[4], "fire_below_hp": value[5], "ult_move": value[6]}


## Writes a validated skill_net row into fighter.skill_view.class_cast, in the clock of the snapshot (`state_tick`).
## An invalid row leaves the view as the plain skill_view row set it. Returns false when rejected.
## `previous`: the class_cast this fighter showed before this row (skill_view was just replaced from the wire).
static func apply_skill(fighter, value, state_tick: int, previous: Dictionary = {}) -> bool:
	var row := read_skill(value)
	if row.is_empty():
		return false
	if row.has("empty"):
		# Remote bodies are drawn up to ~18 ticks behind the snapshot: keep the ended cast until its recovery is past
		# (the client drops it then, see client/session/netfox_session.gd), else the clip is cut short.
		if bool(previous.get("net", false)) and int(previous.get("end", 0)) >= state_tick - LINGER_TICKS:
			fighter.skill_view["class_cast"] = previous
		else:
			fighter.skill_view.erase("class_cast")
		return true
	var cast := {"skill": row["skill"], "start": state_tick + int(row["start"]), "end": state_tick + int(row["end"]), "now": state_tick,
		"target": row["target"], "time_mul": row["time_mul"], "stance_end": state_tick + int(row["stance_end"]) if row["flags"] & 4 else -1,
		"counters": row["counters"].map(func(t): return state_tick + int(t)), "net": true}
	if row["flags"] & 1:
		cast["travel"] = {"from_tick": state_tick + int(row["from_tick"]), "to_tick": state_tick + int(row["to_tick"]), "from": row["from"],
			"to": row["to"], "stopped": bool(row["flags"] & 2)}
	fighter.skill_view["class_cast"] = cast
	return true


static func apply_race(fighter, value) -> bool:
	var row := read_race(value)
	if row.is_empty():
		return false
	if row.has("empty"):
		fighter.race_state = {}
		return true
	var state := {"race": row["race"], "class": row["class"], "ultimate": {"name": row["ult_name"]} if not str(row["ult_name"]).is_empty() else {}, "net": true}
	if row["fire_at"] >= 0.0:
		state["tree"] = {"gauge": {"fire_at": row["fire_at"], "fire_below_hp": row["fire_below_hp"]}}
	if not str(row["ult_move"]).is_empty():
		state["ult"] = {"move": row["ult_move"]}
	fighter.race_state = state
	return true


# ---------------------------------------------------------------- client: presentation math

## Where the authority had the caster at (fractional) clock tick `clock` during the cast's travel frames, or null
## outside them / when the travel hit a wall (then the sampled positions are the truth). Same formula as
## logic/class_skills/engine.gd _travel: after tick t the body is at lerp(from, to, (t - t0 + 1) / (t1 - t0 + 1)).
static func travel_point(cast: Dictionary, clock: float, half_width: float = INF, half_depth: float = INF):
	var travel: Dictionary = cast.get("travel", {})
	if travel.is_empty() or bool(travel.get("stopped", false)):
		return null
	var t0 := float(travel["from_tick"])
	var t1 := float(travel["to_tick"])
	if clock < t0 - 1.0 or clock > t1:
		return null
	var f := clampf((clock - t0 + 1.0) / maxf(1.0, t1 - t0 + 1.0), 0.0, 1.0)
	var p: Vector3 = Vector3(travel["from"]).lerp(Vector3(travel["to"]), f)
	p.x = clampf(p.x, -half_width, half_width)
	p.z = clampf(p.z, -half_depth, half_depth)
	return p


## The presented position of a REMOTE caster: `sampled` is its interpolated authority position at clock tick `clock`
## (runtime/netfox/remote_state.gd rendered_tick - base_tick). Inside the travel frames the body follows the
## authority's travel line, never more than `snap_m` from the samples (a wall stop or a late row falls back to them).
## Also stamps view["class_cast"].view_tick = clock (the clip clock, client/fighter_view.gd) and drops a cast whose
## recovery is past the drawn tick. `view` is the fighter's skill_view (client copy, presentation only).
static func remote_position(view: Dictionary, sampled: Vector3, clock: float, half_width: float, half_depth: float, snap_m: float) -> Vector3:
	var cast: Dictionary = view.get("class_cast", {})
	if cast.is_empty() or not bool(cast.get("net", false)) or clock < 0.0:
		return sampled
	if clock > float(cast.get("end", 0)) + 1.0:
		view.erase("class_cast")
		return sampled
	cast["view_tick"] = clock
	var point = travel_point(cast, clock, half_width, half_depth)
	if point == null:
		return sampled
	point.y = sampled.y
	return point if point.distance_to(sampled) <= snap_m else sampled


static func _coord_ok(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and absf(v.x) <= MAX_COORD and absf(v.y) <= MAX_COORD and absf(v.z) <= MAX_COORD


static func _class_ids() -> Array:
	if _classes.is_empty():
		_classes = Array(preload("res://logic/card_deck.gd").classes())
	return _classes


static func _reject(reason: String) -> Dictionary:
	rejected += 1
	var now := Time.get_ticks_msec()
	if now - _last_log_ms >= 5000:  # rate-limited: one line per 5 s at most
		_last_log_ms = now
		push_warning("skill_net rejected a row (%s); %d rejected so far" % [reason, rejected])
	return {}
