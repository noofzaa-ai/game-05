extends CanvasLayer
## The end-of-fight result in the battle (Boss phone playtest 2026-11-14): a leather + parchment plate with the
## result line and real buttons (tap, click, or focus + Enter / gamepad A) instead of printed key hints. The stage
## decides which actions a result offers and what each does (stage_view.gd _result_action); the keys stay as
## shortcuts but are never printed. Display only: no game rules here.
## Placed in the middle of the screen, below the top bars and above the squad tray (the stage hides the boss bar
## while it shows). Sizes are CardTokens reference units (1080p) scaled to the stage's logical screen.

signal action(id: String)

const CardTokens := preload("res://client/card_tokens.gd")
const HubLook := preload("res://client/hub_look.gd")

## Every word the panel shows ([th, en]; CardTokens.language picks). Kept here so the shared token file is not
## edited by two agents at once.
const TEXT := {
	"defeated": ["พ่ายแพ้ — ของในเป้ถูกส่งกลับคลังแล้ว", "Defeated — your bag was sent back to storage"],
	"journey_complete": ["จบการเดินทาง", "Journey complete"],
	"stage_clear": ["ผ่านด่าน", "Stage clear"],
	"load_failed": ["โหลดด่านนี้ไม่ได้", "This stage could not be loaded"],
	"room_closed": ["ห้องปิดหรือเชื่อมต่อไม่ได้", "The room closed or the connection was lost"],
	"continue": ["ไปต่อ", "Continue"],
	"retry": ["ลองใหม่", "Try again"],
	"play_again": ["เล่นอีกครั้ง", "Play again"],
	"camp": ["กลับแคมป์", "Back to camp"],
}
const PANEL_W := 1000.0  ## plate width (reference px); never wider than the screen minus the margins
const PAD := 36.0
const GAP := 22.0
const RIM := 8.0  ## leather around the parchment
const BUTTON := Vector2(380.0, 96.0)
const FONT_TITLE := 46
const FONT_BUTTON := 32
const TOP_KEEP := 110.0  ## logical px kept free at the top (wave banner, trip line)

var _root: Control
var _plate: Panel
var _paper: Panel
var _title: Label
var _row: HBoxContainer
var _key := ""
var _buttons: Array[Button] = []


static func text(key: String) -> String:
	var entry: Array = TEXT.get(key, [key, key])
	return str(entry[0 if CardTokens.language == "th" else 1])


func _ready() -> void:
	layer = 14  # over the squad tray (6) and the squad room HUD (13)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_plate = Panel.new()
	_plate.name = "ResultPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP  # a tap on the plate never reaches the camera
	_root.add_child(_plate)
	_paper = Panel.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_paper)
	_title = CardTokens.hub_label("", FONT_TITLE, CardTokens.HUB_INK, 1.0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_paper.add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_child(_row)
	visible = false
	get_viewport().size_changed.connect(_place)


## Shows `title_key` (a TEXT key) with one button per [id, text_key] in `actions`. Cheap to call every frame.
func show_result(title_key: String, actions: Array) -> void:
	var key := "%s|%s" % [title_key, str(actions)]
	if key == _key and visible:
		return
	_key = key
	_title.text = text(title_key)
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	for entry in actions:
		var b := Button.new()
		b.name = "Result_" + str(entry[0])
		b.text = text(str(entry[1]))
		b.focus_mode = Control.FOCUS_ALL
		var id := str(entry[0])
		b.pressed.connect(func() -> void: action.emit(id))
		_row.add_child(b)
		_buttons.append(b)
	visible = true
	_place()
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()  # keyboard / gamepad: Enter or A presses it


func hide_result() -> void:
	if visible:
		visible = false
		_key = ""


func shown() -> bool:
	return visible


## The plate in viewport pixels (Rect2() while hidden), for layout tests and the combat pop-up keep-out.
func plate_rect() -> Rect2:
	return _plate.get_global_rect() if visible else Rect2()


func buttons() -> Array[Button]:
	return _buttons


func _place() -> void:
	if _root == null or not visible:
		return
	var area := get_viewport().get_visible_rect().size
	var s := CardTokens.scale_for(area)
	var phone := CardTokens.is_phone(area)
	var margin := 24.0
	var width := minf(PANEL_W * s, area.x - margin * 2.0)
	var rim := RIM * s
	var pad := PAD * s
	var inner := width - rim * 2.0 - pad * 2.0
	CardTokens.panel(_plate, HubLook.leather(s))
	CardTokens.panel(_paper, HubLook.parchment(s))
	CardTokens.hub_text(_title, FONT_TITLE, CardTokens.HUB_INK, s)
	_title.size = Vector2(inner, 0.0)
	_title.custom_minimum_size = Vector2(inner, 0.0)
	var title_h := _title.get_combined_minimum_size().y
	var button_size := Vector2(BUTTON.x * s, CardTokens.tap(BUTTON.y, phone) * s)
	var count := _buttons.size()
	if count > 0:
		button_size.x = minf(button_size.x, (inner - GAP * s * float(count - 1)) / float(count))
	CardTokens.gap(_row, GAP, s)
	for b in _buttons:
		b.custom_minimum_size = button_size
		CardTokens.hub_plate_button(b, s)
		CardTokens.hub_fit(b, b.text, FONT_BUTTON, button_size.x - (CardTokens.HUB_PLATE_MARGINS[0] + CardTokens.HUB_PLATE_MARGINS[2]) * s, CardTokens.HUB_INK, s)
	var row_h := button_size.y if count > 0 else 0.0
	var height := rim * 2.0 + pad * 2.0 + title_h + (GAP * s + row_h if count > 0 else 0.0)
	# Middle of the free band: under the top bars, over the squad tray at the bottom.
	var tray := CardTokens.SQUAD_HUD_CARD.y + CardTokens.SQUAD_HUD_MARGIN + CardTokens.SQUAD_HUD_CALLOUT_H + 12.0
	var top := TOP_KEEP
	var bottom := area.y - tray
	var y := clampf(top + (bottom - top - height) * 0.5, margin, maxf(margin, area.y - margin - height))
	_plate.position = Vector2((area.x - width) * 0.5, y)
	_plate.size = Vector2(width, height)
	_paper.position = Vector2(rim, rim)
	_paper.size = _plate.size - Vector2(rim, rim) * 2.0
	_title.position = Vector2(pad, pad)
	_title.size = Vector2(inner, title_h)
	_row.position = Vector2(pad, pad + title_h + GAP * s)
	_row.size = Vector2(inner, row_h)
