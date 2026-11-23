extends Control
## The Skills tab of the card character screen (design/gdd/skill-tree.md 9.1, 9.2): header (level, XP, points, branch
## counters, Reset Class (gold) / Reset Race (free) / Confirm / Cancel draft), the tree on the parchment map (class
## branch left: 4 + 8 (OR pairs) + 2 + 2, race branch right in the race colour: 2 + 2 + 2 + 2, the combo capstone at the
## top between them, tier bands with their gate numbers) and a detail panel docked at the right edge (name, text, cost,
## gate, OR partner, Learn / Unlearn (draft)).
## The player edits a DRAFT for free (logic/skill_tree.gd draft_learn / draft_unlearn / check_draft, the same rules the
## server runs) and sends it with one `tree_save`; resets are `tree_reset_class` / `tree_reset_race`. Display only: it
## reads the profile's card deck and the tree data, never changes them itself. Touch first: tap = select, double-tap /
## right-click = learn, every action is also a button (>= 96 px on phones), nothing needs hover.
## Nodes whose rule the battle engine does not run yet are shown like any other (PO 2026-11-13).
## Every colour, size and word comes from client/card_tokens.gd (STRINGS_TREE).

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")  ## the carved ink-wash look (Boss 2026-11-14)
const SkillTreeNode := preload("res://client/skill_tree_node.gd")
const SkillTree := preload("res://logic/skill_tree.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const CardProgress := preload("res://logic/card_progress.gd")
const CardDeck := preload("res://logic/card_deck.gd")

signal changed()  ## a command changed the profile

## (request: Dictionary) -> Dictionary, may be a coroutine (the hub's command sender).
var send: Callable
## (text: String) -> void: a short status line.
var notify: Callable
var s := 1.0
var phone := false

var card := ""
var deck := {}  ## the profile's card deck (read only)
var gold := 0
var draft := {}  ## {"class", "race", "combo"}: what the player is building (free until Confirm)
var selected := ""
var _busy := false
var _reset_armed := ""  ## "class" | "race": the reset button tapped once (a second tap sends it)
var _manifest := {}
var _textures := {}

var _map: TextureRect
var _scroll: ScrollContainer  ## the tree canvas
var _lines: Control  ## the scrolled content: tier bands, gate numbers, "or" words and ink paths are drawn here; holds the nodes
var tree_data = null  ## the tree data (tests set a fixture); null = the game's data
var _nodes := {}  ## node id -> SkillTreeNode
var _positions := {}  ## node id -> centre (in _lines space)
var _bands: Array = []  ## [{"y", "x0", "x1", "gate", "color"}]
var _header: Panel
var _level: Label
var _xp_back: Panel
var _xp_fill: Panel
var _xp_text: Label
var _points: Label
var _coin: TextureRect
var _branches: Label
var _reset_class: Button
var _reset_race: Button
var _confirm: Button
var _cancel: Button
var _detail: Panel
var _d_name: Label
var _d_branch: Label
var _d_state: Label
var _d_text: Label
var _d_cost: Label
var _learn: Button
var _unlearn: Button
var _close: Button  ## compact only: closes the detail sheet
var _d_scroll: ScrollContainer  ## the detail text scrolls when it does not fit (never cut)
var _d_box: VBoxContainer
var _d_spacer: Control
var _compact := false  ## phone landscape: one-row header, full-width tree, detail as a sheet (TREE_COMPACT_BELOW)
var node_base := 0.0  ## the fitted base node size N in screen px (each kind is N x TREE_NODE_KIND)
var _labels_in_rows := false  ## gate tags under each row (tall canvas) instead of in side gutters (wide canvas)
var _combo_id := ""
var _or_marks: Array = []  ## centres of the "or" words between OR pairs
var _opened_at: Array = []  ## [card, content size] the scroll was last reset for


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CardTokens.TREE_MANIFEST)) if FileAccess.file_exists(CardTokens.TREE_MANIFEST) else null
	_manifest = parsed if parsed is Dictionary else {}
	_map = TextureRect.new()
	_map.texture = _cropped(_texture(str(_manifest.get("background", ""))))
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	_scroll = ScrollContainer.new()  # scrolls only when the nodes would be under their least size (many nodes / tiny screen)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.scroll_deadzone = int(CardTokens.TREE_GAP)
	add_child(_scroll)
	_lines = Control.new()  # the content: lines and labels are drawn here, the nodes are its children
	_lines.mouse_filter = Control.MOUSE_FILTER_PASS
	_lines.draw.connect(_draw_lines)
	_scroll.add_child(_lines)
	_build_header()
	_build_detail()


func _build_header() -> void:
	_header = Panel.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_level = CardTokens.hub_label("", CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, 1.0, 0, "display")
	_header.add_child(_level)
	_xp_back = Panel.new()
	_xp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_xp_back)
	_xp_fill = Panel.new()
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_back.add_child(_xp_fill)
	_xp_text = CardTokens.hub_label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_CREAM, 1.0, 0, "medium")
	_header.add_child(_xp_text)
	_coin = TextureRect.new()
	_coin.texture = _texture(str(_manifest.get("badges", {}).get("point_coin", "")))
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_coin)
	_points = CardTokens.hub_label("", CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, 1.0, 0, "display")
	_header.add_child(_points)
	_branches = CardTokens.hub_label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_MUTED, 1.0, 0, "medium")
	_header.add_child(_branches)
	_reset_class = _button(_on_reset.bind("class"))
	_reset_race = _button(_on_reset.bind("race"))
	_confirm = _button(confirm)
	_cancel = _button(cancel_draft)


func _build_detail() -> void:
	_detail = Panel.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail)
	_d_scroll = ScrollContainer.new()
	_d_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.add_child(_d_scroll)
	_d_box = VBoxContainer.new()
	_d_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_scroll.add_child(_d_box)
	_d_name = CardTokens.hub_label("", CardTokens.TREE_FONT_NAME, CardTokens.HUB_INK, 1.0, 0, "display")
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_box.add_child(_d_name)
	_d_branch = CardTokens.hub_label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_SUBTEXT, 1.0, 0, "medium")
	_d_branch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_box.add_child(_d_branch)
	_d_state = CardTokens.hub_label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	_d_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_box.add_child(_d_state)
	_d_text = CardTokens.hub_label("", CardTokens.TREE_FONT_BODY, CardTokens.HUB_INK, 1.0, 0, "medium")
	_d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_d_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_d_text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_d_box.add_child(_d_text)
	_d_spacer = Control.new()  # keeps the cost lines at the bottom when the text is short
	_d_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_d_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_box.add_child(_d_spacer)
	_d_cost = CardTokens.hub_label("", CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, 1.0, 0, "medium")
	_d_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_d_cost.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_d_cost.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_d_box.add_child(_d_cost)
	# Learn / Unlearn / Close are the tab's children (placed in the detail panel, or in the header on a phone)
	_learn = _button(func() -> void: learn(selected))
	_unlearn = _button(func() -> void: unlearn(selected))
	_close = _button(func() -> void: select(""))


func _button(callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(callback)
	add_child(b)
	return b


## The map art without its own leather border (the card board around the tab is the only frame).
func _cropped(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cut := Vector2(texture.get_size()) * CardTokens.TREE_MAP_CROP
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(cut, Vector2(texture.get_size()) - cut * 2.0)
	return atlas


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


# ================================================================== API
## Shows card `class_id` of `card_deck` with `gold` in the stash. Keeps the draft when the same card is shown again.
func show_card(class_id: String, card_deck: Dictionary, stash_gold: int) -> void:
	var same := class_id == card
	card = class_id
	deck = card_deck
	gold = stash_gold
	_reset_armed = ""
	if not same or draft.is_empty() or not SkillTree.check_draft(deck, card, draft).is_empty():
		draft = SkillTree.owned(deck, card)
		selected = ""
	_build_nodes()
	layout_tab()


## True while the draft holds nodes the server has not saved.
func has_changes() -> bool:
	return draft != SkillTree.owned(deck, card)


## Adds one node to the draft (free). Returns "" or the reason it cannot go in.
func learn(node_id: String) -> String:
	if node_id.is_empty():
		return "unknown_node"
	var next := SkillTree.draft_learn(draft, node_id)
	if next.is_empty():
		return "already_learned"
	var reason := SkillTree.check_draft(deck, card, next)
	if not reason.is_empty():
		_say(CardTokens.tree_error(reason))
		return reason
	draft = next
	selected = node_id
	refresh()
	return ""


## Takes one draft node back off (free); draft nodes that needed it come off too. Confirmed nodes need a reset.
func unlearn(node_id: String) -> String:
	var next := SkillTree.draft_unlearn(deck, card, draft, node_id)
	if next.is_empty():
		_say(CardTokens.tree_error("confirmed_removed"))
		return "confirmed_removed"
	var points := CardProgress.points_of(deck, card)
	draft = SkillTree.repaired(next, card, CardDeck.race_of(deck, card), points)
	for branch in SkillTree.BRANCHES:  # the confirmed nodes are always kept (they were valid without the draft)
		for id in SkillTree.owned(deck, card)[branch]:
			if not draft[branch].has(id):
				draft[branch].append(id)
	refresh()
	return ""


func cancel_draft() -> void:
	draft = SkillTree.owned(deck, card)
	refresh()


func select(node_id: String) -> void:
	selected = node_id
	refresh()


## Sends the draft (tree_save). On success the profile holds it; the caller redraws through show_card.
func confirm() -> void:
	if not has_changes():
		return
	var result := await _run({"type": "tree_save", "card": card, "draft": draft.duplicate(true)})
	if result.get("ok", false):
		_say(CardTokens.tt("tree_saved_ok"))


func _on_reset(branch: String) -> void:
	if _reset_armed != branch:  # a reset needs a second tap (it costs gold / takes learned nodes off)
		_reset_armed = branch
		refresh()
		return
	_reset_armed = ""
	var result := await _run({"type": "tree_reset_" + branch, "card": card})
	if result.get("ok", false):
		draft = {}
		_say(CardTokens.tt("tree_reset_ok") % int(result.get("result", {}).get("refunded", 0)))


func _run(request: Dictionary) -> Dictionary:
	if _busy or not send.is_valid():
		return {"ok": false}
	_busy = true
	var result: Dictionary = await send.call(request)
	_busy = false
	if not result.get("ok", false):
		_say(CardTokens.tree_error(str(result.get("error", result.get("reason", "")))))
	else:
		changed.emit()
	return result


func _say(text: String) -> void:
	if notify.is_valid():
		notify.call(text)


# ================================================================== nodes
func _data():
	return tree_data if tree_data != null else TreeData.load_default()


## The nodes this card shows: its class branch, its race's branch and its class x race combo.
func shown_nodes() -> Array:
	var data = _data()
	var race := CardDeck.race_of(deck, card)
	var out: Array = data.class_nodes(card) + data.race_nodes(race)
	var combo: Dictionary = data.combo_node(race, card)
	if not combo.is_empty():
		out.append(combo)
	return out


func _build_nodes() -> void:
	for id in _nodes:
		_nodes[id].queue_free()
	_nodes.clear()
	for n in shown_nodes():
		var id := str(n["id"])
		var b := SkillTreeNode.new()
		b.node_id = id
		b.kind = "combo" if _data().branch_of(id) == "combo" else str(n["type"])
		b.cost = int(n["cost"])
		b.exclusive = not str(n["excl"]).is_empty()
		b.art = _texture(str(n["icon"]))
		b.tooltip_text = str(n["name"])
		b.setup()
		b.mouse_filter = Control.MOUSE_FILTER_PASS  # a drag that starts on a node still scrolls the tree
		b.pressed.connect(select.bind(id))
		b.activated.connect(func() -> void:
			select(id)
			learn(id))
		_lines.add_child(b)
		_nodes[id] = b


## The state of one node in the current draft (GDD 9.2).
func node_state(node_id: String) -> int:
	var branch: String = _data().branch_of(node_id)
	if SkillTree.owned(deck, card).get(branch, []).has(node_id):
		return SkillTreeNode.State.TAKEN
	if draft.get(branch, []).has(node_id):
		return SkillTreeNode.State.DRAFT
	var next := SkillTree.draft_learn(draft, node_id)
	var reason := SkillTree.check_draft(deck, card, next) if not next.is_empty() else "unknown_node"
	if reason.is_empty():
		return SkillTreeNode.State.AVAILABLE
	return SkillTreeNode.State.NO_POINTS if reason == "not_enough_points" else SkillTreeNode.State.LOCKED


# ================================================================== layout
func layout_tab() -> void:
	if _header == null or card.is_empty():
		return
	_compact = size.y / maxf(s, 0.01) < CardTokens.TREE_COMPACT_BELOW
	var head_h := _layout_header_compact() if _compact else _layout_header()
	var gap := CardTokens.TREE_GAP * s
	var top := head_h + gap
	var canvas: Rect2
	if _compact:  # the tree takes the whole width; the details open as a sheet over it (_place_sheet)
		canvas = Rect2(0.0, top, size.x, size.y - top)
		_detail.size = Vector2(size.x * CardTokens.TREE_SHEET_W, size.y - top)
		_detail.position = Vector2(size.x - _detail.size.x, top)
	else:  # detail panel at the right edge, the canvas fills the rest
		var dw := maxf(CardTokens.TREE_DETAIL_W * s, size.x * CardTokens.TREE_DETAIL_SHARE)
		_detail.position = Vector2(size.x - dw, top)
		_detail.size = Vector2(dw, size.y - top)
		canvas = Rect2(0.0, top, size.x - dw - gap, size.y - top)
	CarvedLook.inset(_detail, s)  # carved look: a parchment inset with an ink line
	_map.position = canvas.position
	_map.size = canvas.size
	_scroll.position = canvas.position
	_scroll.size = canvas.size
	_layout_nodes(Rect2(Vector2.ZERO, canvas.size))
	_layout_detail()
	refresh()


## The big-screen header: level + XP bar, points + branch counters, the four buttons at the right (a row of their own
## under the counters when they do not fit). Returns the header height.
func _layout_header() -> float:
	var gap := CardTokens.TREE_GAP * s
	var head_h := CardTokens.tap(CardTokens.TREE_HEADER_H, phone) * s
	_header.position = Vector2.ZERO
	_header.size = Vector2(size.x, head_h)
	CarvedLook.dark_pill(_header, s)  # carved look: the dark ink pill
	var bh := head_h - gap
	var x := gap
	_level.position = Vector2(x, gap * 0.2)
	_level.size = Vector2(170.0 * s, head_h * 0.5)
	CardTokens.hub_text(_level, CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, s, 0, "display")
	_xp_back.position = Vector2(x, head_h * 0.58)
	_xp_back.size = Vector2(170.0 * s, CardTokens.CHAR_BAR_H * s)
	_style_xp()
	x += 170.0 * s + gap
	_coin.position = Vector2(x, (head_h - bh * 0.7) * 0.5)
	_coin.size = Vector2(bh * 0.7, bh * 0.7)
	x += bh * 0.7 + gap * 0.4
	_points.position = Vector2(x, 0.0)
	_points.size = Vector2(170.0 * s, head_h * 0.55)
	CardTokens.hub_text(_points, CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, s, 0, "display")
	_branches.position = Vector2(x, head_h * 0.5)
	_branches.size = Vector2(320.0 * s, maxf(head_h * 0.45, _px(CardTokens.FONT_CHAR_SLOT) * 1.3))
	CardTokens.hub_text(_branches, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_MUTED, s, 0, "medium")
	# buttons from the right: Confirm, Cancel, Reset Race, Reset Class; narrowed to the room right of the counters
	var right := size.x - gap
	var widths := [[_confirm, 190.0], [_cancel, 210.0], [_reset_race, 230.0], [_reset_class, 280.0]]
	var wanted := 0.0
	for pair in widths:
		wanted += float(pair[1]) * s + gap * 0.5
	var room := right - (_points.position.x + maxf(_text_w(_branches), _text_w(_points)) + gap)
	var two_rows := room < wanted * 0.8  # small screens: the four buttons get a row of their own under the counters
	var fit := clampf((size.x - gap * 2.0) / maxf(wanted, 1.0), 0.45, 1.0) if two_rows else clampf(room / maxf(wanted, 1.0), 0.45, 1.0)
	var row_y := gap * 0.5
	if two_rows:
		row_y = head_h
		head_h += bh + gap * 0.5
		_header.size.y = head_h
	for pair in widths:
		var b: Button = pair[0]
		var w: float = float(pair[1]) * s * fit
		b.size = Vector2(w, bh)
		b.position = Vector2(right - w, row_y)
		right -= w + gap * 0.5
		_skin(b)
		b.visible = true
	return head_h


## The phone header (one row): level + XP, points + branch counters, and two button slots at the right that show the
## pair that can be used now: Reset Class / Reset Race with no draft, Cancel draft / Confirm while drafting (the other
## pair is disabled then anyway). Labels wrap to two lines. Returns the header height.
func _layout_header_compact() -> float:
	var gap := CardTokens.TREE_GAP * s
	var line := _px(CardTokens.FONT_CHAR_SLOT) * 1.3
	var head_h := maxf(CardTokens.tap(CardTokens.TREE_HEADER_H, phone) * s, line * 2.2)
	_header.position = Vector2.ZERO
	_header.size = Vector2(size.x, head_h)
	CarvedLook.dark_pill(_header, s)  # carved look: the dark ink pill
	var face := CardTokens.medium_font()
	var fpx := int(_px(CardTokens.FONT_CHAR_SLOT))
	var xp_sample := CardTokens.tt("tree_xp") % [99999, 99999]
	var level_w := CardTokens.display_font().get_string_size(CardTokens.tt("tree_level") % 99, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(CardTokens.TREE_FONT_HEAD))).x
	var left_w := maxf(face.get_string_size(xp_sample, HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x, level_w) + gap
	var x := gap
	_level.position = Vector2(x, head_h * 0.5 - line)
	_level.size = Vector2(left_w, line)
	CardTokens.hub_text(_level, CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, s, 0, "display")
	_xp_back.position = Vector2(x, head_h * 0.5 + line * 0.05)
	_xp_back.size = Vector2(left_w, line * 0.9)
	_style_xp()
	x += left_w + gap
	var coin := line * 0.95
	_coin.position = Vector2(x, head_h * 0.5 - line + (line - coin) * 0.5)
	_coin.size = Vector2(coin, coin)
	_points.position = Vector2(x + coin + gap * 0.4, head_h * 0.5 - line)
	_points.size = Vector2(170.0 * s + coin, line)
	CardTokens.hub_text(_points, CardTokens.TREE_FONT_HEAD, CardTokens.HUB_CREAM, s, 0, "display")
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# two slots from the right: Confirm / Reset Race, then Cancel / Reset Class
	var bw := CardTokens.TREE_COMPACT_BUTTON_W * s
	var bh := head_h - gap * 0.6
	var right := size.x - gap * 0.5
	for slot in [[_confirm, _reset_race], [_cancel, _reset_class]]:
		for b in slot:
			b.size = Vector2(bw, bh)
			b.position = Vector2(right - bw, (head_h - bh) * 0.5)
			_skin(b)
		right -= bw + gap * 0.5
	_branches.position = Vector2(x, head_h * 0.5)
	_branches.size = Vector2(maxf(0.0, right - x - gap * 0.5), line)
	CardTokens.hub_text(_branches, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_MUTED, s, 0, "medium")
	_branches.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return head_h


func _style_xp() -> void:
	CardTokens.panel(_xp_back, CardTokens.hub_bar(CardTokens.HUB_BAR_BACK, s))
	CardTokens.panel(_xp_fill, CardTokens.hub_bar(CardTokens.HUB_BAR_FILL, s))
	_xp_text.position = _xp_back.position
	_xp_text.size = _xp_back.size
	CardTokens.hub_text(_xp_text, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "medium")


## The plate art on big screens; the flat parchment button where the plate's fixed margins would not fit.
func _skin(b: Button) -> void:
	b.custom_minimum_size = Vector2.ZERO
	if s >= CardTokens.TREE_PLATE_MIN_SCALE:
		CarvedLook.plate_button(b, s)
	else:
		CarvedLook.chip_button(b, s)
	CardTokens.tree_keep_plate_when_disabled(b)
	b.clip_text = true  # the text never makes the button wider than its slot (it wraps instead, _fit_button)


## Fits a button's label into the room inside its skin: the largest size down to FONT_MIN on one line, else two lines.
func _fit_button(b: Button, font: int, color: Color, face: String) -> void:
	var box := b.get_theme_stylebox("normal")
	var room := b.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0) - 4.0 * s
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	CardTokens.hub_fit(b, b.text, font, room, color, s, 0, face)
	var px := b.get_theme_font_size("font_size")
	var used: Font = b.get_theme_font("font")
	if used != null and used.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Disabled buttons keep their plate, dimmed (TREE_PLATE_OFF), with readable ink text (TREE_TEXT_OFF).
func _set_enabled(b: Button, on: bool) -> void:
	b.disabled = not on


## Width kept free at the left of each branch for the gate tags ("Needs 13").
func _gutter() -> float:
	var px := maxi(int(round(CardTokens.TREE_FONT_GATE * s)), CardTokens.FONT_MIN)
	var widest := 0
	for branch in ["class", "race"]:
		for rule in _data().tiers(branch):
			widest = maxi(widest, int(rule["gate"]))
	var label := _gate_text(widest)
	return CardTokens.display_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 22.0 * s


## "Needs 13", or "13+" below TREE_PLATE_MIN_SCALE (small screens, where the long tag would squeeze the nodes).
func _gate_text(gate: int) -> String:
	return CardTokens.tt("tree_needs" if s >= CardTokens.TREE_PLATE_MIN_SCALE else "tree_needs_short") % gate


## Screen px of a font token (never under FONT_MIN).
func _px(font: int) -> float:
	return maxf(float(font) * s, float(CardTokens.FONT_MIN))


func _text_w(label: Label) -> float:
	var face := CardTokens.display_font()
	return face.get_string_size(label.text if not label.text.is_empty() else "Class 00 · Race 00 · Combo 0", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px(CardTokens.FONT_CHAR_SLOT))).x


## The detail panel: name, branch, state, description and cost lines in a scroll box (long text scrolls, never cut),
## the Learn / Unlearn row at its bottom (plus Close on a phone, where the panel is a sheet over the tree).
func _layout_detail() -> void:
	var pad := CardTokens.CHAR_PAD * s * (0.6 if _compact else 1.0)
	var w := _detail.size.x - pad * 2.0
	var bh := CardTokens.tap(CardTokens.CHAR_ACTION_H, phone) * s
	if _compact:
		bh = minf(bh, _detail.size.y * 0.42)
	var row: Array = [_learn, _unlearn, _close] if _compact else [_learn, _unlearn]
	var bw := (w - pad * 0.5 * float(row.size() - 1)) / float(row.size())
	var x := _detail.position.x + pad
	for b in row:
		b.size = Vector2(bw, bh)
		b.position = Vector2(x, _detail.position.y + _detail.size.y - pad - bh)
		x += bw + pad * 0.5
		_skin(b)
	_close.visible = _compact and not selected.is_empty()
	_d_scroll.position = Vector2(pad, pad)
	_d_scroll.size = Vector2(w, maxf(0.0, _detail.size.y - pad * 2.5 - bh))
	_d_box.custom_minimum_size = Vector2(w - CardTokens.CHAR_PAD * s * 0.5, _d_scroll.size.y)
	CardTokens.gap(_d_box, 4.0, s)
	CardTokens.hub_text(_d_name, CardTokens.TREE_FONT_NAME if not _compact else CardTokens.TREE_FONT_HEAD, CardTokens.HUB_INK, s, 0, "display")
	CardTokens.hub_text(_d_branch, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_SUBTEXT, s, 0, "medium")
	CardTokens.hub_text(_d_state, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
	CardTokens.hub_text(_d_text, CardTokens.TREE_FONT_BODY, CardTokens.HUB_INK, s, 0, "medium")
	_d_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	CardTokens.hub_text(_d_cost, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK, s, 0, "medium")
	_d_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for l in [_d_name, _d_branch, _d_state, _d_text, _d_cost]:  # full height in the scroll box (no ellipsis, no clip)
		l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		l.clip_text = false
		l.custom_minimum_size = Vector2(_d_box.custom_minimum_size.x, 0.0)


## Phone: the detail sheet covers the half of the tree away from the selected node, so the node stays in view.
func _place_sheet() -> void:
	if not _compact:
		_detail.visible = true
		return
	var open := not selected.is_empty() and _nodes.has(selected)
	_detail.visible = open
	if not open:
		return
	var at: Vector2 = _positions.get(selected, Vector2.ZERO) + _scroll.position - Vector2(_scroll.scroll_horizontal, 0.0)
	_detail.position.x = 0.0 if at.x > size.x * 0.5 else size.x - _detail.size.x
	_layout_detail()


## Places the nodes (Boss 2026-11-23: the pictures are the hero). Class branch left, race branch right, tiers from the
## bottom (T1) to the top (T4); the combo sits at the right end of the top class row, next to the race branch. One base
## size N is fitted to the canvas (each kind N x TREE_NODE_KIND, at most TREE_NODE_MAX); the gate tags go in a strip under
## each row when the height allows, else in side gutters, whichever leaves N larger. N never goes under TREE_NODE_MIN
## (TREE_NODE_MIN_PHONE on a phone): the tree scrolls then instead (many nodes / a tiny screen).
func _layout_nodes(canvas: Rect2) -> void:
	var data = _data()
	var race := CardDeck.race_of(deck, card)
	var class_tiers := _by_tier(data.class_nodes(card))
	var race_tiers := _by_tier(data.race_nodes(race))
	var combo: Dictionary = data.combo_node(race, card)
	_combo_id = str(combo.get("id", ""))
	var top_tier := 1
	for t in class_tiers.keys() + race_tiers.keys():
		top_tier = maxi(top_tier, int(t))
	var tiers: Array = range(1, top_tier + 1)
	# the rows in N units: widths (nodes + OR gaps + group gaps) and heights
	var class_units := 0.0
	var race_units := 0.0
	var tall_units := 0.0
	var labelled := 0
	for tier in tiers:
		var class_row: Array = class_tiers.get(tier, []).duplicate()
		if tier == top_tier and not combo.is_empty():
			class_row.append(combo)
		class_units = maxf(class_units, _row_units(class_row))
		race_units = maxf(race_units, _row_units(race_tiers.get(tier, [])))
		var h := 0.0
		for n in class_row + race_tiers.get(tier, []):
			h = maxf(h, _kind_of(n))
		tall_units += h * _row_pad()
		if _gate(data, "class", tier) > 0 or _gate(data, "race", tier) > 0:
			labelled += 1
	var wide_units := class_units + race_units + (CardTokens.TREE_BRANCH_GAP if race_units > 0.0 else 0.0)
	var label_h := _px(CardTokens.TREE_FONT_GATE) * 1.3
	var gutter := _gutter()
	var in_rows := minf(canvas.size.x / maxf(wide_units, 1.0), (canvas.size.y - label_h * labelled) / maxf(tall_units, 1.0))
	var in_gutters := minf((canvas.size.x - gutter * 2.0) / maxf(wide_units, 1.0), canvas.size.y / maxf(tall_units, 1.0))
	_labels_in_rows = in_rows >= in_gutters
	var n_fit := maxf(in_rows, in_gutters)
	var n_min := (CardTokens.TREE_NODE_MIN_COMPACT if _compact else (CardTokens.TREE_NODE_MIN_PHONE if phone else CardTokens.TREE_NODE_MIN)) * s
	node_base = clampf(n_fit, n_min, maxf(CardTokens.TREE_NODE_MAX * s, n_min))
	# the content: the canvas, or larger when N had to stay over its least size (the tree scrolls then)
	var side_room := 0.0 if _labels_in_rows else gutter * 2.0
	var strip := label_h if _labels_in_rows else 0.0
	var need := Vector2(wide_units * node_base + side_room, tall_units * node_base + strip * labelled)
	var content := Vector2(maxf(canvas.size.x, ceilf(need.x)), maxf(canvas.size.y, ceilf(need.y)))
	_lines.custom_minimum_size = content
	_lines.size = content
	var left := 0.0 if _labels_in_rows else gutter
	var usable := content.x - side_room - (CardTokens.TREE_BRANCH_GAP * node_base if race_units > 0.0 else 0.0)
	var class_w := usable * class_units / maxf(class_units + race_units, 0.01)
	var race_x := left + class_w + CardTokens.TREE_BRANCH_GAP * node_base
	var race_w := usable - class_w
	var extra := (content.y - need.y) / float(tiers.size())  # spare height, shared by the rows
	_positions.clear()
	_bands.clear()
	_or_marks.clear()
	var class_color: Color = CardTokens.palette(card)["shadow"]
	var race_color := CardTokens.race_color(race)
	var y := content.y
	for tier in tiers:
		var class_row: Array = class_tiers.get(tier, [])
		var race_row: Array = race_tiers.get(tier, [])
		var h := 0.0
		for n in class_row + race_row + ([combo] if tier == top_tier and not combo.is_empty() else []):
			h = maxf(h, _kind_of(n))
		var has_gate := _gate(data, "class", tier) > 0 or _gate(data, "race", tier) > 0
		var own_strip := strip if has_gate else 0.0
		var row_h := h * _row_pad() * node_base + extra
		var centre_y := y - own_strip - row_h * 0.5
		var band_y := y - own_strip * 0.5 if _labels_in_rows else y
		var combo_slot := 0.0
		if tier == top_tier and not combo.is_empty():  # the combo: right end of the top class row, by the race branch
			var side := node_base * _kind_of(combo)
			combo_slot = side + _group_gap() * node_base
			_put(_combo_id, Vector2(left + class_w - combo_slot * 0.5, centre_y), side)
		_place_row(class_row, left, class_w - combo_slot, centre_y)
		_place_row(race_row, race_x, race_w, centre_y)
		if tier > 1 or has_gate:
			_bands.append({"y": band_y, "x0": left, "x1": left + class_w, "gate": _gate(data, "class", tier), "color": class_color})
			if not race_row.is_empty():
				_bands.append({"y": band_y, "x0": race_x, "x1": race_x + race_w, "gate": _gate(data, "race", tier), "color": race_color, "right": true})
		y -= own_strip + row_h
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content.x > canvas.size.x + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content.y > canvas.size.y + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	if _opened_at != [card, content]:  # a new card / size opens at the bottom (T1, where the player starts)
		_opened_at = [card, content]
		_scroll_to_start.call_deferred()
	_lines.queue_redraw()


func _scroll_to_start() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(maxf(0.0, _lines.size.y - _scroll.size.y))
		_scroll.scroll_horizontal = 0


func _row_pad() -> float:
	return CardTokens.TREE_ROW_PAD_COMPACT if _compact else CardTokens.TREE_ROW_PAD


func _group_gap() -> float:
	return CardTokens.TREE_GROUP_GAP_COMPACT if _compact else CardTokens.TREE_GROUP_GAP


func _gate(data, branch: String, tier: int) -> int:
	return int(data.tier_rule(branch, tier).get("gate", 0))


## True when the tree is larger than its canvas (it scrolls).
func scrolls() -> bool:
	return _lines.size.x > _scroll.size.x + 0.5 or _lines.size.y > _scroll.size.y + 0.5


## A row's width in N units: its groups (an OR pair as one group with the "or" gap) and the gaps between and around them.
func _row_units(row: Array) -> float:
	var groups := _groups(row)
	if groups.is_empty():
		return 0.0
	var units := _group_gap() * float(groups.size() + 1)
	for group in groups:
		for n in group:
			units += _kind_of(n)
		if group.size() > 1:
			units += CardTokens.TREE_PAIR_GAP
	return units


## [[node, node?]] in data order, an OR pair as one group.
func _groups(row: Array) -> Array:
	var groups: Array = []
	var seen := {}
	for n in row:
		var excl := str(n["excl"])
		if excl.is_empty():
			groups.append([n])
		elif not seen.has(excl):
			seen[excl] = groups.size()
			groups.append([n])
		else:
			groups[int(seen[excl])].append(n)
	return groups


func _by_tier(nodes: Array) -> Dictionary:
	var out := {}
	for n in nodes:
		var tier := int(n["tier"])
		if not out.has(tier):
			out[tier] = []
		out[tier].append(n)
	return out


## A node's size in N units (TREE_NODE_KIND of its kind; the combo is "combo").
func _kind_of(n: Dictionary) -> float:
	var kind := "combo" if _data().branch_of(str(n["id"])) == "combo" else str(n["type"])
	return float(CardTokens.TREE_NODE_KIND.get(kind, 1.0))


## One row in [x, x + w] at height y: the groups spread evenly (equal gaps between and around them); an OR pair keeps
## its two nodes TREE_PAIR_GAP apart with the "or" word between them.
func _place_row(row: Array, x: float, w: float, y: float) -> void:
	var groups := _groups(row)
	if groups.is_empty():
		return
	var widths: Array = []
	var total := 0.0
	for group in groups:
		var gw := 0.0
		for n in group:
			gw += _kind_of(n) * node_base
		if group.size() > 1:
			gw += CardTokens.TREE_PAIR_GAP * node_base
		widths.append(gw)
		total += gw
	var gap := maxf(0.0, (w - total) / float(groups.size() + 1))
	var at := x + gap
	for i in groups.size():
		var group: Array = groups[i]
		var cx := at
		for j in group.size():
			var side := _kind_of(group[j]) * node_base
			_put(str(group[j]["id"]), Vector2(cx + side * 0.5, y), side)
			cx += side
			if j == 0 and group.size() > 1:
				_or_marks.append(Vector2(cx + CardTokens.TREE_PAIR_GAP * node_base * 0.5, y))
				cx += CardTokens.TREE_PAIR_GAP * node_base
		at += float(widths[i]) + gap


func _put(id: String, centre: Vector2, side: float) -> void:
	if not _nodes.has(id):
		return
	var b: Control = _nodes[id]
	b.size = Vector2(side, side)
	b.position = centre - b.size * 0.5
	b.set("s", s)
	_positions[id] = centre


# ================================================================== picture
func refresh() -> void:
	if card.is_empty() or _header == null:
		return
	var data = _data()
	var summary := CardProgress.summary(deck, card)
	var used := SkillTree.spent(draft, data)
	var owned := SkillTree.owned(deck, card)
	var owned_used := SkillTree.spent(owned, data)
	var free := int(summary["points"]) - int(used["total"])
	_level.text = CardTokens.tt("tree_level") % int(summary["level"])
	_xp_text.text = CardTokens.tt("tree_xp_max") if bool(summary["max"]) else CardTokens.tt("tree_xp") % [int(summary["xp"]), int(summary["xp_next"])]
	var fill := 1.0 if bool(summary["max"]) else float(summary["xp"]) / maxf(1.0, float(summary["xp_next"]))
	_xp_fill.size = Vector2(_xp_back.size.x * clampf(fill, 0.0, 1.0), _xp_back.size.y)
	_points.text = CardTokens.tt("tree_points") % free
	_branches.text = CardTokens.tt("tree_branch_points") % [int(used["class"]), int(used["race"]), int(used["combo"])]
	var reset_gold: int = int(owned_used["class"]) * data.class_reset_gold_per_point()
	_reset_class.text = CardTokens.tt("tree_reset_confirm") if _reset_armed == "class" else CardTokens.tt("tree_reset_class") % reset_gold
	_set_enabled(_reset_class, not (owned["class"].is_empty() or gold < reset_gold or has_changes()))
	_reset_race.text = CardTokens.tt("tree_reset_confirm") if _reset_armed == "race" else CardTokens.tt("tree_reset_race")
	_set_enabled(_reset_race, not ((owned["race"].is_empty() and owned["combo"].is_empty()) or has_changes()))
	_confirm.text = CardTokens.tt("tree_confirm")
	_set_enabled(_confirm, has_changes())
	_cancel.text = CardTokens.tt("tree_cancel")
	_set_enabled(_cancel, has_changes())
	for b in [_reset_class, _reset_race, _confirm, _cancel]:
		_fit_button(b, CardTokens.FONT_CHAR_SLOT, CardTokens.HUB_INK if not b.disabled else CardTokens.TREE_TEXT_OFF, "medium")
		CardTokens.tree_disabled_text(b)
	if _compact:  # one pair per slot: the draft buttons while drafting, else the resets
		_confirm.visible = has_changes()
		_cancel.visible = has_changes()
		_reset_class.visible = not has_changes()
		_reset_race.visible = not has_changes()
	for id in _nodes:
		var b = _nodes[id]
		b.state = node_state(id)
		b.selected = id == selected
		b.queue_redraw()
	_place_sheet()
	_refresh_detail()
	_lines.queue_redraw()


func _refresh_detail() -> void:
	var data = _data()
	var n: Dictionary = data.node(selected)
	var empty := n.is_empty() or not _nodes.has(selected)
	_learn.visible = not empty
	_unlearn.visible = not empty
	_close.visible = _compact and not empty
	if empty:
		_d_name.text = CardTokens.tt("tree_pick")
		_d_branch.text = ""
		_d_state.text = ""
		_d_text.text = ""
		_d_cost.text = ""
		return
	var branch: String = data.branch_of(selected)
	_d_name.text = str(n["name"])
	_d_branch.text = CardTokens.tt("tree_branch_" + branch) + ("  ·  T%d" % int(n["tier"]) if int(n["tier"]) > 0 else "")
	var state := node_state(selected)
	_d_state.text = CardTokens.tt(["tree_state_locked", "tree_state_available", "tree_state_no_points", "tree_state_taken", "tree_state_draft"][state])
	_d_state.visible = not _compact
	if _compact:  # phone: branch and state share one line (more room for the description)
		_d_branch.text += "  ·  " + _d_state.text
	_d_text.text = data.description(selected, CardTokens.language)
	var lines: Array[String] = [CardTokens.tt("tree_cost") % int(n["cost"])]
	if branch == "combo":
		lines.append(CardTokens.tt("tree_gate_combo") % [int(data.combo_rule()["class_gate"]), int(data.combo_rule()["race_gate"])])
	else:
		var gate := int(data.tier_rule(branch, int(n["tier"])).get("gate", 0))
		if gate > 0:
			lines.append(CardTokens.tt("tree_gate") % gate)
	if not str(n["excl"]).is_empty():
		for other in shown_nodes():
			if str(other["excl"]) == str(n["excl"]) and other["id"] != n["id"]:
				lines.append(CardTokens.tt("tree_or") % str(other["name"]))
	_d_cost.text = "\n".join(lines)
	_d_scroll.scroll_vertical = 0
	_learn.text = CardTokens.tt("tree_learn")
	_set_enabled(_learn, state == SkillTreeNode.State.AVAILABLE)
	_unlearn.text = CardTokens.tt("tree_unlearn")
	_set_enabled(_unlearn, state == SkillTreeNode.State.DRAFT)
	_close.text = CardTokens.t("close")
	for b in [_learn, _unlearn, _close]:
		_fit_button(b, CardTokens.FONT_CHAR_LINE, CardTokens.HUB_INK if not b.disabled else CardTokens.TREE_TEXT_OFF, "display")
		CardTokens.tree_disabled_text(b)


## Tier lines with their gate numbers as plain outlined ink ("Needs 8", no tag box), the small "or" word between each OR
## pair, and the only ink paths: a class T1 node up to its two T2 fork nodes (solid colour once taken, else faint ink).
## The other tiers need no path: their gate line says what opens them.
func _draw_lines() -> void:
	var font := CardTokens.display_font()
	var font_size := int(_px(CardTokens.TREE_FONT_GATE))
	var outline := maxi(2, int(4.0 * s))
	for band in _bands:
		_lines.draw_line(Vector2(band["x0"], band["y"]), Vector2(band["x1"], band["y"]), CardTokens.TREE_BAND, maxf(1.0, 2.0 * s))
		if int(band["gate"]) > 0:
			var text := _gate_text(int(band["gate"]))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var right := bool(band.get("right", false))
			var x: float
			if _labels_in_rows:  # inside the strip under the row, at the branch's outer end
				x = float(band["x1"]) - w - 6.0 * s if right else float(band["x0"]) + 6.0 * s
			else:  # in the side gutter
				x = float(band["x1"]) + 6.0 * s if right else float(band["x0"]) - w - 6.0 * s
			var at := Vector2(x, float(band["y"]) + font_size * 0.35)
			_lines.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, CardTokens.HUB_PAPER)
			_lines.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CardTokens.HUB_INK)  # ink: readable for every race colour
	var or_size := int(_px(CardTokens.TREE_FONT_OR))
	var or_text := CardTokens.tt("tree_or_word")
	var or_w := font.get_string_size(or_text, HORIZONTAL_ALIGNMENT_LEFT, -1, or_size).x
	for mark in _or_marks:
		var at := Vector2(mark.x - or_w * 0.5, mark.y + or_size * 0.35)
		_lines.draw_string_outline(font, at, or_text, HORIZONTAL_ALIGNMENT_LEFT, -1, or_size, outline, CardTokens.HUB_PAPER)
		_lines.draw_string(font, at, or_text, HORIZONTAL_ALIGNMENT_LEFT, -1, or_size, CardTokens.HUB_INK)
	var data = _data()
	var class_nodes: Array = data.class_nodes(card)
	var t1: Array = class_nodes.filter(func(n): return int(n["tier"]) == 1)
	var pairs: Array = []
	for n in class_nodes:
		if int(n["tier"]) == 2 and not pairs.has(str(n["excl"])):
			pairs.append(str(n["excl"]))
	var width := maxf(1.5, CardTokens.TREE_PATH_W * s)
	for id in _positions:
		var n: Dictionary = data.node(id)
		if data.branch_of(id) != "class" or int(n["tier"]) != 2:
			continue
		var at := pairs.find(str(n["excl"]))
		if at < 0 or at >= t1.size() or not _positions.has(str(t1[at]["id"])):
			continue
		var to: Vector2 = _positions[id]
		var parent: Vector2 = _positions[str(t1[at]["id"])]
		var on: bool = draft.get("class", []).has(id)
		var from := parent - Vector2(0.0, (_nodes[str(t1[at]["id"])] as Control).size.y * 0.5)
		_lines.draw_line(from, to + Vector2(0.0, (_nodes[id] as Control).size.y * 0.5), CardTokens.TREE_PATH_ON if on else CardTokens.TREE_PATH_OFF, width, true)
