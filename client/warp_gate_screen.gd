extends CanvasLayer
## The Warp Gate window: the player walks into the warp gate in the camp and picks what to play.
## Three tabs (Journey / Farm / PvP), a list of destinations, a detail pane and one big Enter button.
## Enter starts the content itself through the same GameState calls the old campfire menu used
## (GameState.start_journey(id), GameState.start_stage(mode, map id)); Esc / B / Close emits `closed`.
## It pauses nothing and decides no rule: the lists come from data (data/journeys/*.json, the maps in
## data/maps/index.json for each mode) and the facts shown are read from that data.
##   var gate = WarpGateScreen.new(); add_child(gate); gate.closed.connect(on_closed)
## The window frees itself after `closed`. Set `tab` before add_child() to open on another tab.
## Keyboard / gamepad: up/down/left/right moves the focus, accept picks; focusing a destination
## selects it, accepting it moves on to Enter. Touch: every target is at least 44 pt on a phone.
## EXTENDING: a new tab is one more entry in TABS + TEXT words + a branch in destinations_for() and
## enter(); a journey's own blurb is TEXT["blurb_<journey id>"] (or a "blurb" field in its file).

const InkUi := preload("res://client/ink_ui.gd")
const BrassIcons := preload("res://client/brass_icons.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const JourneyData := preload("res://logic/journey_data.gd")

signal closed
signal skill_requested
## Emitted right before the chosen content is started ("journey" / "farm" / "pvp", the journey or map id).
signal entered(kind: String, id: String)

const JOURNEY_DIR := "res://data/journeys/"
const DEFAULT_JOURNEY := "ink_road"  ## listed first (GameState.DEFAULT_JOURNEY)
## The tabs, left to right.
const TABS := ["journey", "farm", "pvp"]
const TAB_ICONS := {"journey": "journey", "farm": "pve", "pvp": "pvp"}

## Every word the window shows (one place, for translation). Tab and button words are also how the
## tests find them.
const TEXT := {
	"title": "Warp Gate", "close": "Close", "enter": "Enter",
	"journey": "Journey", "farm": "Farm", "pvp": "PvP",
	"empty_journey": "No journey is open yet.", "empty_farm": "No farm stage is open yet.",
	"empty_pvp": "No PvP arena is open yet.",
	"empty_detail": "The gate shows nothing here yet. Try another tab.",
	"broken": "This destination's data could not be read.",
	"start_failed": "The gate could not open this journey (its data is broken). Pick another.",
	"pick": "Pick a destination on the left.",
	"blurb_journey": "A road of %d stages. After each stage you pick the next one; a boss waits at the end.",
	"blurb_farm": "A single stage. Fight, gather loot and come back to camp.",
	"blurb_pvp": "An arena for fighting other players.",
	"row_journey": "%d stages  ·  monster level %s",
	"row_map": "%s  ·  %s",
	"camps": "Camps: one of stages %s, and stage %d",
	"boss": "Boss: %s at stage %d",
	"treasure": "Treasure: %s gear or better",
	"bag_note": "Leave before a camp and the run bag is lost.",
	"bank_note": "At a camp you can send the bag to the stash.",
	"monsters": "%d monsters", "no_monsters": "no monsters",
	"monster_kinds": "Monsters: %s",
	"monster_level": "Monster level %s",
	"rest_points": "Rest points: %d",
	"no_rest": "No rest point",
	"practice": "No monsters: a place to try your moves.",
}

## Layout per mode, in menu units: window size (0 = the whole room), tab / row / Enter heights
## (>= 56 on phones = 44 pt), the list's width (0 = above the details), the portal emblem's size.
const LAYOUT := {
	InkUi.WIDE: {"panel": Vector2(1080.0, 640.0), "tab": 48.0, "row": 64.0, "enter": 60.0, "list": 380.0, "emblem": 108.0, "close": 48.0},
	InkUi.COMPACT: {"panel": Vector2.ZERO, "tab": 56.0, "row": 60.0, "enter": 60.0, "list": 380.0, "emblem": 72.0, "close": 56.0},
	InkUi.PORTRAIT: {"panel": Vector2.ZERO, "tab": 56.0, "row": 60.0, "enter": 64.0, "list": 0.0, "emblem": 72.0, "close": 56.0},
}

var tab := "journey"  ## the open tab (set before add_child() to open on another)
## What starts the content: the GameState autoload unless set before add_child() (the tests use a fake
## with start_journey(id) -> bool and start_stage(mode, id)).
var starter: Object
## > 0 replaces the screen's pixel density (screenshot tools on a Retina Mac use 1).
var density_override := 0.0
var tab_buttons := {}  ## tab -> Button
var rows: Array[Button] = []  ## the destinations of the open tab
var selected := -1  ## index into the open tab's destinations
var enter_button: Button
var close_button: Button
var skill_button: Button
var connection_copy: Button
var message: Label  ## an error (a journey that would not start)

var _destinations := {}  ## tab -> Array[Dictionary] (see destinations_for())
var _root: Control
var _window: PanelContainer
var _list_box: VBoxContainer
var _detail: VBoxContainer
var _emblem: Portal
var _mode := ""
var _layout := {}
var _closing := false


func _ready() -> void:
	layer = 20  # (over the camp's HUD)
	if starter == null:
		starter = get_node_or_null("/root/GameState")
	if not tab in TABS:
		tab = TABS[0]
	for key in TABS:
		_destinations[key] = destinations_for(key)
	_root = Control.new()
	_root.theme = InkUi.make_theme(InkUi.FONT_BODY)
	add_child(_root)
	var scrim := ColorRect.new()  # (stops clicks reaching the world: a click there is an attack)
	scrim.color = InkUi.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_play("open")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Closes the window (Esc, B, the Close button): emits `closed` once, then frees itself.
func close() -> void:
	if _closing:
		return
	if starter==GameState and (GameState._solo_connecting or (GameState.remote_session!=null and not GameState.remote_session.ready)):
		GameState.cancel_pending_solo()
	_closing = true
	_play("click")
	closed.emit()
	queue_free()


# ------------------------------------------------------------------ data

## The destinations of a tab, from data: [{"id", "name", "sub" (short words under the name),
## "blurb", "facts": Array[String], "note", "ok": bool}]. Journey: every file in data/journeys/
## (the default one first); Farm / PvP: the valid maps of data/maps/index.json for "pve" / "pvp",
## in index order (the same list the campfire menu showed).
static func destinations_for(kind: String) -> Array:
	match kind:
		"journey":
			var list: Array = []
			for id in journey_ids():
				list.append(_journey_entry(id))
			return list
		"farm", "pvp":
			var list: Array = []
			for map in MapLoader.list_for_mode("pve" if kind == "farm" else "pvp"):
				list.append(_map_entry(map, kind))
			return list
	return []


## The journey ids in data/journeys/, the default journey first, the rest by name.
static func journey_ids() -> Array:
	var ids: Array = []
	for file_name in DirAccess.get_files_at(JOURNEY_DIR):
		if file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
	ids.sort()
	if ids.has(DEFAULT_JOURNEY):
		ids.erase(DEFAULT_JOURNEY)
		ids.push_front(DEFAULT_JOURNEY)
	return ids


static func _journey_entry(id: String) -> Dictionary:
	var data = JourneyData.load_by_id(id)
	if not data.is_valid():
		return {"id": id, "name": id.capitalize(), "sub": TEXT["broken"], "blurb": TEXT["broken"], "facts": [], "note": "", "ok": false}
	var low := 999
	var high := 0
	for stage in data.stages:
		for enemy in stage.get("enemies", []):
			var level := int(enemy.get("level", stage.get("level", 1)))
			low = mini(low, level)
			high = maxi(high, level)
	var levels := _range_text(low, high) if high > 0 else "?"
	var facts: Array[String] = []  # (the stage count and monster levels are in the subtitle)
	var first: Array = data.first_camp_stages.duplicate()
	first.sort()
	if not first.is_empty():
		var first_text := _range_text(int(first[0]), int(first[-1])) if first.size() > 1 else str(first[0])
		facts.append(TEXT["camps"] % [first_text, data.last_camp_stage])
	var boss_name := ""
	for enemy in data.stages[-1].get("enemies", []):
		if bool(enemy.get("boss", false)):
			boss_name = str(enemy.get("type", "")).capitalize()
	if boss_name != "":
		facts.append(TEXT["boss"] % [boss_name, data.stage_count])
	if not str(data.treasure.get("min_tier", "")).is_empty():
		facts.append(TEXT["treasure"] % str(data.treasure["min_tier"]).capitalize())
	if data.camp_banks_bag:
		facts.append(TEXT["bank_note"])
	var note: String = TEXT["bag_note"]
	var blurb: String = TEXT.get("blurb_" + id, TEXT["blurb_journey"] % data.stage_count)
	var own = JSON.parse_string(FileAccess.get_file_as_string(JOURNEY_DIR + id + ".json"))
	if own is Dictionary and str(own.get("blurb", "")) != "":
		blurb = str(own["blurb"])
	return {"id": id, "name": data.display_name, "sub": TEXT["row_journey"] % [data.stage_count, levels], "blurb": blurb,
		"facts": facts, "note": note, "ok": true}


static func _map_entry(map, kind: String) -> Dictionary:
	var count: int = map.enemy_spawns.size()
	var low := 999
	var high := 0
	var kinds: Array[String] = []
	for spawn in map.enemy_spawns:
		var level := int(spawn.get("level", 1))
		low = mini(low, level)
		high = maxi(high, level)
		var type_name := str(spawn.get("type", "")).capitalize()
		if not type_name in kinds:
			kinds.append(type_name)
	var tag := _tag(map.display_name)
	var sub_words: String = TEXT["monsters"] % count if count > 0 else TEXT["no_monsters"]
	if tag == sub_words:
		tag = ""
	var facts: Array[String] = []
	if count > 0:
		facts.append(TEXT["monster_kinds"] % ", ".join(kinds))
		facts.append(TEXT["monster_level"] % _range_text(low, high))
	facts.append(TEXT["rest_points"] % map.rest_points.size() if not map.rest_points.is_empty() else TEXT["no_rest"])
	return {"id": map.id, "name": _base_name(map.display_name), "sub": TEXT["row_map"] % [tag, sub_words] if tag != "" else sub_words,
		"blurb": TEXT["blurb_" + kind] if count > 0 or kind == "pvp" else TEXT["practice"], "facts": facts, "note": "", "ok": true}


## "Ink Garden (wide arena)" -> "Ink Garden"; the words in brackets -> _tag().
static func _base_name(display_name: String) -> String:
	return display_name.get_slice(" (", 0)


static func _tag(display_name: String) -> String:
	if not " (" in display_name:
		return ""
	return display_name.get_slice(" (", 1).trim_suffix(")")


static func _range_text(low: int, high: int) -> String:
	return str(low) if low == high else "%d-%d" % [low, high]


func destinations(kind: String = "") -> Array:
	return _destinations.get(tab if kind == "" else kind, [])


# ------------------------------------------------------------------ actions

## Opens a tab (rebuilds the list and selects its first destination).
func show_tab(kind: String) -> void:
	if not kind in TABS:
		return
	var changed := kind != tab
	tab = kind
	for key in tab_buttons:
		tab_buttons[key].set_pressed_no_signal(key == tab)
	_build_list()
	select(0 if not destinations().is_empty() else -1)
	if changed:
		_play("click")


## Selects destination `index` of the open tab and shows it in the detail pane.
func select(index: int) -> void:
	var list := destinations()
	selected = index if index >= 0 and index < list.size() else -1
	for i in rows.size():
		rows[i].set_pressed_no_signal(i == selected)
		rows[i].queue_redraw()
	if message != null:
		message.visible = false
	_show_detail()


## Starts the selected destination (the Enter button).
func enter() -> void:
	var list := destinations()
	if selected < 0 or selected >= list.size() or not list[selected]["ok"] or starter == null:
		return
	if starter==GameState and GameState.remote_session!=null and not GameState.remote_session.ready:
		GameState.cancel_pending_solo(false)
	var id := str(list[selected]["id"])
	_play("select")
	entered.emit(tab, id)
	match tab:
		"journey":
			if not starter.start_journey(id):
				message.text = TEXT["start_failed"]
				message.visible = true
		"farm":
			starter.start_stage(GameState.Mode.PVE, id)
		"pvp":
			starter.start_stage(GameState.Mode.PVP, id)


func _play(sound: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and is_inside_tree():
		audio.play_ui(sound)


# ------------------------------------------------------------------ layout

func _fit() -> void:
	if _root == null or not is_inside_tree():
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	var density := density_override if density_override > 0.0 else DisplayServer.screen_get_scale()
	apply_layout(InkUi.layout_for(window, logical, density))


## Lays the window out for a layout (InkUi.layout_for()): rebuilt when the mode changes (a phone
## turned), only resized otherwise.
func apply_layout(layout: Dictionary) -> void:
	_layout = layout
	_root.scale = Vector2.ONE * float(layout["scale"])
	_root.size = layout["size"]
	if layout["mode"] != _mode:
		_mode = layout["mode"]
		_build_window()
	_place_window()


func _place_window() -> void:
	var area := _root.size
	var wanted: Vector2 = LAYOUT[_mode]["panel"]
	var room := area - Vector2.ONE * float(InkUi.edge_for(_mode)) * 2.0
	var size := room if wanted == Vector2.ZERO else Vector2(minf(wanted.x, room.x), minf(wanted.y, room.y))
	_window.custom_minimum_size = size
	_window.size = size
	_window.position = (area - size) * 0.5


func _build_window() -> void:
	var keep_focus := selected
	if _window != null:
		_root.remove_child(_window)
		_window.queue_free()
	var spec: Dictionary = LAYOUT[_mode]
	_window = PanelContainer.new()
	InkUi.panel(_window, InkUi.window_style())
	_root.add_child(_window)
	var box := VBoxContainer.new()
	InkUi.gap(box, InkUi.GAP_L if _mode == InkUi.WIDE else InkUi.GAP_M)
	_window.add_child(box)

	var header := HBoxContainer.new()
	header.add_child(InkUi.brush_title(TEXT["title"], InkUi.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	close_button = Button.new()
	close_button.text = TEXT["close"]
	close_button.custom_minimum_size = Vector2(120.0, spec["close"])
	InkUi.close_button(close_button)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	var tabs := HBoxContainer.new()
	InkUi.gap(tabs, InkUi.GAP_S)
	var group := ButtonGroup.new()
	tab_buttons.clear()
	for key in TABS:
		var button := Button.new()
		button.text = TEXT[key]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0.0, spec["tab"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _mode != InkUi.PORTRAIT:  # (upright the tabs are too narrow for an icon and the word)
			InkUi.icon_button(button, TAB_ICONS[key], 24)
		button.set_pressed_no_signal(key == tab)
		button.pressed.connect(show_tab.bind(key))
		tabs.add_child(button)
		tab_buttons[key] = button
	box.add_child(tabs)

	var body: BoxContainer = VBoxContainer.new() if float(spec["list"]) <= 0.0 else HBoxContainer.new()
	InkUi.gap(body, InkUi.GAP_XL if _mode == InkUi.WIDE else InkUi.GAP_M)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if float(spec["list"]) > 0.0:
		list_scroll.custom_minimum_size = Vector2(spec["list"], 0.0)
	else:
		list_scroll.custom_minimum_size = Vector2(0.0, float(spec["row"]) * 4.0 + InkUi.GAP_S * 3.0)
	body.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(_list_box, InkUi.GAP_S)
	list_scroll.add_child(_list_box)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)
	var detail_box := VBoxContainer.new()
	InkUi.gap(detail_box, InkUi.GAP_M)
	detail_panel.add_child(detail_box)
	var head := HBoxContainer.new()
	InkUi.gap(head, InkUi.GAP_XL)
	detail_box.add_child(head)
	_emblem = Portal.new()
	_emblem.custom_minimum_size = Vector2.ONE * float(spec["emblem"])
	_emblem.ring = InkUi.ORNAMENT
	_emblem.light = Color(InkUi.GLASS_GLOW, 0.55)  # (the portal's glow is the glass teal, stronger)
	_emblem.core = InkUi.INK
	_emblem.spark = InkUi.GOLD
	_emblem.icon_tint = InkUi.ICON_TINT
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_emblem)
	_detail = VBoxContainer.new()  # (the name and its words: refilled by _show_detail())
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(_detail)
	var facts_scroll := ScrollContainer.new()
	facts_scroll.name = "Facts"
	facts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	facts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(facts_scroll)
	var facts := VBoxContainer.new()
	facts.name = "List"
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(facts, InkUi.GAP_S)
	facts_scroll.add_child(facts)
	var note := _wrapped("", InkUi.WARN, InkUi.FONT_LABEL)  # (a warning stays in view, outside the scroll)
	note.name = "Note"
	note.visible = false
	detail_box.add_child(note)
	message = _wrapped(TEXT["start_failed"], InkUi.BAD, InkUi.FONT_LABEL)
	message.visible = false
	detail_box.add_child(message)
	skill_button=Button.new();skill_button.text="ตั้งค่า Skill Tree / Build"
	skill_button.custom_minimum_size=Vector2(180,44)
	skill_button.visible=false
	skill_button.pressed.connect(func() -> void: close();skill_requested.emit())
	detail_box.add_child(skill_button)
	connection_copy=Button.new();connection_copy.text="คัดลอกเหตุขัดข้อง / Connection report"
	connection_copy.custom_minimum_size=Vector2(180,44)
	connection_copy.pressed.connect(_copy_connection)
	detail_box.add_child(connection_copy)
	enter_button = Button.new()
	enter_button.text = TEXT["enter"]
	enter_button.custom_minimum_size = Vector2(0.0, spec["enter"])
	InkUi.make_primary(enter_button)
	InkUi.style_text(enter_button, InkUi.TEXT_STRONG, InkUi.FONT_TITLE)
	enter_button.pressed.connect(enter)
	detail_box.add_child(enter_button)

	_build_list()
	select(keep_focus if keep_focus >= 0 else (0 if not destinations().is_empty() else -1))
	_focus_start.call_deferred()


func _focus_start() -> void:
	if not is_inside_tree():
		return
	if selected >= 0 and selected < rows.size():
		rows[selected].grab_focus()
	elif tab_buttons.has(tab):
		tab_buttons[tab].grab_focus()


func _build_list() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	rows.clear()
	var list := destinations()
	if list.is_empty():
		_list_box.add_child(_wrapped(TEXT["empty_" + tab], InkUi.MUTED, InkUi.FONT_LABEL))
		return
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in list.size():
		var row := Row.new()
		row.toggle_mode = true
		row.button_group = group
		row.custom_minimum_size = Vector2(0.0, LAYOUT[_mode]["row"])
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.marker = InkUi.SEAL
		row.marker_dark = InkUi.INK
		var line := HBoxContainer.new()  # (room on the left for the drawn selection marker)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		InkUi.gap(line, 0)
		row.add_child(line)
		var room := Control.new()
		room.custom_minimum_size = Vector2(Row.MARKER_ROOM, 0.0)
		room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(room)
		var words := VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		InkUi.gap(words, 0)
		line.add_child(words)
		var tail := Control.new()
		tail.custom_minimum_size = Vector2(InkUi.GAP_M, 0.0)
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(tail)
		var name_label := InkUi.label(list[i]["name"], InkUi.PAPER if list[i]["ok"] else InkUi.BAD, InkUi.FONT_SECTION)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.add_child(name_label)
		var sub_label := InkUi.label(list[i]["sub"], InkUi.MUTED, InkUi.FONT_NOTE)
		sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.add_child(sub_label)
		for label in [name_label, sub_label]:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.pressed.connect(_row_pressed.bind(i))
		row.focus_entered.connect(func() -> void:
			if selected != i:
				select(i))
		_list_box.add_child(row)
		rows.append(row)


## Clicking / accepting a destination selects it; accepting the selected one moves on to Enter.
func _row_pressed(index: int) -> void:
	var was := selected
	select(index)
	if was == index and enter_button != null and not enter_button.disabled:
		enter_button.grab_focus()


func _show_detail() -> void:
	if _detail == null:
		return
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var facts: VBoxContainer = _window.find_child("List", true, false)
	for child in facts.get_children():
		facts.remove_child(child)
		child.queue_free()
	_emblem.icon_name = TAB_ICONS[tab]
	var list := destinations()
	if selected < 0:
		_emblem.lit = false
		_detail.add_child(InkUi.label(TEXT[tab], InkUi.MUTED, InkUi.FONT_TITLE))
		facts.add_child(_wrapped(TEXT["empty_detail"] if list.is_empty() else TEXT["pick"], InkUi.MUTED, InkUi.FONT_BODY))
		enter_button.disabled = true
		(_window.find_child("Note", true, false) as Label).visible = false
		_emblem.queue_redraw()
		return
	var entry: Dictionary = list[selected]
	_emblem.lit = entry["ok"]
	var title := InkUi.label(entry["name"], InkUi.GOLD if entry["ok"] else InkUi.BAD, InkUi.FONT_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(120.0, 0.0)
	_detail.add_child(title)
	_detail.add_child(_wrapped(entry["sub"], InkUi.MUTED, InkUi.FONT_SMALL))
	if _mode != InkUi.COMPACT or entry["facts"].size() < 3:  # (a phone on its side: room for the facts first)
		facts.add_child(_wrapped(entry["blurb"], InkUi.PAPER, InkUi.FONT_BODY))
	for line in entry["facts"]:
		facts.add_child(_bullet(line))
	var note: Label = _window.find_child("Note", true, false)
	note.text = "! " + str(entry["note"])
	note.visible = str(entry["note"]) != ""
	enter_button.disabled = not entry["ok"]
	_emblem.queue_redraw()


func _wrapped(text: String, color: Color, size: int) -> Label:
	var l := InkUi.label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120.0, 0.0)
	return l


## One fact line with a small brass diamond in front.
func _bullet(text: String) -> Control:
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_M)
	var mark := Bullet.new()
	mark.color = InkUi.ORNAMENT
	mark.custom_minimum_size = Vector2(12.0, 22.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	row.add_child(_wrapped(text, InkUi.PAPER, InkUi.FONT_LABEL))
	return row


# ------------------------------------------------------------------ drawn pieces

## The portal emblem in the detail pane: a toothed brass ring around a glowing teal well, with a
## slowly turning dashed ring and the tab's brass icon in the middle. Unlit (an empty tab, broken
## data): the well is dark and the dashes stop. Drawn in code (0 KB).
class Portal:
	extends Control
	var ring: Color
	var light: Color
	var core: Color
	var spark: Color
	var icon_tint: Color
	var icon_name := "journey"
	var lit := true
	var _turn := 0.0

	func _process(delta: float) -> void:
		if lit and is_visible_in_tree():
			_turn = fmod(_turn + delta * 0.35, TAU)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		if r <= 4.0:
			return
		# the well: a dark core with the glass light rising from its rim
		draw_circle(c, r * 0.86, core)
		if lit:
			for step in 6:
				var k := 1.0 - float(step) / 6.0
				draw_circle(c, r * 0.86 * k, Color(light, light.a * 0.22))
		# the toothed brass ring
		var teeth := PackedVector2Array()
		for i in 64:
			var angle := TAU * float(i) / 64.0
			teeth.append(c + Vector2.from_angle(angle) * (r if (i / 2) % 2 == 0 else r * 0.93))
		teeth.append(teeth[0])
		draw_polyline(teeth, ring, 1.5, true)
		draw_arc(c, r * 0.86, 0.0, TAU, 48, ring, 2.0, true)
		draw_arc(c, r * 0.80, 0.0, TAU, 48, Color(ring, 0.45), 1.0, true)
		# the turning dashes
		var dash := Color(spark, 0.85 if lit else 0.25)
		for i in 12:
			var a := _turn + TAU * float(i) / 12.0
			draw_arc(c, r * 0.70, a, a + 0.28, 6, dash, 2.0, true)
		# four studs on the ring
		for i in 4:
			var at := c + Vector2.from_angle(TAU * float(i) / 4.0 + PI * 0.25) * r * 0.86
			var s := maxf(2.5, r * 0.07)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)]), ring)
		var icon_r := r * 0.42
		BrassIcons.draw(self, icon_name, Rect2(c - Vector2.ONE * icon_r, Vector2.ONE * icon_r * 2.0), icon_tint if lit else Color(icon_tint, 0.4))


## A destination in the list: a toggle button; when selected an ember diamond shows in front of the
## words (with the pressed plate's notch), so the choice never rests on color alone.
class Row:
	extends Button
	const MARKER_ROOM := 30.0
	var marker: Color
	var marker_dark: Color

	func _draw() -> void:
		if not button_pressed:
			return
		var c := Vector2(15.0, size.y * 0.5)
		var r := 7.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), marker)
		var r2 := r * 0.4
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0)]), marker_dark)


## A small filled diamond (a fact bullet).
class Bullet:
	extends Control
	var color: Color

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 11.0)
		var r := 4.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


func _process(_delta: float) -> void:
	if skill_button!=null:
		skill_button.visible=starter==GameState and GameState.account_session!=null and not preload("res://logic/skill_build.gd").ready_for_run(GameState.account_session.profile)
	if starter == GameState and GameState.account_session != null and message != null:
		if GameState._solo_connecting:
			message.text = "กำลังเปิดห้องเซิร์ฟเวอร์… " + GameState.solo_phase
			message.show()
		elif GameState.remote_session!=null and not GameState.remote_session.ready:
			var remote=GameState.remote_session
			message.text="รอสถานะห้อง… " + str(remote.error)
			if not remote.close_history.is_empty():message.text+=" · "+str(remote.close_history.back().get("reason",""))
			message.show()
		elif not GameState.online_error.is_empty():
			message.text = GameState.online_error
			message.show()


func _copy_connection() -> void:
	var report:Dictionary={"phase":GameState.solo_phase,"opening":GameState._solo_connecting,"error":GameState.online_error,"last_failure":GameState.last_room_open_failure.duplicate(true)}
	if GameState.remote_session!=null:
		var remote=GameState.remote_session
		report["session"]=remote.debug_metrics();report["close_history"]=remote.close_history.duplicate(true)
	if OS.has_feature("web"):report["build"]=JavaScriptBridge.eval("window.zorxBoot.manifest.build",true)
	DisplayServer.clipboard_set("[ROOM OPEN REPORT v1]\n"+JSON.stringify(report))
