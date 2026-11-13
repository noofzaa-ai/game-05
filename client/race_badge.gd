extends Panel
## The race mockup badge (design/gdd/races-and-classes.md 3.8): a rounded plate in the race colour with its letter
## ("H", "V", "E", "R"). Colours and letters come from the race file's `mockup` block through client/card_tokens.gd.
## Used on the hub cards, the squad tray slots, the synergy line, the character screen race button and the race picker.
## Display only. Until the Studio emblems exist this is the whole race look on cards (3.8 real-art row replaces it).

const CardTokens := preload("res://client/card_tokens.gd")

var race := ""
var _letter: Label
var _edge := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letter = Label.new()
	_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_letter)


## Shows `race_id` as a square badge of `edge` screen px (top-left stays where it is). "" hides it.
func show_race(race_id: String, edge: float) -> void:
	visible = not race_id.is_empty()
	if race_id.is_empty():
		race = ""
		return
	size = Vector2(edge, edge)
	custom_minimum_size = size
	if race_id == race and is_equal_approx(edge, _edge):
		return
	race = race_id
	_edge = edge
	CardTokens.panel(self, CardTokens.race_badge_box(race_id, edge))
	_letter.text = CardTokens.race_letter(race_id)
	CardTokens.race_badge_text(_letter, race_id, edge)
	tooltip_text = CardTokens.race_name(race_id)
