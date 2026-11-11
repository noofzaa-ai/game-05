extends CanvasLayer
## The squad's info in an auto-battle fight (Boss 2026-11-10): one card per fighter at the bottom of the
## upright screen with its name, health and ultimate gauge. Nothing here can be pressed: nobody steers.

const InkUi := preload("res://client/ink_ui.gd")
const Fighter := preload("res://logic/fighter.gd")
const CARD_HEIGHT := 78.0
const MARGIN := 12.0
const GAP := 8.0
const MAX_CARD_WIDTH := 260.0
const NAMES := {"sword_shield": "Sword & Shield", "greatsword": "Great Sword", "longbow": "Longbow", "magic": "Magic"}

var _root: Control
var _cards: Dictionary = {}  ## fighter id -> {"panel", "name", "hp_fill", "hp_text", "ult_fill", "gauge_back"}
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
		card["hp_text"].text = "%d / %d" % [int(ceilf(maxf(fighter.hp, 0.0))), int(fighter.max_hp())]
		var gauge := clampf(fighter.gauge / gauge_max, 0.0, 1.0)
		card["ult_fill"].size.x = card["bar_width"] * gauge
		card["ult_fill"].color = InkUi.ULT_READY_TEXT if gauge >= 1.0 else InkUi.ULT
		card["panel"].modulate.a = 1.0 if fighter.is_alive() else 0.45


func _rebuild() -> void:
	for card in _cards.values():
		card["panel"].queue_free()
	_cards.clear()
	var index := 0
	for id in _order:
		index += 1
		var panel := ColorRect.new()
		panel.color = InkUi.HUD_PANEL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var hp_text := Label.new()
		InkUi.style_text(hp_text, InkUi.HUD_TEXT, InkUi.FONT_CAPTION)
		hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_back.add_child(hp_text)
		var ult_back := ColorRect.new()
		ult_back.color = InkUi.HUD_PANEL
		ult_back.position = Vector2(8, 56)
		ult_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ult_back)
		var ult_fill := ColorRect.new()
		ult_fill.color = InkUi.ULT
		ult_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ult_back.add_child(ult_fill)
		_cards[id] = {"panel": panel, "name": name_label, "hp_back": hp_back, "hp_fill": hp_fill, "hp_text": hp_text, "ult_back": ult_back, "ult_fill": ult_fill, "bar_width": 100.0}
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
		index += 1
