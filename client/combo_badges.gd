extends Control
## Skill combo badges (client/combo_ui.gd): "Sets [icons]  Pays off [icons]" in one row. Display only.
const ComboUiRef := preload("res://client/combo_ui.gd")
const CardTokens := preload("res://client/card_tokens.gd")

var skill := ""
var data = null
var s := 1.0
var font_size := 18
var ink := Color("3A2414")
var _parts: Array = []  ## [{"kind": "text"|"icon", ...}]

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_skill(id: String, scale: float = 1.0) -> void:
	skill = id
	s = scale
	_parts.clear()
	var b := ComboUiRef.badges_for(id, data)
	var sets: Array = b["sets"]
	var pays: Array = ComboUiRef.payoff_states(id, data)
	if not sets.is_empty():
		_parts.append({"kind": "text", "text": ComboUiRef.t("sets")})
		for st in sets:
			_parts.append({"kind": "icon", "state": st})
	if not pays.is_empty():
		if not sets.is_empty():
			_parts.append({"kind": "gap"})
		_parts.append({"kind": "text", "text": ComboUiRef.t("payoff")})
		for st in pays:
			_parts.append({"kind": "icon", "state": st})
	visible = not _parts.is_empty()
	custom_minimum_size = Vector2(_w(), _h())
	queue_redraw()

func _w() -> float:
	var font := CardTokens.medium_font()
	var fs := maxi(int(font_size * s), CardTokens.FONT_MIN)
	var r := _h() * 0.36
	var x := 0.0
	for p in _parts:
		match p["kind"]:
			"text": x += (font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 40.0) + r * 0.6
			"icon": x += r * 2.5
			"gap": x += r * 1.2
	return x


func _h() -> float:
	return maxf(font_size * s * 1.5, 16.0)

func _draw() -> void:
	var font := CardTokens.medium_font()
	var h := _h()
	var fs := maxi(int(font_size * s), CardTokens.FONT_MIN)
	var r := h * 0.36
	var x := 0.0
	for p in _parts:
		match p["kind"]:
			"text":
				if font != null:
					draw_string(font, Vector2(x, h * 0.5 + fs * 0.35), p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
					x += font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + r * 0.6
			"icon":
				ComboUiRef.draw_state_icon(self, Vector2(x + r, h * 0.5), r, p["state"], data)
				x += r * 2.5
			"gap":
				x += r * 1.2
