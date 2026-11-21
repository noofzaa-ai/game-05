extends RefCounted
## Daily quests (Boss 2026-11-21; data/world/daily_quests.json). Pure rules over Profile.daily
## {"day": int, "counts": {stat: int}, "claimed": [quest ids]}. The day is the SERVER clock's unix time (the `now` every
## command already gets) shifted so it turns over at reset_hour_utc; a block of another day reads as empty, so the reset
## needs no timer. Counters change only at a run's end on the authority (record_run, from logic/journey.gd); the
## reward only through the daily_claim command (logic/commands.gd). No nodes, no client code.

const PATH := "res://data/world/daily_quests.json"
const STATS := ["fights", "waves", "bosses"]
const DAY := 86400

static var _cache = null


static func data() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func quests() -> Array:
	return Array(data().get("quests", []))


static func quest(id: String) -> Dictionary:
	for q in quests():
		if str(q.get("id", "")) == id:
			return q
	return {}


## The day number of a unix time (the day turns over at reset_hour_utc). now <= 0 = the clock is missing: day 0.
static func day_of(now: int) -> int:
	if now <= 0:
		return 0
	return int(floor(float(now - int(data().get("reset_hour_utc", 0)) * 3600) / DAY))


## Seconds until the next reset.
static func seconds_to_reset(now: int) -> int:
	var offset := int(data().get("reset_hour_utc", 0)) * 3600
	return (day_of(now) + 1) * DAY + offset - now


## The profile's block for the day of `now` (a fresh one when the stored day is older).
static func today(profile, now: int) -> Dictionary:
	var d := day_of(now)
	var stored = profile.daily if profile != null and "daily" in profile and profile.daily is Dictionary else {}
	if int(stored.get("day", -1)) != d:
		return {"day": d, "counts": {}, "claimed": []}
	return {"day": d, "counts": Dictionary(stored.get("counts", {})).duplicate(), "claimed": Array(stored.get("claimed", [])).duplicate()}


## [{id, current, target, done, claimed, reward_gold, name_th, name_en, desc_th, desc_en}] for the day of `now`.
static func progress(profile, now: int) -> Array:
	var t := today(profile, now)
	var out: Array = []
	for q in quests():
		var target := maxi(int(q.get("target", 1)), 1)
		var cur := mini(int(t.counts.get(str(q.get("stat", "")), 0)), target)
		var fill := func(text: String) -> String: return text.replace("{cur}", str(cur)).replace("{target}", str(target))
		out.append({"id": str(q.get("id", "")), "current": cur, "target": target, "done": cur >= target,
			"claimed": t.claimed.has(str(q.get("id", ""))), "reward_gold": int(q.get("reward", {}).get("gold", 0)),
			"name_th": str(q.get("name_th", "")), "name_en": str(q.get("name_en", "")),
			"desc_th": fill.call(str(q.get("desc_th", ""))), "desc_en": fill.call(str(q.get("desc_en", "")))})
	return out


## How many quests are done but not claimed yet (the hub hint).
static func claimable(profile, now: int) -> int:
	return progress(profile, now).filter(func(q): return q.done and not q.claimed).size()


## Authority, at a run's end: one finished fight, its cleared waves, a boss when won. now <= 0 records nothing.
static func record_run(profile, now: int, waves: int, won: bool) -> void:
	if profile == null or not "daily" in profile or now <= 0:
		return
	var t := today(profile, now)
	t.counts["fights"] = int(t.counts.get("fights", 0)) + 1
	t.counts["waves"] = int(t.counts.get("waves", 0)) + maxi(waves, 0)
	if won:
		t.counts["bosses"] = int(t.counts.get("bosses", 0)) + 1
	profile.daily = t


## daily_claim: pays the quest's gold once per day when it is done. {ok, reason?, gold?}
static func claim(profile, quest_id: String, now: int) -> Dictionary:
	if now <= 0:
		return {"ok": false, "reason": "clock_unavailable"}
	var q := quest(quest_id)
	if q.is_empty():
		return {"ok": false, "reason": "unknown_quest"}
	for row in progress(profile, now):
		if row.id != quest_id:
			continue
		if row.claimed:
			return {"ok": false, "reason": "already_claimed"}
		if not row.done:
			return {"ok": false, "reason": "quest_not_done"}
		var t := today(profile, now)
		t.claimed.append(quest_id)
		profile.daily = t
		profile.stash.gold += int(row.reward_gold)
		return {"ok": true, "gold": int(row.reward_gold)}
	return {"ok": false, "reason": "unknown_quest"}


## A saved block, cleaned (from_dict): only known stats, non-negative ints, string ids.
static func sanitized(raw) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	var counts := {}
	if raw.get("counts") is Dictionary:
		for k in raw["counts"]:
			if str(k) in STATS:
				counts[str(k)] = maxi(int(raw["counts"][k]), 0)
	var claimed: Array = []
	if raw.get("claimed") is Array:
		for id in raw["claimed"]:
			if not claimed.has(str(id)):
				claimed.append(str(id))
	return {"day": int(raw.get("day", 0)), "counts": counts, "claimed": claimed}


## Data check (tests).
static func problems() -> Array:
	var out: Array = []
	var ids := {}
	if quests().is_empty():
		return ["no daily quests"]
	var hour := int(data().get("reset_hour_utc", -1))
	if hour < 0 or hour > 23:
		out.append("reset_hour_utc out of range")
	for q in quests():
		var id := str(q.get("id", ""))
		if id.is_empty() or ids.has(id):
			out.append("bad or repeated id %s" % id)
		ids[id] = true
		if not str(q.get("stat", "")) in STATS:
			out.append("%s unknown stat" % id)
		if int(q.get("target", 0)) < 1:
			out.append("%s target < 1" % id)
		var gold := int(q.get("reward", {}).get("gold", -1))
		if gold < 1 or gold > 5000:
			out.append("%s reward gold out of range" % id)
		for key in ["name_th", "name_en", "desc_th", "desc_en"]:
			if str(q.get(key, "")).is_empty():
				out.append("%s missing %s" % [id, key])
	return out
