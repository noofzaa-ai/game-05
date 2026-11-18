extends "res://client/hub_service_panel.gd"
## Quests (Boss 2026-11-18): the side menu's Quests entry. Every zone unlock quest of data/world/zone_quests.json
## (logic/zone_quests.gd) in map order: the quest name and its state (In progress / Done, a word and a tick, not
## colour only), the description, each step with [x] / [ ] and its live progress ("best card Lv 5/15") and the zone
## it opens. A finished quest stays listed, dimmed with a tick. Tapping a quest asks the hub to open the world map on
## that zone (`zone_requested`; the hub tracker does the same). No quest at all: one short empty line.
## Display only: every rule and number comes from the profile through logic/.

const Zones := preload("res://logic/world_zones.gd")
const ZoneQuests := preload("res://logic/zone_quests.gd")
const HubQuestTracker := preload("res://client/hub_quest_tracker.gd")

signal zone_requested(zone_id: String)

var _hint: Label
var _empty: Label
var _scroll: ScrollContainer
var _list: Control
var _rows: Array[Button] = []  ## one per quest zone (row.name = "Quest_<zone>")


func _init() -> void:
	service = "quests"


func build() -> void:
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


func first_focus() -> Control:
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
	var done := ZoneQuests.met(profile, zone_id)
	var steps: Array = []
	for step in ZoneQuests.progress(profile, zone_id):
		steps.append({"text": CardTokens.t("quest_mark_done" if step.done else "quest_mark_todo") + str(step.get("text_th" if th else "text_en", "")), "done": bool(step.done)})
	return {
		"name": str(q.get("name_th" if th else "name_en", zone_id)),
		"state": CardTokens.t("quest_state_done" if done else "quest_state_pending"),
		"done": done,
		"desc": str(q.get("desc_th" if th else "desc_en", "")),
		"steps": steps,
		"opens": CardTokens.t("quest_opens") % str(z.get("name_th" if th else "name_en", zone_id)),
	}


var _area := Vector2.ZERO


func layout_body(area: Vector2) -> void:
	_area = area
	var gap := CardTokens.CHAR_GAP * s
	var hint_h := _px(CardTokens.FONT_CHAR_LINE) * 1.8
	_hint.position = Vector2.ZERO
	_hint.size = Vector2(area.x, hint_h)
	CardTokens.hub_text(_hint, _px(CardTokens.FONT_CHAR_LINE), CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium")
	_scroll.position = Vector2(0.0, hint_h + gap * 0.3)
	_scroll.size = Vector2(area.x, area.y - _scroll.position.y)
	_empty.position = _scroll.position
	_empty.size = Vector2(area.x, hint_h * 2.0)
	CardTokens.hub_text(_empty, _px(CardTokens.FONT_CHAR_LINE), CardTokens.HUB_INK, 1.0, 0, "medium")


func refresh() -> void:
	super()
	if _list == null or _area == Vector2.ZERO:
		return
	var p = _profile()
	_empty.visible = _rows.is_empty()
	_hint.visible = not _rows.is_empty()
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


## Draws one quest row; returns its height. Lines: name + state word, description, steps, "Opens: zone".
func _fill_row(row: Button, lines: Dictionary, w: float, pad: float) -> float:
	var done: bool = lines.done
	CardTokens.bare_button(row, s, CardTokens.HUB_RADIUS)
	var sk := CarvedLook.inset(row, s, CarvedLook.TINT_IDLE if done else CarvedLook.TINT_NORMAL)
	sk.follow_button = true
	var title_px := _px(CardTokens.FONT_HUB_QUEST_ROW_TITLE)
	var line_px := _px(CardTokens.FONT_CHAR_LINE)
	var icon := title_px * 1.6
	var chev := CardTokens.HUB_QUEST_CHEVRON * s
	var text_x := pad + icon + pad * 0.5
	var text_w := maxf(w - text_x - pad - chev, 1.0)
	var texts: Array = [{"key": "Name", "text": "%s  ·  %s" % [lines.name, (CardTokens.t("quest_mark_done") + lines.state) if done else lines.state], "px": title_px, "face": "display", "color": CardTokens.HUB_INK},
		{"key": "Desc", "text": lines.desc, "px": line_px, "face": "medium", "color": CardTokens.HUB_TAB_IDLE}]
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
	tick.modulate = CardTokens.HUB_LOCKED if done else CardTokens.HUB_WHITE
	var chevron := row.get_node("Chevron") as TextureRect
	chevron.size = Vector2(chev * 0.7, chev)
	chevron.position = Vector2(w - pad * 0.6 - chevron.size.x, (total - chev) * 0.5)
	row.tooltip_text = "%s: %s" % [lines.name, lines.state]
	return total


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