extends Control
## The squad's skill combos (Boss 2026-11-25), opened from the hub's combo pill: one column per squad card with its 4
## class skills (each with its Sets / Pays off badges), coloured links from a setter skill to the payoff skill it feeds
## (link colour = the shared state), "Combos in squad: N pairs" on top, and a tap on a skill shows
## "Works with: <class> <skill>, ..." at the bottom. Display only (client/combo_ui.gd reads data/combat/combos.json).

const CardTokens := preload("res://client/card_tokens.gd")
const HubLook := preload("res://client/hub_look.gd")
const ComboUi := preload("res://client/combo_ui.gd")
const ComboBadges := preload("res://client/combo_badges.gd")

signal closed()

var data = null  ## tests / screenshots set a fixture; null = the game's file
var squad: Array = []
var selected_skill := ""
var _links: Array = []
var _rows := {}  ## skill id -> Button
var _panel: PanelContainer
var _title: Label
var _count: Label
var _grid: HBoxContainer
var _works: Label
var _lines: Control
var _s := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed: close())
	add_child(dim)
	get_viewport().size_changed.connect(_rebuild)


func open(squad_ids: Array, use_data = null) -> void:
	squad = squad_ids.duplicate()
	if use_data != null:
		data = use_data
	selected_skill = ""
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	closed.emit()


func squad_skills() -> Dictionary:
	var out := {}
	for id in squad:
		out[str(id)] = ComboUi.class_skills(str(id))
	return out


func links() -> Array:
	return _links


func select_skill(id: String) -> void:
	selected_skill = "" if selected_skill == id else id
	_works.text = ComboUi.t("tap_skill") if selected_skill.is_empty() else ComboUi.works_with_text(selected_skill, _links)
	for k in _rows:
		(_rows[k] as Button).modulate = Color.WHITE if selected_skill.is_empty() or k == selected_skill or _partner(k) else Color(1, 1, 1, 0.45)
	_lines.queue_redraw()


func _partner(id: String) -> bool:
	for l in _links:
		if (l["from"] == id and l["to"] == selected_skill) or (l["to"] == id and l["from"] == selected_skill):
			return true
	return false


func _rebuild() -> void:
	if not is_inside_tree() or not visible:
		return
	if _panel != null:
		_panel.queue_free()
	_rows.clear()
	var screen := get_viewport().get_visible_rect().size
	_s = CardTokens.scale_for(screen)
	var phone := CardTokens.is_phone(screen)
	var k := _s * (1.25 if phone else 1.0)  # phone: text a size up (844x390 reads at ~0.36 scale)
	_links = ComboUi.squad_links(squad_skills(), data)
	_panel = PanelContainer.new()
	CardTokens.panel(_panel, HubLook.parchment(_s))
	add_child(_panel)
	var pad := MarginContainer.new()
	CardTokens.margin(pad, 24.0, _s)
	_panel.add_child(pad)
	var box := VBoxContainer.new()
	CardTokens.gap(box, 10.0, _s)
	pad.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = CardTokens.hub_label(ComboUi.t("title"), 40, CardTokens.HUB_INK, k)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	head.add_child(_title)
	_count = CardTokens.hub_label(ComboUi.pairs_text(_links, squad.size()), 30, CardTokens.HUB_GOOD if not _links.is_empty() else CardTokens.HUB_SLOT_TEXT, k, 0, "medium")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count)
	var x := Button.new()
	x.text = CardTokens.t("close")
	x.custom_minimum_size = Vector2(150.0 * _s, CardTokens.tap(64.0, phone) * _s)
	CardTokens.hub_plate_button(x, _s)
	CardTokens.hub_text(x, 26, CardTokens.HUB_INK, k)
	x.pressed.connect(close)
	head.add_child(x)
	var stack := Control.new()  # the columns + the link layer on top of them
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(stack)
	_grid = HBoxContainer.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	CardTokens.gap(_grid, 60.0 if phone else 90.0, _s)  # wide gutters: the links run here
	stack.add_child(_grid)
	var no_data := ComboUi._data(data).is_empty()
	for id in squad:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CardTokens.gap(col, 6.0, _s)
		_grid.add_child(col)
		var cname := CardTokens.hub_label(CardTokens.t("class_" + str(id)) if CardTokens.STRINGS.has("class_" + str(id)) else str(id).capitalize(), 28, CardTokens.HUB_SUBTEXT, k)
		col.add_child(cname)
		for skill in ComboUi.class_skills(str(id)):
			var b := Button.new()
			b.custom_minimum_size = Vector2(0.0, CardTokens.tap(78.0, phone) * _s)
			b.focus_mode = Control.FOCUS_ALL
			b.add_theme_stylebox_override("normal", HubLook.leather(_s))
			b.add_theme_stylebox_override("hover", HubLook.leather(_s))
			b.add_theme_stylebox_override("pressed", HubLook.leather(_s))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.pressed.connect(select_skill.bind(str(skill)))
			col.add_child(b)
			var v := VBoxContainer.new()
			v.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			v.add_theme_constant_override("separation", 0)
			b.add_child(v)
			var n := CardTokens.hub_label(ComboUi.skill_info(str(skill))["name"], 24, Color("F3E6C8"), k)
			v.add_child(n)
			var badges := ComboBadges.new()
			badges.data = data
			badges.ink = Color("F3E6C8")
			badges.font_size = 17
			badges.show_skill(str(skill), k)
			badges.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(badges)
			_rows[str(skill)] = b
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_links)
	stack.add_child(_lines)
	_works = CardTokens.hub_label(ComboUi.t("no_data") if no_data else ComboUi.t("tap_skill"), 24, CardTokens.HUB_INK, k, 0, "medium")
	_works.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_works.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_works.custom_minimum_size = Vector2(screen.x * 0.8, 0.0)
	box.add_child(_works)
	var margin := 24.0 * _s + CardTokens.hub_safe_x(screen, _s)
	_panel.position = Vector2(margin, 16.0 * _s)
	_panel.size = Vector2(screen.x - margin * 2.0, screen.y - 32.0 * _s)
	stack.resized.connect(func() -> void: _lines.queue_redraw())
	_lines.queue_redraw.call_deferred()
	if not selected_skill.is_empty():
		select_skill.call_deferred(selected_skill)


## Links: setter's right/left edge to the payoff's facing edge, one curve per link, dashed into one stripe per state.
func _draw_links() -> void:
	var lane := {}  # per (column pair) offset so parallel links do not overlap
	for l in _links:
		var a: Button = _rows.get(l["from"])
		var b: Button = _rows.get(l["to"])
		if a == null or b == null:
			continue
		var ra := Rect2(a.global_position - _lines.global_position, a.size)
		var rb := Rect2(b.global_position - _lines.global_position, b.size)
		var right := rb.position.x > ra.position.x
		var p0 := Vector2(ra.end.x if right else ra.position.x, ra.get_center().y)
		var p1 := Vector2(rb.position.x if right else rb.end.x, rb.get_center().y)
		var key: String = "%d" % roundi(minf(p0.x, p1.x))
		var n := int(lane.get(key, 0))
		lane[key] = n + 1
		var lit: bool = selected_skill.is_empty() or l["from"] == selected_skill or l["to"] == selected_skill
		var w := (5.0 if lit else 2.5) * maxf(_s, 0.5)
		var bend := (p1.x - p0.x) * 0.45
		var pts := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			var c1 := p0 + Vector2(bend, 0)
			var c2 := p1 - Vector2(bend, 0)
			pts.append(p0.bezier_interpolate(c1, c2, p1, t) + Vector2(0, (n % 3 - 1) * 3.0 * _s * sin(t * PI)))
		var states: Array = l["states"]
		for i in pts.size() - 1:
			var st := str(states[i % states.size()])
			var col: Color = ComboUi.state_info(st, data)["color"]
			col.a = 1.0 if lit else 0.3
			_lines.draw_line(pts[i], pts[i + 1], Color(0.1, 0.07, 0.05, col.a), w + 3.0 * _s)
			_lines.draw_line(pts[i], pts[i + 1], col, w)
		# arrow head into the payoff skill + the state icon at the middle
		var dir := (pts[20] - pts[18]).normalized()
		var tip := pts[20]
		_lines.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14.0 * _s + dir.orthogonal() * 8.0 * _s, tip - dir * 14.0 * _s - dir.orthogonal() * 8.0 * _s]), Color(0.1, 0.07, 0.05, 1.0 if lit else 0.3))
		if lit:
			ComboUi.draw_state_icon(_lines, pts[10], maxf(9.0, 14.0 * _s), str(states[0]), data)
