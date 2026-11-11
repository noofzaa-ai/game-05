extends CanvasLayer
## The squad's info in an auto-battle fight (Boss 2026-11-10): one card per fighter at the bottom of the
## screen with its name and health (the ultimate gauge is hidden: Boss 2026-11-11, skills only, no ultimate yet). Nobody steers: a card (click, or key 1-3) only picks which
## fighter the camera follows when zoomed in.

const InkUi := preload("res://client/ink_ui.gd")
const Fighter := preload("res://logic/fighter.gd")
const SHOW_ULTIMATE := false  ## Boss 2026-11-11: skills only for now; turn on when ultimates come back
const CARD_HEIGHT := 78.0 if SHOW_ULTIMATE else 58.0
const MARGIN := 12.0
const GAP := 8.0
const MAX_CARD_WIDTH := 260.0
const NAMES := {"sword_shield": "Sword & Shield", "greatsword": "Great Sword", "longbow": "Longbow", "magic": "Magic"}
const CALLOUT_SECONDS := 1.3  ## how long a skill's name stays above its fighter's card
const CALLOUT_HEIGHT := 30.0
const CALLOUT_WHITEN := 0.55  ## how far a skill's colour is lifted toward the HUD text colour (readable on any ground)

signal selected(id: int)  ## the player picked this fighter for the camera

var _root: Control
var _selected := -1
var _cards: Dictionary = {}  ## fighter id -> {"panel", "name", "hp_fill", "hp_text", "ult_fill", "gauge_back", "callout"}
var _order: Array = []


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	get_viewport().size_changed.connect(_place)


## `classes`: fighter id -> class id (data/classes), for the card titles.
var classes: Dictionary = {}


func update_from(fighters: Dictionary, local_id: int, combat_data) -> void:
	var ids: Array = []
	var team := ""
	if fighters.has(local_id):
		team = str(fighters[local_id].team)
	for id in fighters:
		if str(fighters[id].team) == team:
			ids.append(id)
	ids.sort()
	if ids != _order:
		_order = ids
		_rebuild()
	var gauge_max := float(combat_data.rules["ultimate_gauge_max"])
	for id in _order:
		var fighter: Fighter = fighters[id]
		var card: Dictionary = _cards[id]
		var ratio := clampf(fighter.hp / maxf(fighter.max_hp(), 1.0), 0.0, 1.0)
		card["hp_fill"].size.x = card["bar_width"] * ratio
		card["hp_text"].text = hp_text(fighter.hp, fighter.max_hp())
		var gauge := clampf(fighter.gauge / gauge_max, 0.0, 1.0)
		card["ult_fill"].size.x = card["bar_width"] * gauge
		card["ult_fill"].color = InkUi.ULT_READY_TEXT if gauge >= 1.0 else InkUi.ULT
		card["panel"].modulate.a = 1.0 if fighter.is_alive() else 0.45
		card["panel"].color = InkUi.HUD_PANEL.lightened(0.25) if id == _selected else InkUi.HUD_PANEL


## "hp / max" as whole numbers that never show more than the maximum (both fractional in the rules).
static func hp_text(hp: float, max_hp: float) -> String:
	var top := maxi(roundi(max_hp), 1)
	var now := clampi(ceili(maxf(hp, 0.0)), 0, top)
	return "%d / %d" % [now, top]


## A skill was cast by fighter `id`: its name pops up above that fighter's card (each card has its own
## callout, so casts on the same tick never pile up on one banner; a newer cast replaces the text).
func callout(id: int, text: String, color: Color) -> void:
	if not _cards.has(id) or not _cards[id].has("callout"):
		return
	var label: Label = _cards[id]["callout"]
	label.text = text
	var tint := color.lerp(InkUi.HUD_TEXT, CALLOUT_WHITEN)
	InkUi.style_text(label, tint)
	label.visible = true
	label.modulate.a = 1.0
	label.scale = Vector2(1.25, 1.25)
	var old = _cards[id].get("callout_tween")
	if old is Tween and old.is_valid():
		old.kill()
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_interval(CALLOUT_SECONDS - 0.42)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.hide)
	_cards[id]["callout_tween"] = tween


## The squad cards and their callouts, in viewport pixels (combat pop-ups keep off them).
func keep_out_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for card in _cards.values():
		var rect: Rect2 = (card["panel"] as Control).get_global_rect()
		rects.append(Rect2(rect.position - Vector2(0.0, CALLOUT_HEIGHT + 4.0), rect.size + Vector2(0.0, CALLOUT_HEIGHT + 4.0)).grow(6.0))
	return rects


func select(id: int) -> void:
	if _cards.has(id):
		_selected = id
		selected.emit(id)


func _on_card_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var index: int = event.keycode - KEY_1
		if index < _order.size():
			select(_order[index])


func _rebuild() -> void:
	for card in _cards.values():
		card["panel"].queue_free()
	_cards.clear()
	var index := 0
	for id in _order:
		index += 1
		var panel := ColorRect.new()
		panel.color = InkUi.HUD_PANEL
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_card_input.bind(id))
		_root.add_child(panel)
		var name_label := Label.new()
		name_label.text = "%d  %s" % [index, NAMES.get(str(classes.get(id, "sword_shield")), "Sword & Shield")]
		InkUi.style_text(name_label, InkUi.HUD_TEXT, InkUi.FONT_SMALL)
		name_label.position = Vector2(8, 4)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_label)
		var hp_back := ColorRect.new()
		hp_back.color = InkUi.HUD_PANEL
		hp_back.position = Vector2(8, 30)
		hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(hp_back)
		var hp_fill := ColorRect.new()
		hp_fill.color = InkUi.HP
		hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_back.add_child(hp_fill)
		var hp_label := Label.new()
		InkUi.style_text(hp_label, InkUi.HUD_TEXT, InkUi.FONT_CAPTION)
		hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_back.add_child(hp_label)
		var ult_back := ColorRect.new()
		ult_back.color = InkUi.HUD_PANEL
		ult_back.position = Vector2(8, 56)
		ult_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ult_back.visible = SHOW_ULTIMATE
		panel.add_child(ult_back)
		var ult_fill := ColorRect.new()
		ult_fill.color = InkUi.ULT
		ult_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ult_back.add_child(ult_fill)
		var callout := Label.new()
		callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		callout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		InkUi.style_text(callout, InkUi.HUD_TEXT, InkUi.FONT_HEADING, 7)
		callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		callout.visible = false
		panel.add_child(callout)
		_cards[id] = {"panel": panel, "name": name_label, "hp_back": hp_back, "hp_fill": hp_fill, "hp_text": hp_label, "ult_back": ult_back, "ult_fill": ult_fill, "bar_width": 100.0, "callout": callout}
	_place()


func _place() -> void:
	if _root == null or _order.is_empty():
		return
	var size := get_viewport().get_visible_rect().size
	var count := _order.size()
	var width := minf(MAX_CARD_WIDTH, (size.x - MARGIN * 2.0 - GAP * float(count - 1)) / float(count))
	var left := (size.x - width * float(count) - GAP * float(count - 1)) * 0.5
	var index := 0
	for id in _order:
		var card: Dictionary = _cards[id]
		var panel: ColorRect = card["panel"]
		panel.size = Vector2(width, CARD_HEIGHT)
		panel.position = Vector2(left + float(index) * (width + GAP), size.y - MARGIN - CARD_HEIGHT)
		var bar_width := width - 16.0
		card["bar_width"] = bar_width
		card["hp_back"].size = Vector2(bar_width, 20.0)
		card["hp_fill"].size = Vector2(bar_width, 20.0)
		card["hp_text"].size = Vector2(bar_width, 20.0)
		card["hp_text"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card["ult_back"].size = Vector2(bar_width, 10.0)
		card["ult_fill"].size = Vector2(0.0, 10.0)
		card["callout"].size = Vector2(width, CALLOUT_HEIGHT)
		card["callout"].position = Vector2(0.0, -CALLOUT_HEIGHT - 4.0)
		card["callout"].pivot_offset = card["callout"].size * 0.5
		index += 1
