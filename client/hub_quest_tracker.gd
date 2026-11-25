extends Button
## Hub quest tracker (Boss 2026-11-18): the unlock quest of the next zone, shown on the hub (bottom left, under the
## side menu) so the player sees it without opening the world map. A parchment inset with the quest scroll icon, the
## quest name, one line per step ("[x] Defeat the Goblin Chief", "[ ] ... best card Lv 7/15") and a carved chevron
## that says "tap me": tapping it opens the world map on that zone (the hub connects `pressed`).
## Display only: which zone, its steps and their progress come from logic/world_zones.gd + logic/zone_quests.gd
## (data/world/zone_quests.json), the live numbers from the profile. Every size / colour / word is a card_tokens.gd token.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")
const Zones := preload("res://logic/world_zones.gd")
const ZoneQuests := preload("res://logic/zone_quests.gd")
const Tutorial := preload("res://logic/tutorial.gd")
const DailyQuests := preload("res://logic/daily_quests.gd")

var zone_id := ""  ## the zone whose quest is shown ("" = hidden)
var steps: Array = []  ## ZoneQuests.progress() of that zone
var s := 1.0
var screen_k := 1.0  ## window px per canvas px (a phone shrinks the whole hub; text keeps an on-screen floor)
var room_ok := true  ## false when the hub had too little room (the tracker hides rather than overlap)
var _icon: TextureRect
var _title: Label
var _lines: Array[Label] = []
var _chevron: TextureRect


## The zone whose quest the hub tracks: the ACTIVE main quest (Boss 2026-11-21: the zone quests are a chain, the first
## one not done yet; logic/zone_quests.gd active_main). "" when every main quest is done, or while the new-player
## tutorial is still running (it has its own spotlight steps; the tracker would only clutter them).
static func tracked_zone(profile) -> String:
	if not tutorial_done(profile):
		return ""
	return ZoneQuests.active_main(profile)


## True once the new-player tutorial is over (a profile without a tutorial block counts as done). The tracker and the
## Quests panel show only then; during the tutorial the Quests entry keeps its "coming soon" panel.
static func tutorial_done(profile) -> bool:
	if profile == null:
		return false
	return not ("tutorial" in profile and profile.tutorial is Dictionary) or Tutorial.current(profile) == Tutorial.DONE


## The quest zones in map order (every zone with an unlock quest, done or not).
static func quest_zones() -> Array:
	var out: Array = []
	for z in Zones.zones():
		if ZoneQuests.has_quest(str(z.get("id", ""))):
			out.append(str(z.get("id", "")))
	return out


## The text lines for `zone`: [title, step lines...] in the current language, plus a last "Daily: N reward ready" line
## when a daily quest waits to be claimed (`now` = the display clock, 0 = this machine's).
static func lines_for(profile, zone: String, now: int = 0) -> Array:
	if zone.is_empty():
		return []
	var th := CardTokens.language == "th"
	var q := ZoneQuests.quest(zone)
	var z := Zones.zone(zone)
	var out: Array = [CardTokens.t("quest_track_title") % [str(q.get("name_th" if th else "name_en", "")), str(z.get("name_th" if th else "name_en", zone))]]
	for step in ZoneQuests.progress(profile, zone):
		out.append(CardTokens.t("quest_mark_done" if step.done else "quest_mark_todo") + str(step.get("text_th" if CardTokens.desc_language() == "th" else "text_en", "")))
	var ready := DailyQuests.claimable(profile, now if now > 0 else int(Time.get_unix_time_from_system()))
	if ready > 0:
		out.append(CardTokens.t("daily_ready_hint") % ready)
	return out


func _init() -> void:
	name = "QuestTracker"
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	visible = false
	_icon = CardTokens.carved_rect(CardTokens.CARVED_ICON_PREFIX + "quest", true)
	add_child(_icon)
	_title = _make_label()
	_chevron = CardTokens.carved_rect(CardTokens.CARVED_ICON_PREFIX + "next", true)
	add_child(_chevron)


func _make_label() -> Label:
	var l := CardTokens.hub_label("", CardTokens.FONT_HUB_QUEST_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	return l


## Shows the tracked quest of `profile` (or hides). Called with every hub refresh (profile sync, map close).
func show_for(profile) -> void:
	zone_id = tracked_zone(profile)
	steps = ZoneQuests.progress(profile, zone_id) if not zone_id.is_empty() else []
	var text := lines_for(profile, zone_id)
	visible = not text.is_empty() and room_ok
	if text.is_empty():
		return
	_title.text = str(text[0])
	while _lines.size() < text.size() - 1:
		_lines.append(_make_label())
	for i in _lines.size():
		_lines[i].visible = i < text.size() - 1
		_lines[i].text = str(text[i + 1]) if _lines[i].visible else ""
	tooltip_text = CardTokens.t("quest_track_tip")
	_place()


## Lays the tracker out in `rect` (hub canvas px); hides it when the rect is smaller than HUB_QUEST_MIN.
func place_in(rect: Rect2, p_s: float, p_screen_k: float) -> void:
	s = p_s
	screen_k = maxf(p_screen_k, 0.01)
	room_ok = rect.size.x >= CardTokens.HUB_QUEST_MIN.x * s and rect.size.y >= CardTokens.HUB_QUEST_MIN.y * s
	if not room_ok:
		visible = false
	position = rect.position
	size = rect.size
	CardTokens.bare_button(self, s, CardTokens.HUB_RADIUS)
	var sk := CarvedLook.inset(self, s)
	sk.follow_button = true
	_place()


func _shown_labels() -> Array[Label]:
	var out: Array[Label] = [_title]
	for l in _lines:
		if l.visible:
			out.append(l)
	return out


## One line per row (title + steps), all at one size: the largest that fits both the row height and every row's
## width; under the on-screen floor the line is cut with an ellipsis (the full text is on the map and the tooltip).
func _place() -> void:
	if _title == null or size.x <= 0.0:
		return
	var pad := CardTokens.HUB_QUEST_PAD * s
	var chev := CardTokens.HUB_QUEST_CHEVRON * s
	_chevron.size = Vector2(chev * 0.7, chev)
	_chevron.position = Vector2(size.x - pad * 0.5 - _chevron.size.x, (size.y - chev) * 0.5)
	var left := pad * 0.8
	var w := maxf(_chevron.position.x - pad * 0.3 - left, 1.0)
	# (a headless or tiny window reports a silly screen_k: the floor never asks for more than twice the token size)
	var base := int(maxf(roundf(CardTokens.FONT_HUB_QUEST_LINE * s), 8.0))
	var floor_px := int(clampf(ceilf(CardTokens.HUB_QUEST_SCREEN_MIN / screen_k), CardTokens.FONT_MIN, maxf(base * 2.0, CardTokens.FONT_MIN)))
	# Too many rows for the height at the floor size (a phone, a 3-step quest + the daily hint): drop the daily hint
	# first, then done steps, then the last steps (the full list is on the Quests panel).
	for l in _lines:
		l.visible = not l.text.is_empty()
	var font: Font = CardTokens.medium_font()
	while font != null and _shown_labels().size() > 2 and font.get_height(floor_px) > (size.y - pad * 0.8) / float(_shown_labels().size()) * 1.05:
		var drop: Label = null
		for i in _lines.size():
			if _lines[i].visible and i >= steps.size():
				drop = _lines[i]  # the daily hint
		if drop == null:
			for i in mini(steps.size(), _lines.size()):
				if _lines[i].visible and bool(steps[i].done):
					drop = _lines[i]
					break
		if drop == null:
			for l in _lines:
				if l.visible:
					drop = l
		drop.visible = false
	var labels := _shown_labels()
	var row_h := (size.y - pad * 0.8) / float(labels.size())
	var px := maxi(base, floor_px)  # never under FONT_MIN canvas px, nor HUB_QUEST_SCREEN_MIN window px
	while px > floor_px and not _fits(labels, px, w, row_h):
		px -= 1
	var icon_w := row_h * 0.9
	var y := pad * 0.4
	for i in labels.size():
		var l: Label = labels[i]
		var face := "medium"  # (the serif display face is 1.8x its size tall: three rows would not fit a phone)
		var k := _lines.find(l)  # (rows may be dropped: map the label back to its step)
		var done: bool = k >= 0 and (k >= steps.size() or bool(steps[k].done))  # (the daily hint line is green too)
		CardTokens.hub_text(l, px, CardTokens.HUB_GOOD if done else CardTokens.HUB_INK, 1.0, 0, face)  # (px is already canvas px)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var lx := left + (icon_w + pad * 0.2 if l == _title else 0.0)
		l.position = Vector2(lx, y)
		l.size = Vector2(w - (lx - left), row_h)
		y += row_h
	_icon.size = Vector2(icon_w, row_h)
	_icon.position = Vector2(left, pad * 0.4)


func _fits(labels: Array[Label], px: int, w: float, row_h: float) -> bool:
	for l in labels:
		var font: Font = CardTokens.medium_font()
		if font == null:
			continue
		var room := w - (row_h * 0.9 + CardTokens.HUB_QUEST_PAD * s * 0.2 if l == _title else 0.0)
		if font.get_height(px) > row_h * 1.05 or font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
			return false
	return true