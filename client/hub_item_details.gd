extends Panel
## The pinned item details of the hub screens (docs/ui/hub_layout_spec.md §4), shared by the card character screen
## and the hub service panels (Blacksmith, Storage, Shop): the item cell, name + refine, slot · tier, main stat
## (with the refine share), substats, an optional "vs worn" compare row, the durability bar with its number, a
## cost line and a row of action buttons the owner fills (add_action). Display only: it never sends commands.
## Every colour, size and word comes from client/card_tokens.gd.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")  ## the carved ink-wash look (Boss 2026-11-14)
const HubItemCell := preload("res://client/hub_item_cell.gd")
const ItemText := preload("res://client/item_text.gd")
const HubLook := preload("res://client/hub_look.gd")
const BossLoot := preload("res://logic/boss_loot.gd")
const BrassIcons := preload("res://client/brass_icons.gd")

var s := 1.0
var cell: HubItemCell
var title: Label
var sub: Label
var level_tag: Label  ## "Lv 15", right end of the sub line; warning colour when the card is below it
var _tag_color := CardTokens.HUB_SUBTEXT
var main_line: Label
var subs: Label
var compare: HBoxContainer
var dur_key: Label
var dur_back: Panel
var dur_fill: Panel
var dur_text: Label
var cost: Label
var actions: HBoxContainer
var socket_row: HBoxContainer  ## boss-loot.md 2: the Relic socket (icon + effect, or "empty"); hidden without a socket
var socket_icon: TextureRect
var socket_text: Label
var boss_line: Label  ## the boss option of a boss-drop piece (Boss 2026-11-21), boss gold; hidden for other pieces
var _boss := false  ## the shown piece is a boss-drop piece: title in boss gold
var _pad := 0.0
var _icon := 0.0
var _ratio := 1.0
var _low := false
var _wide := true
var _text_x := 0.0
var _text_w := 0.0
var _line := 0.0
var _cost_full := ""
var _button_h := 0.0
var _cost_y := 0.0
var _cost_h := 0.0


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
	level_tag = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_SUBTEXT, 1.0, 0, "medium")
	level_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_tag.visible = false
	add_child(level_tag)
	main_line = CardTokens.label("", CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK, 1.0, 0, "medium")
	main_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(main_line)
	subs = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	subs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subs.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(subs)
	boss_line = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_BOSS_TEXT, 1.0, 0, "medium")
	boss_line.visible = false
	add_child(boss_line)
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
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cost)
	actions = HBoxContainer.new()
	add_child(actions)
	socket_row = HBoxContainer.new()
	socket_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	socket_row.visible = false
	add_child(socket_row)
	socket_icon = TextureRect.new()
	socket_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	socket_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	socket_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	socket_row.add_child(socket_icon)
	socket_text = CardTokens.label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	socket_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	socket_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	socket_row.add_child(socket_text)


## Places everything inside a w x h box; `button_h` is the action row height (already a tap size).
## `wide` = true puts the cost line right of the durability number (wide boxes), false under it.
func layout_box(w: float, h: float, button_h: float, p_s: float, wide: bool = true) -> void:
	s = p_s
	size = Vector2(w, h)
	CarvedLook.inset(self, s)
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
	_wide = wide
	_button_h = button_h
	_text_x = tx
	_text_w = tw
	_place_level_tag()
	_line = line
	_pad = pad
	_icon = icon
	_place_lower()
	actions.position = Vector2(pad, h - pad * 0.7 - button_h)
	actions.size = Vector2(w - pad * 2.0, button_h)
	CardTokens.gap(actions, 18.0, s)
	_draw_bar()


## Everything under the substats: the boss option line (boss-drop pieces only), the "vs worn" row, durability, cost,
## socket. Re-run when the boss line appears or goes (show_item / show_empty), so it never overlaps the bar.
func _place_lower() -> void:
	if _line <= 0.0:
		return
	var w := size.x
	var pad := _pad
	var tx := _text_x
	var tw := _text_w
	var line := _line
	var y := subs.position.y + subs.size.y
	if boss_line.visible and not subs.text.is_empty():  # substats can wrap (phone): the boss line goes under their real height
		y = subs.position.y + maxf(subs.size.y, float(subs.get_line_count()) * float(subs.get_line_height()))
	boss_line.position = Vector2(tx, y)
	boss_line.size = Vector2(tw, line)
	if boss_line.visible:  # one line when it fits, else two (phone): never clipped
		var fitted := HubLook.fit(boss_line, str(boss_line.get_meta("full_text", boss_line.text)), CardTokens.FONT_CHAR_SLOT, tw, CardTokens.HUB_BOSS_TEXT, s, 2, "medium")
		boss_line.size.y = maxf(line, HubLook.lines_height(int(fitted["lines"]), int(fitted["px"])))
		y += boss_line.size.y
	compare.position = Vector2(tx, y)
	compare.size = Vector2(tw, line)
	CardTokens.gap(compare, 12.0, s)
	var bar_y := maxf(pad + _icon + pad * 0.5, compare.position.y + compare.size.y)
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
	if _wide:
		cost.position = Vector2(dur_text.position.x + dur_text.size.x, bar_y)
	else:
		cost.position = Vector2(pad, bar_y + dur_key.size.y)
	cost.size = Vector2(maxf(w - cost.position.x - pad, 0.0), dur_key.size.y)
	_cost_y = cost.position.y
	_cost_h = cost.size.y
	_fit_cost()
	_place_socket()
	_fit_title()


## No piece: the slot / prompt in the title and up to three short lines.
func show_empty(heading: String, line_sub: String, line_main: String, line_subs: String, caption: String = "", locked: bool = false) -> void:
	clear_actions()
	cell.show_item(null, null, caption)
	cell.locked = locked
	for node in [dur_key, dur_back, dur_text, cost]:
		node.visible = false
	socket_row.visible = false
	_set_boss("")
	title.text = heading
	_fit_title()
	sub.text = line_sub
	CardTokens.hub_text(sub, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_SUBTEXT, s, 0, "medium")
	level_tag.visible = false
	_place_level_tag()
	main_line.text = line_main
	subs.text = line_subs


## Shows the "Lv N" tag of `item` (also for the Shop preview, which has no full piece line).
func show_level(item, rules) -> void:
	level_tag.text = CardTokens.item_level_label(item, rules.catalog)
	level_tag.visible = true
	_tag_color = CardTokens.HUB_BAD if CardTokens.item_level_low(item, rules.catalog, cell.viewed_card_level()) else (CardTokens.HUB_BOSS_TEXT if _boss else CardTokens.HUB_SUBTEXT)
	_place_level_tag()


## Gives the level tag the right end of the sub line (and takes the same room from the sub text) while it is shown.
func _place_level_tag() -> void:
	var tag_w := 96.0 * s
	if not level_tag.visible:
		sub.size.x = _text_w
		return
	level_tag.size = Vector2(tag_w, sub.size.y)
	level_tag.position = Vector2(_text_x + _text_w - tag_w, sub.position.y)
	CardTokens.hub_text(level_tag, CardTokens.FONT_CHAR_LINE, _tag_color, s, 0, "medium")
	sub.size.x = _text_w - tag_w


## A piece: name + refine, slot · tier, main stat (refine share), substats, durability.
func show_item(item, rules) -> void:
	clear_actions()
	cell.show_item(item, rules, "")
	cell.locked = false
	for node in [dur_key, dur_back, dur_text, cost]:
		node.visible = true
	_set_boss(ItemText.boss_option_text(str(item.item_id)) if ItemText.is_boss_piece(str(item.item_id), rules) else "", ItemText.is_boss_piece(str(item.item_id), rules))
	title.text = item_name(item, rules) + ("  +%d" % item.refine_level if item.refine_level > 0 else "")
	_fit_title()
	var shown: int = ItemText.shown_tier(item, rules)  # a boss-drop piece shows the top tier (Boss 2026-11-21)
	var tier_id := str(rules.tiers[shown]["id"])
	sub.text = "%s  ·  %s  %s" % [CardTokens.slot_name(item.slot), CardTokens.t("tier_" + tier_id), "◆".repeat(shown + 1)]
	CardTokens.hub_text(sub, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_BOSS_TEXT if _boss else CardTokens.HUB_SUBTEXT, s, 0, "medium")
	# Boss 2026-11-16: the item level is always shown ("Lv 1" for starter pieces) in its own tag at the end of the line;
	# the diamonds are dropped when the line would not fit beside it.
	show_level(item, rules)
	var font := sub.get_theme_font("font")
	var px := sub.get_theme_font_size("font_size")
	if font.get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > sub.size.x:
		sub.text = "%s  ·  %s" % [CardTokens.slot_name(item.slot), CardTokens.t("tier_" + tier_id)]
	var factor: float = rules.durability_factor(item.durability_ratio())
	var main: float = item.main_value(rules) * factor
	var refine_part: float = item.base_value(rules) * float(rules.refine.get("bonus_per_level", 0.0)) * float(item.refine_level) * factor
	var stat_label := str(ItemText.STAT_LABELS.get(item.main_stat, item.main_stat))
	var level_mul: float = rules.catalog.main_stat_mul(item.item_id, item.id)
	main_line.text = "%s  %s" % [stat_label, num(main)] + ("  " + CardTokens.t("main_mul") % num(level_mul) if level_mul != 1.0 else "") + ("  " + CardTokens.t("refine_share") % num(refine_part) if refine_part > 0.0 else "")
	var lines: Array[String] = []
	for n in item.substats.size():
		lines.append(ItemText.substat_text(item, rules, n))
	subs.text = "  ·  ".join(lines)
	_place_lower()  # the boss line sits under the (possibly wrapped) substats
	_ratio = item.durability_ratio()
	_low = _ratio < rules.durability_full_above
	_draw_bar()
	dur_text.text = CardTokens.t("durability_of") % [int(round(item.durability)), int(round(item.max_durability))]
	set_cost("")
	show_socket(item, rules)


## The Relic socket of `item` (boss set pieces and legendary items): the socketed Relic's icon + effect text, or an
## empty socket. Items without a socket hide the row. The owner adds the Socket / Remove buttons (it sends commands).
func show_socket(item, rules) -> void:
	socket_row.visible = item != null and rules != null and BossLoot.has_socket(rules, item)
	if socket_row.visible:
		if item.relic.is_empty():
			socket_icon.texture = BrassIcons.texture("ultimate", 48, CardTokens.HUB_TAB_IDLE)
			socket_text.text = CardTokens.t("relic_empty")
		else:
			var info: Dictionary = rules.catalog.relics.get(item.relic, {})
			socket_icon.texture = relic_icon(rules, item.relic)
			socket_text.text = CardTokens.t("relic_in") % str(info.get("text", info.get("name", item.relic)))
	_place_socket()


## The Relic id the player can socket (the first one in the stash, by id), "" when none.
static func owned_relic(profile, rules) -> String:
	if profile == null or rules == null:
		return ""
	var ids: Array = rules.catalog.relics.keys()
	ids.sort()
	for id in ids:
		if profile.stash.material_count(str(id)) > 0:
			return str(id)
	return ""


## Adds the socket action of a socketable `item`: "Remove Relic" when one is in, else "Socket Relic" (disabled, with a
## reason, when the player has none). The owner's callbacks send relic_socket / relic_unsocket.
func add_socket_action(item, rules, profile, on_socket: Callable, on_unsocket: Callable) -> Button:
	if item == null or rules == null or not BossLoot.has_socket(rules, item):
		return null
	var relic := owned_relic(profile, rules)
	var empty: bool = item.relic.is_empty()
	var text := CardTokens.t("relic_socket_btn" if empty else "relic_unsocket_btn")
	var callback := on_socket.bind(item.id, relic) if empty else on_unsocket.bind(item.id)
	var b: Button
	if _wide:
		b = add_action(text, callback)
	else:  # narrow boxes have room: the button sits at the end of the socket row (the action row keeps its labels)
		b = Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(socket_row.size.x * 0.32, _button_h)
		CarvedLook.plate_button(b, s)
		b.pressed.connect(callback)
		socket_row.add_child(b)
		HubLook.fit(b, text, CardTokens.FONT_CHAR_BUTTON, CarvedLook.plate_room(b.custom_minimum_size), CardTokens.HUB_INK, s, 1)
	b.disabled = empty and relic.is_empty()
	b.tooltip_text = CardTokens.t("relic_none_owned") if b.disabled else ""
	return b


## The painted icon of a Relic (catalog icon_path), else the brass "ultimate" mark.
static func relic_icon(rules, relic_id: String) -> Texture2D:
	var path := str(rules.catalog.relics.get(relic_id, {}).get("icon_path", "")) if rules != null else ""
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return BrassIcons.texture("ultimate", 48, CardTokens.HUB_INK)


## Wide boxes: the socket sits right of the main stat line (that line gives up half its width); narrow boxes (Storage,
## Shop, Blacksmith have room below): its own line under the durability / cost lines, full width.
func _place_socket() -> void:
	if socket_row == null or _text_w <= 0.0:
		return
	main_line.size.x = _text_w * 0.5 if socket_row.visible and _wide else _text_w
	var h := _line if _wide else maxf(_line, _button_h)
	if _wide:
		socket_row.position = Vector2(_text_x + _text_w * 0.52, main_line.position.y)
		socket_row.size = Vector2(_text_w * 0.48, h)
	else:
		var x := dur_key.position.x
		socket_row.position = Vector2(x, maxf(cost.position.y + cost.size.y, dur_key.position.y + dur_key.size.y) + _line * 0.3)
		socket_row.size = Vector2(size.x - x * 2.0, h)
	socket_icon.custom_minimum_size = Vector2.ONE * minf(h, _line * 1.4)
	CardTokens.gap(socket_row, 6.0, s)
	if socket_row.visible:
		HubLook.fit(socket_text, socket_text.get_meta("full_text", socket_text.text) if socket_text.text.ends_with("…") else socket_text.text,
			CardTokens.FONT_CHAR_SLOT, socket_row.size.x - socket_icon.custom_minimum_size.x - 12.0 * s - (0.0 if _wide else socket_row.size.x * 0.32), CardTokens.HUB_INK, s, 1, "medium")
		socket_text.set_meta("full_text", socket_text.text if not socket_text.text.ends_with("…") else socket_text.get_meta("full_text", socket_text.text))


## The cost line: one line when it fits (shrinking to FONT_MIN), else its "  ·  " parts on two lines (the repair cost
## used to end in "…"). Use this instead of setting cost.text.
func set_cost(text: String) -> void:
	_cost_full = text
	_fit_cost()
	_place_socket()


func _fit_cost() -> void:
	cost.text = _cost_full
	if _cost_h <= 0.0 or cost.size.x <= 0.0:
		return
	cost.position.y = _cost_y
	cost.size.y = _cost_h
	var one := HubLook.fit(cost, _cost_full, CardTokens.FONT_CHAR_SLOT, cost.size.x, CardTokens.HUB_TAB_IDLE, s, 1, "medium")
	if not str(one["text"]).ends_with("…") or not _cost_full.contains("  ·  "):
		return
	var parts := _cost_full.split("  ·  ")
	var px := 9999
	for part in parts:
		px = mini(px, int(HubLook.fit_text(part, CardTokens.FONT_CHAR_SLOT, cost.size.x, s, 1, "medium")["px"]))
	var lines: Array = []
	for part in parts:
		lines.append(str(HubLook.fit_text(part, px, cost.size.x, 1.0, 1, "medium")["text"]))
	CardTokens.style_text(cost, px, CardTokens.HUB_TAB_IDLE, 1.0, 0, "medium", CardTokens.HUB_OUTLINE)
	cost.text = "\n".join(lines)
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tall := HubLook.lines_height(lines.size(), px)
	cost.position.y = _cost_y - maxf(tall - _cost_h, 0.0) * 0.5  # centred on the durability row
	cost.size.y = maxf(tall, _cost_h)


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


## A one-line reason beside the buttons (why one is off): red, first in the "vs worn" row, which then keeps only the stats.
func set_note(text: String, replace_compare: bool = false) -> void:
	if text.is_empty() or compare == null:
		return
	if replace_compare:  # the "vs worn" row has no room beside a reason (844x390): the reason takes the row
		for child in compare.get_children():
			compare.remove_child(child)
			child.queue_free()
	var note := CardTokens.label(text, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_BAD, s, 0, "medium")
	note.name = "Note"
	note.clip_text = true
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	compare.add_child(note)


func clear_actions() -> void:
	for box in [actions, compare]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if socket_row != null:
		for child in socket_row.get_children():
			if child is Button:
				socket_row.remove_child(child)
				child.queue_free()


## The title (an item name can be long): shrink to FONT_MIN on one line, then "…" (the box has one title line).
func _fit_title() -> void:
	if title.size.x <= 0.0:
		return
	var full: String = title.get_meta("full_text", "") if title.text.ends_with("…") else title.text
	title.set_meta("full_text", full)
	HubLook.fit(title, full, CardTokens.FONT_CHAR_ITEM, title.size.x, CardTokens.HUB_BOSS_TEXT if _boss else CardTokens.HUB_INK, s, 1)


## Boss-drop piece look (Boss 2026-11-21): the title in boss gold and the boss option line under the substats.
## `option` "" hides the line. Re-places the lower rows.
func _set_boss(option: String, is_boss: bool = false) -> void:
	_boss = is_boss
	boss_line.visible = not option.is_empty()
	boss_line.text = option
	boss_line.set_meta("full_text", option)
	_place_lower()


## One parchment plate button in the action row (fills the row; the row height is the tap size).
func add_action(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, actions.size.y)
	b.clip_text = true
	b.size = Vector2(b.size.x, actions.size.y)
	CarvedLook.plate_button(b, s)
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
	# Carved plaques (carved_look.gd): the caps scale with the button height; the text keeps clear of them.
	var cell_w := (row.size.x - gap * float(n - 1)) / float(n)
	var w := CarvedLook.plate_room(Vector2(cell_w, row.size.y if row.size.y > 0.0 else CardTokens.CHAR_ACTION_H * p_s))
	for child in row.get_children():
		var b := child as Button
		if b == null:
			continue
		var full: String = b.get_meta("full_text", b.text)
		b.set_meta("full_text", full)
		var vertical := 8.0 * p_s
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
