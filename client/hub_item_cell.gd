extends Button
## A hub item cell (shared by the character screen and the hub service panels: Blacksmith, Storage, Shop, Tailor).
## One square of the paper-doll or of the Storage grid: the leather slot tile, the real item icon (or the slot's
## shape), tier pips (1-4 diamonds, colour + count), "+N" refine, a "!" worn mark, the slot name when empty, a
## locked look, a gold "fits" frame. A Button: focus, keyboard / gamepad accept and touch.

const CardTokens := preload("res://client/card_tokens.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemIcon := preload("res://client/item_icon.gd")
signal activated()

var key := ""  ## paper-doll "slot:index", "" for storage cells
var slot_id := ""
var index := 0
var item = null
var icon_tex: Texture2D
var caption := ""
var locked := false
var fits := false
var selected := false
var low := false  ## worn down (stats reduced)
var s := 1.0
var _tile: TextureRect  ## the leather tile, its own canvas item behind the cell (not mixed with the glyph draws)

func setup() -> void:
	_tile = CardTokens.art_rect(CardTokens.HUB_SLOT)
	_tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile.show_behind_parent = true
	add_child(_tile)
	focus_mode = Control.FOCUS_ALL
	CardTokens.bare_button(self, 1.0)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	gui_input.connect(_on_input)

func show_item(p_item, rules, empty_caption: String) -> void:
	item = p_item
	caption = empty_caption
	icon_tex = ItemAssets.icon(item, rules.catalog) if item != null and rules != null else null
	low = item != null and rules != null and item.durability_ratio() < rules.durability_full_above
	tooltip_text = ""
	queue_redraw()

func _on_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		activated.emit()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_tile.texture = CardTokens.tex(CardTokens.HUB_SLOT_SELECTED if selected else CardTokens.HUB_SLOT)
	_tile.modulate = CardTokens.HUB_LOCKED if locked else CardTokens.HUB_WHITE
	var font := CardTokens.medium_font()
	if item != null:
		var bounds := rect.grow(-size.x * 0.19)
		if icon_tex != null:
			var picture := icon_tex.get_size()
			var fit := minf(bounds.size.x / picture.x, bounds.size.y / picture.y)
			var fitted := picture * fit
			draw_texture_rect(icon_tex, Rect2(bounds.get_center() - fitted * 0.5 - Vector2(0.0, size.y * 0.03), fitted), false)
		else:
			ItemIcon.draw_icon(self, bounds, ItemIcon.shape_for(item.slot, item.weapon_type), _tier_color(item.tier))
		var count: int = clampi(item.tier + 1, 1, CardTokens.HUB_TIER.size())
		var r := size.x * 0.045
		for i in count:
			var c := Vector2(size.x * 0.5 + (float(i) - float(count - 1) * 0.5) * r * CardTokens.CHAR_PIP_SPACING, size.y * 0.86)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 1.0), c + Vector2(r + 1.0, 0), c + Vector2(0, r + 1.0), c + Vector2(-r - 1.0, 0)]), CardTokens.HUB_OUTLINE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), _tier_color(item.tier))
		if item.refine_level > 0:
			var px := maxi(int(round(size.x * 0.2)), CardTokens.FONT_MIN)
			var words := "+%d" % item.refine_level
			var w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var at := Vector2(size.x * 0.9 - w, size.y * 0.1 + px * 0.8)
			draw_string_outline(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, int(px * 0.15)), CardTokens.HUB_OUTLINE)
			draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, px, CardTokens.HUB_REFINE)
		if low:  # worn down: a red disc with "!" top left (shape + colour)
			var rr := size.x * 0.1
			var cc := Vector2(size.x * 0.17, size.y * 0.17)
			draw_circle(cc, rr + 1.5, CardTokens.HUB_OUTLINE)
			draw_circle(cc, rr, CardTokens.HUB_BAR_LOW)
			var mp := maxi(int(rr * 1.7), 8)
			var mw := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, mp).x
			draw_string(font, cc + Vector2(-mw * 0.5, mp * 0.36), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, mp, CardTokens.HUB_BADGE_TEXT)
	elif not caption.is_empty():
		var px := maxi(int(round(CardTokens.FONT_CHAR_SLOT * s)), CardTokens.FONT_MIN)
		var shown := caption
		while shown.length() > 3 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x * 0.86:
			shown = shown.substr(0, shown.length() - 1)
		var w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + px * 0.35), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px, CardTokens.HUB_CREAM if locked else CardTokens.HUB_SLOT_TEXT)
	if fits:  # fits the selected slot: gold frame + a corner notch (not colour only)
		var inner := rect.grow(-size.x * 0.06)
		draw_rect(inner, CardTokens.HUB_FIT_MARK, false, maxf(2.0, 3.0 * s))
		var k := size.x * 0.22
		draw_colored_polygon(PackedVector2Array([inner.position, inner.position + Vector2(k, 0.0), inner.position + Vector2(0.0, k)]), CardTokens.HUB_FIT_MARK)
	if has_focus():
		draw_style_box(CardTokens.hub_focus(s, 12.0), rect)

static func _tier_color(tier: int) -> Color:
	return CardTokens.HUB_TIER[clampi(tier, 0, CardTokens.HUB_TIER.size() - 1)]
