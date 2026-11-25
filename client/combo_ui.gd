extends RefCounted
## Cross-class skill combos, the display side (Boss 2026-11-25): 8 shared states; each class skill "sets" some and
## "pays off" others (data/combat/combos.json, owned by combat). This file only READS that data and turns it into what
## the screens show: badge lists, squad links ("Combos in squad: N pairs"), "Works with" lines, the fight popup text and
## the summary line. No rules are decided here: whether a payoff fires is the sim's job (event {type:"combo"}).
## Colour language (one place): every state = its colour + its own SHAPE + a short glyph, so it still reads without
## colour (colour-blind safe). Text [th, en] lives in TEXT; CardTokens.language picks.

const CardTokens := preload("res://client/card_tokens.gd")

const PATH := "res://data/combat/combos.json"
const CLASS_SKILLS_PATH := "res://data/class_skills/class_skills.json"
const ORDER: Array[String] = ["stagger", "cluster", "mark", "sunder", "airborne", "taunt", "guarded", "hasted"]
## Fallbacks when the data file leaves a field out (Boss-suggested colours). Shape ids are drawn by draw_state_icon.
const DEFAULTS := {
	"stagger": {"color": "F2C230", "shape": "star", "glyph": "!", "name_en": "Stagger", "name_th": "เซ"},
	"cluster": {"color": "9B5DE5", "shape": "triangle", "glyph": "@", "name_en": "Cluster", "name_th": "รวมกลุ่ม"},
	"mark": {"color": "E5383B", "shape": "diamond", "glyph": "x", "name_en": "Mark", "name_th": "เป้า"},
	"sunder": {"color": "3A3A40", "shape": "square", "glyph": "/", "name_en": "Sunder", "name_th": "เกราะแตก"},
	"airborne": {"color": "3A86FF", "shape": "triangle_down", "glyph": "^", "name_en": "Airborne", "name_th": "ลอย"},
	"taunt": {"color": "FB8500", "shape": "hexagon", "glyph": "!", "name_en": "Taunt", "name_th": "ยั่ว"},
	"guarded": {"color": "2A9D4B", "shape": "shield", "glyph": "+", "name_en": "Guarded", "name_th": "ถูกปกป้อง"},
	"hasted": {"color": "F4F1E8", "shape": "circle", "glyph": ">", "name_en": "Hasted", "name_th": "เร่งความเร็ว"},
}
const TEXT := {
	"sets": ["ติด", "Sets"],
	"payoff": ["รับคอมโบ", "Pays off"],
	"none": ["-", "-"],
	"squad_pairs": ["คอมโบในทีม: %d คู่", "Combos in squad: %d pairs"],
	"squad_pair_one": ["คอมโบในทีม: 1 คู่", "Combos in squad: 1 pair"],
	"squad_none": ["ทีมนี้ยังไม่มีคอมโบ", "No combos in this squad yet"],
	"squad_need": ["เลือก 2-3 การ์ดเพื่อดูคอมโบ", "Pick 2-3 cards to see combos"],
	"works_with": ["ใช้คู่กับ: %s", "Works with: %s"],
	"works_none": ["ยังไม่มีสกิลในทีมที่เข้าคู่", "No skill in this squad pairs with it"],
	"tap_skill": ["แตะสกิลเพื่อดูคู่คอมโบ", "Tap a skill to see its partners"],
	"title": ["คอมโบของทีม", "Squad combos"],
	"combo": ["คอมโบ", "COMBO"],
	"summary": ["คอมโบ %d ครั้ง, ดาเมจคอมโบ %d%%", "Combos %d, combo damage %d%%"],
	"summary_none": ["ยังไม่มีคอมโบในรอบนี้", "No combos this run"],
	"no_data": ["ยังไม่มีข้อมูลคอมโบ", "Combo data not available yet"],
}

static var _default: Dictionary = {}
static var _skill_info: Dictionary = {}  ## skill id -> {"name", "class"}


static func t(key: String) -> String:
	var entry: Array = TEXT.get(key, [key, key])
	return str(entry[0 if CardTokens.language == "th" else 1])


## A TEXT entry in the description language (the "works with" line; menu words use t()).
static func dt(key: String) -> String:
	var entry: Array = TEXT.get(key, [key, key])
	return str(entry[0 if CardTokens.desc_language() == "th" else 1])


## The combos data ({"states", "skills"}); {} until combat ships the file (screens then show "no data" / nothing).
static func load_default() -> Dictionary:
	if _default.is_empty() and FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_default = parsed
	return _default


static func _data(data) -> Dictionary:
	return data if data is Dictionary and not data.is_empty() else load_default()


# ------------------------------------------------------------------ states
## {"id", "name", "color", "shape", "glyph", "duration"} for a state id (data first, DEFAULTS fill the gaps).
static func state_info(state: String, data = null) -> Dictionary:
	var raw: Dictionary = _data(data).get("states", {}).get(state, {})
	var base: Dictionary = DEFAULTS.get(state, {"color": "CCCCCC", "shape": "circle", "glyph": "?", "name_en": state.capitalize(), "name_th": state})
	var th := CardTokens.desc_language() == "th"  # state names are descriptive (Language setting)
	var name := str(raw.get("name_th" if th else "name_en", base["name_th" if th else "name_en"]))
	var color_text := str(raw.get("color", base["color"])).trim_prefix("#")
	var color := Color.html(color_text) if Color.html_is_valid(color_text) else Color.html(str(base["color"]))
	return {"id": state, "name": name, "color": color, "shape": str(raw.get("shape", base["shape"])), "glyph": str(base["glyph"]), "duration": float(raw.get("duration", 0.0))}


## Badges for one skill: {"sets": [state ids], "payoffs": [{"needs": [ids], "effect"}]} (empty lists for an unknown skill).
static func badges_for(skill: String, data = null) -> Dictionary:
	var raw: Dictionary = _data(data).get("skills", {}).get(skill, {})
	var payoffs: Array = []
	for p in raw.get("payoffs", []):
		payoffs.append({"needs": (p.get("needs", []) as Array).map(func(s): return str(s)),
			"effect": str(p.get("effect_th" if CardTokens.desc_language() == "th" and not str(p.get("effect_th", "")).is_empty() else "effect_en", p.get("effect_en", "")))})
	return {"sets": (raw.get("sets", []) as Array).map(func(s): return str(s)), "payoffs": payoffs}


## Every state a skill's payoffs need (unique, in ORDER).
static func payoff_states(skill: String, data = null) -> Array:
	var seen := {}
	for p in badges_for(skill, data)["payoffs"]:
		for s in p["needs"]:
			seen[s] = true
	return ORDER.filter(func(s): return seen.has(s)) + seen.keys().filter(func(s): return not ORDER.has(s))


# ------------------------------------------------------------------ skills and squads
static func skill_info(skill: String) -> Dictionary:
	if _skill_info.is_empty() and FileAccess.file_exists(CLASS_SKILLS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CLASS_SKILLS_PATH))
		if parsed is Dictionary:
			for id in parsed.get("skills", {}):
				var raw: Dictionary = parsed["skills"][id]
				_skill_info[str(id)] = {"name": str(raw.get("name", str(id).capitalize())), "name_th": str(raw.get("name_th", "")), "class": str(raw.get("class", ""))}
	var info: Dictionary = _skill_info.get(skill, {"name": skill.capitalize(), "name_th": "", "class": ""})
	var name := str(info["name"])
	if CardTokens.language == "th" and not str(info.get("name_th", "")).is_empty():
		name = str(info["name_th"])
	return {"name": name, "class": str(info["class"])}


## The 4 class skills of a class (data/classes skill_tree.skills, the same list the Skills tab uses).
static func class_skills(class_id: String) -> Array:
	var data: Dictionary = preload("res://logic/card_deck.gd").class_data(class_id)
	return (data.get("skill_tree", {}).get("skills", []) as Array).duplicate()


## Links between the skills of a squad: one entry per (setter skill, payoff skill) of DIFFERENT cards where the setter
## sets at least one state a payoff of the other needs. `squad_skills` = {class id: [skill ids]}.
## Each link {"from", "from_class", "to", "to_class", "states": [shared state ids]}.
static func squad_links(squad_skills: Dictionary, data = null) -> Array:
	var links: Array = []
	for to_class in squad_skills:
		for to_skill in squad_skills[to_class]:
			var needs := payoff_states(str(to_skill), data)
			if needs.is_empty():
				continue
			for from_class in squad_skills:
				if from_class == to_class:
					continue
				for from_skill in squad_skills[from_class]:
					var sets: Array = badges_for(str(from_skill), data)["sets"]
					var shared := needs.filter(func(s): return sets.has(s))
					if not shared.is_empty():
						links.append({"from": str(from_skill), "from_class": str(from_class), "to": str(to_skill), "to_class": str(to_class), "states": shared})
	return links


## "Combos in squad: N pairs": a pair is one setter skill + one payoff skill (several shared states still count once).
static func pair_count(links: Array) -> int:
	return links.size()


static func pairs_text(links: Array, cards: int) -> String:
	if cards < 2:
		return t("squad_need")
	var n := pair_count(links)
	if n == 0:
		return t("squad_none")
	return t("squad_pair_one") if n == 1 else t("squad_pairs") % n


## "Works with: <class> <skill>, ..." for one skill in the squad (both directions, each partner once).
static func works_with(skill: String, links: Array) -> Array:
	var out: Array = []
	for l in links:
		var other := ""
		var other_class := ""
		if l["from"] == skill:
			other = l["to"]; other_class = l["to_class"]
		elif l["to"] == skill:
			other = l["from"]; other_class = l["from_class"]
		else:
			continue
		var entry := "%s %s" % [CardTokens.t("class_" + other_class) if CardTokens.STRINGS.has("class_" + other_class) else other_class.capitalize().replace("_", " "), skill_info(other)["name"]]
		if not out.has(entry):
			out.append(entry)
	return out


static func works_with_text(skill: String, links: Array) -> String:
	var partners := works_with(skill, links)
	return dt("works_none") if partners.is_empty() else dt("works_with") % ", ".join(partners)


# ------------------------------------------------------------------ fight and summary
## Popup text for a combo event: "STARFALL x2!" (x = how many states it consumed; the icons are drawn before it).
static func popup_text(event: Dictionary) -> String:
	var name := str(skill_info(str(event.get("skill", "")))["name"]).to_upper()
	var n := (event.get("states", []) as Array).size()
	return "%s x%d!" % [name, n] if n > 1 else "%s!" % name


static func summary_text(count: int, share: float) -> String:
	if count <= 0:
		return t("summary_none")
	return t("summary") % [count, roundi(clampf(share, 0.0, 1.0) * 100.0)]


## The states a fighter shows over its head: the sim's own combo state list when it has one (`combo_states`, field
## name from combat), else any effect id that is a combo state. Unique, in ORDER.
static func fighter_states(fighter) -> Array:
	var found := {}
	if fighter == null:
		return []
	var raw = fighter.get("combo_states") if fighter is Object else null
	if raw is Dictionary or raw is Array:
		for s in raw:
			found[str(s)] = true
	var effects = fighter.get("effects") if fighter is Object else null
	if effects is Dictionary:
		for id in effects:
			if DEFAULTS.has(str(id)):
				found[str(id)] = true
	return ORDER.filter(func(s): return found.has(s))


# ------------------------------------------------------------------ drawing
## Draws one state icon (colour + shape + dark rim + glyph) centred at `c` with radius `r` on any CanvasItem.
static func draw_state_icon(ci: CanvasItem, c: Vector2, r: float, state: String, data = null, alpha: float = 1.0) -> void:
	var info := state_info(state, data)
	var col: Color = info["color"]
	col.a = alpha
	var rim := Color(0.1, 0.07, 0.05, alpha)
	var pts := _shape(str(info["shape"]), c, r)
	var outer := _shape(str(info["shape"]), c, r + maxf(1.5, r * 0.18))
	ci.draw_colored_polygon(outer, rim)
	ci.draw_colored_polygon(pts, col)
	var font := CardTokens.display_font()
	if font != null and r >= 7.0:
		var fs := int(r * 1.15)
		var glyph := str(info["glyph"])
		var light := col.get_luminance() > 0.6
		var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		ci.draw_string(font, c + Vector2(-gw.x * 0.5, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.07, 0.05, alpha) if light else Color(1, 1, 1, alpha))


static func _shape(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"star":
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.55))
		"triangle":
			for i in 3:
				pts.append(c + Vector2.from_angle(-PI * 0.5 + i * TAU / 3.0) * r * 1.12)
		"triangle_down":
			for i in 3:
				pts.append(c + Vector2.from_angle(PI * 0.5 + i * TAU / 3.0) * r * 1.12)
		"diamond":
			for i in 4:
				pts.append(c + Vector2.from_angle(-PI * 0.5 + i * TAU / 4.0) * r * 1.1)
		"square":
			for i in 4:
				pts.append(c + Vector2.from_angle(PI * 0.25 + i * TAU / 4.0) * r * 1.05)
		"hexagon":
			for i in 6:
				pts.append(c + Vector2.from_angle(i * TAU / 6.0) * r)
		"shield":
			pts.append_array([c + Vector2(-r, -r * 0.85), c + Vector2(r, -r * 0.85), c + Vector2(r * 0.9, r * 0.2), c + Vector2(0, r * 1.05), c + Vector2(-r * 0.9, r * 0.2)])
		_:
			for i in 16:
				pts.append(c + Vector2.from_angle(i * TAU / 16.0) * r)
	return pts
