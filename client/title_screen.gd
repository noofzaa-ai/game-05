extends Node
## The title screen (scenes/title.tscn), between the boot loader and the campfire: an animated
## backdrop, the ZORX wordmark top right, a plain text menu bottom right (Start, Version Info,
## Settings, Staff, Exit) and the version number at the bottom. Start opens the existing flow (the
## campfire, which shows the character creator to a new player).
## The backdrop is the level designer's client/title_backdrop.gd (a Node3D) when it exists; until then
## a dark gradient. The version notes and the credits are data (data/ui/version_info.json,
## data/ui/credits.json). Shows things and sends the player on; it decides no game rule.
## Keyboard / gamepad: up/down + accept, Esc / B closes a panel. Mouse hover moves the focus, so one
## brass marker shows where you are. Touch: every item is at least 44 pt tall on a phone.
## EXTENDING: a new menu item is one more entry in ITEMS + a TEXT word + a branch in _activate().

const InkUi := preload("res://client/ink_ui.gd")
const VersionInfo := preload("res://client/version_info.gd")

## The animated backdrop, first one that exists (a script for a Node3D, or a scene).
const BACKDROPS := ["res://client/title_backdrop.gd", "res://scenes/title_backdrop.tscn"]
const CREDITS_PATH := "res://data/ui/credits.json"

## Every word the title screen shows (one place, for translation). Menu words are also how the tests
## find the items.
const TEXT := {
	"logo": "ZORX", "full_name": "Zone of Relic eXplorers",
	"tagline": "Explore • Fight • Loot • Rebuild",
	"start": "Start", "versions": "Version Info", "settings": "Settings", "staff": "Staff", "exit": "Exit",
	"version_corner": "v%s  ·  %s  ·  development build",
	"close": "Close", "versions_title": "Version Info", "settings_title": "Settings", "staff_title": "Staff & Credits",
	"new": "New", "changes": "Changes", "fixes": "Fixes", "in_progress": "In progress",
	"no_versions": "The version notes could not be read.",
	"coming_soon": "Coming soon",
	"settings_note": "Settings are not in the game yet. Planned: camera angle, sound and music volume, key bindings and touch controls.",
	"team": "Team", "credits": "Credits", "no_credits": "The credits could not be read.",
}
## The menu, top to bottom.
const ITEMS := ["start", "versions", "settings", "staff", "exit"]

## Layout per mode, in menu units: item height (>= 56 on phones = 44 pt), logo scale, edge margins.
const LAYOUT := {
	InkUi.WIDE: {"item": 52.0, "logo": 0.85, "edge": Vector2(84.0, 64.0), "panel": Vector2(1000.0, 600.0)},
	InkUi.COMPACT: {"item": 56.0, "logo": 0.5, "edge": Vector2(44.0, 16.0), "panel": Vector2(0.0, 0.0)},
	InkUi.PORTRAIT: {"item": 58.0, "logo": 0.5, "edge": Vector2(24.0, 40.0), "panel": Vector2(0.0, 0.0)},
}

var info := VersionInfo.new()
var items := {}  ## menu word key -> TitleItem
var panel: Control  ## the open panel (null when the menu shows)
var panel_kind := ""
var version_tabs: Array[Button] = []  ## the Version Info tabs, newest first (while it is open)
var version_notes: VBoxContainer  ## the selected version's notes

var _backdrop: Node
var _root: Control  ## everything on screen, scaled to the window (InkUi.layout_for())
var _logo: Wordmark
var _menu: VBoxContainer
var _corner: Label
var _mode := InkUi.WIDE
## > 0 replaces the screen's pixel density (screenshot tools on a Retina Mac use 1 to get the desktop layout).
var density_override := 0.0
var _opened_from: Control
var _connection: VBoxContainer
var _connection_label: Label
var _online_retry: Button
var _offline_button: Button


func _ready() -> void:
	info.load_file()
	for problem in info.errors:
		push_warning("title: " + problem)
	_build_backdrop()
	_build_ui()
	get_viewport().size_changed.connect(_fit)
	_menu.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_fit()
	items["start"].grab_focus()
	Online.changed.connect(_connection_changed)
	_connection_changed()
	if DisplayServer.get_name() != "headless":
		Online.begin()
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("window.zorxAutoEnter === true", true)):
		JavaScriptBridge.eval("window.zorxAutoEnter = false", true)
		_auto_start_google.call_deferred()


func _auto_start_google() -> void:
	# Online.begin() is asynchronous; wait for its result before loading the profile.
	while Online.status == Online.Status.CONNECTING:
		await Online.changed
	if not is_inside_tree():
		return
	if Online.status == Online.Status.AUTHENTICATED:
		start_game()


func _build_backdrop() -> void:
	for path in BACKDROPS:
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		if res is PackedScene:
			_backdrop = res.instantiate()
		elif res is Script and res.can_instantiate():
			_backdrop = res.new()
		if _backdrop != null:
			add_child(_backdrop)
			return
	# Fallback until the 3D backdrop exists: a dark night gradient with a low teal glow.
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var back := TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, InkUi.DOLL_SHADE)
	gradient.set_color(1, InkUi.INK)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.32, 0.78)
	texture.fill_to = Vector2(1.05, 0.0)
	back.texture = texture
	layer.add_child(back)
	_backdrop = layer


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# A shade toward the right and the bottom keeps the words readable over any backdrop.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	ramp.colors = PackedColorArray([Color(InkUi.INK, 0.0), Color(InkUi.INK, 0.0), Color(InkUi.INK, 0.72)])
	var ramp_tex := GradientTexture2D.new()
	ramp_tex.gradient = ramp
	ramp_tex.fill_from = Vector2(0.0, 0.0)
	ramp_tex.fill_to = Vector2(1.0, 0.6)
	shade.texture = ramp_tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(shade)

	_root = Control.new()
	_root.theme = InkUi.make_theme(InkUi.FONT_BODY)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)

	_logo = Wordmark.new()
	_logo.word = TEXT["logo"]
	_logo.tagline = TEXT["tagline"]
	_logo.full_name = TEXT["full_name"]
	_logo.face = InkUi.display_font()
	_logo.size_px = InkUi.FONT_LOGO
	_logo.fill = InkUi.GOLD
	_logo.rim = InkUi.ORNAMENT
	_logo.dark = InkUi.INK
	_logo.glow = InkUi.GOLD
	_logo.tag_color = InkUi.ORNAMENT
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_logo)

	_menu = VBoxContainer.new()
	InkUi.gap(_menu, InkUi.GAP_XS)
	_root.add_child(_menu)
	for key in ITEMS:
		var item := TitleItem.new()
		item.text = TEXT[key]
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		InkUi.make_text_item(item)
		item.marker = InkUi.GOLD
		item.marker_dark = InkUi.INK
		item.line = InkUi.ORNAMENT
		item.pressed.connect(_activate.bind(key))
		_menu.add_child(item)
		items[key] = item
	items["exit"].visible = not OS.has_feature("web")  # (a browser tab is closed by the browser)

	_corner = Label.new()
	var newest := info.newest()
	var build = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/build_info.json")) if FileAccess.file_exists("res://data/ui/build_info.json") else null
	_corner.text = "BETA-TEST · source metadata unavailable"
	if build is Dictionary:
		_corner.text = "BETA-TEST · %s · Git %s%s" % [build.get("source_date", "?"), build.get("short_commit", "?"), " + local changes" if build.get("dirty", false) else ""]
	if OS.has_feature("web"):
		var web_build = JavaScriptBridge.eval("window.zorxBoot && window.zorxBoot.manifest ? window.zorxBoot.manifest.build : null", true)
		_corner.text = "BETA-TEST · Build %s" % str(web_build) if web_build != null else "BETA-TEST · Build unavailable"
	InkUi.style_text(_corner, InkUi.MUTED, InkUi.FONT_NOTE, 4)
	_root.add_child(_corner)
	_build_connection_ui()


## Scales everything to the window and places the logo, the menu and the version line for its shape.
func _fit() -> void:
	if _root == null or not is_inside_tree():
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		window = logical
	var density := density_override if density_override > 0.0 else DisplayServer.screen_get_scale()
	var layout := InkUi.layout_for(window, logical, density)
	_mode = layout["mode"]
	var area: Vector2 = layout["size"]
	_root.scale = Vector2.ONE * float(layout["scale"])
	_root.size = area
	var spec: Dictionary = LAYOUT[_mode]
	var edge: Vector2 = spec["edge"]
	for key in items:
		items[key].custom_minimum_size = Vector2(250.0, spec["item"])
	_logo.scale_by = spec["logo"]
	_logo.size = _logo.get_combined_minimum_size()
	_menu.size = _menu.get_combined_minimum_size()
	_corner.size = _corner.get_combined_minimum_size()
	if _mode == InkUi.PORTRAIT:
		_logo.position = Vector2((area.x - _logo.size.x) * 0.5, edge.y + 24.0)
		_menu.position = Vector2((area.x - _menu.size.x) * 0.5, area.y - _menu.size.y - edge.y - _corner.size.y)
		_corner.position = Vector2((area.x - _corner.size.x) * 0.5, area.y - _corner.size.y - InkUi.GAP_HUGE)
	else:
		_logo.position = Vector2(area.x - _logo.size.x - edge.x, edge.y)
		_menu.position = Vector2(area.x - _menu.size.x - edge.x + 24.0, area.y - _menu.size.y - edge.y)
		_corner.position = Vector2(edge.x * 0.5, area.y - _corner.size.y - InkUi.GAP_XL)
	_connection.size = Vector2(420.0 if _mode == InkUi.WIDE else minf(420.0, area.x * 0.5), 0.0)
	_connection.size.y = _connection.get_combined_minimum_size().y
	_connection.position = Vector2(edge.x * 0.5, _corner.position.y - _connection.size.y - InkUi.GAP_S)
	if panel != null:
		_fit_panel()


func _activate(key: String) -> void:
	match key:
		"start":
			start_game()
		"versions":
			open_panel("versions")
		"settings":
			open_panel("settings")
		"staff":
			open_panel("staff")
		"exit":
			var audio := get_node_or_null("/root/Audio")
			if audio != null:
				audio.release_all()
			get_tree().quit()


## Start: on to the campfire (a new player meets the character creator there first).
func start_game() -> void:
	items["start"].disabled = true
	if await GameState.connect_account_profile():
		get_tree().change_scene_to_file(GameState.CARD_DECK_SCENE)  # the class card screen replaced the campfire hub
	else:
		_connection_label.text = GameState.online_error
		items["start"].disabled = false


func _unhandled_input(event: InputEvent) -> void:
	if panel != null and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ panels

## Opens "versions", "settings" or "staff" over the backdrop (the menu hides while it is open).
func open_panel(kind: String) -> void:
	if panel != null:
		close_panel()
	_opened_from = items.get(kind, items["start"])
	panel_kind = kind
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(panel)
	var scrim := ColorRect.new()
	scrim.color = InkUi.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scrim)
	var window := PanelContainer.new()
	window.name = "Window"
	InkUi.panel(window, InkUi.window_style())
	panel.add_child(window)
	var box := VBoxContainer.new()
	InkUi.gap(box, InkUi.GAP_L)
	window.add_child(box)
	var header := HBoxContainer.new()
	header.add_child(InkUi.brush_title(TEXT[kind + "_title"], InkUi.FONT_TITLE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = TEXT["close"]
	close.custom_minimum_size = Vector2(120.0, 48.0 if _mode == InkUi.WIDE else 56.0)
	InkUi.close_button(close)
	close.pressed.connect(close_panel)
	header.add_child(close)
	box.add_child(header)
	var body: Control
	var focus_first: Control = close
	match kind:
		"versions":
			body = _versions_body()
			if not version_tabs.is_empty():
				focus_first = version_tabs[0]
		"staff":
			body = _staff_body()
		_:
			body = _settings_body()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	_connection.visible = false
	_menu.visible = false
	_logo.visible = false
	_fit_panel()
	# Wrapped labels report a very tall minimum before their first layout, which grows the window
	# past the screen; fit again once the real minimum is known.
	window.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)
	_fit_panel.call_deferred()
	focus_first.grab_focus()


func close_panel() -> void:
	if panel == null:
		return
	panel.queue_free()
	panel = null
	panel_kind = ""
	version_tabs.clear()
	version_notes = null
	_connection.visible = true
	_menu.visible = true
	_logo.visible = true
	if _opened_from != null:
		_opened_from.grab_focus()


func _fit_panel() -> void:
	if panel == null:
		return
	var window: Control = panel.get_node("Window")
	var area := _root.size
	var wanted: Vector2 = LAYOUT[_mode]["panel"]
	var margin := float(InkUi.edge_for(_mode))
	var room := area - Vector2.ONE * margin * 2.0
	var size := room if wanted == Vector2.ZERO else Vector2(minf(wanted.x, room.x), minf(wanted.y, room.y))
	if panel_kind == "settings":
		size.y = minf(size.y, 600.0)
	window.custom_minimum_size = size
	window.size = size
	window.position = (area - size) * 0.5


## Version Info: one tab per version on the left (newest first), the chosen one's notes on the right.
func _versions_body() -> Control:
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_XL)
	if info.versions.is_empty():
		row.add_child(InkUi.label(TEXT["no_versions"], InkUi.BAD))
		return row
	var tab_scroll := ScrollContainer.new()
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size = Vector2(230.0 if _mode != InkUi.PORTRAIT else 120.0, 0.0)
	row.add_child(tab_scroll)
	var tabs := VBoxContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(tabs, InkUi.GAP_S)
	tab_scroll.add_child(tabs)
	var group := ButtonGroup.new()
	for i in info.versions.size():
		var v: Dictionary = info.versions[i]
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = group
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.text = "v%s\n%s" % [v.id, v.name] if _mode != InkUi.PORTRAIT else "v%s" % v.id
		tab.custom_minimum_size = Vector2(0.0, 64.0)
		tab.pressed.connect(show_version.bind(i))
		tab.focus_entered.connect(func() -> void:
			tab.button_pressed = true
			show_version(i))
		tabs.add_child(tab)
		version_tabs.append(tab)
	var notes_scroll := ScrollContainer.new()
	notes_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notes_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	row.add_child(notes_scroll)
	var notes_panel := PanelContainer.new()
	notes_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_scroll.add_child(notes_panel)
	version_notes = VBoxContainer.new()
	InkUi.gap(version_notes, InkUi.GAP_M)
	notes_panel.add_child(version_notes)
	version_tabs[0].button_pressed = true
	show_version(0)
	return row


## Shows version `index` (0 = newest) on the right of the Version Info panel.
func show_version(index: int) -> void:
	if version_notes == null or index < 0 or index >= info.versions.size():
		return
	for child in version_notes.get_children():
		version_notes.remove_child(child)
		child.queue_free()
	if index < version_tabs.size() and not version_tabs[index].button_pressed:
		version_tabs[index].button_pressed = true
	var v: Dictionary = info.versions[index]
	var heading := InkUi.label("v%s  %s" % [v.id, v.name], InkUi.GOLD, InkUi.FONT_TITLE)
	version_notes.add_child(heading)
	if v.date != "":
		version_notes.add_child(InkUi.label(v.date, InkUi.MUTED, InkUi.FONT_SMALL))
	if v.th != "":
		version_notes.add_child(_wrapped(v.th, InkUi.PAPER, InkUi.FONT_LABEL))
	for key in VersionInfo.SECTIONS:
		var lines: Array = v.sections.get(key, [])
		if lines.is_empty():
			continue
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0.0, InkUi.GAP_XS)
		version_notes.add_child(gap)
		version_notes.add_child(InkUi.brush_title(TEXT[key]))
		for line in lines:
			version_notes.add_child(_bullet(line))
	var scroll := version_notes.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0


func _settings_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# the hub settings rows (dark ink) on their parchment, inside the title's own window
	var tokens := preload("res://client/card_tokens.gd")
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tokens.panel(paper, tokens.hub_paper(1.0))
	var pad := MarginContainer.new()
	tokens.margin(pad, tokens.CHAR_PAD, 1.0)
	paper.add_child(pad)
	var settings := preload("res://client/graphics_panel.gd").contents(true, 0.6, false)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(settings)
	scroll.add_child(paper)
	return scroll


## Staff & Credits: the team's roles, then every outside work the game ships (data/ui/credits.json).
func _staff_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	InkUi.gap(box, InkUi.GAP_S)
	scroll.add_child(box)
	var data = null
	if FileAccess.file_exists(CREDITS_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	if not (data is Dictionary):
		box.add_child(InkUi.label(TEXT["no_credits"], InkUi.BAD))
		return scroll
	box.add_child(InkUi.brush_title(TEXT["team"]))
	var grid := GridContainer.new()
	grid.columns = 2
	InkUi.gap(grid, InkUi.GAP_HUGE, InkUi.GAP_XS)
	for member in data.get("team", []):
		grid.add_child(InkUi.label(str(member.get("role", "")), InkUi.MUTED, InkUi.FONT_LABEL))
		grid.add_child(InkUi.label(str(member.get("who", "")), InkUi.PAPER, InkUi.FONT_LABEL))
	box.add_child(grid)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, InkUi.GAP_M)
	box.add_child(gap)
	box.add_child(InkUi.brush_title(TEXT["credits"]))
	for credit in data.get("credits", []):
		box.add_child(InkUi.label(str(credit.get("what", "")), InkUi.HEADING_ACCENT, InkUi.FONT_LABEL))
		box.add_child(_wrapped(str(credit.get("who", "")), InkUi.PAPER, InkUi.FONT_SMALL))
		box.add_child(InkUi.label(str(credit.get("licence", "")), InkUi.MUTED, InkUi.FONT_NOTE))
	return scroll


func _wrapped(text: String, color: Color, size: int) -> Label:
	var l := InkUi.label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120.0, 0.0)
	return l


## One note line with a small brass diamond in front.
func _bullet(text: String) -> Control:
	var row := HBoxContainer.new()
	InkUi.gap(row, InkUi.GAP_M)
	var mark := Diamond.new()
	mark.color = InkUi.ORNAMENT
	mark.custom_minimum_size = Vector2(12.0, 22.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	row.add_child(_wrapped(text, InkUi.PAPER, InkUi.FONT_BODY))
	return row


# ------------------------------------------------------------------ drawn pieces

## The ZORX wordmark: gold letters in the display face with a brass rim, a dark edge and a soft glow,
## a brass rule with a diamond under it and a small spaced tagline. Drawn in code (0 KB).
class Wordmark:
	extends Control
	var word := ""
	var tagline := ""
	var full_name := ""
	var face: Font
	var size_px := 132
	var scale_by := 1.0
	var fill: Color
	var rim: Color
	var dark: Color
	var glow: Color
	var tag_color: Color

	func _px() -> int:
		return int(round(size_px * scale_by))

	func _tag_px() -> int:
		return maxi(14, int(round(size_px * scale_by * 0.16)))

	func _spaced(px: int) -> Font:
		var v := FontVariation.new()
		v.base_font = face if face != null else get_theme_default_font()
		v.spacing_glyph = int(px * 0.06)
		return v

	func _get_minimum_size() -> Vector2:
		var px := _px()
		var f := _spaced(px)
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var tw := _spaced(_tag_px()).get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_px()).x
		var nw := _spaced(_tag_px()).get_string_size(full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_px()).x
		return Vector2(maxf(w, maxf(tw, nw)) + px * 0.5, f.get_height(px) + _tag_px() * 4.1 + px * 0.2)

	func _draw() -> void:
		var px := _px()
		var f := _spaced(px)
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at := Vector2((size.x - w) * 0.5, px * 0.12 + f.get_ascent(px))
		# glow, dark edge, brass rim, then the gold face
		for step in [[0.34, 0.05], [0.22, 0.08], [0.12, 0.12]]:
			draw_string_outline(f, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(px * step[0]), Color(glow, step[1]))
		draw_string_outline(f, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(4, int(px * 0.09)), dark)
		draw_string_outline(f, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, int(px * 0.035)), rim)
		draw_string(f, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, fill)
		# the brass rule: tapering lines out of a centre diamond, small studs at the ends
		var y := at.y + f.get_descent(px) + px * 0.06
		var cx := size.x * 0.5
		var reach := w * 0.5
		var lw := maxf(1.5, px * 0.014)
		for s in [-1.0, 1.0]:
			draw_line(Vector2(cx + s * px * 0.13, y), Vector2(cx + s * reach, y), rim, lw, true)
			draw_line(Vector2(cx + s * px * 0.13, y + lw * 2.5), Vector2(cx + s * reach * 0.62, y + lw * 2.5), Color(rim, 0.5), lw * 0.7, true)
			_diamond(Vector2(cx + s * (reach + px * 0.04), y), px * 0.025, rim)
			_diamond(Vector2(cx + s * px * 0.19, y), px * 0.03, rim)
		_diamond(Vector2(cx, y), px * 0.075, rim)
		_diamond(Vector2(cx, y), px * 0.05, dark)
		_diamond(Vector2(cx, y), px * 0.028, fill)
		if full_name != "":
			var np := _tag_px()
			var nf := _spaced(np)
			var nw := nf.get_string_size(full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, np).x
			var nat := Vector2((size.x - nw) * 0.5, y + px * 0.1 + nf.get_ascent(np) + np * 0.4)
			draw_string_outline(nf, nat, full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, np, 5, dark)
			draw_string(nf, nat, full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, np, fill)
		if tagline != "":
			var tp := _tag_px()
			var tf := _spaced(tp)
			var tw := tf.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, tp).x
			var tat := Vector2((size.x - tw) * 0.5, y + px * 0.1 + tf.get_ascent(tp) + tp * 1.9)
			draw_string_outline(tf, tat, tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, 5, dark)
			draw_string(tf, tat, tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, tag_color)

	func _diamond(at: Vector2, r: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), color)


## A title menu item: its words alone; when focused (keyboard, gamepad, or the mouse over it, which
## moves the focus) a brass diamond shows in front and a brass line fades out under the words.
class TitleItem:
	extends Button
	var marker: Color
	var marker_dark: Color
	var line: Color

	func _ready() -> void:
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(func() -> void:
			if is_visible_in_tree():
				grab_focus())

	func _draw() -> void:
		if not has_focus():
			return
		var c := Vector2(13.0, size.y * 0.5)
		var r := 8.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), marker_dark)
		var r2 := r - 1.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0)]), marker)
		var r3 := r2 * 0.4
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r3), c + Vector2(r3, 0), c + Vector2(0, r3), c + Vector2(-r3, 0)]), marker_dark)
		var font := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else size.x * 0.5
		var y := size.y * 0.5 + fs * 0.62
		var x0 := 30.0
		draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x0 + tw + 40.0, y), Vector2(x0 + tw + 40.0, y + 1.5), Vector2(x0, y + 1.5)]),
			PackedColorArray([line, Color(line, 0.0), Color(line, 0.0), line]))


## A small filled diamond (a note bullet).
class Diamond:
	extends Control
	var color: Color

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 11.0)
		var r := 4.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


func _build_connection_ui() -> void:
	_connection = VBoxContainer.new()
	InkUi.gap(_connection, InkUi.GAP_S)
	_root.add_child(_connection)
	_connection_label = Label.new()
	_connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	InkUi.style_text(_connection_label, InkUi.MUTED, InkUi.FONT_SECTION, 4)
	_connection.add_child(_connection_label)
	var buttons := HBoxContainer.new()
	InkUi.gap(buttons, InkUi.GAP_S)
	_connection.add_child(buttons)
	_online_retry = Button.new()
	_online_retry.text = "เชื่อมต่ออีกครั้ง"
	_online_retry.custom_minimum_size = Vector2(170, 48)
	_online_retry.pressed.connect(func() -> void: Online.connect_account())
	buttons.add_child(_online_retry)
	_offline_button = Button.new()
	_offline_button.text = "เล่นออฟไลน์"
	_offline_button.custom_minimum_size = Vector2(150, 48)
	_offline_button.pressed.connect(func() -> void:
		Online.use_offline()
		start_game())
	buttons.add_child(_offline_button)


func _connection_changed() -> void:
	_connection_label.text = Online.status_text()
	_online_retry.disabled = Online.status == Online.Status.CONNECTING
	_online_retry.visible = Online.status != Online.Status.AUTHENTICATED
	_offline_button.visible = false
	_fit.call_deferred()
