extends RefCounted
## Class skills v2 data (design/gdd/class-skills.md): loads data/class_skills/class_skills.json, validates it against
## the class clip files and data/combat/effects.json, and turns each skill's Studio clip window into sim ticks
## (cast/release/travel/end). Pure rules: no nodes. The engine (engine.gd) and the pilot (use_rules.gd) read it.
## Timing (GDD 3.1 rule 7): a segment [clip, start, end, speed, releases] lasts (end - start) / speed seconds; segments
## play back to back (the cross-fade overlaps, it adds no time). A clip time t inside segment i is
## skill t = sum(previous segment lengths) + (t - start) / speed. 60 ticks per second.

const PATH := "res://data/class_skills/class_skills.json"
const EFFECTS_PATH := "res://data/combat/effects.json"
const TICKS := 60.0
const KINDS: Array[String] = ["dash_strike", "stance", "ally_leap", "circle", "arc", "leap_slam", "pull_circle", "self_buff",
	"shot", "volley", "vault_shot", "orb", "delayed_circle", "ally_buff"]
## Conditions the skill `use` rules may name (GDD 3.7): the race list (logic/auto_pilot.gd use_matches) plus the skill-only ones.
const CONDITIONS: Array[String] = ["enemies_near", "boss_near", "elite_near", "self_hurt", "boss_telegraph", "ally_hurt",
	"peel_target_attacking_ally", "target_within", "self_attacked_by", "ally_below_hp_attacked", "self_hp_at_least",
	"enemies_in_arc", "boss_in_arc", "held_for", "dense_point", "boss_between", "loose_pack", "best_shot",
	"enemy_near_backline", "closing_enemy", "nearest_within", "target_cluster", "target_is_boss"]
## Old skill ids (GDD 3.6): no data file may name them once the classes are switched (acceptance criterion 1).
const OLD_IDS: Array[String] = ["storm_blades", "riposte", "blood_shield", "flame_dash", "ground_slam", "shatter_smash",
	"eruption", "war_cry", "piercing_shot", "thorn_trap", "ice_lance", "chain_lightning", "fireball", "fire_ring",
	"lightning_strike", "frost_armor"]

static var _default = null

var skills: Dictionary = {}  ## id -> raw skill dictionary (+ "timing")
var classes: Dictionary = {}  ## class id -> [4 skill ids]
var impact: Dictionary = {}
var errors: Array[String] = []


static func load_default():
	if _default == null:
		_default = load_from(PATH)
	return _default


static func load_from(path: String):
	var data = new()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		data.errors.append("%s is missing or not valid JSON" % path)
		return data
	data.parse(parsed)
	return data


## The 4 skill ids of a class (data/classes/<class>.json id), [] for an unknown class.
func class_skills(class_id: String) -> Array:
	return classes.get(class_id, [])


## The class (data/classes id) whose combat weapon style is `style` (blade -> sword_shield ...), "" if none.
static func class_for_style(style: String) -> String:
	for class_id in ["sword_shield", "greatsword", "longbow", "magic"]:
		if str(preload("res://logic/card_deck.gd").class_data(class_id).get("weapon", "")) == style:
			return class_id
	return ""


func skill(id: String) -> Dictionary:
	return skills.get(id, {})


func parse(raw: Dictionary) -> void:
	impact = raw.get("impact", {})
	var statuses: Dictionary = {}
	var fx = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS_PATH))
	if fx is Dictionary:
		statuses = fx.get("effects", {})
	var blend := float(raw.get("blend", 0.12))
	for class_id in raw.get("classes", {}):
		var ids: Array = raw["classes"][class_id]
		if ids.size() != 4:
			errors.append("classes.%s must list 4 skills" % class_id)
		classes[str(class_id)] = ids.duplicate()
	for id in raw.get("skills", {}):
		var s: Dictionary = (raw["skills"][id] as Dictionary).duplicate(true)
		var label := "skills.%s" % id
		if OLD_IDS.has(str(id)):
			errors.append("%s reuses an old skill id" % label)
		if not KINDS.has(str(s.get("kind", ""))):
			errors.append("%s.kind '%s' is unknown" % [label, s.get("kind", "")])
		var owner := str(s.get("class", ""))
		if not classes.get(owner, []).has(str(id)):
			errors.append("%s.class '%s' does not list it" % [label, owner])
		for key in ["stamina", "impact_tier", "priority"]:
			if not (s.get(key) is float or s.get(key) is int):
				errors.append("%s.%s must be a number" % [label, key])
		var stats: Dictionary = s.get("stats", {})
		if not (stats.get("cooldown") is float or stats.get("cooldown") is int) or float(stats.get("cooldown", 0)) <= 0.0:
			errors.append("%s.stats.cooldown must be > 0" % label)
		for key in ["stun", "shock", "slow", "weaken"]:
			if stats.has(key) and not statuses.has(key):
				errors.append("%s.stats.%s: no such status in effects.json" % [label, key])
		if stats.has("bonus_status") and not statuses.has(str(stats["bonus_status"])):
			errors.append("%s.stats.bonus_status: no such status" % label)
		var use: Dictionary = s.get("use", {})
		if use.get("any_of", []).is_empty():
			errors.append("%s.use.any_of is empty" % label)
		for rule in use.get("any_of", []) + use.get("and", []):
			_check_rule(rule, label, errors)
		if not s.has("vfx"):
			errors.append("%s.vfx key is missing" % label)
		var clips := _clip_lengths(owner)
		var motion: Dictionary = s.get("motion", {})
		for part in ["segs", "counter", "exit"]:
			for seg in motion.get(part, []):
				_check_seg(seg, clips, "%s.motion.%s" % [label, part], errors)
		if motion.get("segs", []).is_empty():
			errors.append("%s.motion.segs is empty" % label)
		s["timing"] = timing(motion, float(motion.get("blend", blend)))
		var timing_info: Dictionary = s["timing"]
		if timing_info["releases"].is_empty() and str(s.get("kind")) != "stance":
			errors.append("%s.motion has no release" % label)
		if motion.has("travel") and timing_info["travel"].is_empty():
			errors.append("%s.motion.travel is outside its segment" % label)
		skills[str(id)] = s
	for class_id in classes:
		for id in classes[class_id]:
			if not skills.has(str(id)):
				errors.append("classes.%s names unknown skill %s" % [class_id, id])


static func _check_rule(rule, label: String, errors: Array) -> void:
	if not rule is Dictionary or not CONDITIONS.has(str(rule.get("if", ""))):
		errors.append("%s.use condition %s is unknown" % [label, rule])
		return
	for extra in rule.get("and", []):
		_check_rule(extra, label, errors)


static func _check_seg(seg, clips: Dictionary, label: String, errors: Array) -> void:
	if not seg is Array or seg.size() != 5:
		errors.append("%s: a segment is [clip, start, end, speed, releases]" % label)
		return
	var clip := str(seg[0])
	if not clips.has(clip):
		errors.append("%s: clip '%s' is not in the class clip file" % [label, clip])
		return
	var length := float(clips[clip])
	if float(seg[1]) < 0.0 or float(seg[1]) >= float(seg[2]) or float(seg[2]) > length + 0.001 or float(seg[3]) <= 0.0:
		errors.append("%s: %s %s-%s @ %s is outside 0..%s" % [label, clip, seg[1], seg[2], seg[3], length])
	for t in seg[4]:
		if float(t) < float(seg[1]) - 0.0001 or float(t) > float(seg[2]) + 0.0001:
			errors.append("%s: release %s outside %s-%s" % [label, t, seg[1], seg[2]])


## Clip name -> length (s) of a class's clip file (data/classes/<class>.json clip_marks).
static func _clip_lengths(class_id: String) -> Dictionary:
	var path := str(preload("res://logic/card_deck.gd").class_data(class_id).get("clip_marks", ""))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() and FileAccess.file_exists(path) else null
	var out := {}
	if parsed is Dictionary:
		for clip in parsed:
			if parsed[clip] is Dictionary:
				out[str(clip)] = float(parsed[clip].get("length", 0.0))
	return out


## Seconds -> {releases [s], travel [from s, to s] or [], end s, pull [s] or [], blend}; plus counter/exit for a stance.
static func timing(motion: Dictionary, blend: float = 0.12) -> Dictionary:
	var out := {"releases": [], "travel": [], "end": 0.0, "pull": [], "blend": blend}
	var at := 0.0
	var segs: Array = motion.get("segs", [])
	for i in segs.size():
		var seg: Array = segs[i]
		var speed := float(seg[3])
		for t in seg[4]:
			out["releases"].append(at + (float(t) - float(seg[1])) / speed)
		var travel: Array = motion.get("travel", [])
		if travel.size() == 3 and int(travel[0]) == i and float(travel[1]) >= float(seg[1]) - 0.0001 and float(travel[2]) <= float(seg[2]) + 0.0001:
			out["travel"] = [at + (float(travel[1]) - float(seg[1])) / speed, at + (float(travel[2]) - float(seg[1])) / speed]
		var pull: Array = motion.get("pull_at", [])
		if pull.size() == 2 and int(pull[0]) == i:
			out["pull"] = [at + (float(pull[1]) - float(seg[1])) / speed]
		at += (float(seg[2]) - float(seg[1])) / speed
	out["end"] = at
	if motion.has("counter"):
		var c := 0.0
		for seg in motion["counter"]:
			for t in seg[4]:
				out["counter_release"] = c + (float(t) - float(seg[1])) / float(seg[3])
			c += (float(seg[2]) - float(seg[1])) / float(seg[3])
		out["counter_length"] = c
	if motion.has("exit"):
		var e := 0.0
		for seg in motion["exit"]:
			e += (float(seg[2]) - float(seg[1])) / float(seg[3])
		out["exit"] = e
	return out


static func ticks(seconds: float) -> int:
	return int(round(seconds * TICKS))
