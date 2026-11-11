extends RefCounted
## The look of every screen in one place: the design tokens (palette, semantic colors, type scale,
## spacing, shapes), the Theme for menu controls, and small helpers that apply a token to a node.
## Screens and the HUD use these instead of colors, font sizes or style boxes of their own (checked
## by tests/test_ui_tokens.gd), so the whole UI is restyled by changing token values here.
## The values here are the live look: D "Night Brass" (navy-teal glass, engraved brass lines, brass
## line icons, gem-cut rarity frames), chosen by the director on 2026-10-12. Older proposals are other
## values for the same tokens (client/ui_themes.gd).
## Also decides how big a menu is drawn on the current screen (desktop, phone landscape, phone
## portrait), so the same screen stays readable and touchable everywhere (see layout_for()).
## Style rules and token meanings: docs/design/ui_style_guide.md.
## EXTENDING: a new widget look is one more entry in make_theme(); a new meaning is one more token
## (add it to every theme in ui_themes.gd); a new layout is one more mode.

# ------------------------------------------------------------------ palette: surfaces and text
# (static vars, not consts, so a theme can swap them before the screens are built; see apply_tokens())
static var INK := Color(0.04, 0.07, 0.095)  ## the darkest backdrop (window panels, outlines on text)
static var PANEL := Color(0.065, 0.11, 0.135)  ## panels on the backdrop
static var PANEL_LIGHT := Color(0.095, 0.155, 0.18)  ## cells, buttons
static var SLOT_BG := Color(0.045, 0.08, 0.1)  ## an equipment slot (darker than a bag cell)
static var FIELD_BG := Color(0.03, 0.055, 0.075)  ## text fields
static var BORDER := Color(0.45, 0.37, 0.23)
static var HOVER_BG := Color(0.12, 0.2, 0.23)
static var PRESSED_BG := Color(0.09, 0.25, 0.27)  ## pressed button, the open tab
static var TAB_HOVER_BG := Color(0.1, 0.17, 0.2)
static var DISABLED_BG := Color(0.055, 0.085, 0.1)
static var DISABLED_BORDER := Color(0.22, 0.21, 0.18)
static var SCROLL_TRACK := Color(0, 0, 0, 0.3)
static var SCRIM := Color(0.01, 0.03, 0.05, 0.72)  ## dims the game behind a menu
static var SCRIM_STRONG := Color(0.01, 0.03, 0.05, 0.86)  ## dims more (the character creator)
static var CLEAR := Color(0, 0, 0, 0)

static var PAPER := Color(0.92, 0.89, 0.8)  ## body text
static var MUTED := Color(0.68, 0.7, 0.66)  ## secondary text
static var TEXT_STRONG := Color(1, 0.97, 0.88)  ## text on a hovered/pressed/selected control
static var TEXT_DISABLED := Color(0.42, 0.45, 0.44)
static var TEXT_PLAIN := Color(0.92, 0.89, 0.8)  ## list text with no meaning of its own (camp lists)
static var TEXT_BRIGHT := Color(0.92, 0.89, 0.8)  ## a cost the player can pay
static var TEXT_TAG := Color(0.68, 0.7, 0.66)  ## small "Worn" / "Stash" tags in lists
static var TEXT_LOCKED := Color(0.5, 0.53, 0.52)  ## not unlocked yet (always with words: "camp level 3")
static var TEXT_UNLOCKED := Color(0.92, 0.89, 0.8)
static var HEADING_ACCENT := Color(0.96, 0.78, 0.4)  ## list section headings
static var SUBSTAT := Color(0.62, 0.85, 0.86)  ## an item's extra stats

# ------------------------------------------------------------------ palette: meaning
static var SEAL := Color(1, 0.44, 0.22)  ## ember: selection, the one main action (always with a shape too)
static var GOLD := Color(0.96, 0.78, 0.4)  ## money, highlights, focus
static var GOOD := Color(0.52, 0.88, 0.64)  ## gains (always shown with a + sign and an up mark too)
static var GOOD_TEXT := Color(0.52, 0.88, 0.64)  ## "all fine" lines in lists
static var BAD := Color(1, 0.5, 0.44)  ## losses, warnings (always with a - sign or words too)
static var CANT_AFFORD := Color(1, 0.5, 0.44)  ## a cost the player cannot pay (always with words)
static var WARN := Color(1, 0.66, 0.25)  ## worn-down mark on a cell (with a "!")
static var WEAR_OK := Color(0.68, 0.7, 0.66)  ## durability text
static var WEAR_LOW := Color(1, 0.66, 0.25)
static var WEAR_BROKEN := Color(1, 0.5, 0.44)
static var ICON_INK := Color(0.02, 0.03, 0.05)  ## outlines of the drawn item icons
static var ICON_FALLBACK := Color(0.8, 0.8, 0.8)  ## an icon/material with no color of its own
static var DOLL_SHADE := Color(0.1, 0.22, 0.26)  ## the soft disc behind the paper doll
static var SELECT_MARK := Color(1, 0.97, 0.88)  ## the corner brackets on a selected cell (with the SEAL frame)
static var TITLE_TEXT := Color(0.96, 0.78, 0.4)  ## text on the brush-stroke title
static var TITLE_OUTLINE := Color(0.02, 0.03, 0.05)
## journey stage kinds (each also has its own word on the button)
static var STAGE_COMBAT := Color(0.92, 0.89, 0.8)
static var STAGE_CHALLENGE := Color(1, 0.44, 0.22)
static var STAGE_TREASURE := Color(0.96, 0.78, 0.4)
static var STAGE_CAMP := Color(0.52, 0.88, 0.64)
static var STAGE_BOSS := Color(1, 0.44, 0.22)

## Item rarity by the tier's color key in data/items/rules.json. Every rarity also has a shape:
## 1-4 diamond pips and a thicker frame per tier on cells, and its name in words in text.
static var RARITY := {"blue": Color(0.38, 0.64, 1), "gold": Color(1, 0.77, 0.3), "green": Color(0.42, 0.86, 0.58), "purple": Color(0.76, 0.5, 1), "white": Color(0.8, 0.83, 0.88)}
## The same over the 3D world (loot beams, loot lines and the HUD loot feed): a little brighter.
static var RARITY_WORLD := {"blue": Color(0.45, 0.7, 1), "gold": Color(1, 0.8, 0.3), "green": Color(0.48, 0.92, 0.62), "purple": Color(0.82, 0.56, 1), "white": Color(0.88, 0.9, 0.94)}

# ------------------------------------------------------------------ HUD (in-combat) colors
static var HUD_PANEL := Color(0.04, 0.08, 0.1, 0.86)  ## bar backs, skill icons
static var HUD_TEXT := Color(1, 0.98, 0.93)
static var HUD_OUTLINE := Color(0.02, 0.03, 0.05)
static var LOOT_OUTLINE := Color.BLACK  ## loot feed lines are in rarity colors: always a dark outline
static var HP := Color(0.8, 0.19, 0.2)
static var HP_TRAIL := Color(0.42, 0.09, 0.12)  ## the damage just taken, draining after the bar
static var STAMINA := Color(0.1, 0.5, 0.44)  ## dark enough for white text on it
static var STAMINA_EXHAUSTED := Color(0.95, 0.4, 0.3)
static var STAMINA_BLINK := Color(1.0, 0.15, 0.15)  ## blinks when an action needs more stamina
static var ULT := Color(0.5, 0.32, 0.86)
static var ULT_READY_TEXT := Color(0.95, 0.85, 1.0)
static var ULT_ICON_PULSE_A := Color(0.42, 0.22, 0.62, 0.92)
static var ULT_ICON_PULSE_B := Color(0.6, 0.4, 0.85, 0.95)
static var ULT_ICON_FILL_ALPHA := 0.45
static var BUFF := Color(0.4, 1.0, 0.5)  ## chip edge (plus a "+" mark)
static var DEBUFF := Color(1.0, 0.35, 0.3)  ## chip edge (plus a "-" mark)
static var CHIP_BASE := Color.BLACK  ## a chip's back = CHIP_BASE blended toward the effect's own color...
static var CHIP_TINT := 0.4  ## ... by this much
static var CHIP_ALPHA := 0.9
static var KEY_BADGE := Color(0.03, 0.06, 0.08, 0.95)
static var KEY_TEXT := Color(0.96, 0.78, 0.4)
static var ICON_LABEL := Color(0.92, 0.89, 0.8)
static var COOLDOWN_COVER := Color(0.0, 0.0, 0.0, 0.62)
static var ICON_ACTIVE := Color(0.14, 0.46, 0.6, 0.92)  ## the action is happening (guarding)
static var ICON_UNAFFORDABLE := Color(0.42, 0.1, 0.1, 0.88)  ## not enough stamina
static var ICON_CHARGING := Color(0.12, 0.12, 0.16, 0.7)  ## not ready, nothing wrong
static var ICON_DIM_ALPHA := 0.55
static var COMBO_COOL := Color(1.0, 1.0, 1.0)
static var COMBO_HOT := Color(1, 0.44, 0.22)
static var COMBO_OUTLINE := Color(0.1, 0.05, 0.0)
static var COMBO_LABEL := Color(0.96, 0.78, 0.4)
static var COMBO_TIMER := Color(0.96, 0.78, 0.4)
static var WARNING_TEXT := Color(1, 0.5, 0.44)
static var TRIP_TEXT := Color(0.92, 0.89, 0.8)
static var SKILL_BANNER_BG := Color(0.04, 0.09, 0.11, 0.92)
static var SKILL_BANNER_TEXT := Color(1, 0.9, 0.66)
static var PROMPT_TEXT := Color(0.96, 0.78, 0.4)
static var INFO_TEXT := Color(0.92, 0.89, 0.8)
static var HELP_TEXT := Color(0.92, 0.89, 0.8)
static var HELP_PLATE := Color(0.03, 0.07, 0.09, 0.72)

# ------------------------------------------------------------------ world feedback (stage_view)
static var DAMAGE := Color.WHITE
static var DAMAGE_BIG := Color(1, 0.8, 0.3)
static var DAMAGE_CRIT := Color(1, 0.44, 0.22)  ## also bigger and with a "!"
static var DAMAGE_BLOCKED := Color(0.6, 0.8, 1.0)  ## also says BLOCK
static var POPUP_RESIST := Color(0.7, 0.7, 0.75)
static var LOOT_GOLD := Color(0.96, 0.78, 0.4)
static var LOOT_PROBLEM := Color(1, 0.5, 0.44)  ## BAG FULL
static var BAG_LOST := Color(1, 0.5, 0.44)

# ------------------------------------------------------------------ type scale (menu units)
## FONT SLOTS. The chosen UI fonts (Boss, 2026-10-12): Sarabun for body text, Taviraj for display.
## Both carry Thai AND Latin, so Thai renders everywhere (the engine default, Open Sans SemiBold,
## has no Thai, so Thai shows as boxes on the web — style guide section 11). Each slot keeps the
## engine default as a glyph fallback (_with_fallback()), so any character the subset lacks still
## draws. A theme may swap these for another face (null = the engine default, no Thai).
## Credits/licence: art/fonts/CREDITS.md (SIL OFL 1.1). Subset by tools/fonts/subset_fonts.py.
static var FONT: Font = _load_font("res://art/fonts/Sarabun-Regular.woff2")
static var FONT_EMBOLDEN := 0.0  ## > 0 makes every menu and HUD text bolder (FontVariation, 0 KB)
static var FONT_TINY := 12
static var FONT_CAPTION := 13
static var FONT_NOTE := 14
static var FONT_SMALL := 15
static var FONT_LABEL := 16
static var FONT_BODY := 17
static var FONT_SECTION := 18  ## brush titles, the journey screen
static var FONT_ITEM := 19  ## an item's name in the details
static var FONT_HEADING := 20
static var FONT_TITLE := 24
static var FONT_DISPLAY := 28
static var FONT_LOGO := 132  ## the ZORX wordmark on the title screen (display face)
static var FONT_MENU := 26  ## the title menu's plain text items (display face)
## The HUD's own sizes (HUD units; the HUD scales x1.8 on phones).
static var HUD_FONT := {
	"hp": 17, "bar": 13, "bar_small": 12, "chip": 13, "key": 19, "icon": 13, "cooldown": 22, "loot": 18,
	"combo": 80, "combo_compact": 64, "combo_label": 22, "combo_damage": 20, "banner": 42, "skill": 40,
	"prompt": 20, "trip": 17, "info": 14, "help": 13, "warning": 13, "debug": 16, "boss": 18,
}

# ------------------------------------------------------------------ spacing (menu units)
static var GAP_XXS := 2
static var GAP_XS := 4
static var GAP_S := 6
static var GAP_M := 8
static var GAP_L := 10
static var GAP_XL := 12
static var GAP_XXL := 14
static var GAP_HUGE := 16
static var EDGE_WIDE := 24  ## the menu's margin to the window edge, per layout mode
static var EDGE_COMPACT := 8
static var EDGE_PORTRAIT := 4
static var EDGE_HUB := 40

# ------------------------------------------------------------------ shapes
static var RADIUS_ADD := 4  ## added to every corner radius (rounder themes)
static var CORNER_SKEW := 0  ## top-left and bottom-right corners this much rounder: a brushed edge
static var BORDER_SCALE := 1  ## multiplies every border width (bolder outlines)
static var SHADOW_SIZE := 0  ## a drop shadow under panels and buttons (0 = none)
static var SHADOW_OFFSET := Vector2.ZERO
static var SHADOW_COLOR := Color(0, 0, 0, 0.6)
static var TITLE_STYLE := "engraved"  ## the section title's backing: "brush", "ribbon", "underline" or "engraved"
static var TITLE_BG := Color(0.13, 0.32, 0.34, 0.9)  ## the brush/ribbon color
static var CORNER_DETAIL := 1  ## segments per rounded corner; 1 = cut (chamfered) corners
## "plain", or "engraved": panels get a second, inset ORNAMENT line with corner diamonds, the window
## a medallion on its top edge; HUD bars and icons get an ORNAMENT line, diamond key badges and a
## pointed skill-banner plate. All drawn in code (0 KB).
static var FRAME_STYLE := "engraved"
static var ORNAMENT := Color(0.84, 0.68, 0.38)  ## the engraved lines and ornaments (FRAME_STYLE "engraved")
static var DISPLAY_FONT: Font = _load_font("res://art/fonts/Taviraj-SemiBold.woff2")  ## titles (FONT_TITLE and up), section titles, the HUD's big words; null = FONT
## "brass": screens show the line icons of brass_icons.gd (tabs, filters, slots, wallet, HUD actions);
## "plain": no icons (the older proposals).
static var ICON_STYLE := "brass"
static var ICON_TINT := Color(0.90, 0.74, 0.44)  ## the line icons (brighter than ORNAMENT, for small sizes)
## "brass": HUD bars get a gloss, segment ticks, a hatched damage trail, end caps and a low-HP pulse;
## "plain": flat bars.
static var BAR_STYLE := "brass"
static var HP_LOW := Color(1.0, 0.30, 0.22)  ## the HP frame pulses toward this under LOW_HP (with a "!" cap)
const LOW_HP := 0.3  ## the HP ratio under which the low-HP warning shows
static var GLASS_GLOW := Color(0.55, 0.85, 0.90, 0.07)  ## the glassy highlight at the top of panels
## Real width of the engraved lines on phones (logical pixels): lines are drawn at least this thick
## after the menu is scaled down (see layout_for()).
static var LINE_PHONE := 1.75

## Layout modes for a screen size.
const WIDE := "wide"  ## desktop / tablet landscape
const COMPACT := "compact"  ## phone landscape
const PORTRAIT := "portrait"  ## phone portrait

## The design sizes each mode is laid out for (in the menu's own units); the menu is scaled so this
## fits the screen. Phones get fewer units (so everything is drawn bigger).
const WIDE_MIN := Vector2(1240.0, 680.0)
const COMPACT_HEIGHT := 500.0
const COMPACT_MIN_WIDTH := 1020.0
const PORTRAIT_WIDTH := 430.0
const PORTRAIT_MIN_HEIGHT := 860.0
## A screen shorter than this (in real, density-independent pixels) is a phone in landscape.
const PHONE_HEIGHT := 560.0

const MaterialIcons := preload("res://client/material_icons.gd")
const BrassIcons := preload("res://client/brass_icons.gd")

static var _defaults := {}  ## the built-in token values, saved on the first apply_tokens()


## Picks the layout for a window. `window_pixels` is the real window size, `logical` the viewport's
## visible size (after the project's stretch), `density` the screen's pixel ratio (2-3 on phones on
## the web, 1 on desktop). Returns {"mode": String, "scale": float (logical units per menu unit),
## "size": Vector2 (the menu's area in its own units)}.
static func layout_for(window_pixels: Vector2, logical: Vector2, density: float = 1.0) -> Dictionary:
	var real := window_pixels / maxf(density, 0.01)
	var mode := WIDE
	if real.x < real.y * 0.9:
		mode = PORTRAIT
	elif real.y < PHONE_HEIGHT:
		mode = COMPACT
	var scale := 1.0
	match mode:
		WIDE:
			scale = minf(1.0, minf(logical.x / WIDE_MIN.x, logical.y / WIDE_MIN.y))
		COMPACT:
			scale = minf(logical.y / COMPACT_HEIGHT, logical.x / COMPACT_MIN_WIDTH)
		PORTRAIT:
			scale = minf(logical.x / PORTRAIT_WIDTH, logical.y / PORTRAIT_MIN_HEIGHT)
	scale = maxf(scale, 0.25)
	# Engraved lines: 1 unit on a desktop, but never thinner than LINE_PHONE real pixels on a phone.
	EngravedBox.width = 1.0 if mode == WIDE else clampf(LINE_PHONE / scale, 1.0, 3.0)
	return {"mode": mode, "scale": scale, "size": logical / scale}


## The menu's margin to the window edge for a layout mode.
static func edge_for(mode: String) -> int:
	return EDGE_WIDE if mode == WIDE else (EDGE_COMPACT if mode == COMPACT else EDGE_PORTRAIT)


# ------------------------------------------------------------------ themes

## Replaces token values: {"PAPER": Color(...), "FONT_BODY": 18, ...}. Returns false if a name is not
## a token (the known ones are still applied). Call before building screens; make_theme() and the helpers read the new values.
static func apply_tokens(values: Dictionary) -> bool:
	var script: Script = load("res://client/ink_ui.gd")
	var known := {}  # the static vars (tokens are the upper-case ones)
	for property in script.get_property_list():
		var name := str(property["name"])
		if name.to_upper() == name and name.to_lower() != name:
			known[name] = true
	if _defaults.is_empty():
		for name in known:
			_defaults[name] = _copy(script.get(name))
	var ok := true
	for name in values:
		if not known.has(name):
			ok = false  # (the caller reports it: see ui_themes.gd)
			continue
		script.set(name, _copy(values[name]))
	return ok


## Puts every token back to the built-in look.
static func reset_tokens() -> void:
	if not _defaults.is_empty():
		apply_tokens(_defaults)


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary else value


# ------------------------------------------------------------------ style boxes and the Theme

static func flat(color: Color, border: Color = CLEAR, border_width: int = 0, radius: int = 3, margin: float = 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(border_width * BORDER_SCALE)
	var r := radius + RADIUS_ADD if radius > 0 else 0
	box.set_corner_radius_all(r)
	# Uneven corners: a little like a brushed edge rather than a machined one.
	box.corner_radius_top_left = r + CORNER_SKEW
	box.corner_radius_bottom_right = r + CORNER_SKEW
	box.set_content_margin_all(margin)
	box.corner_detail = CORNER_DETAIL
	if SHADOW_SIZE > 0 and color.a > 0.0:
		box.shadow_size = SHADOW_SIZE
		box.shadow_offset = SHADOW_OFFSET
		box.shadow_color = SHADOW_COLOR
	return box


## `base` drawn as an engraved brass plate when the theme has one (FRAME_STYLE), else `base` itself.
## `lines` inset brass lines (1-3), `corners` "none" / "diamond" / "ornate", `crest` a medallion on
## the top edge, `notch` a diamond on the bottom edge (the open tab, a pressed button), `glow` a glassy
## highlight at the top. `line_color` overrides ORNAMENT (hover/pressed states).
static func engraved(base: StyleBoxFlat, inset: float = 4.0, line_alpha: float = 1.0, crest: bool = false, lines: int = 2,
		corners: String = "diamond", notch: bool = false, line_color: Color = CLEAR, glow: bool = true) -> StyleBox:
	if FRAME_STYLE != "engraved":
		return base
	var box := EngravedBox.new()
	box.base = base
	box.edge = base.border_color if base.border_width_left > 0 else CLEAR
	base.set_border_width_all(0)  # (the box draws its own edge, at the phone-safe width)
	var tint := ORNAMENT if line_color.a <= 0.0 else line_color
	box.line = Color(tint, tint.a * line_alpha)
	box.fill = base.bg_color
	box.inset = inset
	box.crest = crest
	box.lines = lines
	box.corners = corners
	box.notch = notch
	box.notch_color = SEAL
	box.glow = GLASS_GLOW if glow else CLEAR
	box.dark = INK
	box.cut = float(base.corner_radius_top_left)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, base.get_content_margin(side))
	return box


## A brass-framed plate for buttons and tabs: one inset line, no corner ornaments.
static func plate(bg: Color, edge: Color, line_alpha: float, notch: bool = false, line_color: Color = CLEAR, margin: float = 8.0) -> StyleBox:
	var base := flat(bg, edge, 1, 3, margin)
	return engraved(base, 3.0, line_alpha, false, 1 if line_alpha > 0.0 else 0, "none", notch, line_color)


## The window behind a whole menu (camp, rest point, character creator, campfire): three lines,
## ornate corners and a crest on the top edge.
static func window_style() -> StyleBox:
	return engraved(flat(INK, BORDER, 1, 4, 14.0), 5.0, 1.0, true, 3, "ornate")


## Camp menu's fine double rails and corner fittings; keep other screens' line widths intact.
static func camp_menu_window_style() -> StyleBox:
	var box := engraved(flat(INK, GOLD, 1, 18, 16.0), 4.0, 1.0, true, 2, "ornate", true, GOLD, false)
	if box is EngravedBox:
		box.line_width_override = 1.0
		box.notch_color = GOLD
		box.crest_offset = 4.0
	return box


static func camp_menu_section_text(control: Control, size: int) -> void:
	text_size(control, size)
	control.add_theme_font_override("font", display_font())


static func camp_menu_card_text(control: Control, size: int) -> void:
	text_size(control, size)
	control.add_theme_font_override("font", font())


static func camp_menu_card(button: Button) -> void:
	# Labels are drawn by the card children; keep Button.text for semantic navigation.
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color"]:
		button.add_theme_color_override(key, CLEAR)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var active: bool = state in ["hover", "pressed", "hover_pressed", "focus"]
		var bg := CLEAR if state == "focus" else (PRESSED_BG if state in ["pressed", "hover_pressed"] else PANEL)
		var box := engraved(flat(bg, GOLD, 1, 12, 8.0), 3.0, 1.0 if active else 0.7, false, 2, "ornate", false, GOLD, false)
		if box is EngravedBox:
			box.line_width_override = 1.2 if active else 0.85
		button.add_theme_stylebox_override(state, box)


## A panel inside a window (details, a card): two lines and corner diamonds.
static func panel_style() -> StyleBox:
	return engraved(flat(PANEL, BORDER, 1, 4, 10.0), 3.0, 0.6)


## The frame around the paper doll in the Look tab.
static func doll_frame_style() -> StyleBox:
	return engraved(flat(PANEL, BORDER, 1, 3, 4), 3.0, 0.6)


## A dark plate behind HUD text over the world (loot lines): a little brass edge, no ornament.
static func hud_plate_style() -> StyleBox:
	return engraved(flat(HELP_PLATE, CLEAR, 0, 2, 4.0), 2.0, 0.45, false, 1, "none", false, CLEAR, false)


## The ornament line around a HUD piece (`size` in HUD units), or null when the theme has none.
## `double` adds a second, inset line (skill icons); `ticks` a small square on each corner.
static func hud_ornament(size: Vector2, double: bool = false, ticks: bool = true) -> Control:
	if FRAME_STYLE != "engraved":
		return null
	var frame := OrnamentFrame.new()
	frame.size = size
	frame.line = ORNAMENT
	frame.double = double
	frame.ticks = ticks
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


## The decoration over a HUD bar (`size` in HUD units), or null when BAR_STYLE is "plain": gloss on
## the filled part, a hatched damage trail, segment ticks every `tick_every` of the bar, a brass frame
## with end caps. Feed it with set_values(); `low` > 0 pulses the frame toward HP_LOW with a "!" cap.
static func bar_decor(size: Vector2, ticks: int = 10) -> Control:
	if BAR_STYLE == "plain":
		return null
	var decor := BarDecor.new()
	decor.size = size
	decor.ticks = ticks
	decor.line = ORNAMENT
	decor.dark = HUD_OUTLINE
	decor.low_color = HP_LOW
	decor.hatch = Color(HP_TRAIL.lerp(HUD_TEXT, 0.35), 0.55)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return decor


## The one main action of a screen (e.g. Start in the character creator).
static func make_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", flat(SEAL, GOLD, 1, 3, 8.0))


## A plain text menu item (the title menu): no plate, the words alone in the display face with a dark
## outline (readable over the moving 3D backdrop); brighter when hovered or focused. `marker_room`
## leaves space on the left for the item's own focus marker (the title screen draws a brass diamond).
static func make_text_item(button: Button, size: int = FONT_MENU, marker_room: float = 30.0) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var none := StyleBoxEmpty.new()
		none.content_margin_left = marker_room
		none.content_margin_right = 8.0
		button.add_theme_stylebox_override(state, none)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", TEXT_STRONG)
	button.add_theme_color_override("font_focus_color", TEXT_STRONG)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_hover_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_color_override("font_outline_color", INK)
	button.add_theme_constant_override("outline_size", 6)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_font_override("font", display_font())


## A color-swatch button (hair, skin): its face is the color; vermilion frame when picked.
static func make_swatch(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", flat(color, BORDER, 1, 3, 4))
	button.add_theme_stylebox_override("hover", flat(color, PAPER, 2, 3, 4))
	button.add_theme_stylebox_override("pressed", flat(color, SEAL, 4, 3, 4))
	button.add_theme_stylebox_override("hover_pressed", flat(color, SEAL, 4, 3, 4))
	button.add_theme_stylebox_override("focus", flat(CLEAR, GOLD, 1, 3, 4))


## Loads a UI font from res:// and gives it the engine default as a glyph fallback, so a character
## the subset font lacks still draws (safety net). Returns null if the file is missing (then the slot
## behaves as "engine default", exactly as before the fonts were added). Called by the FONT slots.
static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		push_warning("ink_ui: UI font missing, falling back to the engine default: " + path)
		return null
	var file: Font = load(path)
	if file == null:
		return null
	# Fall back to the engine default for any glyph the subset does not carry (0 KB: already loaded).
	var fallback := ThemeDB.fallback_font
	if fallback != null and file is FontFile:
		var list: Array[Font] = file.fallbacks.duplicate()
		if not list.has(fallback):
			list.append(fallback)
		file.fallbacks = list
	return file


## The font every text uses (the theme's FONT, made bolder by FONT_EMBOLDEN); null = engine default.
static func font() -> Font:
	if FONT == null and FONT_EMBOLDEN <= 0.0:
		return null
	var variation := FontVariation.new()
	variation.base_font = FONT if FONT != null else ThemeDB.fallback_font
	variation.variation_embolden = FONT_EMBOLDEN
	return variation


## The face for titles and the HUD's big words: DISPLAY_FONT (made bolder like font()), else font().
static func display_font() -> Font:
	if DISPLAY_FONT == null:
		return font()
	var variation := FontVariation.new()
	variation.base_font = DISPLAY_FONT
	variation.variation_embolden = FONT_EMBOLDEN
	return variation


## The HUD text roles drawn in the display face (big words, never numbers that must be read fast).
const DISPLAY_ROLES := ["skill", "banner"]


## The theme every menu control uses. `font_size` is the body text size in menu units.
static func make_theme(font_size: int = FONT_BODY) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = font_size
	if font() != null:
		theme.default_font = font()
	theme.set_color("font_color", "Label", PAPER)

	var normal := plate(PANEL_LIGHT, BORDER, 0.4)
	var hover := plate(HOVER_BG, GOLD, 0.8, false, GOLD)
	var pressed := plate(PRESSED_BG, SEAL, 0.9, true, GOLD)
	var disabled := plate(DISABLED_BG, DISABLED_BORDER, 0.0)
	var focus := flat(CLEAR, GOLD, 2, 3, 8.0)
	if FRAME_STYLE != "engraved":  # (the older proposals: plain boxes)
		normal = flat(PANEL_LIGHT, BORDER, 1, 3, 8.0)
		hover = flat(HOVER_BG, GOLD, 1, 3, 8.0)
		pressed = flat(PRESSED_BG, SEAL, 2, 3, 8.0)
		disabled = flat(DISABLED_BG, DISABLED_BORDER, 1, 3, 8.0)
	theme.set_constant("h_separation", "Button", GAP_S)
	theme.set_constant("icon_max_width", "Button", 26)
	for type in ["Button"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, PAPER)
		theme.set_color("font_hover_color", type, TEXT_STRONG)
		theme.set_color("font_pressed_color", type, TEXT_STRONG)
		theme.set_color("font_hover_pressed_color", type, TEXT_STRONG)
		theme.set_color("font_disabled_color", type, TEXT_DISABLED)
		theme.set_color("font_focus_color", type, TEXT_STRONG)

	theme.set_stylebox("normal", "LineEdit", flat(FIELD_BG, BORDER, 1, 3, 8.0))
	theme.set_stylebox("focus", "LineEdit", flat(CLEAR, GOLD, 2, 3, 8.0))
	theme.set_color("font_color", "LineEdit", PAPER)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", GOLD)

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "TabContainer", flat(CLEAR, CLEAR, 0, 0, 0.0))
	var tab_selected: StyleBox = plate(PRESSED_BG, GOLD, 0.9, true, GOLD, 10.0)
	var tab_unselected: StyleBox = plate(PANEL, BORDER, 0.3, false, CLEAR, 10.0)
	var tab_hovered: StyleBox = plate(TAB_HOVER_BG, ORNAMENT, 0.6, false, CLEAR, 10.0)
	if FRAME_STYLE != "engraved":
		var underline := flat(PRESSED_BG, SEAL, 0, 3, 10.0)
		underline.border_width_bottom = 3 * BORDER_SCALE
		tab_selected = underline
		tab_unselected = flat(PANEL, CLEAR, 0, 3, 10.0)
		tab_hovered = flat(TAB_HOVER_BG, CLEAR, 0, 3, 10.0)
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	theme.set_constant("icon_max_width", "TabContainer", 24)
	theme.set_constant("icon_separation", "TabContainer", GAP_S)
	theme.set_stylebox("tab_focus", "TabContainer", focus)
	theme.set_color("font_selected_color", "TabContainer", TEXT_STRONG)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", PAPER)
	theme.set_font_size("font_size", "TabContainer", font_size + 1)
	theme.set_constant("side_margin", "TabContainer", 0)

	theme.set_stylebox("panel", "TooltipPanel", engraved(flat(INK, BORDER, 1, 3, 8.0), 3.0, 0.8, false, 1, "none"))
	theme.set_color("font_color", "TooltipLabel", PAPER)
	var scroll_grabber := flat(BORDER, CLEAR, 0, 4, 0.0)
	theme.set_stylebox("grabber", "VScrollBar", scroll_grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", flat(GOLD, CLEAR, 0, 4, 0.0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", flat(SEAL, CLEAR, 0, 4, 0.0))
	theme.set_stylebox("scroll", "VScrollBar", flat(SCROLL_TRACK, CLEAR, 0, 4, 0.0))
	theme.set_stylebox("separator", "HSeparator", flat(BORDER, CLEAR, 0, 0, 0.0))
	return theme


# ------------------------------------------------------------------ helpers that apply tokens
# Screens call these with token values (InkUi.FONT_TITLE, InkUi.GOLD...) and never set theme
# overrides themselves.

## Sets a text's color (and size, outline) from tokens. `size` 0 keeps the theme's size; `outline`
## -1 leaves the outline alone.
static func style_text(control: Control, color: Color, size: int = 0, outline: int = -1, outline_color: Color = INK) -> void:
	control.add_theme_color_override("font_color", color)
	if size > 0:
		text_size(control, size)
	if outline >= 0:
		control.add_theme_color_override("font_outline_color", outline_color)
		control.add_theme_constant_override("outline_size", outline)


## Only the size of a text (keeps its color).
static func text_size(control: Control, size: int) -> void:
	control.add_theme_font_size_override("font_size", size)
	if DISPLAY_FONT != null and size >= FONT_TITLE and size <= FONT_DISPLAY:  # menu titles (not the HUD combo number)
		control.add_theme_font_override("font", display_font())


## A new label from tokens.
static func label(text: String, color: Color, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	style_text(l, color, size)
	return l


## A HUD text: the HUD role's size (HUD_FONT), a color and a dark outline, never taking clicks.
static func hud_text(role: String, color: Color, outline: int, outline_color: Color = HUD_OUTLINE) -> Label:
	var l := Label.new()
	style_text(l, color, int(HUD_FONT[role]), outline, outline_color)
	var face := display_font() if role in DISPLAY_ROLES else font()
	if face != null:
		l.add_theme_font_override("font", face)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The gap between a box's children; give `v_gap` too for flow/grid containers (h and v).
static func gap(container: Control, h_gap: int, v_gap: int = -1) -> void:
	if v_gap < 0:
		container.add_theme_constant_override("separation", h_gap)
	else:
		container.add_theme_constant_override("h_separation", h_gap)
		container.add_theme_constant_override("v_separation", v_gap)


## The same margin on all four sides of a MarginContainer.
static func margins(container: MarginContainer, edge: int) -> void:
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_" + side, edge)


## A panel's style from tokens (e.g. InkUi.window_style()).
static func panel(container: Control, style: StyleBox) -> void:
	container.add_theme_stylebox_override("panel", style)


## Native Button interaction with a complete supplied image skin.
static func art_button(button: Button, art: Texture2D) -> void:
	for key in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxTexture.new()
		box.texture = art
		if key in ["pressed", "disabled"]:
			box.modulate_color = MUTED
		button.add_theme_stylebox_override(key, box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## A visible touch scroll lane for the item grid, using the existing brass palette.
static func inventory_scrollbar(bar: VScrollBar, touch: bool) -> void:
	bar.custom_minimum_size.x = 32.0 if touch else 14.0
	for key in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		bar.remove_theme_stylebox_override(key)
	if not touch:
		return
	bar.add_theme_stylebox_override("scroll", flat(PANEL_LIGHT, BORDER, 1, 5, 0))
	for key in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var box := flat(SEAL if key == "grabber_pressed" else GOLD, BORDER, 1, 5, 5)
		box.content_margin_top = 24
		box.content_margin_bottom = 24
		bar.add_theme_stylebox_override(key, box)


## Large content pictures override the small icon limit used by action buttons.
static func picture_button(button: Button, texture: Texture2D, px: int) -> void:
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", px)


## Puts brass icon `name` on a button (or nothing when ICON_STYLE is "plain"). `px` in menu units.
static func icon_button(button: Button, name: String, px: int = 22, cog: bool = false) -> void:
	if ICON_STYLE == "plain":
		return
	button.icon = BrassIcons.texture(name, px * 2, ICON_TINT, CLEAR, cog)  # (drawn at 2x: sharp when scaled up)
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", px)


## The brass icon `name` as a texture (`px` in menu units, drawn at 2x), or null when ICON_STYLE is
## "plain". `color` CLEAR = ICON_TINT.
static func icon(name: String, px: int = 22, color: Color = CLEAR) -> Texture2D:
	if MaterialIcons.TEXTURES.has(name):
		return MaterialIcons.TEXTURES[name]
	if ICON_STYLE == "plain":
		return null
	return BrassIcons.texture(name, px * 2, ICON_TINT if color.a <= 0.0 else color)


## A small gold count badge (a coin with a number) for a button's corner, or null when ICON_STYLE is
## "plain". Set the number with badge.set_count(n); 0 hides it.
static func count_badge() -> Control:
	if ICON_STYLE == "plain":
		return null
	var badge := CountBadge.new()
	badge.coin = GOLD
	badge.rim = ORNAMENT
	badge.ink = INK
	badge.size = Vector2(22.0, 22.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


## Rarity color for a tier's color key ("white", "blue", "purple", "gold"); `world` = over the 3D world.
static func rarity_color(key: String, world: bool = false) -> Color:
	return (RARITY_WORLD if world else RARITY).get(key, TEXT_PLAIN)


## A section title on the theme's title backing (a tapered brush stroke by default).
static func brush_title(text: String, font_size: int = FONT_SECTION) -> Control:
	var holder := BrushStroke.new()
	holder.tint = TITLE_BG
	holder.style = TITLE_STYLE
	var l := Label.new()
	l.text = text
	style_text(l, TITLE_TEXT, font_size, 3, TITLE_OUTLINE)
	if DISPLAY_FONT != null:
		l.add_theme_font_override("font", display_font())
	l.position = Vector2(14.0 if TITLE_STYLE != "engraved" else 22.0, 0.0)
	holder.add_child(l)
	holder.custom_minimum_size = Vector2(l.get_minimum_size().x + (40.0 if TITLE_STYLE != "engraved" else 70.0), l.get_minimum_size().y + 2.0)
	holder.line = ORNAMENT
	holder.label = l
	return holder


## The backing behind a title: by default one sweep of a brush, thick in the middle, dry and thin at
## the tail. Other themes: a ribbon (a plain tag with a notched tail) or an underline.
class BrushStroke:
	extends Control
	var label: Label
	var tint := Color.WHITE  ## (TITLE_BG and TITLE_STYLE when made: inner classes cannot read the tokens)
	var style := "brush"
	var line := Color.WHITE  ## ORNAMENT (the engraved style)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match style:
			"engraved":
				# A dark band that fades out to the right, a hairline under it, a diamond at each end.
				var band := PackedVector2Array([Vector2(0, 1), Vector2(w, 1), Vector2(w, h - 2), Vector2(0, h - 2)])
				draw_polygon(band, PackedColorArray([tint, Color(tint, 0.0), Color(tint, 0.0), tint]))
				draw_line(Vector2(10.0, h - 1.0), Vector2(w - 6.0, h - 1.0), Color(line, 0.8), 1.0)
				_diamond(Vector2(9.0, h * 0.5), 4.5)
				_diamond(Vector2(w - 4.0, h - 1.0), 2.5)
				return
			"ribbon":
				draw_colored_polygon(PackedVector2Array([Vector2(0, 2), Vector2(w - 2, 2), Vector2(w - 14, h * 0.5), Vector2(w - 2, h - 2), Vector2(0, h - 2)]), tint)
				return
			"underline":
				draw_rect(Rect2(4.0, h - 4.0, w - 20.0, 3.0), tint)
				return
		var top := h * 0.14
		var bottom := h * 0.92
		var points := PackedVector2Array([
			Vector2(2.0, top + 4.0), Vector2(w * 0.25, top), Vector2(w * 0.7, top + 1.0), Vector2(w - 2.0, top + h * 0.22),
			Vector2(w - 10.0, h * 0.55), Vector2(w - 1.0, bottom - h * 0.12), Vector2(w * 0.6, bottom),
			Vector2(w * 0.2, bottom - 1.0), Vector2(0.0, bottom - 3.0),
		])
		draw_colored_polygon(points, Color(tint, 0.92))
		# a few dry bristle streaks at the tail
		for i in 3:
			var y := top + (bottom - top) * (0.25 + 0.25 * i)
			draw_line(Vector2(w - 26.0 + i * 5.0, y), Vector2(w + 6.0 - i * 3.0, y + 1.0), Color(tint, 0.5), 1.5)


	## A filled diamond (a square turned 45 degrees) of half-diagonal `r`, in the ornament color.
	func _diamond(at: Vector2, r: float) -> void:
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), line)


## The engraved panel (FRAME_STYLE "engraved"): the fill with a glassy top highlight, its own edge,
## 1-3 brass lines inset along the cut corners, corner ornaments, and optionally a crest on the top
## edge and a notch on the bottom edge. Drawn with the RenderingServer (no textures).
class EngravedBox:
	extends StyleBox
	static var width := 1.0  ## line width in the box's own units (thicker on phones: see layout_for())
	var base: StyleBoxFlat
	var line_width_override := 0.0  ## optional local width, independent of phone theme scaling
	var crest_offset := 0.0
	var edge := Color.TRANSPARENT
	var line := Color.WHITE
	var fill := Color.BLACK  ## the base's fill (the crest's face)
	var dark := Color.BLACK
	var glow := Color.TRANSPARENT
	var notch_color := Color.WHITE
	var inset := 4.0
	var cut := 4.0
	var lines := 2
	var corners := "diamond"
	var crest := false
	var notch := false

	func _draw(item: RID, rect: Rect2) -> void:
		base.draw(item, rect)
		var w := line_width_override if line_width_override > 0.0 else width
		if glow.a > 0.0:
			var g := Rect2(rect.position + Vector2(cut, w), Vector2(rect.size.x - cut * 2.0, minf(rect.size.y * 0.45, 90.0)))
			if g.size.x > 0.0:
				RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]),
					PackedColorArray([glow, glow, Color(glow, 0.0), Color(glow, 0.0)]))
		if edge.a > 0.0:
			_octagon(item, rect.grow(-w * 0.5), cut, edge, w)
		var alphas := [1.0, 0.45, 0.28]
		for k in clampi(lines, 0, 3):
			var at := inset + float(k) * 3.5 * w
			_octagon(item, rect.grow(-at), maxf(2.0, cut - at * 0.4), Color(line, line.a * alphas[k]), w)
		var r := rect.grow(-inset)
		var c_in := maxf(2.0, cut - inset * 0.4)
		if lines > 0 and corners == "diamond":
			for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				_diamond(item, corner + (rect.get_center() - corner).sign() * (c_in + 3.0), 2.5 * w, line)
		elif lines > 0 and corners == "ornate":
			var reach := minf(26.0, minf(rect.size.x, rect.size.y) * 0.18)
			for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var into: Vector2 = (rect.get_center() - corner).sign()
				# a heavier fitting along both edges from the cut corner, ending in small studs
				var a: Vector2 = corner + Vector2(into.x * c_in, 0.0)
				var b: Vector2 = corner + Vector2(0.0, into.y * c_in)
				RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([a + Vector2(into.x * reach, 0.0), a, b, b + Vector2(0.0, into.y * reach)]),
					PackedColorArray([line]), 2.5 * w, true)
				_diamond(item, a + Vector2(into.x * (reach + 4.0 * w), 0.0), 2.2 * w, line)
				_diamond(item, b + Vector2(0.0, into.y * (reach + 4.0 * w)), 2.2 * w, line)
				_diamond(item, corner + into * (c_in + 6.0 * w), 3.2 * w, line)
				_diamond(item, corner + into * (c_in + 6.0 * w), 1.4 * w, dark)
		if crest:
			_crest(item, Vector2(rect.get_center().x, rect.position.y + w * 0.5 + crest_offset), minf(rect.size.x * 0.24, 240.0), w)
		if notch:
			var bottom := Vector2(rect.get_center().x, rect.end.y - w * 0.5)
			_diamond(item, bottom, 4.5 * w, notch_color)
			_diamond(item, bottom, 2.0 * w, dark)

	## A medallion on the top edge: a toothed ring around a gem, with flourishes along the edge.
	func _crest(item: RID, top: Vector2, reach: float, w: float) -> void:
		for s in [-1.0, 1.0]:
			RenderingServer.canvas_item_add_line(item, top + Vector2(s * 22.0, -3.0 * w), top + Vector2(s * reach, -3.0 * w), line, w, true)
			RenderingServer.canvas_item_add_line(item, top + Vector2(s * 22.0, 3.0 * w), top + Vector2(s * reach * 0.72, 3.0 * w), Color(line, line.a * 0.6), w, true)
			_diamond(item, top + Vector2(s * reach, -3.0 * w), 3.0 * w, line)
			_diamond(item, top + Vector2(s * reach * 0.72, 3.0 * w), 2.0 * w, line)
			_diamond(item, top + Vector2(s * 30.0, 0.0), 4.0 * w, line)
			_diamond(item, top + Vector2(s * 30.0, 0.0), 2.0 * w, fill)
		var teeth := PackedVector2Array()
		for i in 48:
			var angle := TAU * float(i) / 48.0
			teeth.append(top + Vector2.from_angle(angle) * (18.0 if (i / 2) % 2 == 0 else 15.5))
		RenderingServer.canvas_item_add_polygon(item, teeth, PackedColorArray([line]))
		RenderingServer.canvas_item_add_circle(item, top, 14.5, fill)
		_ring(item, top, 12.0, line, w)
		_diamond(item, top, 8.0, line)
		_diamond(item, top, 6.2, fill)
		_diamond(item, top, 3.2, line)

	static func _octagon(item: RID, r: Rect2, c: float, color: Color, w: float) -> void:
		var points := PackedVector2Array([
			Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
			Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
			Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c), Vector2(r.position.x + c, r.position.y),
		])
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), w, true)

	static func _ring(item: RID, at: Vector2, radius: float, color: Color, w: float) -> void:
		var points := PackedVector2Array()
		for i in 33:
			points.append(at + Vector2.from_angle(TAU * float(i) / 32.0) * radius)
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), w, true)

	static func _diamond(item: RID, at: Vector2, r: float, color: Color) -> void:
		RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), PackedColorArray([color]))


## A count on a gold coin (see count_badge()).
class CountBadge:
	extends Control
	var coin := Color.WHITE
	var rim := Color.WHITE
	var ink := Color.BLACK
	var count := 0

	func set_count(n: int) -> void:
		count = n
		visible = n > 0
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r, ink)
		draw_circle(c, r - 1.5, coin)
		draw_arc(c, r - 3.5, 0.0, TAU, 20, Color(ink, 0.35), 1.0, true)
		var text := str(count) if count < 100 else "99+"
		var font := get_theme_default_font()
		var fs := 13 if count < 10 else 11
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## The decoration over a HUD bar (see bar_decor()). Its own size is the bar's; caps and the frame
## reach a little outside.
class BarDecor:
	extends Control
	var ratio := 1.0
	var trail := 1.0
	var ticks := 10
	var low := 0.0
	var line := Color.WHITE
	var dark := Color.BLACK
	var low_color := Color.RED
	var hatch := Color.WHITE

	func set_values(fill_ratio: float, trail_ratio: float, low_amount: float = 0.0) -> void:
		if is_equal_approx(fill_ratio, ratio) and is_equal_approx(trail_ratio, trail) and is_equal_approx(low_amount, low):
			return
		ratio = fill_ratio
		trail = trail_ratio
		low = low_amount
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var filled := w * clampf(ratio, 0.0, 1.0)
		if filled > 0.5:  # gloss: a light band on top, a shade at the bottom
			var light := Color(1, 1, 1, 0.30)
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(filled, 0), Vector2(filled, h * 0.5), Vector2(0, h * 0.5)]),
				PackedColorArray([light, light, Color(light, 0.0), Color(light, 0.0)]))
			var shade := Color(dark, 0.35)
			draw_polygon(PackedVector2Array([Vector2(0, h * 0.6), Vector2(filled, h * 0.6), Vector2(filled, h), Vector2(0, h)]),
				PackedColorArray([Color(shade, 0.0), Color(shade, 0.0), shade, shade]))
		var trail_end := w * clampf(trail, 0.0, 1.0)
		if trail_end - filled > 1.0:  # the damage just taken: hatched, so it never reads as more HP
			var x := filled - h
			while x < trail_end:
				var a := Vector2(maxf(x, filled), h - (maxf(x, filled) - x))
				var b := Vector2(minf(x + h, trail_end), h - (minf(x + h, trail_end) - x))
				if b.x > a.x:
					draw_line(a, b, hatch, 1.5, true)
				x += 6.0
		for i in range(1, ticks):
			var tx := roundf(w * float(i) / float(ticks))
			var major := ticks >= 10 and i % 5 == 0
			draw_line(Vector2(tx, h * (0.0 if major else 0.55)), Vector2(tx, h), Color(dark, 0.6 if major else 0.45), 1.0)
		var frame := line.lerp(low_color, clampf(low, 0.0, 1.0))
		draw_rect(Rect2(-1.0, -1.0, w + 2.0, h + 2.0), Color(dark, 0.9), false, 1.0)
		draw_rect(Rect2(-2.5, -2.5, w + 5.0, h + 5.0), frame, false, 1.5)
		# end caps: a gem on the left, a point on the right
		var r := minf(h * 0.5 + 3.0, 12.0)
		var c := Vector2(-r + 1.0, h * 0.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), dark)
		var r2 := r - 2.0
		draw_polyline(PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0), c + Vector2(0, -r2)]), frame, 1.5, true)
		if low > 0.0:
			var font := get_theme_default_font()
			var fs := int(h + 4.0)
			var mark_w := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-mark_w * 0.5, fs * 0.36), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, frame)
		else:
			var r3 := r2 * 0.45
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r3), c + Vector2(r3, 0), c + Vector2(0, r3), c + Vector2(-r3, 0)]), frame)
		var e := Vector2(w + 2.5, h * 0.5)
		draw_colored_polygon(PackedVector2Array([e + Vector2(0, -h * 0.5 - 2.5), e + Vector2(7.0, 0), e + Vector2(0, h * 0.5 + 2.5)]), frame)


## The ornament line around a HUD piece: one line (two with `double`) and a small square at each corner.
class OrnamentFrame:
	extends Control
	var line := Color.WHITE
	var double := false
	var ticks := true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(-0.5), line, false, 1.0)
		if double:
			draw_rect(r.grow(-3.5), Color(line, line.a * 0.5), false, 1.0)
		if not ticks:
			return
		for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
			draw_rect(Rect2(corner - Vector2(2.0, 2.0), Vector2(4, 4)), line)


## Minimal rounded capsule for compact mobile resource bars.
static func capsule_style(color: Color, height: float, outline: bool = false) -> StyleBoxFlat:
	var style := flat(color, BORDER if outline else CLEAR, 1 if outline else 0, maxi(1, int(height * .5)), 0.0)
	style.corner_detail = 12
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## All dismissible windows share the same gold X and a minimum touch target.
static func close_button(button: Button) -> void:
	button.text = ""
	button.icon = null
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_constant_override("h_separation", 0)
	if not button.has_meta("centered_cross"):
		button.set_meta("centered_cross", true)
		button.draw.connect(func():
			var center := button.size * 0.5
			var radius := minf(button.size.x, button.size.y) * 0.17
			var color := Color(GOLD, 0.4 if button.disabled else 1.0)
			button.draw_line(center - Vector2(radius, radius), center + Vector2(radius, radius), color, 3.0, true)
			button.draw_line(center + Vector2(-radius, radius), center + Vector2(radius, -radius), color, 3.0, true))
	button.tooltip_text = "ปิด / Close (Esc)"
	button.custom_minimum_size = Vector2(52, 52)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	text_size(button, 16)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, GOLD)
	button.add_theme_stylebox_override("normal", plate(INK, GOLD, 1.0, true, GOLD, 4))
	button.add_theme_stylebox_override("hover", plate(PANEL_LIGHT, GOLD, 1.0, true, GOLD, 4))
	button.add_theme_stylebox_override("pressed", plate(PANEL, GOLD, 1.0, true, GOLD, 4))
	button.add_theme_stylebox_override("focus", plate(CLEAR, GOLD, 1.0, true, GOLD, 4))
	if not button.has_meta("corner_close_scheduled"):
		button.set_meta("corner_close_scheduled", true)
		_dock_corner_close.call_deferred(button)

static func _dock_corner_close(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var ancestor := button.get_parent()
	while ancestor != null and not ancestor is PanelContainer:
		ancestor = ancestor.get_parent()
	if ancestor == null: return
	var window := ancestor as PanelContainer
	var previous := button.get_parent()
	# Keep header contents clear of the overlaid corner button.
	if previous is Container:
		var reserve := Control.new()
		reserve.custom_minimum_size = Vector2(104 if button.has_meta("npc_help_requested") else 44, 44)
		previous.add_child(reserve)
		previous.move_child(reserve, button.get_index())
	# Node2D is not managed by PanelContainer's content margins or scrolling.
	var overlay := Node2D.new()
	overlay.name = "CornerCloseOverlay"
	overlay.z_index = 30
	window.add_child(overlay)
	button.reparent(overlay, false)
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.size = Vector2(52, 52)
	var arrange := func():
		if is_instance_valid(button):
			button.position = Vector2(window.size.x - 44, -8)
	window.resized.connect(arrange)
	arrange.call()


static func add_close(header: HBoxContainer, action: Callable) -> Button:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var button := Button.new()
	close_button(button)
	button.pressed.connect(action)
	header.add_child(button)
	return button

## Reserved NPC guide entry, positioned alongside the corner close after docking.
static func npc_help(close: Button, guide_key: String = "default") -> void:
	close.set_meta("npc_help_requested", true)
	_attach_npc_help.call_deferred(close, guide_key)

static func _attach_npc_help(close: Button, guide_key: String) -> void:
	if not is_instance_valid(close) or close.has_meta("npc_help"): return
	close.set_meta("npc_help", true)
	var help := Button.new()
	help.name = "NpcHelp"
	help.text = "!"
	help.tooltip_text = "วิธีใช้งาน · กำลังเตรียมคำแนะนำ"
	help.custom_minimum_size = Vector2(52, 52)
	help.alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_size(help, 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		help.add_theme_stylebox_override(state, plate(PANEL_LIGHT if state == "hover" else INK, GOLD, 1.0, true, GOLD, 4))
		help.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), GOLD)
	close.get_parent().add_child(help)
	help.z_index = close.z_index
	var arrange := func():
		if is_instance_valid(help) and is_instance_valid(close):
			help.size = close.size
			help.position = close.position - Vector2(close.size.x + 8, 0)
	close.resized.connect(arrange)
	close.item_rect_changed.connect(arrange)
	arrange.call()
	help.pressed.connect(func(): preload("res://client/npc_guide.gd").show_for(help, guide_key))
