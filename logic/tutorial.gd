extends RefCounted
## New-player tutorial progress (design/gdd/tutorial.md 3-4, 6). Pure rules over data/tutorial/steps.json and the
## profile's `tutorial` block. The server is the only writer (logic/commands.gd tutorial_step / tutorial_replay).
##
## profile.tutorial.step is the CURRENT step: the one the player is on now ("" = not started, the first step;
## "done" = nothing left). `tutorial_step {step: X}` completes X and is accepted only when X is the current step,
## or "skip_tour" while the current step is a tour step. Steps about a card that already has a race are passed
## automatically (a second device, tutorial.md 6). The unlock group runs once unlocks are set and unlock_seen is false.

const PATH := "res://data/tutorial/steps.json"
const DONE := "done"
const SKIP_TOUR := "skip_tour"
const FIELDS := ["id", "group", "screen", "target", "text_th", "text_en", "done_on", "skippable"]
const GROUPS := ["race", "fight", "tour", "unlock"]
const MAX_TEXT := 60
const CardDeck := preload("res://logic/card_deck.gd")
const Unlocks := preload("res://logic/unlocks.gd")

static var _cache = null


## {"version": int, "steps": [step...]}; {} when the file is missing or broken.
static func data() -> Dictionary:
	if _cache == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary and parsed.get("steps") is Array else {}
	return _cache


static func version() -> int:
	return int(data().get("version", 0))


static func steps() -> Array:
	return data().get("steps", [])


## Problems of a steps document (the validation test, tutorial.md 7 test 7); [] when sound.
static func problems(doc: Dictionary) -> Array:
	var out: Array = []
	if not doc.get("version") is float and not doc.get("version") is int:
		out.append("version missing")
	if not doc.get("steps") is Array or (doc["steps"] as Array).is_empty():
		out.append("steps missing")
		return out
	var seen := {}
	var last_group := 0
	for step in doc["steps"]:
		if not step is Dictionary:
			out.append("step not an object")
			continue
		for key in FIELDS:
			if not step.has(key):
				out.append("%s: %s missing" % [step.get("id", "?"), key])
		var id := str(step.get("id", ""))
		if id.is_empty() or id in [DONE, SKIP_TOUR] or seen.has(id):
			out.append("bad or repeated id '%s'" % id)
		seen[id] = true
		var group := GROUPS.find(str(step.get("group", "")))
		if group < 0:
			out.append("%s: unknown group" % id)
		elif group < last_group:
			out.append("%s: groups out of order" % id)
		last_group = maxi(last_group, group)
		for key in ["text_th", "text_en"]:
			var text := str(step.get(key, ""))
			if text.strip_edges().is_empty() or text.length() > MAX_TEXT:
				out.append("%s: %s empty or over %d characters" % [id, key, MAX_TEXT])
		if not step.get("done_on") is Dictionary or str(step["done_on"].get("event", "")).is_empty():
			out.append("%s: done_on.event missing" % id)
		if not step.get("skippable") is bool:
			out.append("%s: skippable not a bool" % id)
	return out


static func index_of(id: String) -> int:
	var list := steps()
	for i in list.size():
		if str(list[i].get("id", "")) == id:
			return i
	return -1


static func step_data(id: String) -> Dictionary:
	var at := index_of(id)
	return steps()[at] if at >= 0 else {}


static func group_of(id: String) -> String:
	return str(step_data(id).get("group", ""))


## The step the player is on now ("" in the save = the first step).
static func current(profile) -> String:
	var step := str(profile.tutorial.get("step", DONE))
	if step.is_empty() and not steps().is_empty():
		return str(steps()[0]["id"])
	if step == DONE and _unlock_pending(profile):
		return _first_of("unlock")
	return step


## True once the player is past `id` (or finished): e.g. past("battle_tip") opens online rooms (tutorial.md 6).
static func past(profile, id: String) -> bool:
	var step := str(profile.tutorial.get("step", DONE))
	if step == DONE:
		return true
	if step.is_empty():
		return false
	var at := index_of(step)
	return at < 0 or at > index_of(id)


## Completes `id` (or "skip_tour"). {"ok": true, "step": new current} or {"ok": false, "reason": "invalid_step"}.
static func step(profile, id: String) -> Dictionary:
	var now := current(profile)
	if now == DONE:
		return {"ok": false, "reason": "invalid_step"}
	if id == SKIP_TOUR:
		if group_of(now) != "tour":
			return {"ok": false, "reason": "invalid_step"}
		profile.tutorial["tour_done"] = true
		_store(profile, _after_group(now))
		return {"ok": true, "step": str(profile.tutorial["step"])}
	if id != now:
		return {"ok": false, "reason": "invalid_step"}
	if id == _last_of("tour"):
		profile.tutorial["tour_done"] = true
	if group_of(id) == "unlock" and id == _last_of("unlock"):
		profile.tutorial["unlock_seen"] = true
	_store(profile, _next_after(index_of(id)))
	return {"ok": true, "step": str(profile.tutorial["step"])}


## Settings "replay tour" (tutorial.md 6): resets the tour fields only; refused before the tour has been reached.
static func replay(profile) -> Dictionary:
	var first := _first_of("tour")
	if first.is_empty() or not past(profile, _prev_of(first)):
		return {"ok": false, "reason": "not_available_here"}
	profile.tutorial["tour_done"] = false
	profile.tutorial["step"] = first
	profile.tutorial["version"] = version()
	return {"ok": true, "step": first}


# ---------------------------------------------------------------- internals

static func _unlock_pending(profile) -> bool:
	return Unlocks.unlocked(profile) and not bool(profile.tutorial.get("unlock_seen", true)) and not _first_of("unlock").is_empty()


## Stores `next` as the current step after passing every step that is already true.
static func _store(profile, next: String) -> void:
	while next != DONE and _already_true(profile, step_data(next)):
		if next == _last_of("unlock"):
			profile.tutorial["unlock_seen"] = true
		next = _next_after(index_of(next))
	profile.tutorial["step"] = next
	profile.tutorial["version"] = version()


## A card step whose card already has a race (tutorial.md 6: auto-advance).
static func _already_true(profile, data: Dictionary) -> bool:
	var card := str(data.get("card", ""))
	return not card.is_empty() and CardDeck.has_race(profile.card_deck, card)


## The step after index `at`; the unlock group only when it is pending, else "done".
static func _next_after(at: int) -> String:
	var list := steps()
	if at + 1 >= list.size():
		return DONE
	var next := str(list[at + 1]["id"])
	if group_of(next) == "unlock" and group_of(str(list[at]["id"])) != "unlock":
		return DONE  # current() reopens the unlock group when it becomes pending
	return next


static func _after_group(id: String) -> String:
	var group := group_of(id)
	var at := index_of(id)
	while at + 1 < steps().size() and group_of(str(steps()[at + 1]["id"])) == group:
		at += 1
	return _next_after(at)


static func _first_of(group: String) -> String:
	for s in steps():
		if str(s["group"]) == group:
			return str(s["id"])
	return ""


static func _last_of(group: String) -> String:
	var found := ""
	for s in steps():
		if str(s["group"]) == group:
			found = str(s["id"])
	return found


static func _prev_of(id: String) -> String:
	var at := index_of(id)
	return str(steps()[at - 1]["id"]) if at > 0 else ""
