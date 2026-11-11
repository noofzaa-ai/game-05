extends RefCounted
## Design tokens of the Class Card screen (docs/ui/class_card_ui_handoff.md §5, §7, §8, §11, §12).
## Every colour, size, string and art path of client/card_deck_screen.gd and client/card_portrait.gd lives
## here (tests/test_ui_tokens.gd checks that the screens hold none of their own).
## Sizes are at the 1920x1080 reference; the screen multiplies them by its scale.
## FINAL ART: drop the PNGs of §12 into ART_DIR with the names of the table; every skin() / tex() call below
## uses the file when it exists and falls back to the flat placeholder when it does not.

const InkUi := preload("res://client/ink_ui.gd")

const ART_DIR := "res://art/ui/class_cards/"  ## the one path the real art is read from
const FONT_DISPLAY_PATH := "res://art/fonts/Mitr-SemiBold.woff2"  ## spec §2; absent until art-director adds it
const FONT_MEDIUM_PATH := "res://art/fonts/Mitr-Medium.woff2"

# ------------------------------------------------------------------ palette (§5.2)
const INK := Color("1B1530")
const SKY_TOP := Color("7FC8FF")
const SKY_BOTTOM := Color("FFE1B8")
const CLOUD := Color("FFFFFF")
const CLOUD_SHADOW := Color("CFE4FF")
const PAPER := Color("FFF6E6")
const PAPER_SHADOW := Color("F0D9B5")
const NIGHT := Color("3B3266")
const FRAME := Color("FFD35C")
const FRAME_SHADOW := Color("E8A93A")
const FRAME_LIGHT := Color("FFF2B0")
const ACTION := Color("FF7A2F")
const ACTION_SHADOW := Color("D9531A")
const ACTION_LIGHT := Color("FFC08A")
const DISABLED := Color("B9B3C9")
const DISABLED_SHADOW := Color("8F88A6")
const ERROR := Color("FF5A6E")
const TEXT_DARK := Color("1B1530")
const TEXT_LIGHT := Color("FFFFFF")
const ADD_GREEN := Color("6CCF5A")
const FOCUS := Color("FFFFFF")
const STICKER_SHADOW := Color(0.106, 0.082, 0.188, 0.35)  ## ink at 35%
const FLASH := Color("FFFFFF")
const SLATE := Color("6E7892")
const BORDER_OUTER := Color("D5D9E0")  ## card border, light grey: outer line
const BORDER_INNER := Color("B8BEC9")  ## inner line
const SLATE_PLATE := Color("2B3347")  ## name plate and badge base
const NAVY := Color("141A2E")  ## card backdrop base
const BACKDROP_MIX_TOP := 0.30  ## how much of the class accent tints the flat backdrop (top, bottom)
const BACKDROP_MIX_BOTTOM := 0.08
const BACKDROP_ART_PREFIX := "card_backdrop_"  ## ART_DIR + prefix + class id + ".png" replaces the flat backdrop when it exists

## Class accents (Boss 2026-11-11 plain card look). "base" is the accent; "emblem" is the placeholder glyph until
## card_emblem_<class>.png exists.
const CLASSES := {
	"sword_shield": {"base": Color("3F7FA6"), "shadow": Color("2B5C7A"), "light": Color("8DB8D2"), "emblem": "SS"},
	"greatsword": {"base": Color("A8473F"), "shadow": Color("7C302A"), "light": Color("D89A94"), "emblem": "GS"},
	"longbow": {"base": Color("5E8F57"), "shadow": Color("416A3C"), "light": Color("A3C79E"), "emblem": "LB"},
	"magic": {"base": Color("7B65B0"), "shadow": Color("574780"), "light": Color("B7A8D8"), "emblem": "MG"},
}
const CLASS_FALLBACK := {"base": Color("B9B3C9"), "shadow": Color("8F88A6"), "light": Color("E6E2F0"), "emblem": "?"}

# ------------------------------------------------------------------ type scale (§5.4, at 1080p)
const FONT_SCREEN_TITLE := 40
const FONT_CARD_NAME := 22
const FONT_EDITOR_NAME := 34
const FONT_FIGHT := 36
const FONT_TAB := 22
const FONT_OPTION := 18
const FONT_HINT := 18
const FONT_STICKER := 22
const FONT_MIN := 16  ## text never shrinks below this on screen

# ------------------------------------------------------------------ outlines (§5.1)
const OUTLINE_FRAME := 7
const OUTLINE_BUTTON := 4
const OUTLINE_PRIMARY := 5
const OUTLINE_ICON := 3
const OUTLINE_TEXT := 4
const OUTLINE_TEXT_SMALL := 3
const SHADOW_DROP := 6
const FOCUS_WIDTH := 4

# ------------------------------------------------------------------ layout (§6, §7) at 1920x1080
const REF_SIZE := Vector2(1920.0, 1080.0)
const SAFE := Vector2(48.0, 32.0)
const CARD_SIZE := Vector2(220.0, 308.0)
const CARD_GAP := 48.0
const CARD_MIN_WIDTH := 170.0  ## §15: with 5-6 cards the row shrinks to this, then scrolls
const CARD_FAN_ROTATION: Array[float] = [-6.0, -2.0, 2.0, 6.0]
const CARD_FAN_DROP: Array[float] = [12.0, 0.0, 0.0, 12.0]
const CARD_TOP := 180.0
# Card frame (client/card_frame.gd), sizes at the 220 px wide card
const CARD_RADIUS := 22.0  ## corner radius
const CARD_LINE_OUTER := 5.0
const CARD_LINE_INNER := 2.5
const CARD_LINE_GAP := 4.0
const CARD_NOTCH_HALF := 12.0  ## notch at top centre of the border lines
const CARD_NOTCH_DEPTH := 5.0
const CARD_WINDOW_INSET := 12.0  ## portrait window distance from the card edge
const CARD_PLATE_H := 40.0  ## name plate height
const CARD_PLATE_LINE := 2.0  ## class accent line on top of the plate
const CARD_BADGE := Vector2(50.0, 58.0)  ## shield hexagon, top left
const CARD_BADGE_MARGIN := 13.0
const CARD_BADGE_LINE := 2.5
const CARD_ARC_STEPS := 8  ## segments per rounded corner
const CARD_BADGE_SHOULDER := 0.14  ## hexagon shoulder drop and lower point, as fractions of the badge height
const CARD_BADGE_WAIST := 0.62
const CARD_NUMBER := 30.0  ## numeric badge slot, top right
const CARD_NUMBER_RADIUS := 0.3  ## corner radius as a fraction of the slot
const CARD_NUMBER_FILL_ALPHA := 0.6
const CARD_EMBLEM_TEXT_MIN_UNIT := 0.5  ## below this card scale the emblem letters are left out
const CARD_RING_PAD := 6.0
const CARD_RING_WIDTH := 4.0
const EDITOR_CARD := Vector2(420.0, 588.0)
const EDITOR_CARD_POS := Vector2(120.0, 140.0)
const EDITOR_SHEET_POS := Vector2(620.0, 140.0)
const EDITOR_SHEET_SIZE := Vector2(1180.0, 760.0)
const STRIP_CARD := Vector2(88.0, 124.0)
const STRIP_GAP := 16.0
const SQUAD_BAR := Vector2(900.0, 180.0)
const SQUAD_BAR_POS := Vector2(48.0, 820.0)
const SQUAD_SLOT := Vector2(140.0, 150.0)
const SQUAD_SLOT_GAP := 24.0
const FIGHT_SIZE := Vector2(400.0, 120.0)
const TOP_BAR_H := 72.0
const ICON_BUTTON := 64.0
const ICON_GAP := 16.0
const PILL_H := 64.0
const BUBBLE := 96.0
const BUBBLE_GAP := 24.0
const BLOB := 56.0
const STICKER_BUTTON := 48.0
const SLOT_REMOVE := 40.0
const OUTFIT_TILE := Vector2(220.0, 280.0)
const SKILL_SOCKET := 140.0
const PICKER_SIZE := Vector2(480.0, 420.0)
const TOAST_H := 56.0
const TOAST_SECONDS := 2.5
const PHONE_ASPECT := 2.0  ## width/height from here on counts as a phone landscape (§7.3)
const PHONE_CARD := Vector2(190.0, 266.0)
const PHONE_CARD_GAP := 32.0
const PHONE_FIGHT := Vector2(340.0, 110.0)
const PHONE_SQUAD_W := 760.0
const PHONE_EDITOR_CARD := Vector2(340.0, 476.0)
const PHONE_BUBBLE := 84.0
const MIN_TOUCH := 56.0
const SCALE_MIN := 0.45
const SCALE_MAX := 1.5

# ------------------------------------------------------------------ motion (§9, §10)
const BOB_PIXELS := 4.0
const BOB_SECONDS := 2.5
const BOB_OFFSET := 0.4
const SQUASH := 0.03
const SHINE_EVERY := 5.0
const HOVER_LIFT := 10.0
const HOVER_SECONDS := 0.18
const TILT_MAX := 8.0
# Holo card (the card the pointer or focus is on): foil sheen, tilt parallax and sparkles. See client/card_holo.gd.
const HOLO_SMOOTH := 10.0  ## how fast the tilt follows the pointer (per second)
const HOLO_SWAY := Vector2(0.35, 0.2)  ## idle sway (-1..1 tilt) while focused without a pointer
const HOLO_SWAY_SPEED := Vector2(0.8, 0.6)
# Card depth layers (Boss 2026-11-11 "living inside the card"): base, backdrop art, holo, lines, the 3D character
# (clipped by the outer card shape only, so it can cross the inner lines), then badge / number / name plate.
const BACKDROP_PARALLAX := 0.022  ## backdrop shift AGAINST the tilt, as a fraction of the card (UV)
const BACKDROP_ART_ZOOM := 1.06  ## the art is drawn this much bigger than the window so the shift never shows an edge
const FIGURE_PARALLAX := 0.05  ## character shift WITH the tilt, as a fraction of the card size (more than the backdrop)
const FIGURE_SHADOW_FOLLOW := 0.45  ## the character's shadow sits on the backdrop: it follows the character this much
const FIGURE_SHADOW_DROP := Vector2(4.0, 6.0)  ## shadow offset at the 220 px card
const FIGURE_SHADOW_BLUR := 2.5  ## texture pixels
const FIGURE_SHADOW_COLOR := Color(0.02, 0.03, 0.07, 0.62)
const FIGURE_HALO_COLOR := Color(0.02, 0.03, 0.07, 0.42)  ## soft dark halo behind the body
const FIGURE_HALO_CLEAR := Color(0.02, 0.03, 0.07, 0.0)
const FIGURE_HALO_CENTER := Vector2(0.5, 0.5)  ## fractions of the card
const FIGURE_HALO_SIZE := Vector2(1.0, 0.78)
const VIGNETTE_COLOR := Color(0.03, 0.04, 0.09, 0.7)  ## backdrop edge darkening
const VIGNETTE_CLEAR := Color(0.03, 0.04, 0.09, 0.0)
const VIGNETTE_INNER := 0.45  ## the vignette starts at this fraction of the radius
const HOLO_SHEEN := 0.10
const HOLO_RAINBOW := 0.16
const HOLO_STREAK := 0.30
const HOLO_EDGE := 0.40
## Editor card (always-on foil): weaker so the backdrop art reads, still a visible subtle foil.
const HOLO_EDITOR_SCALE := 0.45
const HOLO_FADE_SECONDS := 0.2
const HOLO_SPARKLES := 8
const HOLO_SPARKLE_SECONDS := 1.6
const HOLO_SPARKLE_SIZE := 26.0
const HOLO_SPARKLE_COLOR := Color(1.0, 0.97, 0.8, 0.9)
const HOLO_DOT_COLOR := Color(1.0, 1.0, 1.0, 1.0)  ## sparkle dot texture: opaque centre
const HOLO_DOT_CLEAR := Color(1.0, 1.0, 1.0, 0.0)
const SELECT_SCALE := 1.15
const SELECT_SETTLE := 1.1
const SELECT_SECONDS := 0.22
const EDITOR_SHEET_SECONDS := 0.25
const WIGGLE_DEGREES := 3.0
const WIGGLE_SECONDS := 0.2
const SHAKE_PIXELS := 8.0
const SHAKE_SECONDS := 0.25
const FADE_SECONDS := 0.15  ## reduced motion: transitions become this fade
const CLOUD_SPEED := 8.0
const SUMMON_HOP := 0.30
const SUMMON_FLIP := 0.40
const SUMMON_BURST := 0.30
const SUMMON_FLASH := 0.20
const SUMMON_TOTAL := 1.2  ## summon_finished is emitted at this time (§13)
const SUMMON_STACK_OFFSET := 14.0
const BURST_POINTS := 12
const BURST_INNER := 0.55
const BURST_RADIUS := 260.0
const CLOUD_Y: Array[float] = [0.10, 0.36, 0.60, 0.22]  ## fractions of the screen height
const CLOUD_WIDTH: Array[float] = [420.0, 320.0, 520.0, 360.0]
const CLOUD_HEIGHT := 120.0
const CLOUD_FADE := 0.9
const INTRO_SECONDS := 0.3  ## coming back from a fight: the cards bob in
const INTRO_RISE := 24.0
const SQUAD_BAR_LABEL_W := 90.0
const STAR_SPIN_SECONDS := 0.4

# ------------------------------------------------------------------ 3D portrait (card_portrait.gd)
const PORTRAIT_MAX_PIXELS := Vector2(440.0, 620.0)
const PORTRAIT_MIN_PIXELS := Vector2(64.0, 96.0)
const PORTRAIT_FOV := 24.0
const PORTRAIT_FRAME_PAD := 1.08  ## "full" / "bust" framing margin
## "card" framing (deck and editor cards): the portrait covers the whole card; the model's top lands at
## PORTRAIT_FRAME_TOP and its feet at PORTRAIT_FRAME_BOTTOM (fractions of the card height, >1 = below the card,
## hidden by the name plate). The top sits just over the inner border line, so the head breaks out of the window.
const PORTRAIT_FRAME_TOP := 0.012
const PORTRAIT_FRAME_BOTTOM := 1.045  ## about 0.9x of the first framing (1.16): the face clears the badge
## "card_deck" framing (deck cards only): smaller figure so a shield / weapon stays above the name plate.
const PORTRAIT_DECK_TOP := 0.012
const PORTRAIT_DECK_BOTTOM := 0.90
const PORTRAIT_KEY_ENERGY := 0.25
const PORTRAIT_RIM_ENERGY := 1.6  ## rim light from behind: lifts the character off the backdrop
const PORTRAIT_AMBIENT := Color(0.82, 0.8, 0.78)
const PORTRAIT_AMBIENT_ENERGY := 0.8
const PORTRAIT_LIGHT := Color(1.0, 0.96, 0.9)
const PORTRAIT_LIGHT_ENERGY := 1.1
const PORTRAIT_LIGHT_ANGLE := Vector3(-35.0, 30.0, 0.0)
const PORTRAIT_THROTTLE_SECONDS := 0.2  ## unselected cards redraw this often (web performance)
const PORTRAIT_HOVER_TURN := 0.35  ## radians the character turns toward the pointer
const PORTRAIT_PULSE_SCALE := 1.08
const PORTRAIT_PULSE_SECONDS := 0.25

# ------------------------------------------------------------------ strings (§11): Thai first, English second
## The game has no localisation system yet; this table is the one place the screen's words live.
static var language := "th"
const STRINGS := {
	"deck_title": ["การ์ดของฉัน", "My Cards"],
	"deck_hint": ["แตะการ์ดเพื่อแต่ง · แตะ + เพื่อลงทัพ", "Tap a card to customise · Tap + to add to squad"],
	"squad": ["ทัพ", "Squad"],
	"squad_full": ["ทัพเต็มแล้ว (3)", "Squad full (3)"],
	"squad_need_one": ["ต้องมีอย่างน้อย 1 ใบ", "Need at least 1 card"],
	"squad_ready": ["ทัพครบ", "Full squad"],
	"fight": ["ออกรบ!", "FIGHT!"],
	"bag": ["กระเป๋า", "Bag"],
	"settings": ["ตั้งค่า", "Settings"],
	"back": ["กลับ", "Back"],
	"reset_card": ["รีเซ็ตการ์ด", "Reset card"],
	"reset_confirm": ["คืนการ์ดใบนี้เป็นแบบเริ่มต้น?", "Reset this card to its starting look?"],
	"yes": ["ใช่", "Yes"],
	"no": ["ไม่", "No"],
	"tab_hair": ["ผม", "Hair"],
	"tab_eyes": ["ตา", "Eyes"],
	"tab_outfit": ["ชุด", "Outfit"],
	"tab_body": ["ตัว", "Body"],
	"tab_skills": ["สกิล", "Skills"],
	"coming_soon": ["เร็วๆ นี้", "Coming soon"],
	"eye_color": ["สีตา", "Eye colour"],
	"eye_makeup": ["แต่งตา", "Eye makeup"],
	"skin_tone": ["สีผิว", "Skin tone"],
	"custom": ["กำหนดเอง", "Custom"],
	"done": ["เสร็จ", "Done"],
	"cancel": ["ยกเลิก", "Cancel"],
	"change_failed": ["เปลี่ยนไม่สำเร็จ ลองใหม่อีกครั้ง", "Couldn't change that, try again"],
	"class_sword_shield": ["ดาบและโล่", "Sword & Shield"],
	"class_greatsword": ["ดาบใหญ่", "Great Sword"],
	"class_longbow": ["ธนูยาว", "Longbow"],
	"class_magic": ["เวทมนตร์", "Magic"],
	"outfit_none": ["ชุดพื้นฐาน", "Basic"],
	"outfit_silver": ["Silver Silk", "Silver Silk"],
	"makeup_none": ["ไม่แต่ง", "None"],
	"makeup_sharp_wing": ["Sharp Wing", "Sharp Wing"],
	"hair_prefix": ["ผม ", "Hair "],
	"remove_from_squad": ["เอาออกจากทัพ", "Remove from squad"],
	"add_to_squad": ["ลงทัพ", "Add to squad"],
}


static func t(key: String) -> String:
	var entry: Array = STRINGS.get(key, [key, key])
	return str(entry[0 if language == "th" else 1])


static func class_name_of(class_id: String) -> String:
	var key := "class_" + class_id
	return t(key) if STRINGS.has(key) else class_id.replace("_", " ").capitalize()


static func hair_name(hair_id: String) -> String:
	return t("hair_prefix") + hair_id.to_upper()


## Name of an outfit / makeup choice (the ids are the ones of logic/card_deck.gd).
static func choice_name(part: String, choice: String) -> String:
	var key := "%s_%s" % [part, choice]
	return t(key) if STRINGS.has(key) else choice


# ------------------------------------------------------------------ palette and art lookups
static func palette(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, CLASS_FALLBACK)


## Dark backdrop of a class card: the art file when it exists, else a flat vertical gradient (see card_frame.gd).
static func backdrop(class_id: String) -> Texture2D:
	return tex(BACKDROP_ART_PREFIX + class_id)


static func backdrop_top(class_id: String) -> Color:
	return NAVY.lerp(palette(class_id)["base"], BACKDROP_MIX_TOP)


static func backdrop_bottom(class_id: String) -> Color:
	return NAVY.lerp(palette(class_id)["base"], BACKDROP_MIX_BOTTOM)


static var _radials := {}


## A soft round gradient (centre colour to edge colour, starting at `inner`), cached per key.
static func radial(key: String, centre: Color, edge: Color, inner: float) -> GradientTexture2D:
	if _radials.has(key):
		return _radials[key]
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, inner, 1.0])
	gradient.colors = PackedColorArray([centre, centre, edge])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_radials[key] = texture
	return texture


static func vignette() -> GradientTexture2D:
	return radial("vignette", VIGNETTE_CLEAR, VIGNETTE_COLOR, VIGNETTE_INNER)


static func figure_halo() -> GradientTexture2D:
	return radial("halo", FIGURE_HALO_COLOR, FIGURE_HALO_CLEAR, 0.0)


static func clear_style() -> StyleBox:
	return StyleBoxEmpty.new()


static func tex(art_name: String) -> Texture2D:
	var path := ART_DIR + art_name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Layout scale of a screen size: the 1920x1080 reference fitted into it.
static func scale_for(screen: Vector2) -> float:
	return clampf(minf(screen.x / REF_SIZE.x, screen.y / REF_SIZE.y), SCALE_MIN, SCALE_MAX)


static func is_phone(screen: Vector2) -> bool:
	return screen.x / maxf(screen.y, 1.0) >= PHONE_ASPECT


# ------------------------------------------------------------------ fonts and text
static func _font(path: String, fallback: Font) -> Font:
	if ResourceLoader.exists(path):
		var face: Font = load(path)
		if face != null:
			return face
	return fallback


static func display_font() -> Font:
	return _font(FONT_DISPLAY_PATH, InkUi.display_font())


static func medium_font() -> Font:
	return _font(FONT_MEDIUM_PATH, InkUi.display_font())


static func body_font() -> Font:
	return InkUi.font()


## Styles a Label / Button text. `role` is one of the FONT_ sizes (at 1080p), `s` the layout scale.
static func style_text(control: Control, size: int, color: Color, s: float, outline: int = 0, face: String = "display") -> void:
	var px := maxi(int(round(size * s)), FONT_MIN)
	control.add_theme_font_size_override("font_size", px)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_outline_color", INK)
	control.add_theme_constant_override("outline_size", int(round(outline * s)) if outline > 0 else 0)
	var font: Font = display_font() if face == "display" else (medium_font() if face == "medium" else body_font())
	if font != null:
		control.add_theme_font_override("font", font)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		if control is Button:
			control.add_theme_color_override(state, color)
	if control is Button:
		control.add_theme_color_override("font_disabled_color", Color(color, 0.6))


## A new Label (never takes clicks).
static func label(text: String, size: int, color: Color, s: float, outline: int = 0, face: String = "display") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	style_text(l, size, color, s, outline, face)
	return l


# ------------------------------------------------------------------ style boxes (the only StyleBoxFlat of the screen)
static func flat(fill: Color, border: Color, border_width: float, radius: float, s: float, sticker: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(round(border_width * s)))
	box.set_corner_radius_all(int(round(radius * s)))
	box.anti_aliasing = true
	if sticker:
		box.shadow_color = STICKER_SHADOW
		box.shadow_offset = Vector2(0.0, SHADOW_DROP * s)
		box.shadow_size = 0
	return box


static func ring(color: Color, width: float, radius: float, s: float) -> StyleBoxFlat:
	var box := flat(Color(color, 0.0), color, width, radius, s)
	box.draw_center = false
	return box


## The real art when ART_DIR has `art_name`, else `fallback`. `margins` = left, top, right, bottom of the 9-slice.
static func skin(art_name: String, margins: Array, fallback: StyleBox) -> StyleBox:
	var image := tex(art_name)
	if image == null:
		return fallback
	var box := StyleBoxTexture.new()
	box.texture = image
	box.texture_margin_left = float(margins[0])
	box.texture_margin_top = float(margins[1])
	box.texture_margin_right = float(margins[2])
	box.texture_margin_bottom = float(margins[3])
	return box


static func panel_paper(s: float, radius: float = 28.0) -> StyleBox:
	return skin("panel_paper", [64, 64, 64, 64], flat(PAPER, INK, OUTLINE_BUTTON, radius, s, true))


## Pill buttons and tabs (§8). kind: "primary" | "secondary" | "icon" | "tab" | "tab_open" | "bubble" | "blob" | "sticker".
## `tint` is the class colour (tab_open), the paint colour (blob) or the sticker colour.
static func button_skin(button: Button, kind: String, s: float, tint: Color = ACTION) -> void:
	var fills := {"normal": PAPER, "hover": FRAME_LIGHT, "pressed": PAPER_SHADOW, "disabled": DISABLED}
	var border_color := INK
	var width := float(OUTLINE_BUTTON)
	var radius := 32.0
	match kind:
		"primary":
			fills = {"normal": ACTION, "hover": ACTION_LIGHT, "pressed": ACTION_SHADOW, "disabled": DISABLED}
			width = OUTLINE_PRIMARY
			radius = 60.0
		"icon":
			width = OUTLINE_ICON
			radius = 64.0
		"tab_open":
			fills = {"normal": tint, "hover": tint, "pressed": tint, "disabled": DISABLED}
		"bubble":
			radius = BUBBLE
		"blob", "sticker":
			fills = {"normal": tint, "hover": tint.lightened(0.15), "pressed": tint.darkened(0.15), "disabled": DISABLED}
			width = OUTLINE_ICON
			radius = BUBBLE
	for state in fills:
		var drop: float = SHADOW_DROP * 0.67 if kind != "primary" else SHADOW_DROP
		var box := flat(fills[state], border_color, width, radius, s, state != "pressed" and state != "disabled")
		if state == "pressed":
			box.content_margin_top = drop * s
		box.shadow_offset = Vector2(0.0, drop * s) if state != "pressed" else Vector2.ZERO
		var art := skin("btn_%s_%s" % [kind, state], [60, 0, 60, 0] if kind == "primary" else [32, 0, 32, 0], box) if kind in ["primary", "secondary"] else box
		button.add_theme_stylebox_override(state, art)
	var focus := ring(FOCUS, FOCUS_WIDTH, radius + 4.0, s)
	focus.expand_margin_left = 3.0 * s
	focus.expand_margin_right = 3.0 * s
	focus.expand_margin_top = 3.0 * s
	focus.expand_margin_bottom = 3.0 * s
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))


static func selected_ring(s: float, radius: float) -> StyleBoxFlat:
	return ring(ACTION, 6.0, radius, s)


static func sky_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([SKY_TOP, SKY_BOTTOM])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture


## The screen sets styles and spacing only through these (no theme overrides in the screen file).
static func panel(control: Control, style: StyleBox) -> void:
	control.add_theme_stylebox_override("panel", style)


static func gap(container: Control, px: float, s: float) -> void:
	container.add_theme_constant_override("separation", int(round(px * s)))


static func flow_gap(container: Control, px: float, s: float) -> void:
	container.add_theme_constant_override("h_separation", int(round(px * s)))
	container.add_theme_constant_override("v_separation", int(round(px * s)))


static func margin(container: MarginContainer, px: float, s: float) -> void:
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_" + side, int(round(px * s)))


## Makes a ColorPicker the small hue-wheel + preview of spec §7.2 (no sliders, hex, sampler or presets).
static func simple_picker(picker: ColorPicker) -> void:
	picker.edit_alpha = false
	picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	picker.sampler_visible = false
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.presets_visible = false
