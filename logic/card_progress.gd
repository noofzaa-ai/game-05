extends RefCounted
## Card levels, XP and skill points (design/gdd/skill-tree.md 3.2, 3.7, formulas 4.1-4.3).
## Pure rules on plain data: a card's progress lives on the card itself (logic/card_deck.gd,
## card["progress"] = {"level": int, "xp": int}); a card without it is level 1 with 0 XP (older saves stay valid).
## Numbers come from data/progression/card_levels.json. XP is paid only at run end, once, by the journey
## (logic/journey.gd pay_card_xp), so a client can never grant itself XP.

const RULES_PATH := "res://data/progression/card_levels.json"
const PROGRESS := "progress"

static var _rules: Dictionary = {}


## The level rules (cached). Missing keys fall back to the GDD defaults.
static func rules() -> Dictionary:
	if _rules.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH)) if FileAccess.file_exists(RULES_PATH) else null
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var rewards: Dictionary = data.get("xp_rewards", {}) if data.get("xp_rewards") is Dictionary else {}
		_rules = {
			"max_level": int(data.get("max_level", 25)),
			"xp_base": float(data.get("xp_base", 100.0)),
			"xp_exp": float(data.get("xp_exp", 1.2)),
			"milestone_levels": (data.get("milestone_levels", [10, 20]) as Array).map(func(m): return int(m)),
			"xp_rewards": {
				"wave_base": int(rewards.get("wave_base", 20)), "wave_step": int(rewards.get("wave_step", 5)),
				"max_waves": int(rewards.get("max_waves", 11)), "boss": int(rewards.get("boss", 100)),
				"win": int(rewards.get("win", 50)),
			},
		}
	return _rules


static func max_level() -> int:
	return int(rules()["max_level"])


## XP needed to go from `level` to level + 1 (formula 4.2). 0 at max level (the bar shows MAX).
static func xp_req(level: int) -> int:
	if level >= max_level():
		return 0
	return int(round(float(rules()["xp_base"]) * pow(float(maxi(level, 1)), float(rules()["xp_exp"]))))


## Skill points a card of `level` has earned (formula 4.1): level - 1, plus one per milestone reached.
static func points(level: int) -> int:
	var clamped := clampi(level, 1, max_level())
	var bonus := 0
	for milestone in rules()["milestone_levels"]:
		if int(milestone) <= clamped:
			bonus += 1
	return clamped - 1 + bonus


## XP one run pays every card that started it (formula 4.3). `waves_cleared` counts normal waves only
## (capped at max_waves); the boss wave is the `boss_killed` bonus.
static func run_xp(waves_cleared: int, boss_killed: bool, won: bool) -> int:
	var reward: Dictionary = rules()["xp_rewards"]
	var total := 0
	for wave in range(1, clampi(waves_cleared, 0, int(reward["max_waves"])) + 1):
		total += int(reward["wave_base"]) + int(reward["wave_step"]) * wave
	if boss_killed:
		total += int(reward["boss"])
	if won:
		total += int(reward["win"])
	return total


## A clean {"level", "xp"} from anything saved (missing, float JSON numbers, out of range).
static func clean(saved: Variant) -> Dictionary:
	var level := 1
	var xp := 0
	if saved is Dictionary:
		if typeof(saved.get("level")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(saved["level"])):
			level = clampi(int(saved["level"]), 1, max_level())
		if typeof(saved.get("xp")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(saved["xp"])):
			xp = maxi(int(saved["xp"]), 0)
	if level >= max_level():
		xp = 0
	else:
		xp = mini(xp, xp_req(level) - 1)
	return {"level": level, "xp": xp}


## "" when a saved progress block is sound (integral numbers, level in 1..max, xp below the next level).
static func problem(saved: Variant) -> String:
	if not saved is Dictionary or saved.size() != 2 or not saved.has_all(["level", "xp"]):
		return "bad_progress"
	for key in ["level", "xp"]:
		var value = saved[key]
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
			return "bad_progress"
	return "" if clean(saved) == {"level": int(saved["level"]), "xp": int(saved["xp"])} else "bad_progress"


## The card's progress {"level", "xp"} (level 1, 0 XP for a card that never earned any).
static func progress_of(deck: Dictionary, class_id: String) -> Dictionary:
	var card = deck.get("cards", {}).get(class_id)
	return clean(card.get(PROGRESS) if card is Dictionary else null)


static func level_of(deck: Dictionary, class_id: String) -> int:
	return int(progress_of(deck, class_id)["level"])


## Skill points this card has earned so far (spent + unspent).
static func points_of(deck: Dictionary, class_id: String) -> int:
	return points(level_of(deck, class_id))


## What the UI shows for one card: level, xp, xp to next (0 at max), max flag, points earned.
static func summary(deck: Dictionary, class_id: String) -> Dictionary:
	var progress := progress_of(deck, class_id)
	var level := int(progress["level"])
	return {"level": level, "xp": int(progress["xp"]), "xp_next": xp_req(level), "max": level >= max_level(), "points": points(level)}


## Adds `amount` XP to one card, levelling up as often as it reaches the curve. XP past max level is dropped.
## Returns {"card", "xp_gained", "level_before", "level", "xp", "levels_gained"}; {} for an unknown card.
static func grant(deck: Dictionary, class_id: String, amount: int) -> Dictionary:
	var card = deck.get("cards", {}).get(class_id)
	if not card is Dictionary:
		return {}
	var progress := clean(card.get(PROGRESS))
	var before := int(progress["level"])
	var level := before
	var xp := int(progress["xp"]) + maxi(amount, 0)
	while level < max_level() and xp >= xp_req(level):
		xp -= xp_req(level)
		level += 1
	if level >= max_level():
		xp = 0
	card[PROGRESS] = {"level": level, "xp": xp}
	return {"card": class_id, "xp_gained": maxi(amount, 0), "level_before": before, "level": level, "xp": xp, "levels_gained": level - before}
