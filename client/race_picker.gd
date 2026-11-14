extends Control
## The race picker of the card character screen (design/gdd/races-and-classes.md 3.7-3.9, Boss 2026-11-13: free race
## choice in the hub). A dimmed full-screen layer with one parchment panel: a title, then the 4 races side by side; each
## tile shows the race colour and letter badge, its name, and for THIS card's class the race passive (name + text) and
## the race ultimate (name + text), read from data/races through logic/race_data.gd. The card's race is ringed in its
## colour and tagged CURRENT.
## States: browsing (tap a race) -> [the card has Race or Combo skill-tree points] confirming (the warning line
## "Race and Combo points (N) will be returned" + Change / Cancel) -> busy (the command is out) -> browsing again with
## the new race marked. A card without such points changes on the first tap.
## Display only: it emits `race_chosen` and the character screen sends the `card_race` command (logic/commands.gd);
## then it calls show_card() again with the deck the profile now holds.
## Touch first (tiles and buttons >= 96 px on phones), keyboard / gamepad focus on every tile, Esc / B closes.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")  ## the carved ink-wash look (Boss 2026-11-14)
const CardDeck := preload("res://logic/card_deck.gd")
const RaceData := preload("res://logic/race_data.gd")
const SkillTree := preload("res://logic/skill_tree.gd")
const RaceBadge := preload("res://client/race_badge.gd")
const TutorialMarks := preload("res://client/tutorial_marks.gd")

signal race_chosen(race_id: String)
signal locked_tapped(race_id: String)  ## tutorial.md 5: a locked race (Runeborn before wave 12): the screen shows a toast
signal closed()

var reduced_motion := false
var card := ""
var current := ""
var pending := ""  ## the race waiting for the refund confirmation ("" none)
var busy := false
var locked_races: Array = []  ## tutorial.md 5: race ids shown greyed with a padlock; a tap only emits locked_tapped
var refund_points := 0  ## the card's Race + Combo skill-tree points (SkillTree.state spent race + combo)

var _s := 1.0
var _phone := false
var _shade: Panel
var _panel: Panel
var _title: Label
var _sub: Label
var _tiles := {}  ## race id -> {"button", "badge", "name", "tag", "p_head", "p_text", "u_head", "u_text"}
var _ids: Array = []
var _warn: Label
var _confirm: Button
var _cancel: Button
var _close: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_shade = Panel.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardTokens.panel(_shade, CardTokens.hub_shade(CardTokens.HUB_DIM))
	add_child(_shade)
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_title = CardTokens.hub_label("", CardTokens.FONT_RACE_TITLE, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB)
	_panel.add_child(_title)
	_sub = CardTokens.hub_label(CardTokens.t("race_sub"), CardTokens.FONT_RACE_SUB, CardTokens.HUB_MUTED, 1.0, 0, "medium")
	_panel.add_child(_sub)
	_ids = RaceData.load_default().ids()
	for race in _ids:
		_build_tile(str(race))
	_warn = CardTokens.hub_label("", CardTokens.FONT_RACE_WARN, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium")
	_panel.add_child(_warn)
	_confirm = _button("", _on_confirm)
	_cancel = _button(CardTokens.t("race_cancel"), _on_cancel)
	_close = _button(CardTokens.t("race_close"), close)
	resized.connect(_layout)


func _build_tile(race: String) -> void:
	var b := Button.new()
	b.name = "Race_" + race  # tutorial target (design/gdd/tutorial.md 4)
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	b.pressed.connect(_on_tile.bind(race))
	_panel.add_child(b)
	var parts := {"button": b}
	var badge := RaceBadge.new()
	b.add_child(badge)
	parts["badge"] = badge
	parts["name"] = _tile_label(b, CardTokens.FONT_RACE_NAME, CardTokens.HUB_INK, "display")
	parts["tag"] = _tile_label(b, CardTokens.FONT_RACE_TAG, CardTokens.HUB_INK, "medium")
	parts["p_head"] = _tile_label(b, CardTokens.FONT_RACE_HEAD, CardTokens.RACE_HEAD_INK, "display")
	parts["p_text"] = _tile_label(b, CardTokens.FONT_RACE_BODY, CardTokens.HUB_INK, "medium", true)
	parts["u_head"] = _tile_label(b, CardTokens.FONT_RACE_HEAD, CardTokens.RACE_HEAD_INK, "display")
	parts["u_text"] = _tile_label(b, CardTokens.FONT_RACE_BODY, CardTokens.HUB_INK, "medium", true)
	_tiles[race] = parts


func _tile_label(parent: Control, font: int, color: Color, face: String, wrap: bool = false) -> Label:
	var l := CardTokens.label("", font, color, 1.0, 0, face, CardTokens.HUB_OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.text = text
	b.pressed.connect(callback)
	_panel.add_child(b)
	return b


# ================================================================== API
## Opens (or redraws) the picker for card `class_id` of `deck` (Profile.card_deck).
func open(class_id: String, deck: Dictionary) -> void:
	var was_open := visible
	visible = true
	pending = ""
	busy = false
	show_card(class_id, deck)
	if not was_open and not reduced_motion:
		_panel.modulate.a = 0.0
		create_tween().tween_property(_panel, "modulate:a", 1.0, CardTokens.FADE_SECONDS)
	var tile: Dictionary = _tiles.get(current, {})
	if not tile.is_empty():
		(tile["button"] as Button).grab_focus.call_deferred()


## Redraws from the deck: the card's race, its Race + Combo points, the passive / ultimate texts for its class.
func show_card(class_id: String, deck: Dictionary) -> void:
	card = class_id
	current = CardDeck.race_of(deck, class_id)
	var tree: Dictionary = SkillTree.state(deck, class_id)
	refund_points = int(tree["spent"].get("race", 0)) + int(tree["spent"].get("combo", 0))
	var races = RaceData.load_default()
	_title.text = CardTokens.t("race_title") % CardTokens.class_name_of(class_id)
	for race in _tiles:
		var parts: Dictionary = _tiles[race]
		var passive: Dictionary = races.passive_for(race, class_id)
		var ultimate: Dictionary = races.ultimate_for(race, class_id)
		(parts["name"] as Label).text = CardTokens.race_name(race)
		(parts["tag"] as Label).text = CardTokens.t("race_current") if race == current else ""
		(parts["p_head"] as Label).text = CardTokens.t("race_passive") % str(passive.get("name", ""))
		(parts["p_text"] as Label).text = str(passive.get("text", ""))
		(parts["u_head"] as Label).text = CardTokens.t("race_ultimate") % str(ultimate.get("name", ""))
		(parts["u_text"] as Label).text = str(ultimate.get("text", ""))
		(parts["button"] as Button).tooltip_text = CardTokens.race_name(race)
	_layout()


func close() -> void:
	if not visible:
		return
	visible = false
	pending = ""
	closed.emit()


## The command came back: `ok` = the deck now holds the new race (show_card was called), else back to browsing.
func finish(_ok: bool) -> void:
	busy = false
	pending = ""
	_refresh_state()


# ================================================================== input
func _on_tile(race: String) -> void:
	if busy:
		return
	if locked_races.has(race):
		locked_tapped.emit(race)
		return
	if race == current:
		pending = ""
		_refresh_state()
		return
	if refund_points > 0:
		pending = race
		_refresh_state()
		_confirm.grab_focus.call_deferred()
		return
	_choose(race)


func _on_confirm() -> void:
	if not pending.is_empty() and not busy:
		_choose(pending)


func _on_cancel() -> void:
	var back := pending
	pending = ""
	_refresh_state()
	var tile: Dictionary = _tiles.get(back, {})
	if not tile.is_empty():
		(tile["button"] as Button).grab_focus.call_deferred()


func _choose(race: String) -> void:
	busy = true
	pending = race
	_refresh_state()
	race_chosen.emit(race)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if not pending.is_empty() and not busy:
			_on_cancel()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton:
		if event.is_pressed():
			get_viewport().set_input_as_handled()  # Q / E / 1-3 / LB / RB of the screen under it wait until the picker closes


# ================================================================== layout
func _layout() -> void:
	if _panel == null or size.x <= 0.0:
		return
	_s = CardTokens.scale_for(size)
	_phone = CardTokens.is_phone(size)
	var s := _s
	var side := CardTokens.hub_safe_x(size, s)
	var pw := minf(CardTokens.RACE_PANEL.x * s, size.x - side * 2.0)
	var ph := minf(CardTokens.RACE_PANEL.y * s, size.y - CardTokens.HUB_SAFE.y * s * 2.0)
	_panel.size = Vector2(pw, ph)
	_panel.position = (size - _panel.size) * 0.5
	CarvedLook.board(_panel, s)  # carved gilded-wood board, parchment face: ink text
	var pad := CardTokens.RACE_PANEL_PAD * s
	var head_h := CardTokens.RACE_HEADER_H * s
	_title.position = Vector2(pad, pad * 0.5)
	_title.size = Vector2(pw - pad * 2.0, head_h * 0.58)
	CardTokens.hub_fit(_title, _title.text, CardTokens.FONT_RACE_TITLE, _title.size.x, CardTokens.HUB_INK, s)
	_sub.position = Vector2(pad, pad * 0.5 + head_h * 0.58)
	_sub.size = Vector2(pw - pad * 2.0, head_h * 0.36)
	CardTokens.hub_fit(_sub, _sub.text, CardTokens.FONT_RACE_SUB, _sub.size.x, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	var foot_h := CardTokens.tap(CardTokens.RACE_FOOT_H, _phone) * s
	var gap := CardTokens.RACE_TILE_GAP * s
	var count := maxi(_ids.size(), 1)
	var tile_w := (pw - pad * 2.0 - gap * float(count - 1)) / float(count)
	var tile_y := pad * 0.5 + head_h
	var tile_h := ph - tile_y - foot_h - pad * 0.5
	var tp := CardTokens.RACE_TILE_PAD * s
	var i := 0
	for race in _ids:
		var parts: Dictionary = _tiles[race]
		var b: Button = parts["button"]
		b.position = Vector2(pad + float(i) * (tile_w + gap), tile_y)
		b.size = Vector2(tile_w, tile_h)
		var inner := tile_w - tp * 2.0
		var badge_edge := CardTokens.RACE_BADGE_PICKER * s
		var badge: Control = parts["badge"]
		badge.position = Vector2(tp, tp)
		badge.show_race(race, badge_edge)
		var name_label: Label = parts["name"]
		name_label.position = Vector2(tp + badge_edge + tp * 0.7, tp - 4.0 * s)
		name_label.size = Vector2(inner - badge_edge - tp * 0.7, badge_edge * 0.62)
		CardTokens.hub_fit(name_label, name_label.text, CardTokens.FONT_RACE_NAME, name_label.size.x, CardTokens.HUB_INK, s)
		var tag: Label = parts["tag"]
		tag.position = Vector2(name_label.position.x, tp + badge_edge * 0.6)
		tag.size = Vector2(name_label.size.x, badge_edge * 0.42)
		CardTokens.style_text(tag, CardTokens.FONT_RACE_TAG, CardTokens.race_plate(race).darkened(0.35), s, 0, "medium")
		var y := tp * 1.6 + badge_edge
		for key in ["p", "u"]:
			var head: Label = parts[key + "_head"]
			var body: Label = parts[key + "_text"]
			head.position = Vector2(tp, y)
			head.size = Vector2(inner, CardTokens.FONT_RACE_HEAD * 1.5 * s)
			CardTokens.hub_fit(head, head.text, CardTokens.FONT_RACE_HEAD, inner, CardTokens.RACE_HEAD_INK, s)
			y += head.size.y
			body.position = Vector2(tp, y)
			body.size = Vector2(inner, 0.0)
			CardTokens.style_text(body, CardTokens.FONT_RACE_BODY, CardTokens.HUB_INK, s, 0, "medium")
			body.size = Vector2(inner, maxf(body.get_minimum_size().y, CardTokens.FONT_RACE_BODY * 1.4 * s))
			y += body.size.y + tp
		i += 1
	# foot: the warning + Change / Cancel, or the hint + Close
	var bh := CardTokens.tap(CardTokens.RACE_CLOSE.y, _phone) * s
	var foot_y := ph - foot_h - pad * 0.25 + (foot_h - bh) * 0.5
	_close.size = Vector2(CardTokens.RACE_CLOSE.x * s, bh)
	_close.position = Vector2(pw - pad - _close.size.x, foot_y)
	_cancel.size = _close.size
	_cancel.position = _close.position
	_confirm.size = Vector2(CardTokens.RACE_CONFIRM_BUTTON.x * s, bh)
	_confirm.position = Vector2(_cancel.position.x - gap - _confirm.size.x, foot_y)
	_warn.position = Vector2(pad, foot_y)
	_warn.size = Vector2(_confirm.position.x - pad * 2.0, bh)
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for b in [_close, _cancel, _confirm]:
		CarvedLook.plate_button(b, s)
	_refresh_state()


## tutorial.md 5: 40% saturation + a padlock medallion on a locked race tile.
func _mark_locked(b: Button, locked: bool) -> void:
	b.material = TutorialMarks.locked_material() if locked else null
	b.use_parent_material = false
	for child in b.get_children():
		if child is CanvasItem and child.name != "LockMark":
			(child as CanvasItem).use_parent_material = locked
	var mark := b.get_node_or_null("LockMark")
	if locked and mark == null:
		mark = TutorialMarks.new(TutorialMarks.Kind.LOCK)
		b.add_child(mark)
	if mark != null:
		mark.visible = locked
		var edge := CardTokens.RACE_BADGE_PICKER * _s
		mark.place(Vector2(b.size.x - edge - CardTokens.RACE_TILE_PAD * _s, CardTokens.RACE_TILE_PAD * _s), edge)


## Tiles' rings, the foot (warning / buttons) for the current state.
func _refresh_state() -> void:
	if _panel == null:
		return
	var s := _s
	for race in _tiles:
		var b: Button = _tiles[race]["button"]
		CarvedLook.race_tile(b, race, race == current, race == pending, s)
		b.disabled = busy
		_mark_locked(b, locked_races.has(race))
	var confirming := not pending.is_empty() and refund_points > 0
	_confirm.visible = confirming
	_cancel.visible = confirming
	_close.visible = not confirming
	_confirm.disabled = busy
	_cancel.disabled = busy
	if confirming:
		_confirm.text = CardTokens.t("race_confirm") % CardTokens.race_name(pending)
		_warn.text = CardTokens.t("race_refund_warn") % refund_points
		CardTokens.hub_fit(_warn, _warn.text, CardTokens.FONT_RACE_WARN, _warn.size.x, CardTokens.RACE_HEAD_INK, s, 0, "display")
	else:
		_warn.text = CarvedLook.hint_text(CardTokens.t("race_hint"), CarvedLook.touch_hints(size))
		CardTokens.hub_fit(_warn, _warn.text, CardTokens.FONT_HUB_HINT, _warn.size.x, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	for b in [_close, _cancel, _confirm]:
		CardTokens.hub_fit(b, b.text, CardTokens.FONT_RACE_BUTTON, b.size.x * 0.85, CardTokens.HUB_INK, s)
