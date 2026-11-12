extends Panel
## The pinned item details of the hub screens (docs/ui/hub_layout_spec.md §4), shared by the card character screen
## and the hub service panels (Blacksmith, Storage, Shop): the item cell, name + refine, slot · tier, main stat
## (with the refine share), substats, an optional "vs worn" compare row, the durability bar with its number, a
## cost line and a row of action buttons the owner fills (add_action). Display only: it never sends commands.
## Every colour, size and word comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const HubItemCell := preload("res://client/hub_item_cell.gd")
const ItemText := preload("res://client/item_text.gd")
const HubLook := preload("res://client/hub_look.gd")

var s := 1.0
var cell: HubItemCell
var title: Label
var sub: Label
var main_line: Label
var subs: Label
var compare: HBoxContainer
var dur_key: Label
var dur_back: Panel
var dur_fill: Panel
var dur_text: Label
var cost: Label
var actions: HBoxContainer
var _ratio := 1.0
var _low := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell = HubItemCell.new()
	cell.setup()
	cell.focus_mode = Control.FOCUS_NONE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.selected = true
	add_child(cell)
	title = CardTokens.label("", CardTokens.FONT_CHAR_ITEM, CardTokens.HUB_INK, 1.0)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title)
	sub = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_SUBTEXT, 1.0, 0, "medium")
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(sub)
	main_line = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	main_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(main_line)
	subs = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	subs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subs.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(subs)
	compare = HBoxContainer.new()
	compare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compare)
	dur_key = CardTokens.label(CardTokens.t("durability"), CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium")
	add_child(dur_key)
	dur_back = Panel.new()
	dur_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dur_back)
	dur_fill = Panel.new()
	dur_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dur_back.add_child(dur_fill)
	dur_text = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	add_child(dur_text)
	cost = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium")
	cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(cost)
	actions = HBoxContainer.new()
	add_child(actions)


## Places everything inside a w x h box; `button_h` is the action row height (already a tap size).
## `wide` = true puts the cost line right of the durability number (wide boxes), false under it.
func layout_box(w: float, h: float, button_h: float, p_s: float, wide: bool = true) -> void:
	s = p_s
	size = Vector2(w, h)
	CardTokens.panel(self, CardTokens.hub_box(CardTokens.HUB_DETAIL_BACK, CardTokens.HUB_DETAIL_EDGE, 3.0, 18.0, s))
	var pad := CardTokens.CHAR_PAD * s
	var line := CardTokens.FONT_CHAR_LINE * 1.3 * s
	var icon := minf(CardTokens.CHAR_DETAIL_ICON * s, h - button_h - pad * 3.0 - (0.0 if wide else line))
	icon = maxf(icon, CardTokens.CHAR_STORE_CELL * s * 0.8)
	cell.s = s
	cell.position = Vector2(pad, pad)
	cell.size = Vector2(icon, icon)
	var tx := pad * 2.0 + icon
	var tw := w - tx - pad
	var y := pad * 0.6
	for pair in [[title, CardTokens.FONT_CHAR_ITEM, 1.45], [sub, CardTokens.FONT_CHAR_LINE, 1.5], [main_line, CardTokens.FONT_CHAR_LINE, 1.5]]:
		var l: Label = pair[0]
		l.position = Vector2(tx, y)
		l.size = Vector2(tw, float(pair[1]) * float(pair[2]) * s)
		y += l.size.y
	CardTokens.hub_text(title, CardTokens.FONT_CHAR_ITEM, CardTokens.HUB_INK, s)
	CardTokens.hub_text(sub, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_SUBTEXT, s, 0, "medium")
	CardTokens.hub_text(main_line, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, s, 0, "medium")
	subs.position = Vector2(tx, y)
	subs.size = Vector2(tw, line)
	CardTokens.hub_text(subs, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
	compare.position = Vector2(tx, y + subs.size.y)
	compare.size = Vector2(tw, line)
	CardTokens.gap(compare, 12.0, s)
	var bar_y := maxf(pad + icon + pad * 0.5, compare.position.y + compare.size.y)
	var key_w := 130.0 * s
	dur_key.position = Vector2(pad, bar_y)
	dur_key.size = Vector2(key_w, CardTokens.CHAR_BAR_H * s * 1.4)
	CardTokens.hub_text(dur_key, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	dur_back.position = Vector2(pad + key_w, bar_y + CardTokens.CHAR_BAR_H * s * 0.2)
	dur_back.size = Vector2(minf(370.0 * s, w * 0.4), CardTokens.CHAR_BAR_H * s)
	CardTokens.panel(dur_back, CardTokens.hub_bar(CardTokens.HUB_BAR_BACK, s))
	dur_text.position = Vector2(dur_back.position.x + dur_back.size.x + pad, bar_y)
	dur_text.size = Vector2(140.0 * s, dur_key.size.y)
	CardTokens.hub_text(dur_text, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
	if wide:
		cost.position = Vector2(dur_text.position.x + dur_text.size.x, bar_y)
	else:
		cost.position = Vector2(pad, bar_y + dur_key.size.y)
	cost.size = Vector2(maxf(w - cost.position.x - pad, 0.0), dur_key.size.y)
	CardTokens.hub_text(cost, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	_fit_title()
	actions.position = Vector2(pad, h - pad * 0.7 - button_h)
	actions.size = Vector2(w - pad * 2.0, button_h)
	CardTokens.gap(actions, 18.0, s)
	_draw_bar()


## No piece: the slot / prompt in the title and up to three short lines.
func show_empty(heading: String, line_sub: String, line_main: String, line_subs: String, caption: String = "", locked: bool = false) -> void:
	clear_actions()
	cell.show_item(null, null, caption)
	cell.locked = locked
	for node in [dur_key, dur_back, dur_text, cost]:
		node.visible = false
	title.text = heading
	_fit_title()
	sub.text = line_sub
	main_line.text = line_main
	subs.text = line_subs


## A piece: name + refine, slot · tier, main stat (refine share), substats, durability.
func show_item(item, rules) -> void:
	clear_actions()
	cell.show_item(item, rules, "")
	cell.locked = false
	for node in [dur_key, dur_back, dur_text, cost]:
		node.visible = true
	title.text = item_name(item, rules) + ("  +%d" % item.refine_level if item.refine_level > 0 else "")
	_fit_title()
	var tier_id := str(rules.tiers[clampi(item.tier, 0, rules.tiers.size() - 1)]["id"])
	sub.text = "%s  ·  %s  %s" % [CardTokens.slot_name(item.slot), CardTokens.t("tier_" + tier_id), "◆".repeat(item.tier + 1)]
	var factor: float = rules.durability_factor(item.durability_ratio())
	var main: float = item.main_value(rules) * factor
	var refine_part: float = item.base_value(rules) * float(rules.refine.get("bonus_per_level", 0.0)) * float(item.refine_level) * factor
	var stat_label := str(ItemText.STAT_LABELS.get(item.main_stat, item.main_stat))
	main_line.text = "%s  %s" % [stat_label, num(main)] + ("  " + CardTokens.t("refine_share") % num(refine_part) if refine_part > 0.0 else "")
	var lines: Array[String] = []
	for n in item.substats.size():
		lines.append(ItemText.substat_text(item, rules, n))
	subs.text = "  ·  ".join(lines)
	_ratio = item.durability_ratio()
	_low = _ratio < rules.durability_full_above
	_draw_bar()
	dur_text.text = CardTokens.t("durability_of") % [int(round(item.durability)), int(round(item.max_durability))]
	cost.text = ""


## The "vs worn" row (green up / red down arrows + signed numbers, not colour only). `old` null = an empty slot.
func fill_compare(item, old, rules) -> void:
	for child in compare.get_children():
		compare.remove_child(child)
		child.queue_free()
	var head := CardTokens.label(CardTokens.t("vs_worn"), CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_TAB_IDLE, s, 0, "medium")
	compare.add_child(head)
	if old == null:
		head.text += " " + CardTokens.t("vs_empty")
		return
	var a: Dictionary = item.stat_totals(rules)
	var b: Dictionary = old.stat_totals(rules)
	var shown := 0
	for stat in rules.stat_ids:
		var d := float(a.get(stat, 0.0)) - float(b.get(stat, 0.0))
		if absf(d) < 0.05 or shown >= 4:
			continue
		var up := d > 0.0
		var words := "%s %s%s" % [ItemText.STAT_LABELS.get(stat, stat), "▲ +" if up else "▼ ", num(d)]
		compare.add_child(CardTokens.label(words, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_GOOD if up else CardTokens.HUB_BAD, s, 0, "medium"))
		shown += 1


func clear_actions() -> void:
	for box in [actions, compare]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()


## The title (an item name can be long): shrink to FONT_MIN on one line, then "…" (the box has one title line).
func _fit_title() -> void:
	if title.size.x <= 0.0:
		return
	var full: String = title.get_meta("full_text", "") if title.text.ends_with("…") else title.text
	title.set_meta("full_text", full)
	HubLook.fit(title, full, CardTokens.FONT_CHAR_ITEM, title.size.x, CardTokens.HUB_INK, s, 1)


## One parchment plate button in the action row (fills the row; the row height is the tap size).
func add_action(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, actions.size.y)
	b.clip_text = true
	CardTokens.hub_plate_button(b, s)
	CardTokens.hub_text(b, CardTokens.FONT_CHAR_BUTTON, CardTokens.HUB_INK, s)
	b.pressed.connect(callback)
	actions.add_child(b)
	fit_buttons(actions, s)
	return b


## Shrinks the labels of a row of plate buttons so each fits its share of the row (the plate's arrow tip excluded).
static func fit_buttons(row: Container, p_s: float, columns: int = 0) -> void:
	var n := columns if columns > 0 else maxi(row.get_child_count(), 1)
	var gap := 18.0 * p_s
	# The plate art's 9-slice margins (left + arrow tip) were content margins in unscaled art px: on a small screen
	# they ate the whole label ("To vau", "Discar"). Scale them with the layout so the text keeps its room.
	var left := CardTokens.HUB_PLATE_MARGINS[0] * minf(p_s, 1.0)
	var right := CardTokens.HUB_PLATE_MARGINS[2] * minf(p_s, 1.0)
	var w := (row.size.x - gap * float(n - 1)) / float(n) - left - right - 8.0 * p_s
	for child in row.get_children():
		var b := child as Button
		if b == null:
			continue
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			var box := b.get_theme_stylebox(state) as StyleBoxTexture
			if box != null:
				box.content_margin_left = left
				box.content_margin_right = right
		var full: String = b.get_meta("full_text", b.text)
		b.set_meta("full_text", full)
		var vertical := CardTokens.HUB_PLATE_MARGINS[1] * 2.0 * minf(p_s, 1.0)
		var fitted := HubLook.fit(b, full, CardTokens.FONT_CHAR_BUTTON, w, CardTokens.HUB_INK, p_s, CardTokens.FIT_MAX_LINES)
		if int(fitted["lines"]) > 1 and HubLook.lines_height(int(fitted["lines"]), int(fitted["px"])) > row.size.y - vertical:
			HubLook.fit(b, full, CardTokens.FONT_CHAR_BUTTON, w, CardTokens.HUB_INK, p_s, 1)  # no room for 2 lines: "…"


func _draw_bar() -> void:
	dur_fill.size = Vector2(dur_back.size.x * _ratio, dur_back.size.y)
	CardTokens.panel(dur_fill, CardTokens.hub_bar(CardTokens.HUB_BAR_LOW if _low else CardTokens.HUB_BAR_FILL, s))


## The catalog name of a piece (English when the catalog has it), else its slot name.
static func item_name(item, rules) -> String:
	if item == null:
		return ""
	var entry: Dictionary = rules.catalog.entry(item.item_id)
	return str(entry.get("name", CardTokens.slot_name(item.slot)))


static func num(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return str(int(roundf(value)))
	return String.num(snappedf(value, 0.1), 1)


## "100 gold, 2 Ore" for a {gold, materials} cost ("free" when nothing).
static func cost_text(cost_value: Dictionary, camp) -> String:
	var parts: Array[String] = []
	if int(cost_value.get("gold", 0)) > 0:
		parts.append(CardTokens.t("cost_gold") % int(cost_value["gold"]))
	var needed: Dictionary = cost_value.get("materials", {})
	for id in needed:
		parts.append("%d %s" % [int(needed[id]), str(camp.materials.get(id, {}).get("name", id)) if camp != null else str(id)])
	return CardTokens.t("cost_free") if parts.is_empty() else ", ".join(parts)
