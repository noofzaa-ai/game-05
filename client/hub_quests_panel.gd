extends "res://client/hub_service_panel.gd"
## Quests (Boss 2026-11-18): the side menu's Quests entry. Every zone unlock quest of data/world/zone_quests.json
## (logic/zone_quests.gd) in map order: the quest name and its state (In progress / Done, a word and a tick, not
## colour only), the description, each step with [x] / [ ] and its live progress ("best card Lv 5/15") and the zone
## it opens. A finished quest stays listed, dimmed with a tick. Tapping a quest asks the hub to open the world map on
## that zone (`zone_requested`; the hub tracker does the same). No quest at all: one short empty line.
## Display only: every rule and number comes from the profile through logic/.
## Two pages (Boss 2026-11-21), big tab plates at the top: MAIN = the zone quests as a chain (logic/zone_quests.gd
## main_state: done / active / locked "finish X first"), DAILY = logic/daily_quests.gd (progress, reward, Claim -> the
## daily_claim server command, the reset countdown from the clock). The Claim result redraws from the synced profile.

const Zones := preload("res://logic/world_zones.gd")
const ZoneQuests := preload("res://logic/zone_quests.gd")
const HubQuestTracker := preload("res://client/hub_quest_tracker.gd")
const DailyQuests := preload("res://logic/daily_quests.gd")
const MAIN := "main"
const DAILY := "daily"

signal zone_requested(zone_id: String)

var _hint: Label
var _empty: Label
var _scroll: ScrollContainer
var _list: Control
var _rows: Array[Button] = []  ## one per quest zone (row.name = "Quest_<zone>")
var page := MAIN
var _tabs: Array[Button] = []  ## [Main, Daily]
var _daily_scroll: ScrollContainer
var _daily_list: Control
var _daily_rows: Array[Control] = []  ## one per daily quest (name = "Daily_<id>"), a Claim button inside
var _reset: Label
## Clock for the Daily page's countdown and "today" (display only; the server decides with its own clock). Tests set it.
var now_override := 0


func _init() -> void:
	service = "quests"


func build() -> void:
	for id in [MAIN, DAILY]:
		var tab := plate(CardTokens.t("quest_tab_" + id), func() -> void: show_page(id))
		tab.name = "Tab_" + id
		body.add_child(tab)
		_tabs.append(tab)
	_hint = CardTokens.label(CardTokens.t("quest_list_hint"), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_hint)
	_empty = CardTokens.label(CardTokens.t("quest_none"), CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_list = Control.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)
	for zone in HubQuestTracker.quest_zones():
		var row := Button.new()
		row.name = "Quest_" + str(zone)
		row.focus_mode = Control.FOCUS_ALL
		row.clip_contents = true
		row.tooltip_text = CardTokens.t("quest_track_tip")
		row.pressed.connect(func() -> void: zone_requested.emit(str(zone)))
		row.set_meta("zone", str(zone))
		var tick := CardTokens.carved_rect(CarvedLook.ICON_PREFIX + "quest", true)
		tick.name = "Icon"
		row.add_child(tick)
		var chevron := CardTokens.carved_rect(CarvedLook.ICON_PREFIX + "next", true)
		chevron.name = "Chevron"
		row.add_child(chevron)
		_list.add_child(row)
		_rows.append(row)
	_reset = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	_reset.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_reset)
	_daily_scroll = ScrollContainer.new()
	_daily_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_daily_scroll.follow_focus = true
	body.add_child(_daily_scroll)
	_daily_list = Control.new()
	_daily_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_scroll.add_child(_daily_list)
	for q in DailyQuests.quests():
		var id := str(q.get("id", ""))
		var row := Control.new()
		row.name = "Daily_" + id
		row.set_meta("quest", id)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var claim := Button.new()
		claim.name = "Claim"
		claim.focus_mode = Control.FOCUS_ALL
		claim.clip_text = true
		claim.pressed.connect(func() -> void: _claim(id))
		row.add_child(claim)
		_daily_list.add_child(row)
		_daily_rows.append(row)


func show_page(id: String) -> void:
	page = id
	refresh()
	var first := first_focus()
	if visible and first != null and first.is_inside_tree():
		first.grab_focus.call_deferred()


func now() -> int:
	return now_override if now_override > 0 else int(Time.get_unix_time_from_system())


## The daily row of `quest_id` (tests), or null.
func daily_row_of(quest_id: String) -> Control:
	for row in _daily_rows:
		if str(row.get_meta("quest")) == quest_id:
			return row
	return null


func _claim(quest_id: String) -> void:
	var gold := int(DailyQuests.quest(quest_id).get("reward", {}).get("gold", 0))
	var result := await run({"type": "daily_claim", "quest": quest_id})
	if result.get("ok", false):
		say(CardTokens.t("daily_got") % gold)


func first_focus() -> Control:
	if page == DAILY:
		for row in _daily_rows:
			var b := row.get_node("Claim") as Button
			if not b.disabled:
				return b
		return _tabs[1] if _tabs.size() > 1 else _close
	return _rows[0] if not _rows.is_empty() else _close


## The row of `zone_id` (tests), or null.
func row_of(zone_id: String) -> Button:
	for row in _rows:
		if str(row.get_meta("zone")) == zone_id:
			return row
	return null


## The lines a row shows, in order: [name, state, description, steps..., opens]. (tests read them too)
static func row_lines(profile, zone_id: String) -> Dictionary:
	var th := CardTokens.language == "th"
	var q := ZoneQuests.quest(zone_id)
	var z := Zones.zone(zone_id)
	var main := ZoneQuests.main_state(profile, zone_id)
	var done := main == ZoneQuests.MAIN_DONE
	var locked := main == ZoneQuests.MAIN_LOCKED
	var prev := ZoneQuests.quest(ZoneQuests.previous_main(zone_id))
	var number := ZoneQuests.chain().find(zone_id) + 1
	var steps: Array = []
	for step in ZoneQuests.progress(profile, zone_id):
		steps.append({"text": CardTokens.t("quest_mark_done" if step.done else "quest_mark_todo") + str(step.get("text_th" if CardTokens.desc_language() == "th" else "text_en", "")), "done": bool(step.done)})
	return {
		"name": str(q.get("name_th" if th else "name_en", zone_id)),
		"number": CardTokens.t("quest_main_step") % number,
		"state": CardTokens.t("quest_state_done" if done else ("quest_state_locked" if locked else "quest_state_pending")),
		"done": done,
		"locked": locked,
		"locked_line": (CardTokens.t("quest_locked_after") % str(prev.get("name_th" if th else "name_en", ""))) if locked else "",
		"desc": str(q.get("desc_th" if CardTokens.desc_language() == "th" else "desc_en", "")),
		"steps": steps,
		"opens": CardTokens.t("quest_opens") % str(z.get("name_th" if th else "name_en", zone_id)),
	}


var _area := Vector2.ZERO


## Daily row lines: [{id, name, desc, reward, done, claimed, button}].
static func daily_lines(profile, now_unix: int) -> Array:
	var th := CardTokens.language == "th"
	var out: Array = []
	for q in DailyQuests.progress(profile, now_unix):
		out.append({"id": q.id, "name": str(q.get("name_th" if th else "name_en")), "desc": CardTokens.t("quest_mark_done" if q.done else "quest_mark_todo") + str(q.get("desc_th" if CardTokens.desc_language() == "th" else "desc_en")),
			"reward": CardTokens.t("daily_reward") % int(q.reward_gold), "done": bool(q.done), "claimed": bool(q.claimed),
			"button": CardTokens.t("daily_claimed" if q.claimed else ("daily_claim" if q.done else "daily_not_done"))})
	return out


static func reset_text(now_unix: int) -> String:
	var left := maxi(DailyQuests.seconds_to_reset(now_unix), 0)
	return CardTokens.t("daily_reset_in") % [left / 3600, (left % 3600) / 60]


func layout_body(area: Vector2) -> void:
	_area = area
	var gap := CardTokens.CHAR_GAP * s
	# the page tabs: big plates (a phone gets the HUB_TAP_MIN_PHONE height)
	var tab_h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var tab_w := minf(area.x * 0.5 - gap * 0.5, CardTokens.SVC_ROW_H * 6.0 * s)
	for i in _tabs.size():
		_tabs[i].position = Vector2(i * (tab_w + gap), 0.0)
		_tabs[i].size = Vector2(tab_w, tab_h)
	var top := tab_h + gap * 0.6
	var hint_h := _px(CardTokens.FONT_CHAR_LINE) * 1.8
	_hint.position = Vector2(0.0, top)
	_hint.size = Vector2(area.x, hint_h)
	CardTokens.hub_text(_hint, _px(CardTokens.FONT_CHAR_LINE), CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium")
	_scroll.position = Vector2(0.0, top + hint_h + gap * 0.3)
	_scroll.size = Vector2(area.x, area.y - _scroll.position.y)
	_reset.position = _hint.position
	_reset.size = _hint.size
	CardTokens.hub_text(_reset, _px(CardTokens.FONT_CHAR_LINE), CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium")
	_daily_scroll.position = _scroll.position
	_daily_scroll.size = _scroll.size
	_empty.position = _scroll.position
	_empty.size = Vector2(area.x, hint_h * 2.0)
	CardTokens.hub_text(_empty, _px(CardTokens.FONT_CHAR_LINE), CardTokens.HUB_INK, 1.0, 0, "medium")


func refresh() -> void:
	super()
	if _list == null or _area == Vector2.ZERO:
		return
	var p = _profile()
	for i in _tabs.size():
		var on := (i == 0) == (page == MAIN)
		CarvedLook.chip_button(_tabs[i], s, on, not on)
		_fit_px(_tabs[i], CardTokens.HUB_INK if on else CardTokens.HUB_TAB_IDLE, "display" if on else "medium")
	var daily := page == DAILY
	_scroll.visible = not daily
	_daily_scroll.visible = daily
	_reset.visible = daily
	_empty.visible = _daily_rows.is_empty() if daily else _rows.is_empty()
	_empty.text = CardTokens.t("daily_none" if daily else "quest_none")
	_hint.visible = not daily and not _rows.is_empty()
	if daily:
		_refresh_daily(p)
		return
	var gap := CardTokens.CHAR_GAP * s
	var pad := CardTokens.HUB_QUEST_PAD * s
	var w := _scroll.size.x - gap  # (room for the scroll bar)
	var y := 0.0
	for row in _rows:
		var h := _fill_row(row, row_lines(p, str(row.get_meta("zone"))), w, pad)
		row.position = Vector2(0.0, y)
		row.size = Vector2(w, h)
		y += h + gap
	_list.custom_minimum_size = Vector2(w, maxf(y - gap, 0.0))


func _refresh_daily(p) -> void:
	var t := now()
	_reset.text = reset_text(t)
	var gap := CardTokens.CHAR_GAP * s
	var pad := CardTokens.HUB_QUEST_PAD * s
	var w := _daily_scroll.size.x - gap
	var lines := daily_lines(p, t)
	var y := 0.0
	for i in _daily_rows.size():
		var row: Control = _daily_rows[i]
		var h := _fill_daily(row, lines[i], w, pad) if i < lines.size() else 0.0
		row.position = Vector2(0.0, y)
		row.size = Vector2(w, h)
		y += h + gap
	_daily_list.custom_minimum_size = Vector2(w, maxf(y - gap, 0.0))


## One daily row: name, progress line, reward on the left; the Claim button on the right. Returns the height.
func _fill_daily(row: Control, lines: Dictionary, w: float, pad: float) -> float:
	var claimed: bool = lines.claimed
	var ready: bool = lines.done and not claimed
	CarvedLook.inset(row, s, CarvedLook.TINT_IDLE if claimed else CarvedLook.TINT_NORMAL)
	var title_px := _px(CardTokens.FONT_HUB_QUEST_ROW_TITLE)
	var line_px := _px(CardTokens.FONT_CHAR_LINE)
	var btn_h := CardTokens.tap(CardTokens.SVC_ROW_H, phone) * s
	var btn_w := minf(maxf(w * 0.26, btn_h * 2.2), w * 0.4)
	var text_x := pad
	var text_w := maxf(w - pad * 2.0 - btn_w - pad, 1.0)
	var texts: Array = [{"key": "Name", "text": lines.name, "px": title_px, "face": "display", "color": CardTokens.HUB_INK},
		{"key": "Desc", "text": lines.desc, "px": line_px, "face": "medium", "color": CardTokens.HUB_GOOD if lines.done else CardTokens.HUB_INK},
		{"key": "Reward", "text": lines.reward, "px": line_px, "face": "medium", "color": CardTokens.HUB_TAB_IDLE}]
	var y := pad * 0.6
	for t in texts:
		var l := row.get_node_or_null(str(t.key)) as Label
		if l == null:
			l = CardTokens.label("", line_px, CardTokens.HUB_INK, 1.0, 0, "medium")
			l.name = str(t.key)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			row.add_child(l)
		l.size = Vector2(text_w, 1.0)  # (width before text: an autowrapped label sizes its minimum height at its width)
		l.text = str(t.text)
		CardTokens.hub_text(l, int(t.px), t.color, 1.0, 0, str(t.face))
		var font: Font = CardTokens.display_font() if t.face == "display" else CardTokens.medium_font()
		var h: float = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, text_w, int(t.px), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y if font != null else t.px * 1.4
		l.position = Vector2(text_x, y)
		l.size = Vector2(text_w, h)
		y += h
	var total := maxf(y + pad * 0.6, btn_h + pad * 1.2)
	var b := row.get_node("Claim") as Button
	b.text = str(lines.button)
	b.disabled = not ready
	b.size = Vector2(btn_w, btn_h)
	b.position = Vector2(w - pad - btn_w, (total - btn_h) * 0.5)
	CarvedLook.chip_button(b, s, ready, not ready)
	_fit_px(b, CardTokens.HUB_INK if ready else CardTokens.HUB_TAB_IDLE, "display" if ready else "medium")
	CardTokens.readable_disabled(b)  # (a word, not colour only)
	b.tooltip_text = "%s: %s" % [lines.name, lines.button]
	return total


## Draws one quest row; returns its height. Lines: name + state word, description, steps, "Opens: zone".
func _fill_row(row: Button, lines: Dictionary, w: float, pad: float) -> float:
	var done: bool = lines.done
	var locked: bool = lines.get("locked", false)
	CardTokens.bare_button(row, s, CardTokens.HUB_RADIUS)
	var sk := CarvedLook.inset(row, s, CarvedLook.TINT_IDLE if (done or locked) else CarvedLook.TINT_NORMAL)
	sk.follow_button = true
	var title_px := _px(CardTokens.FONT_HUB_QUEST_ROW_TITLE)
	var line_px := _px(CardTokens.FONT_CHAR_LINE)
	var icon := title_px * 1.6
	var chev := CardTokens.HUB_QUEST_CHEVRON * s
	var text_x := pad + icon + pad * 0.5
	var text_w := maxf(w - text_x - pad - chev, 1.0)
	var texts: Array = [{"key": "Number", "text": lines.get("number", ""), "px": line_px, "face": "medium", "color": CardTokens.HUB_TAB_IDLE},
		{"key": "Name", "text": "%s  ·  %s" % [lines.name, (CardTokens.t("quest_mark_done") + lines.state) if done else lines.state], "px": title_px, "face": "display", "color": CardTokens.HUB_TAB_IDLE if locked else CardTokens.HUB_INK},
		{"key": "Desc", "text": lines.desc, "px": line_px, "face": "medium", "color": CardTokens.HUB_TAB_IDLE}]
	if locked:
		texts.append({"key": "Locked", "text": lines.locked_line, "px": line_px, "face": "medium", "color": CardTokens.HUB_BAD})
	for i in lines.steps.size():
		texts.append({"key": "Step%d" % i, "text": lines.steps[i].text, "px": line_px, "face": "medium", "color": CardTokens.HUB_GOOD if lines.steps[i].done else CardTokens.HUB_INK})
	texts.append({"key": "Opens", "text": lines.opens, "px": line_px, "face": "medium", "color": CardTokens.HUB_INK})
	# old lines (a quest with fewer steps now) are hidden
	for child in row.get_children():
		if child is Label:
			child.visible = false
	var y := pad * 0.6
	for t in texts:
		var l := row.get_node_or_null(str(t.key)) as Label
		if l == null:
			l = CardTokens.label("", line_px, CardTokens.HUB_INK, 1.0, 0, "medium")
			l.name = str(t.key)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			row.add_child(l)
		l.visible = true
		l.text = str(t.text)
		CardTokens.hub_text(l, int(t.px), t.color, 1.0, 0, str(t.face))
		var font: Font = CardTokens.display_font() if t.face == "display" else CardTokens.medium_font()
		var h: float = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, text_w, int(t.px), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y if font != null else t.px * 1.4
		l.position = Vector2(text_x, y)
		l.size = Vector2(text_w, h)
		y += h + (pad * 0.25 if t.key == "Name" else 0.0)
	var total := y + pad * 0.6
	var tick := row.get_node("Icon") as TextureRect
	tick.texture = CardTokens.carved(CarvedLook.ICON_PREFIX + "quest")
	tick.size = Vector2(icon, icon)
	tick.position = Vector2(pad, pad * 0.5)
	tick.modulate = CardTokens.HUB_LOCKED if (done or locked) else CardTokens.HUB_WHITE
	var chevron := row.get_node("Chevron") as TextureRect
	chevron.size = Vector2(chev * 0.7, chev)
	chevron.position = Vector2(w - pad * 0.6 - chevron.size.x, (total - chev) * 0.5)
	row.tooltip_text = "%s: %s" % [lines.name, lines.state]
	return total


## A button's label at the panel's line size (with the on-screen floor), shrunk only to fit the button's width.
func _fit_px(b: Button, color: Color, face: String) -> void:
	var px := _px(CardTokens.FONT_HUB_QUEST_ROW_TITLE if face == "display" else CardTokens.FONT_CHAR_LINE)
	var w := b.size.x if b.size.x > 0.0 else b.custom_minimum_size.x
	CardTokens.hub_fit(b, b.text, px, maxf(w - 16.0 * s, 1.0), color, 1.0, 0, face)


## A font size in canvas px: the token at this scale, never under FONT_MIN nor HUB_QUEST_SCREEN_MIN window px (the
## canvas_items stretch shrinks the whole hub on a phone, 844x390 -> ~0.54).
func _px(token: int) -> int:
	var want := maxi(int(round(token * s)), CardTokens.FONT_MIN)
	return maxi(want, int(ceilf(CardTokens.HUB_QUEST_SCREEN_MIN / _screen_k())))


func _screen_k() -> float:
	var win := get_viewport() as Window if is_inside_tree() else null
	if win == null or DisplayServer.get_name() == "headless" or win != get_tree().root or win.size.y < 100:
		return 1.0
	var canvas_h := win.get_visible_rect().size.y
	return clampf(float(win.size.y) / canvas_h / maxf(DisplayServer.screen_get_scale(), 1.0), 0.25, 4.0) if canvas_h > 0.0 else 1.0