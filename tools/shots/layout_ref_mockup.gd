extends SceneTree
## PHASE 1 mockup for the Boss's 2026-10-12 layout request (docs/design/layout_ref_2026-10-12.md).
## Composes, from our real theme tokens only (client/ink_ui.gd + client/brass_icons.gd, D Night
## Brass), a static picture of:
##   camp_<size>.png   three panels side by side: STATUS | DOLL+SLOTS | STASH (wide), collapsing to
##                     one-at-a-time with a tab strip on phone sizes
##   hud_<size>.png    the fight HUD framed like the reference (name+level, HP/STAMINA/ULT bars with
##                     brass caps, a currency row, a centred skill row), middle 40% kept free
## This DOES NOT touch the real screens (gear_panel.gd / hud.gd / camp_screen.gd). It is placeholder
## data so the Boss can judge the composition before we wire anything. All colours, sizes, gaps,
## boxes and icons come from InkUi; no raw Color / font size / stylebox is set here (style guide §1).
## Needs a window (run WITHOUT --headless):
##   <godot> --path . --script res://tools/shots/layout_ref_mockup.gd -- <out_dir>

const InkUi := preload("res://client/ink_ui.gd")
const UiThemes := preload("res://client/ui_themes.gd")
const BrassIcons := preload("res://client/brass_icons.gd")

## wide desktop (1600x900), a true phone-landscape (height < 560 -> compact: panels collapse to a
## tab strip, HUD drawn x1.8), and phone portrait. Touch targets are >= 44 in menu units everywhere.
const SIZES := {
	"wide": Vector2i(1600, 900),
	"phone_landscape": Vector2i(1280, 540),
	"portrait": Vector2i(560, 1180),
}

var _root: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://ui_layout_ref"
	if not ("/" in out or "\\" in out or ":" in out):
		push_error("layout_ref_mockup: give the output folder (a path) first")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	UiThemes.apply("brass")  # the live look + a desktop serif standing in for the display font

	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _show(_build_camp(SIZES[size_name]))
		await _save(out.path_join("camp_%s.png" % size_name))
		await _show(await _build_hud(SIZES[size_name]))
		await _save(out.path_join("hud_%s.png" % size_name))
	quit()


## Replaces whatever is on screen with `node` under a themed, scaled root, over a mock 3D backdrop.
func _show(node: Control) -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_root)
	await process_frame
	var backdrop := _world_backdrop()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var scrim := ColorRect.new()
	scrim.color = InkUi.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(node)


func _layout(size: Vector2i) -> Dictionary:
	return InkUi.layout_for(Vector2(size), Vector2(size), 1.0)


## A themed Control filling the whole viewport. We lay the mockup out at the real window size (what a
## desktop/phone screen actually shows) rather than inside a down-scaled design canvas, so the window
## always fills its space and nothing clips. layout_for() is still called (via _layout) to pick the
## mode and set the phone-safe engraved-line thickness.
func _scaled(size: Vector2i) -> Control:
	var lay := _layout(size)
	var holder := Control.new()
	holder.theme = InkUi.make_theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inner := Control.new()
	inner.name = "Inner"
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(inner)
	holder.set_meta("mode", lay["mode"])
	holder.set_meta("inner", inner)
	return holder


# ============================================================= CAMP: three panels

func _build_camp(size: Vector2i) -> Control:
	var holder := _scaled(size)
	var inner: Control = holder.get_meta("inner")
	var mode: String = holder.get_meta("mode")
	var edge := InkUi.edge_for(mode)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	InkUi.margins(margin, edge)
	inner.add_child(margin)

	var window := PanelContainer.new()
	InkUi.panel(window, InkUi.window_style())
	margin.add_child(window)

	var column := VBoxContainer.new()
	InkUi.gap(column, InkUi.GAP_S)
	window.add_child(column)

	# Title row: serif title + close button, like the reference's window header.
	column.add_child(_window_header("Camp"))

	if mode == InkUi.WIDE:
		# All three columns at once: STATUS | DOLL+SLOTS | STASH.
		var row := HBoxContainer.new()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		InkUi.gap(row, InkUi.GAP_XL)
		column.add_child(row)
		row.add_child(_status_panel(0.24))
		row.add_child(_doll_panel(0.30))
		row.add_child(_stash_panel(0.46))
	else:
		# Phone: a tab strip, one panel at a time (STATUS selected is just an example; show STASH,
		# the busiest, so the Boss sees the grid collapse). Touch targets >= 44pt.
		column.add_child(_tab_strip(["Status", "Gear", "Stash"], 2))
		var body := _stash_panel(1.0)
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(body)

	return holder


## A serif window title (engraved brush plate) on the left, a brass close button on the right.
func _window_header(title: String) -> Control:
	var header := HBoxContainer.new()
	InkUi.gap(header, InkUi.GAP_XL)
	header.add_child(InkUi.brush_title(title, InkUi.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	# a small resource footer-style wallet lives at the window top-right too, like the reference
	header.add_child(_wallet_row())
	var close := Button.new()
	close.custom_minimum_size = Vector2(44, 44)
	InkUi.icon_button(close, "close", 22)
	header.add_child(close)
	return header


func _wallet_row() -> Control:
	var plate := PanelContainer.new()
	InkUi.panel(plate, InkUi.plate(InkUi.PANEL, InkUi.BORDER, 0.5, false, InkUi.CLEAR, 6.0))
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_L)
	plate.add_child(row)
	for pair in [["gold", "250"], ["ore", "10"], ["essence", "4"]]:
		var one := HBoxContainer.new()
		InkUi.gap(one, InkUi.GAP_XS)
		var ic := TextureRect.new()
		ic.texture = InkUi.icon(pair[0], 20, InkUi.GOLD if pair[0] == "gold" else InkUi.ICON_TINT)
		ic.custom_minimum_size = Vector2(20, 20)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		one.add_child(ic)
		one.add_child(InkUi.label(pair[1], InkUi.PAPER, InkUi.FONT_SMALL))
		row.add_child(one)
	return plate


# ------------------------------------------------------------- STATUS panel (read-only stats)

func _status_panel(width_ratio: float) -> Control:
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = width_ratio
	var col := VBoxContainer.new()
	InkUi.gap(col, InkUi.GAP_M)
	panel.add_child(col)

	# class-emblem-like round crest + name + level + a thin progress bar
	var head := VBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	InkUi.gap(head, InkUi.GAP_XS)
	var emblem := _round_emblem("challenge", 64)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(emblem)
	var name_lbl := InkUi.label("Wanderer", InkUi.PAPER, InkUi.FONT_HEADING)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(name_lbl)
	var sub := InkUi.label("Camp level 2", InkUi.MUTED, InkUi.FONT_NOTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	head.add_child(_thin_bar(0.6))
	col.add_child(head)

	col.add_child(InkUi.brush_title("Character stats", InkUi.FONT_SECTION))

	# read-only derived stats, numbers right-aligned (NO -/+/+10, NO reset: no stat-point system)
	var stats := [
		["heart", "HP", "1,142"], ["weapon", "ATK", "208"], ["armor", "DEF", "96"],
		["stamina", "Stamina", "100"], ["skill", "Crit", "12%"], ["ultimate", "Ult rate", "6%"],
	]
	for s in stats:
		col.add_child(_stat_row(s[0], s[1], s[2]))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	return panel


func _stat_row(icon_name: String, label_text: String, value: String) -> Control:
	var box := PanelContainer.new()
	InkUi.panel(box, InkUi.plate(InkUi.PANEL_LIGHT, InkUi.BORDER, 0.3, false, InkUi.CLEAR, 6.0))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_S)
	var ic := TextureRect.new()
	ic.texture = InkUi.icon(icon_name, 20)
	ic.custom_minimum_size = Vector2(20, 20)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(ic)
	row.add_child(InkUi.label(label_text, InkUi.MUTED, InkUi.FONT_NOTE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var val := InkUi.label(value, InkUi.PAPER, InkUi.FONT_LABEL)
	row.add_child(val)
	box.add_child(row)
	return box


# ------------------------------------------------------------- DOLL panel (paper doll + slot ring)

func _doll_panel(width_ratio: float) -> Control:
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = width_ratio
	var col := VBoxContainer.new()
	InkUi.gap(col, InkUi.GAP_S)
	panel.add_child(col)
	col.add_child(InkUi.brush_title("Equipment", InkUi.FONT_SECTION))

	# slots ringed symmetrically around the doll: left column | doll | right column
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	InkUi.gap(row, InkUi.GAP_M)
	col.add_child(row)

	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	InkUi.gap(left, InkUi.GAP_M)
	for s in [["hat", 3, 2, true], ["shirt", 2, 1, true], ["pants", 1, 0, true]]:
		left.add_child(_slot_cell(s[0], s[1], s[2], s[3]))
	row.add_child(left)

	var doll := _doll_figure()
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(doll)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	InkUi.gap(right, InkUi.GAP_M)
	for s in [["weapon", 7, 3, true], ["necklace", 1, 0, false], ["ring", 2, 0, true]]:
		right.add_child(_slot_cell(s[0], s[1], s[2], s[3]))
	row.add_child(right)
	return panel


# ------------------------------------------------------------- STASH panel (tabs + grid + footer + actions)

func _stash_panel(width_ratio: float) -> Control:
	var panel := PanelContainer.new()
	InkUi.panel(panel, InkUi.panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = width_ratio
	var col := VBoxContainer.new()
	InkUi.gap(col, InkUi.GAP_S)
	panel.add_child(col)
	col.add_child(InkUi.brush_title("Stash", InkUi.FONT_SECTION))

	# category tabs (our real categories: All / Weapon / Armor / Trinket / Material)
	col.add_child(_tab_strip(["All", "Weapon", "Armor", "Trinket", "Material"], 0, true))

	# search + sort row
	var tools := HBoxContainer.new()
	InkUi.gap(tools, InkUi.GAP_S)
	var search := LineEdit.new()
	search.placeholder_text = "Search"
	search.custom_minimum_size = Vector2(0, 44)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(search)
	var sort := Button.new()
	sort.text = "Sort: Rarity"
	sort.custom_minimum_size = Vector2(0, 44)
	tools.add_child(sort)
	col.add_child(tools)

	# the grid: 8 columns of framed cells with stack counts and rarity pips
	var grid := GridContainer.new()
	grid.columns = 8
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	InkUi.gap(grid, InkUi.GAP_XS, InkUi.GAP_XS)
	col.add_child(grid)
	var tiers := ["white", "blue", "purple", "gold"]
	for i in 32:
		var filled := i < 23
		var tier := i % 4 if filled else -1
		var count := (27 if i == 2 else (12 if i == 5 else (3 if i == 9 else 0)))
		var enhance := (7 if i == 0 else (3 if i == 4 else 0))
		var selected := i == 1
		var warn := 1 if i == 6 else 0
		grid.add_child(_bag_cell(_cell_icon(i), tier, tiers, count, enhance, selected, warn, filled))

	# footer summary line (reference: "Item 1146 · weight …"); ours: capacity + wallet, quiet, right-aligned
	var footer := HBoxContainer.new()
	footer.add_child(InkUi.label("Stash  23 / 40", InkUi.MUTED, InkUi.FONT_SMALL))
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fsp)
	footer.add_child(InkUi.label("Weight  1,596 / 12,940  (12%)", InkUi.MUTED, InkUi.FONT_SMALL))
	col.add_child(footer)

	# action row: each button with a one-line hint under it (Wear / Discard; Enhance/Favourite disabled)
	var actions := HBoxContainer.new()
	InkUi.gap(actions, InkUi.GAP_S)
	actions.add_child(_action_button("Wear", "equip this", false, true))
	actions.add_child(_action_button("Discard", "needs confirm", false, false))
	actions.add_child(_action_button("Enhance", "armory (soon)", true, false))
	actions.add_child(_action_button("Favourite", "pin to top", true, false))
	col.add_child(actions)
	return panel


func _action_button(text: String, hint: String, disabled: bool, primary: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(col, InkUi.GAP_XXS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := Button.new()
	btn.text = text
	btn.disabled = disabled
	btn.custom_minimum_size = Vector2(0, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary and not disabled:
		InkUi.make_primary(btn)
	col.add_child(btn)
	var h := InkUi.label(hint, InkUi.TEXT_DISABLED if disabled else InkUi.MUTED, InkUi.FONT_CAPTION)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	return col


# ============================================================= FIGHT HUD

func _build_hud(size: Vector2i) -> Control:
	var holder := _scaled(size)
	var inner: Control = holder.get_meta("inner")
	var compact: bool = holder.get_meta("mode") != InkUi.WIDE
	var scale := 1.8 if compact else 1.0

	# --- top-left: name + level, then HP / STAMINA / ULT bars with brass caps, then buff chips
	var tl := VBoxContainer.new()
	tl.position = Vector2(InkUi.GAP_HUGE, InkUi.GAP_HUGE)
	InkUi.gap(tl, int(InkUi.GAP_XS * scale))
	inner.add_child(tl)

	var name_row := HBoxContainer.new()
	InkUi.gap(name_row, int(InkUi.GAP_S * scale))
	name_row.add_child(_hud_label("Wanderer", "hp", InkUi.HUD_TEXT, scale))
	name_row.add_child(_hud_label("Lv 2", "bar", InkUi.KEY_TEXT, scale))
	tl.add_child(name_row)

	tl.add_child(_hud_bar("HP  420 / 1,142", 0.37, InkUi.HP, scale, true))
	tl.add_child(_hud_bar("STAMINA  22 / 100", 0.22, InkUi.STAMINA, scale, false))
	tl.add_child(_hud_bar("ULT  60%", 0.60, InkUi.ULT, scale, false))

	var chips := HBoxContainer.new()
	InkUi.gap(chips, int(InkUi.GAP_S * scale))
	chips.add_child(_chip("+ Rage", InkUi.BUFF, scale))
	chips.add_child(_chip("- Poison x2", InkUi.DEBUFF, scale))
	tl.add_child(chips)

	# --- top-right: currency row (coin icons + amounts), framed on a plate (reference top strip)
	var tr := HBoxContainer.new()
	InkUi.gap(tr, int(InkUi.GAP_L * scale))
	tr.add_child(_hud_label("Enemies 3", "bar", InkUi.HUD_TEXT, scale))
	tr.add_child(_hud_label("Bag 9 / 20", "bar", InkUi.HUD_TEXT, scale))
	var gold_row := HBoxContainer.new()
	InkUi.gap(gold_row, int(InkUi.GAP_XS * scale))
	var coin := TextureRect.new()
	coin.texture = InkUi.icon("gold", int(18 * scale), InkUi.GOLD)
	coin.custom_minimum_size = Vector2(18 * scale, 18 * scale)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_row.add_child(coin)
	gold_row.add_child(_hud_label("340", "bar", InkUi.LOOT_GOLD, scale))
	tr.add_child(gold_row)
	# top-right: anchor to the top-right corner so placement does not depend on a measured size.
	var tr_anchor := Control.new()
	tr_anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr_anchor.offset_left = -600
	tr_anchor.offset_top = InkUi.GAP_HUGE
	tr_anchor.offset_right = -InkUi.GAP_HUGE
	var tr_wrap := HBoxContainer.new()
	tr_wrap.alignment = BoxContainer.ALIGNMENT_END
	tr_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	InkUi.gap(tr_wrap, int(InkUi.GAP_L * scale))
	tr_wrap.add_child(tr)
	tr_anchor.add_child(tr_wrap)
	inner.add_child(tr_anchor)
	var view := Vector2(size)

	# --- skill banner near the top-centre (wide) / low beside the skills (compact) — out of the middle 40%
	var banner := _hud_label("Crescent Cut", "skill", InkUi.SKILL_BANNER_TEXT, scale)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = view.y * (0.06 if not compact else 0.56)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(banner)

	# --- bottom-centre: a numbered skill row (reference's skill bar), brass-framed cells
	var skills := HBoxContainer.new()
	skills.alignment = BoxContainer.ALIGNMENT_CENTER
	InkUi.gap(skills, int(InkUi.GAP_S * scale))
	for s in [["guard", "F"], ["dodge", "C"], ["skill", "1"], ["ultimate", "2"]]:
		skills.add_child(_skill_cell(s[0], s[1], scale))
	var skills_anchor := Control.new()
	skills_anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	skills_anchor.offset_top = -(60.0 * scale + InkUi.GAP_HUGE)
	skills_anchor.offset_bottom = -InkUi.GAP_HUGE
	skills.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skills_anchor.add_child(skills)
	inner.add_child(skills_anchor)

	# --- a loot line at the right (rarity colour + dark plate), like the reference's feed
	var loot := _hud_loot("+ Golden Blossom Katana  Epic", InkUi.rarity_color("purple", true), scale)
	var loot_anchor := Control.new()
	loot_anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	loot_anchor.offset_left = -520
	loot_anchor.offset_top = view.y * 0.40
	loot_anchor.offset_right = -InkUi.GAP_HUGE
	var loot_wrap := HBoxContainer.new()
	loot_wrap.alignment = BoxContainer.ALIGNMENT_END
	loot_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	loot_wrap.add_child(loot)
	loot_anchor.add_child(loot_wrap)
	inner.add_child(loot_anchor)

	await process_frame
	await process_frame
	return holder


func _hud_label(text: String, role: String, color: Color, scale: float) -> Label:
	var l := InkUi.hud_text(role, color, 4)
	l.text = text
	InkUi.text_size(l, int(float(InkUi.HUD_FONT[role]) * scale))
	return l


func _hud_bar(text: String, ratio: float, fill: Color, scale: float, low: bool) -> Control:
	var w := 240.0 * scale
	var h := 20.0 * scale
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	# back
	var back := ColorRect.new()
	back.color = InkUi.HUD_PANEL
	back.size = Vector2(w, h)
	holder.add_child(back)
	# fill
	var bar := ColorRect.new()
	bar.color = fill
	bar.size = Vector2(w * ratio, h)
	holder.add_child(bar)
	# brass decoration (caps, ticks, frame) from the real token helper
	var decor := InkUi.bar_decor(Vector2(w, h), 10)
	if decor != null:
		decor.call("set_values", ratio, ratio, 0.6 if low else 0.0)
		holder.add_child(decor)
	# number inside, on the left
	var lbl := _hud_label(text, "bar", InkUi.HUD_TEXT, scale)
	lbl.position = Vector2(InkUi.GAP_S, (h - float(InkUi.HUD_FONT["bar"]) * scale) * 0.5)
	holder.add_child(lbl)
	return holder


func _chip(text: String, edge: Color, scale: float) -> Control:
	var box := PanelContainer.new()
	InkUi.panel(box, InkUi.plate(InkUi.HUD_PANEL, edge, 0.8, false, edge, 4.0))
	var l := _hud_label(text, "chip", edge, scale)
	box.add_child(l)
	return box


func _skill_cell(icon_name: String, key: String, scale: float) -> Control:
	var cell_size := 52.0 * scale
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(cell_size, cell_size)
	cell.size = Vector2(cell_size, cell_size)
	var back := PanelContainer.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	InkUi.panel(back, InkUi.plate(InkUi.HUD_PANEL, InkUi.BORDER, 0.6, false, InkUi.CLEAR, 4.0))
	cell.add_child(back)
	var ic := TextureRect.new()
	ic.texture = InkUi.icon(icon_name, int(cell_size * 0.6))
	var icon_px := cell_size * 0.6
	ic.position = Vector2((cell_size - icon_px) * 0.5, (cell_size - icon_px) * 0.5)
	ic.size = Vector2(icon_px, icon_px)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cell.add_child(ic)
	# key badge, bottom-right corner
	var badge := _hud_label(key, "key", InkUi.KEY_TEXT, scale)
	badge.position = Vector2(cell_size - 16 * scale, cell_size - 20 * scale)
	cell.add_child(badge)
	var frame := InkUi.hud_ornament(Vector2(cell_size, cell_size), true)
	if frame != null:
		cell.add_child(frame)
	return cell


func _hud_loot(text: String, color: Color, scale: float) -> Control:
	var box := PanelContainer.new()
	InkUi.panel(box, InkUi.hud_plate_style())
	var l := _hud_label(text, "loot", color, scale)
	box.add_child(l)
	return box


# ============================================================= small drawn pieces

func _tab_strip(names: Array, selected: int, small: bool = false) -> Control:
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_XS)
	var i := 0
	for n in names:
		var b := Button.new()
		b.text = n
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == selected:
			b.add_theme_stylebox_override("normal", InkUi.plate(InkUi.PRESSED_BG, InkUi.GOLD, 0.9, true, InkUi.GOLD, 8.0))
		row.add_child(b)
		i += 1
	return row


func _thin_bar(ratio: float) -> Control:
	var bar := _ProgressDraw.new()
	bar.ratio = ratio
	bar.fill = InkUi.GOLD
	bar.back = InkUi.SLOT_BG
	bar.line = InkUi.ORNAMENT
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


func _round_emblem(icon_name: String, px: int) -> Control:
	var e := _EmblemDraw.new()
	e.icon_name = icon_name
	e.custom_minimum_size = Vector2(px, px)
	return e


func _doll_figure() -> Control:
	var d := _DollDraw.new()
	d.custom_minimum_size = Vector2(120, 240)
	return d


func _slot_cell(icon_name: String, enhance: int, tier: int, worn: bool) -> Control:
	var c := _CellDraw.new()
	c.icon_name = icon_name
	c.enhance = enhance
	c.tier = tier
	c.worn = worn
	c.is_slot = true
	c.custom_minimum_size = Vector2(56, 56)
	return c


func _bag_cell(icon_name: String, tier: int, tiers: Array, count: int, enhance: int, selected: bool, warn: int, filled: bool) -> Control:
	var c := _CellDraw.new()
	c.icon_name = icon_name if filled else ""
	c.tier = tier
	c.count = count
	c.enhance = enhance
	c.selected = selected
	c.warn = warn
	c.custom_minimum_size = Vector2(56, 56)
	return c


func _cell_icon(i: int) -> String:
	var pool := ["weapon", "hat", "shirt", "pants", "ore", "essence", "herb", "ring", "necklace", "armor"]
	return pool[i % pool.size()]


## A soft navy backdrop standing in for the 3D world behind the menu (so the mockup reads like the
## live game). Uses INK/PANEL tokens only.
func _world_backdrop() -> Control:
	var r := _BackdropDraw.new()
	return r


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)


# ------------------------------------------------------------- custom-drawn helpers (tokens only)

class _ProgressDraw:
	extends Control
	var ratio := 1.0
	var fill := Color.WHITE
	var back := Color.BLACK
	var line := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), back)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), fill)
		draw_rect(Rect2(Vector2.ZERO, size), line, false, 1.0)


class _EmblemDraw:
	extends Control
	var icon_name := "challenge"
	const Ink := preload("res://client/ink_ui.gd")
	const Icons := preload("res://client/brass_icons.gd")
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Ink.SLOT_BG)
		draw_arc(c, r - 1.5, 0.0, TAU, 40, Ink.ORNAMENT, 1.5, true)
		draw_arc(c, r - 5.0, 0.0, TAU, 40, Color(Ink.ORNAMENT, 0.5), 1.0, true)
		Icons.draw(self, icon_name, Rect2(c - Vector2(r, r) * 0.55, Vector2(r, r) * 1.1), Ink.ICON_TINT)


class _DollDraw:
	extends Control
	const Ink := preload("res://client/ink_ui.gd")
	func _draw() -> void:
		# glowing floor circle + a simple silhouette standing on it (placeholder for the 3D model)
		var cx := size.x * 0.5
		var floor_y := size.y * 0.86
		draw_set_transform(Vector2(cx, floor_y), 0.0, Vector2.ONE)
		for i in 6:
			var rr := (size.x * 0.34) * (1.0 - i * 0.06)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(Ink.DOLL_SHADE, 0.5 - i * 0.07), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# silhouette
		var col := Color(Ink.MUTED, 0.6)
		var cxx := cx
		var top := size.y * 0.14
		draw_circle(Vector2(cxx, top + 18), 15, col)  # head
		draw_rect(Rect2(cxx - 16, top + 34, 32, 70), col)  # torso
		draw_rect(Rect2(cxx - 24, top + 40, 10, 56), col)  # arm
		draw_rect(Rect2(cxx + 14, top + 40, 10, 56), col)  # arm
		draw_rect(Rect2(cxx - 14, top + 104, 11, 70), col)  # leg
		draw_rect(Rect2(cxx + 3, top + 104, 11, 70), col)  # leg


class _CellDraw:
	extends Control
	const Ink := preload("res://client/ink_ui.gd")
	const Icons := preload("res://client/brass_icons.gd")
	var icon_name := ""
	var tier := -1
	var count := 0
	var enhance := 0
	var selected := false
	var warn := 0
	var worn := false
	var is_slot := false
	func _tier_color() -> Color:
		var keys := ["white", "blue", "purple", "gold"]
		if tier < 0:
			return Ink.BORDER
		return Ink.rarity_color(keys[clampi(tier, 0, 3)])
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Ink.SLOT_BG if is_slot else Ink.PANEL_LIGHT)
		# rarity glow rising from the bottom
		if tier >= 0:
			var g := _tier_color()
			draw_polygon(PackedVector2Array([Vector2(2, size.y), Vector2(size.x - 2, size.y), Vector2(size.x - 2, size.y * 0.45), Vector2(2, size.y * 0.45)]),
				PackedColorArray([Color(g, 0.35), Color(g, 0.35), Color(g, 0.0), Color(g, 0.0)]))
		# frame, thicker per tier
		var fw := 1.0 + maxf(0.0, float(tier)) * 0.6
		draw_rect(r.grow(-0.5), _tier_color() if tier >= 0 else Ink.BORDER, false, fw)
		# icon
		if icon_name != "":
			Icons.draw(self, icon_name, Rect2(size * 0.22, size * 0.56), Ink.ICON_TINT)
		elif is_slot:
			Icons.draw(self, icon_name, r.grow(-size.x * 0.28), Color(Ink.MUTED, 0.5))
		# diamond pips (1..4) top edge for the tier
		if tier >= 0:
			for p in (tier + 1):
				var at := Vector2(6 + p * 7.0, 7.0)
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3), at + Vector2(3, 0), at + Vector2(0, 3), at + Vector2(-3, 0)]), _tier_color())
		# +N enhance, top-left-ish (gold)
		if enhance > 0:
			draw_string(get_theme_default_font(), Vector2(5, size.y - 6), "+%d" % enhance, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.GOLD)
		# stack count bottom-right
		if count > 0:
			var t := "x%d" % count
			var w := get_theme_default_font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(get_theme_default_font(), Vector2(size.x - w - 4, size.y - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ink.PAPER)
		# worn-down / broken mark
		if warn > 0:
			var c := Vector2(size.x - 9, 9)
			draw_circle(c, 6, Ink.WARN if warn == 1 else Ink.BAD)
			draw_string(get_theme_default_font(), c - Vector2(2, -4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ink.INK)
		# worn (equipped) check on a slot
		if worn and is_slot:
			var c2 := Vector2(size.x - 9, 9)
			draw_circle(c2, 6, Ink.GOOD)
		# selection: ember frame + white corner brackets
		if selected:
			draw_rect(r.grow(2.0), Ink.SEAL, false, 3.0)
			for corner in [Vector2(0, 0), Vector2(size.x, 0), size, Vector2(0, size.y)]:
				var into: Vector2 = (r.get_center() - corner).sign()
				draw_line(corner, corner + Vector2(into.x * 10, 0), Ink.SELECT_MARK, 2.0)
				draw_line(corner, corner + Vector2(0, into.y * 10), Ink.SELECT_MARK, 2.0)


class _BackdropDraw:
	extends Control
	const Ink := preload("res://client/ink_ui.gd")
	func _draw() -> void:
		# a soft vertical navy gradient, so the panels read as glass over a night world
		draw_rect(Rect2(Vector2.ZERO, size), Ink.INK)
		var top := Color(Ink.PANEL, 1.0)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]),
			PackedColorArray([top, top, Ink.INK, Ink.INK]))
		# a few faint horizon lines
		for i in 5:
			var y := size.y * (0.3 + i * 0.12)
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(Ink.ORNAMENT, 0.03), 1.0)
