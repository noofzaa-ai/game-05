extends RefCounted
## Fight-screen text rules (ux-ui 2026-11-25, Boss: "the fight HUD is a mess"; the fight screen must stay CLEAN).
## Every floating word of a fight asks this first: its category decides lane / hide / icon / feed / top / once
## (data/ui/fight_text.json). Lane lines live here (one lane per fighter, max lane_lines, same word within
## merge_seconds merges "WORD x2", a screen budget caps all lanes together). Pure bookkeeping: no nodes, no drawing,
## never changes combat. client/combo_fight.gd draws what this keeps.

const PATH := "res://data/ui/fight_text.json"

var data: Dictionary = {}
var phone := false
## fighter id -> Array of {"text", "base", "count", "color", "age"} (oldest first)
var lanes: Dictionary = {}
## the single top-centre line (combo payoffs): {} or {"text", "states", "color", "age"}
var top: Dictionary = {}
var _once: Dictionary = {}  ## "id:word" -> seconds since shown


static func load_default() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	return parsed if parsed is Dictionary else {}


func _init(rules: Dictionary = {}) -> void:
	data = rules if not rules.is_empty() else load_default()


func category_action(category: String) -> String:
	return str(data.get("categories", {}).get(category, "lane"))


## The category of an applied status effect for the fighter's side ("control" for stun/shock/sleep).
static func effect_category(effect: Dictionary, ours: bool) -> String:
	if not str(effect.get("control", "")).is_empty():
		return "control"
	return ("buff" if str(effect.get("kind", "")) == "buff" else "debuff") + ("_ours" if ours else "_enemy")


func budget() -> int:
	return int(data.get("budget", {}).get("phone" if phone else "desktop", 6))


func line_count() -> int:
	var n := 0
	for lane in lanes.values():
		n += (lane as Array).size()
	return n


## Ask to show `text` of `category` over fighter `id`. Returns what happened: "lane", "merged", "hide", "icon",
## "feed", "top", "once_skipped". Only "lane"/"merged" put a line in the fighter's lane.
func push(id: int, category: String, text: String, color: Color = Color.WHITE) -> String:
	var action := category_action(category)
	match action:
		"hide", "icon", "feed":
			return action
		"top":
			top = {"text": text, "color": color, "age": 0.0}
			return "top"
		"once":
			var key := "%d:%s" % [id, text]
			if _once.has(key) and float(_once[key]) < float(data.get("once_seconds", 6.0)):
				return "once_skipped"
			_once[key] = 0.0
	var lane: Array = lanes.get(id, [])
	var window := float(data.get("merge_seconds", 1.5))
	for line in lane:
		if line["base"] == text and float(line["age"]) < window:
			line["count"] = int(line["count"]) + 1
			line["text"] = "%s x%d" % [text, line["count"]]
			line["age"] = 0.0
			return "merged"
	lane.append({"text": text, "base": text, "count": 1, "color": color, "age": 0.0})
	while lane.size() > int(data.get("lane_lines", 2)):
		lane.pop_front()
	lanes[id] = lane
	# Screen budget: drop the oldest line anywhere until we fit.
	while line_count() > budget():
		_drop_oldest()
	return "lane"


func _drop_oldest() -> void:
	var worst_id = null
	var worst_age := -1.0
	for id in lanes:
		var lane: Array = lanes[id]
		if not lane.is_empty() and float(lane[0]["age"]) > worst_age:
			worst_age = float(lane[0]["age"])
			worst_id = id
	if worst_id != null:
		(lanes[worst_id] as Array).pop_front()


func tick(delta: float) -> void:
	var life := float(data.get("line_seconds", 1.1))
	for id in lanes.keys():
		var lane: Array = lanes[id]
		for line in lane:
			line["age"] = float(line["age"]) + delta
		lane = lane.filter(func(l): return float(l["age"]) < life)
		if lane.is_empty():
			lanes.erase(id)
		else:
			lanes[id] = lane
	for key in _once.keys():
		_once[key] = float(_once[key]) + delta
	if not top.is_empty():
		top["age"] = float(top["age"]) + delta
		if float(top["age"]) >= float(data.get("top_seconds", 1.4)):
			top = {}


## Does a damage number show? Crits and combo payoffs always; normal hits only when big (fraction of max HP).
func shows_number(damage: float, target_max_hp: float, crit: bool, combo: bool = false) -> bool:
	if crit or combo:
		return true
	return damage >= float(data.get("numbers", {}).get("big_hit_fraction", 0.08)) * maxf(target_max_hp, 1.0)


func shows_heal(amount: float, max_hp: float) -> bool:
	return amount >= float(data.get("numbers", {}).get("heal_fraction", 0.1)) * maxf(max_hp, 1.0)


## A status icon's look {"shape", "color", "glyph"} (data/ui/fight_text.json status_icons), or {} if not listed.
func status_icon(effect_id: String) -> Dictionary:
	var raw: Dictionary = data.get("status_icons", {}).get("icons", {}).get(effect_id, {})
	if raw.is_empty():
		return {}
	var c := str(raw.get("color", "CCCCCC"))
	return {"shape": str(raw.get("shape", "circle")), "color": Color.html(c) if Color.html_is_valid(c) else Color.GRAY, "glyph": str(raw.get("glyph", "?"))}


## The status icon radius in px at layout scale `s` (data status_icons.size, phone or desktop).
func icon_radius(s: float) -> float:
	var size: Dictionary = data.get("status_icons", {}).get("size", {})
	var key := "phone" if phone else "desktop"
	return maxf(float(size.get("min_px", {}).get(key, 7.0)), float(size.get("radius", {}).get(key, 11.0)) * s)


func max_icons() -> int:
	return int(data.get("status_icons", {}).get("max_icons", 3))


## The status ids (in a stable order) on a fighter's effects dictionary that have an icon.
func statuses_of(effects: Dictionary) -> Array:
	var ids: Array = []
	for key in data.get("status_icons", {}).get("icons", {}):
		if effects.has(key):
			ids.append(key)
	return ids
