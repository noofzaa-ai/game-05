extends CanvasLayer
## Combos in the fight (Boss 2026-11-25), kept minimal for the clean fight screen: small state icons over each fighter
## that carries a combo state (max MAX_ICONS, then "+n"), a short popup "[icons] -> STARFALL x2!" over the target when the
## sim sends {type:"combo"}, and a small combo counter under the top bar while combos chain. It also tallies the run's
## combo count / combo damage into GameState.run_loot for the summary line. Display only.

const CardTokens := preload("res://client/card_tokens.gd")
const ComboUi := preload("res://client/combo_ui.gd")

const MAX_ICONS := 3
const POPUP_SECONDS := 1.4
const COUNTER_SECONDS := 4.0

var data = null
## (fighter id) -> Vector2 screen point above the head, or null when off screen. Set by the stage.
var head_point: Callable
var fighter_ids: Callable  ## () -> Array of ids to show icons for
var fighter_of: Callable  ## (id) -> Fighter
var run_tally: Dictionary = {}  ## where count / damage go (GameState.run_loot); tests pass their own
var reduced_motion := false

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
	_popups.append({"id": int(event.get("target", -1)), "states": (event.get("states", []) as Array).duplicate(), "text": ComboUi.popup_text(event), "age": 0.0, "at": at})
	if _popups.size() > 3:
		_popups.pop_front()
	run_tally["combo_count"] = int(run_tally.get("combo_count", 0)) + 1
	run_tally["combo_damage"] = float(run_tally.get("combo_damage", 0.0)) + float(event.get("damage", event.get("bonus_damage", 0.0)))


## Our team's damage (hit / skill_hit / dot events), the denominator of the summary's combo damage share.
func on_team_damage(amount: float) -> void:
	run_tally["team_damage"] = float(run_tally.get("team_damage", 0.0)) + amount


func counter() -> int:
	return _counter if _counter_age < COUNTER_SECONDS else 0


func popup_count() -> int:
	return _popups.size()


func _process(delta: float) -> void:
	for p in _popups:
		p["age"] += delta
	_popups = _popups.filter(func(p): return p["age"] < POPUP_SECONDS)
	_counter_age += delta
	if _counter_age >= COUNTER_SECONDS:
		_counter = 0
	_draw.queue_redraw()


func _paint() -> void:
	var screen := _draw.get_viewport_rect().size
	var s := CardTokens.scale_for(screen)
	var phone := CardTokens.is_phone(screen)
	var r := maxf(7.0, (11.0 if not phone else 15.0) * s)  # phone: bigger so 844x390 still reads
	if fighter_ids.is_valid() and head_point.is_valid() and fighter_of.is_valid():
		for id in fighter_ids.call():
			var states := ComboUi.fighter_states(fighter_of.call(id))
			if states.is_empty():
				continue
			var p = head_point.call(id)
			if p == null:
				continue
			var shown := states.slice(0, MAX_ICONS)
			var x0: float = p.x - (shown.size() - 1) * r * 1.2
			for i in shown.size():
				ComboUi.draw_state_icon(_draw, Vector2(x0 + i * r * 2.4, p.y), r, shown[i], data)
			if states.size() > MAX_ICONS:
				_text(Vector2(x0 + shown.size() * r * 2.4 - r * 0.6, p.y + r * 0.4), "+%d" % (states.size() - MAX_ICONS), int(r * 1.3), Color.WHITE)
	var font := CardTokens.display_font()
	for pop in _popups:
		var at: Vector2 = pop["at"]
		if at == Vector2.INF and head_point.is_valid():
			var hp = head_point.call(pop["id"])
			at = hp if hp != null else screen * Vector2(0.5, 0.35)
		elif at == Vector2.INF:
			at = screen * Vector2(0.5, 0.35)
		var t: float = pop["age"] / POPUP_SECONDS
		var rise := 0.0 if reduced_motion else -40.0 * s * t
		var a := clampf((1.0 - t) * 3.0, 0.0, 1.0)
		var fs := maxi(int((34.0 if not phone else 44.0) * s), CardTokens.FONT_MIN + 2)
		var states: Array = pop["states"]
		var ir := fs * 0.42
		var text := "-> " + str(pop["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 100.0
		var total := states.size() * ir * 2.4 + tw
		var x := clampf(at.x - total * 0.5, 8.0, screen.x - total - 8.0)
		var y := at.y - r * 2.6 + rise
		for st in states:
			ComboUi.draw_state_icon(_draw, Vector2(x + ir, y - fs * 0.3), ir, str(st), data, a)
			x += ir * 2.4
		var col: Color = ComboUi.state_info(str(states[0]), data)["color"] if not states.is_empty() else Color.WHITE
		col = col.lerp(Color.WHITE, 0.35)
		col.a = a
		_text(Vector2(x, y), text, fs, col, a)
	if counter() >= 2:
		var fs2 := maxi(int((30.0 if not phone else 38.0) * s), CardTokens.FONT_MIN)
		var label := "%s x%d" % [ComboUi.t("combo"), _counter]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x if font != null else 80.0
		_text(Vector2(screen.x - w - 24.0 * s - CardTokens.hub_safe_x(screen, s), screen.y * 0.22), label, fs2, Color("FFD166"), clampf((COUNTER_SECONDS - _counter_age) * 2.0, 0.0, 1.0))


func _text(at: Vector2, text: String, fs: int, col: Color, a: float = 1.0) -> void:
	var font := CardTokens.display_font()
	if font == null:
		return
	_draw.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 5), Color(0.1, 0.07, 0.05, a))
	_draw.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
