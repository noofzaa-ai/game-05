extends RefCounted
## Class skills v2 on screen (design/gdd/class-skills.md 3.1 rule 7, E16): which Studio clip frame a casting fighter
## shows. Pure display math from the skill's `motion` block in data/class_skills/class_skills.json: segments
## [clip, start, end, speed, releases] play back to back; each join cross-fades over `blend` s (0.12 default) from the
## last pose of the previous segment. The sim owns timing (Fighter.skill_view.class_cast: start/end ticks, time_mul
## from a tree cast_time mod) and moves the body only in the travel frames (root-motion rule D10); the client keeps
## the hips in place (studio05_character_model.gd), so nothing here moves anything.
## Iron Guard (stance): enter segs, then `loop` (block_idle) until the stance ends, a `counter` chain from each counter
## tick, then `exit`.

const SkillData := preload("res://logic/class_skills/skill_data.gd")
const TICKS := 60.0


## {"clip", "time", "from" (optional), "from_time", "weight"} for `cast` (skill_view.class_cast) at sim tick `now`
## (a float: the client interpolates between ticks). {} when the skill has no motion.
static func frame(cast: Dictionary, now: float) -> Dictionary:
	var info: Dictionary = SkillData.load_default().skill(str(cast.get("skill", "")))
	var motion: Dictionary = info.get("motion", {})
	if motion.is_empty():
		return {}
	var mul := maxf(0.05, float(cast.get("time_mul", 1.0)))
	var elapsed := maxf(0.0, (now - float(cast.get("start", now))) / TICKS) / mul
	var blend := float(motion.get("blend", info.get("timing", {}).get("blend", 0.12)))
	if str(info.get("kind", "")) == "stance":
		return _stance(motion, cast, elapsed, mul, blend)
	return chain(motion.get("segs", []), elapsed, blend)


## The pose `elapsed` seconds into a chain of segments (held on the last frame after it ends).
static func chain(segs: Array, elapsed: float, blend: float) -> Dictionary:
	if segs.is_empty():
		return {}
	var at := 0.0
	for i in segs.size():
		var seg: Array = segs[i]
		var length := (float(seg[2]) - float(seg[1])) / float(seg[3])
		if elapsed < at + length or i == segs.size() - 1:
			var local := clampf(elapsed - at, 0.0, length)
			var out := {"clip": str(seg[0]), "time": float(seg[1]) + local * float(seg[3])}
			if i > 0 and local < blend:
				var prev: Array = segs[i - 1]
				if not (str(prev[0]) == str(seg[0]) and is_equal_approx(float(prev[2]), float(seg[1]))):  # same-clip seams are seamless
					out["from"] = str(prev[0])
					out["from_time"] = float(prev[2])
					out["weight"] = local / blend
			return out
		at += length
	return {}


static func length_of(segs: Array) -> float:
	var total := 0.0
	for seg in segs:
		total += (float(seg[2]) - float(seg[1])) / float(seg[3])
	return total


static func _stance(motion: Dictionary, cast: Dictionary, elapsed: float, mul: float, blend: float) -> Dictionary:
	var enter: Array = motion.get("segs", [])
	var enter_len := length_of(enter)
	var stance_end := (float(cast.get("stance_end", -1)) - float(cast.get("start", 0))) / TICKS / mul
	if elapsed < enter_len:
		return chain(enter, elapsed, blend)
	var counter: Array = motion.get("counter", [])
	var counter_len := length_of(counter)
	for tick in cast.get("counters", []):
		var since := elapsed - (float(tick) - float(cast.get("start", 0))) / TICKS / mul
		if since >= 0.0 and since < counter_len:
			return chain(counter, since, blend)
	if stance_end > 0.0 and elapsed >= stance_end:
		return chain(motion.get("exit", []), elapsed - stance_end, blend)
	var loop: Array = motion.get("loop", [])
	if loop.size() >= 3:
		var span := float(loop[2]) - float(loop[1])
		var t := fmod((elapsed - enter_len) * float(loop[3] if loop.size() > 3 else 1.0), maxf(0.01, span))
		var out := {"clip": str(loop[0]), "time": float(loop[1]) + t}
		if elapsed - enter_len < blend and not enter.is_empty():
			out["from"] = str(enter[-1][0])
			out["from_time"] = float(enter[-1][2])
			out["weight"] = (elapsed - enter_len) / blend
		return out
	return chain(enter, enter_len, blend)
