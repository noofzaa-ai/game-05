extends CanvasLayer
## Combos in the fight (Boss 2026-11-25), kept minimal for the clean fight screen: small state icons over each fighter
## that carries a combo state (max MAX_ICONS, then "+n"), a short popup "[icons] -> STARFALL x2!" over the target when the
## sim sends {type:"combo"}, and a small combo counter under the top bar while combos chain. It also tallies the run's
## combo count / combo damage into GameState.run_loot for the summary line. Display only.

const CardTokens := preload("res://client/card_tokens.gd")
const ComboUi := preload("res://client/combo_ui.gd")

const MAX_ICONS := 3
const Rules := preload("res://client/fight_text_rules.gd")
const POPUP_SECONDS := 1.4
const COUNTER_SECONDS := 4.0

var data = null
## (fighter id) -> Vector2 screen point above the head, or null when off screen. Set by the stage.
var head_point: Callable
var fighter_ids: Callable  ## () -> Array of ids to show icons for
var fighter_of: Callable  ## (id) -> Fighter
var run_tally: Dictionary = {}  ## where count / damage go (GameState.run_loot); tests pass their own
var reduced_motion := false
## Fight text rules (data/ui/fight_text.json): per-fighter lanes, merge, screen budget, the top combo lane.
var rules = Rules.new()
var is_ours: Callable  ## (id) -> bool, our squad (status icons go on its card instead of over the head)
var card_rect: Callable  ## (id) -> Rect2 of our squad card, or null
var keep_out: Array[Rect2] = []

var _draw: Control
var _popups: Array = []  ## [{"id", "states", "text", "age", "at"}]
var _counter := 0
var _counter_age := 99.0
var _counter_label: Label


func _ready() -> void:
	layer = 4
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_paint)
	add_child(_draw)
	_counter_label = Label.new()
	_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_label.visible = false
	_draw.add_child(_counter_label)


## A combo event from the sim: popup + counter + tally. `damage` (if the event carries it) feeds the damage share.
func on_combo(event: Dictionary, at: Vector2 = Vector2.INF) -> void:
	_counter += 1
	_counter_age = 0.0
	# One combo popup at a time, in the top-centre lane (never over the fighter): a newer one replaces it.
	rules.push(int(event.get("target", -1)), "combo", ComboUi.popup_text(event))
	rules.top["states"] = (event.get("states", []) as Array).duplicate()
	_popups = [{"id": int(event.get("target", -1)), "states": rules.top["states"], "text": rules.top["text"], "age": 0.0, "at": at}]
	run_tally["combo_count"] = int(run_tally.get("combo_count", 0)) + 1
	run_tally["combo_damage"] = float(run_tally.get("combo_damage", 0.0)) + float(event.get("damage", event.get("bonus_damage", 0.0)))


## Our team's damage (hit / skill_hit / dot events), the denominator of the summary's combo damage share.
func on_team_damage(amount: float) -> void:
	run_tally["team_damage"] = float(run_tally.get("team_damage", 0.0)) + amount


func counter() -> int:
	return _counter if _counter_age < COUNTER_SECONDS else 0


func popup_count() -> int:
	return _popups.size()


## A floating word over fighter `id` (see client/fight_text_rules.gd for what each category does). Returns the action.
func say(id: int, category: String, text: String, color: Color = Color.WHITE) -> String:
	return rules.push(id, category, text, color)


func _process(delta: float) -> void:
	rules.tick(delta)
	rules.phone = CardTokens.is_phone(_draw.get_viewport_rect().size) if _draw != null and _draw.is_inside_tree() else rules.phone
	for p in _popups:
		p["age"] += delta
	_popups = _popups.filter(func(p): return p["age"] < POPUP_SECONDS)
	if _draw == null:
		return
	_counter_age += delta
	if _counter_age >= COUNTER_SECONDS:
		_counter = 0
	_draw.queue_redraw()


func _paint() -> void:
	var screen := _draw.get_viewport_rect().size
	var s := CardTokens.scale_for(screen)
	var phone := CardTokens.is_phone(screen)
	rules.phone = phone
	var r: float = rules.icon_radius(s)  # data/ui/fight_text.json status_icons.size (phone min so 844x390 reads)
	if fighter_ids.is_valid() and head_point.is_valid() and fighter_of.is_valid():
		for id in fighter_ids.call():
			var fighter = fighter_of.call(id)
			var ours: bool = is_ours.is_valid() and bool(is_ours.call(id))
			var statuses: Array = rules.statuses_of(fighter.effects) if fighter != null else []
			if ours and not statuses.is_empty() and card_rect.is_valid():
				_status_row(card_rect.call(id), statuses, r * 0.8)
			var states := ComboUi.fighter_states(fighter)
			var p = head_point.call(id)
			if p == null:
				continue
			if not ours and not statuses.is_empty():  # enemy statuses: a small icon row, no words
				_status_row_at(Vector2(p.x, p.y - (r * 2.6 if not states.is_empty() else 0.0)), statuses, r * 0.75)
			_paint_lane(id, p, s, phone, r)
			if states.is_empty():
				continue
			var shown := states.slice(0, MAX_ICONS)
			var x0: float = p.x - (shown.size() - 1) * r * 1.2
			for i in shown.size():
				ComboUi.draw_state_icon(_draw, Vector2(x0 + i * r * 2.4, p.y), r, shown[i], data)
			if states.size() > MAX_ICONS:
				_text(Vector2(x0 + shown.size() * r * 2.4 - r * 0.6, p.y + r * 0.4), "+%d" % (states.size() - MAX_ICONS), int(r * 1.3), Color.WHITE)
	var font := CardTokens.display_font()
	for pop in _popups:
		var at: Vector2 = _top_lane_point(screen)
		var t: float = pop["age"] / POPUP_SECONDS
		var rise := 0.0
		var a := clampf((1.0 - t) * 3.0, 0.0, 1.0)
		var fs := maxi(int((26.0 if not phone else 30.0) * s), CardTokens.FONT_MIN + 2)
		var states: Array = pop["states"]
		var ir := fs * 0.42
		var text := "-> " + str(pop["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 100.0
		var total := states.size() * ir * 2.4 + tw
		var x := clampf(at.x - total * 0.5, 8.0, screen.x - total - 8.0)
		var y := at.y + rise
		for st in states:
			ComboUi.draw_state_icon(_draw, Vector2(x + ir, y - fs * 0.3), ir, str(st), data, a)
			x += ir * 2.4
		var col: Color = ComboUi.state_info(str(states[0]), data)["color"] if not states.is_empty() else Color.WHITE
		col = col.lerp(Color.WHITE, 0.35)
		col.a = a
		_text(Vector2(x, y), text, fs, col, a)
	if counter() >= 2:
		var label := "%s x%d" % [ComboUi.t("combo"), _counter]
		var box := counter_rect(screen, label)
		_text(Vector2(box.position.x, box.end.y), label, int(box.size.y), Color("FFD166"), clampf((COUNTER_SECONDS - _counter_age) * 2.0, 0.0, 1.0))


## Where the combo counter line ("COMBO x3") sits: right side, below every top keep-out rect on the right (the trip
## line / loot feed), so it never lands on them. The rect's height is the font size; text baseline = rect end.
func counter_rect(screen: Vector2, label: String = "COMBO x9") -> Rect2:
	var s := CardTokens.scale_for(screen)
	var fs := maxi(int((30.0 if not CardTokens.is_phone(screen) else 38.0) * s), CardTokens.FONT_MIN)
	var font := CardTokens.display_font()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 80.0
	var x := screen.x - w - 24.0 * s - CardTokens.hub_safe_x(screen, s)
	var y := screen.y * 0.22
	var box := Rect2(x, y, w, fs)
	for rect in keep_out:
		if rect.position.y < screen.y * 0.5 and rect.intersects(box):
			y = maxf(y, rect.end.y + 4.0)
			box.position.y = y
	return Rect2(x, y, w, fs)


## The top-centre lane: just under the boss bar / trip line (below every keep-out rect that spans the top centre).
func _top_lane_point(screen: Vector2) -> Vector2:
	var y := screen.y * 0.16
	for rect in keep_out:
		if rect.position.y < screen.y * 0.4 and rect.position.x < screen.x * 0.5 and rect.end.x > screen.x * 0.5:
			y = maxf(y, rect.end.y + screen.y * 0.07)
	return Vector2(screen.x * 0.5, y)


## The fighter's text lane (max lane_lines lines, newest nearest the head), above its combo icons.
func _paint_lane(id: int, p: Vector2, s: float, phone: bool, r: float) -> void:
	var lane: Array = rules.lanes.get(id, [])
	if lane.is_empty():
		return
	var font := CardTokens.display_font()
	var fs := maxi(int((24.0 if not phone else 30.0) * s), CardTokens.FONT_MIN)
	var screen := _draw.get_viewport_rect().size
	var y := p.y - r * 5.0
	for i in range(lane.size() - 1, -1, -1):
		var line: Dictionary = lane[i]
		var life := float(rules.data.get("line_seconds", 1.1))
		var a := clampf((life - float(line["age"])) / 0.3, 0.0, 1.0)
		var text := str(line["text"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 60.0
		var box := Rect2(Vector2(p.x - w * 0.5, y - fs), Vector2(w, fs * 1.2))
		box.position += preload("res://client/combat_numbers.gd").avoid(box, keep_out, screen)
		var col: Color = line["color"]
		col.a = a
		_text(Vector2(box.position.x, box.position.y + fs), text, fs, col, a)
		y -= fs * 1.15


func _status_row(rect, statuses: Array, r: float) -> void:
	if rect == null:
		return
	var box: Rect2 = rect
	var shown := statuses.slice(0, rules.max_icons())
	var x := box.end.x - r * 1.3
	var y := box.position.y + r * 1.1
	for i in shown.size():
		_status_icon(Vector2(x - i * r * 2.3, y), r, str(shown[i]))
	if statuses.size() > shown.size():
		_text(Vector2(x - shown.size() * r * 2.3 - r, y + r * 0.45), "+%d" % (statuses.size() - shown.size()), int(r * 1.4), Color.WHITE)


func _status_row_at(p: Vector2, statuses: Array, r: float) -> void:
	var shown := statuses.slice(0, rules.max_icons())
	var x0: float = p.x - (shown.size() - 1) * r * 1.15
	for i in shown.size():
		_status_icon(Vector2(x0 + i * r * 2.3, p.y - r * 2.2), r, str(shown[i]))


func _status_icon(c: Vector2, r: float, effect_id: String) -> void:
	var look: Dictionary = rules.status_icon(effect_id)
	if look.is_empty():
		return
	var outer := ComboUi._shape(str(look["shape"]), c, r + maxf(1.5, r * 0.18))
	_draw.draw_colored_polygon(outer, Color(0.1, 0.07, 0.05))
	_draw.draw_colored_polygon(ComboUi._shape(str(look["shape"]), c, r), look["color"])
	var font := CardTokens.display_font()
	if font != null and r >= 6.0:
		var fs := int(r * 1.2)
		var glyph := str(look["glyph"])
		var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var light: bool = (look["color"] as Color).get_luminance() > 0.6
		_draw.draw_string(font, c + Vector2(-gw.x * 0.5, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.07, 0.05) if light else Color.WHITE)


func _text(at: Vector2, text: String, fs: int, col: Color, a: float = 1.0) -> void:
	var font := CardTokens.display_font()
	if font == null:
		return
	_draw.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 5), Color(0.1, 0.07, 0.05, a))
	_draw.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
