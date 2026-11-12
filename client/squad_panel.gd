extends CanvasLayer
## The squad's info in an auto-battle fight (Boss 2026-11-10): one small leather card plate per fighter at the bottom
## of the screen in the approved hub look (Boss 2026-11-12): the class emblem medallion (cut from the class card frame
## art), the order number and class name on parchment, and the health bar with "hp / max". The ultimate gauge is
## hidden (Boss 2026-11-11: skills only). Nobody steers: a card (click, or key 1-3) only picks which fighter the
## camera follows when zoomed in. A skill cast pops its name on a leather pill above the caster's card.
## Sizes are the stage's logical pixels (1280x720 base, scaled to the window), from card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const HubLook := preload("res://client/hub_look.gd")
const Fighter := preload("res://logic/fighter.gd")
const SHOW_ULTIMATE := false  ## Boss 2026-11-11: skills only for now; turn on when ultimates come back
const CALLOUT_SECONDS := 1.3  ## how long a skill's name stays above its fighter's card
const CALLOUT_HEIGHT := CardTokens.SQUAD_HUD_CALLOUT_H
const CALLOUT_WHITEN := 0.55  ## how far a skill's colour is lifted toward cream (readable on the leather pill)

signal selected(id: int)  ## the player picked this fighter for the camera

var _root: Control
var _selected := -1
var _cards: Dictionary = {}  ## fighter id -> {"panel", "name", "hp_back", "hp_fill", "hp_text", "ult_fill", "callout", "callout_label", "ring", "down", "alive"}
var _order: Array = []
var _dead_material: ShaderMaterial


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	get_viewport().size_changed.connect(_place)


## `classes`: fighter id -> class id (data/classes), for the card titles and emblems.
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
		card["hp_fill"].visible = ratio > 0.0
		card["hp_text"].text = hp_text(fighter.hp, fighter.max_hp())
		card["ult_fill"].size.x = card["bar_width"] * clampf(fighter.gauge / gauge_max, 0.0, 1.0)
		var alive := fighter.is_alive()
		if alive != card["alive"]:
			card["alive"] = alive
			card["panel"].modulate = CardTokens.HUB_WHITE if alive else CardTokens.SQUAD_HUD_DEAD
			card["emblem"].material = null if alive else CardTokens.grey_material()
			card["down"].visible = not alive
		card["ring"].visible = id == _selected


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
	var pill: Control = _cards[id]["callout"]
	var label: Label = _cards[id]["callout_label"]
	label.text = text
	CardTokens.hub_fit(label, text, CardTokens.FONT_SQUAD_HUD_CALLOUT, pill.size.x - 16.0, color.lerp(CardTokens.HUB_CREAM, CALLOUT_WHITEN), 1.0, CardTokens.OUTLINE_HUB)
	pill.visible = true
	pill.modulate.a = 1.0
	pill.scale = Vector2(1.2, 1.2)
	var old = _cards[id].get("callout_tween")
	if old is Tween and old.is_valid():
		old.kill()
	var tween := pill.create_tween()
	tween.tween_property(pill, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_interval(CALLOUT_SECONDS - 0.42)
	tween.tween_property(pill, "modulate:a", 0.0, 0.3)
	tween.tween_callback(pill.hide)
	_cards[id]["callout_tween"] = tween


## The squad cards and their callouts, in viewport pixels (combat pop-ups keep off them).
func keep_out_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for card in _cards.values():
		if not card.has("panel"):
			continue
		var rect: Rect2 = (card["panel"] as Control).get_global_rect()
		var up := CALLOUT_HEIGHT + 4.0
		rects.append(Rect2(rect.position - Vector2(0.0, up), rect.size + Vector2(0.0, up)).grow(6.0))
	return rects


func select(id: int) -> void:
	if _cards.has(id):
		_selected = id
		selected.emit(id)


func _on_card_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select(id)
	elif event is InputEventScreenTouch and event.pressed:
		select(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var index: int = event.keycode - KEY_1
		if index < _order.size():
			select(_order[index])


func _plain(parent: Control) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _rebuild() -> void:
	for card in _cards.values():
		if card.has("panel"):
			card["panel"].queue_free()
	_cards.clear()
	var index := 0
	for id in _order:
		index += 1
		var class_id := str(classes.get(id, "sword_shield"))
		var panel := Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_card_input.bind(id))
		CardTokens.panel(panel, HubLook.leather(1.0, CardTokens.SQUAD_HUD_RADIUS, 3.0))
		_root.add_child(panel)
		var emblem := TextureRect.new()
		emblem.texture = HubLook.class_emblem(class_id)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(emblem)
		var paper := _plain(panel)
		CardTokens.panel(paper, HubLook.parchment(1.0, CardTokens.SQUAD_HUD_RADIUS * 0.6))
		var name_label := CardTokens.label("%d  %s" % [index, CardTokens.class_name_of(class_id)], CardTokens.FONT_SQUAD_HUD_NAME, CardTokens.HUB_INK, 1.0)
		paper.add_child(name_label)
		var hp_back := _plain(paper)
		CardTokens.panel(hp_back, CardTokens.flat(CardTokens.HUD_HP_BACK, CardTokens.HUB_LEATHER_EDGE, 1.0, 5.0, 1.0))
		var hp_fill := _plain(hp_back)
		CardTokens.panel(hp_fill, CardTokens.flat(CardTokens.HUD_HP, CardTokens.HUD_HP, 0.0, 5.0, 1.0))
		var hp_label := CardTokens.label("", CardTokens.FONT_SQUAD_HUD_HP, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_back.add_child(hp_label)
		var ult_fill := _plain(paper)  # kept for when ultimates return (hidden)
		ult_fill.visible = SHOW_ULTIMATE
		var down := CardTokens.label(HubLook.t("squad_down"), CardTokens.FONT_SQUAD_HUD_NAME, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
		down.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		down.visible = false
		panel.add_child(down)
		var ring := _plain(panel)
		CardTokens.panel(ring, CardTokens.ring(CardTokens.HUB_CREAM, CardTokens.SQUAD_HUD_SELECT, CardTokens.SQUAD_HUD_RADIUS + 2.0, 1.0))
		ring.visible = false
		var pill := _plain(panel)
		CardTokens.panel(pill, HubLook.leather(1.0, CALLOUT_HEIGHT * 0.5, 2.0))
		pill.visible = false
		var callout := CardTokens.label("", CardTokens.FONT_SQUAD_HUD_CALLOUT, CardTokens.HUB_CREAM, 1.0, CardTokens.OUTLINE_HUB, "display", CardTokens.HUB_OUTLINE)
		callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		callout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pill.add_child(callout)
		_cards[id] = {"panel": panel, "emblem": emblem, "paper": paper, "name": name_label, "hp_back": hp_back, "hp_fill": hp_fill, "hp_text": hp_label,
			"ult_fill": ult_fill, "ring": ring, "down": down, "callout": pill, "callout_label": callout, "bar_width": 100.0, "alive": true}
	_place()


func _place() -> void:
	if _root == null or _order.is_empty():
		return
	var area := get_viewport().get_visible_rect().size
	var count := _order.size()
	var gap := CardTokens.SQUAD_HUD_GAP
	var margin := CardTokens.SQUAD_HUD_MARGIN
	var width := minf(CardTokens.SQUAD_HUD_CARD.x, (area.x - margin * 2.0 - gap * float(count - 1)) / float(count))
	var height := CardTokens.SQUAD_HUD_CARD.y
	var left := (area.x - width * float(count) - gap * float(count - 1)) * 0.5
	var rim := CardTokens.SQUAD_HUD_LEATHER
	var medal := minf(CardTokens.SQUAD_HUD_EMBLEM, height - rim * 2.0)
	var index := 0
	for id in _order:
		var card: Dictionary = _cards[id]
		var panel: Panel = card["panel"]
		panel.size = Vector2(width, height)
		panel.position = Vector2(left + float(index) * (width + gap), area.y - margin - height)
		card["emblem"].position = Vector2(rim, (height - medal) * 0.5)
		card["emblem"].size = Vector2(medal, medal)
		var paper: Panel = card["paper"]
		paper.position = Vector2(rim * 2.0 + medal, rim)
		paper.size = Vector2(width - paper.position.x - rim, height - rim * 2.0)
		var inner := 8.0
		var name_label: Label = card["name"]
		name_label.position = Vector2(inner, 2.0)
		name_label.size = Vector2(paper.size.x - inner * 2.0, paper.size.y * 0.5 - 2.0)
		CardTokens.hub_fit(name_label, name_label.text, CardTokens.FONT_SQUAD_HUD_NAME, name_label.size.x, CardTokens.HUB_INK, 1.0)
		var bar_width := paper.size.x - inner * 2.0
		card["bar_width"] = bar_width
		var bar_h := CardTokens.SQUAD_HUD_BAR_H
		card["hp_back"].position = Vector2(inner, paper.size.y - bar_h - 6.0)
		card["hp_back"].size = Vector2(bar_width, bar_h)
		card["hp_fill"].size = Vector2(bar_width, bar_h)
		card["hp_text"].position = Vector2(0.0, -3.0)
		card["hp_text"].size = Vector2(bar_width, bar_h + 6.0)
		card["ult_fill"].position = Vector2(inner, paper.size.y - 4.0)
		card["ult_fill"].size = Vector2(0.0, 3.0)
		card["down"].position = card["emblem"].position
		card["down"].size = card["emblem"].size
		card["ring"].position = Vector2.ZERO
		card["ring"].size = panel.size
		card["callout"].size = Vector2(width, CALLOUT_HEIGHT)
		card["callout"].position = Vector2(0.0, -CALLOUT_HEIGHT - 4.0)
		card["callout"].pivot_offset = card["callout"].size * 0.5
		index += 1
