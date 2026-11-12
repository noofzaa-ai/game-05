extends RefCounted
## Design tokens of the Class Card screen (docs/ui/class_card_ui_handoff.md §5, §7, §8, §11, §12).
## Every colour, size, string and art path of client/card_deck_screen.gd and client/card_portrait.gd lives
## here (tests/test_ui_tokens.gd checks that the screens hold none of their own).
## Sizes are at the 1920x1080 reference; the screen multiplies them by its scale.
## FINAL ART: drop the PNGs of §12 into ART_DIR with the names of the table; every skin() / tex() call below
## uses the file when it exists and falls back to the flat placeholder when it does not.

const InkUi := preload("res://client/ink_ui.gd")

const ART_DIR := "res://art/ui/class_cards/"  ## the one path the real art is read from
## Hub look (Boss 2026-11-11): Taviraj for titles / plates, Sarabun for body text (both in art/fonts/).
const FONT_DISPLAY_PATH := "res://art/fonts/Taviraj-SemiBold.woff2"
const FONT_MEDIUM_PATH := "res://art/fonts/Sarabun-SemiBold.woff2"

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

# ------------------------------------------------------------------ hub (docs/ui/hub_layout_spec.md, Boss 2026-11-11)
## Leather / parchment palette of the approved v10 art.
const HUB_INK := Color("3A2414")  ## dark brown text on parchment
const HUB_CREAM := Color("F0E2C4")  ## light text over the night scene
const HUB_MUTED := Color("D9C8A6")  ## secondary light text
const HUB_SLOT_TEXT := Color("8C7458")  ## empty slot names on dark leather
const HUB_TAB_IDLE := Color("6A5038")  ## inactive tab label
const HUB_UNDERLINE := Color("7A2E1C")  ## active tab underline
const HUB_OUTLINE := Color("120C08")  ## dark outline of light text
const HUB_BADGE := Color("C8372D")  ## notification disc
const HUB_BADGE_RING := Color("2A140C")
const HUB_BADGE_TEXT := Color("FFFFFF")
const HUB_GOLD_EDGE := Color("B98A4E")
const HUB_PILL := Color(0.149, 0.086, 0.047, 0.9)  ## gold counter back
const HUB_GLOW := Color(1.0, 0.75, 0.42, 0.75)  ## hover glow / squad card glow
const HUB_SCENE_DIM := Color(0.031, 0.039, 0.078, 0.24)  ## over the background (the mock darkens it a little)
const HUB_FIGHT_GLOW := Color(1.0, 0.59, 0.27, 0.8)
const HUB_HOVER := Color(1.12, 1.06, 0.96)  ## menu plate brightened on hover / focus
const HUB_PRESSED := Color(0.92, 0.92, 0.92)  ## pressed: 8% darker
const HUB_LOCKED := Color(0.6, 0.58, 0.56)  ## locked: darkened (plus the grey shader)
const HUB_DIM := Color(0.024, 0.016, 0.008, 0.62)  ## behind a panel over the hub
const HUB_CHAR_DIM := Color(0.024, 0.016, 0.008, 0.47)  ## over the background of the character screen
const HUB_PAPER := Color("F3E6C8")  ## details box parchment
const HUB_PAPER_EDGE := Color("B98A4E")
const HUB_LEATHER := Color("5A3420")
const HUB_LEATHER_EDGE := Color("2A140C")
const HUB_BAR_BACK := Color("4A2C1A")  ## durability bar
const HUB_BAR_FILL := Color("D4A866")
const HUB_BAR_LOW := Color("C8372D")
const HUB_STAT_STRIP := Color(0.07, 0.05, 0.04, 0.78)
const HUB_TIER: Array[Color] = [Color("E8E2D4"), Color("5A8FD8"), Color("A06AD8"), Color("E0A83A")]  ## pips 1..4
const HUB_SUBTEXT := Color("3E6CB8")  ## slot · tier line
const HUB_REFINE := Color("FFE7A8")  ## "+N" on slots
const HUB_GOOD := Color("2E7D32")
const HUB_BAD := Color("B3261E")
const HUB_WINDOW_BOTTOM := Color(0.094, 0.07, 0.055)  ## card window gradient bottom (top = class accent)
const HUB_WINDOW_LOCKED := Color(0.16, 0.16, 0.16)
const HUB_CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const HUB_WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Art (ART_DIR + name + ".png"); imported from art_source/ui/class_cards/v10 (Boss accepted 2026-11-11).
const HUB_BG := "hub_bg_ruins"
const HUB_CARD_FRAME_PREFIX := "card_frame_"  ## + class id
const HUB_MENU_PLATE := "hub_menu_plate"
const HUB_ICON_PREFIX := "hub_icon_"  ## + service icon id
const HUB_TRAY := "hub_squad_tray"
const HUB_FIGHT := "hub_fight_button"
const HUB_PANEL := "hub_panel_tabs"
const HUB_SLOT := "equip_slot_normal"
const HUB_SLOT_SELECTED := "equip_slot_selected"
const HUB_SYS_PREFIX := "hub_sys_"  ## settings | back | gold | account

## Side menu, most used first (spec §2). icon = HUB_ICON_PREFIX + icon.
const HUB_SERVICES: Array[Dictionary] = [
	{"id": "blacksmith", "icon": "blacksmith"}, {"id": "shop", "icon": "shop"}, {"id": "tailor", "icon": "tailor"},
	{"id": "storage", "icon": "storage"}, {"id": "quests", "icon": "quest"}, {"id": "relics", "icon": "relics"},
]
const HUB_STAGE_FILE := "res://data/journeys/goblin_waves.json"  ## the stage name over FIGHT (its "name")

# Fonts (at the 1080 reference)
const FONT_HUB_TITLE := 52
const FONT_HUB_MENU := 34
const FONT_HUB_MENU_SUB := 18
const FONT_HUB_CARD_NAME := 24
const FONT_HUB_SQUAD := 18
const FONT_HUB_LOCKED := 36
const FONT_HUB_HINT := 22
const FONT_HUB_FIGHT := 64
const FONT_HUB_STAGE := 22
const FONT_HUB_GOLD := 28
const FONT_HUB_BADGE := 20
const FONT_HUB_TRAY_NUM := 24
const FONT_HUB_TRAY_ADD := 18
const FONT_HUB_PANEL_TITLE := 44
const FONT_HUB_BODY := 26
const FONT_CHAR_TITLE := 52
const FONT_CHAR_SWITCH := 20
const FONT_CHAR_TAB := 30
const FONT_CHAR_ITEM := 34
const FONT_CHAR_LINE := 22
const FONT_CHAR_SLOT := 16
const FONT_CHAR_STAT := 18
const FONT_CHAR_BUTTON := 26
const OUTLINE_HUB := 3

# Layout at the 1920x1080 reference
const HUB_SAFE := Vector2(40.0, 24.0)
const HUB_PHONE_SAFE_X := 132.0  ## extra side inset on phones (notch / rounded corners)
const HUB_TITLE_Y := 64.0  ## title line centre
const HUB_SYS_SIZE := 80.0
const HUB_SYS_PHONE := 96.0  ## phones: bigger system buttons (spec §1)
const HUB_SYS_Y := 26.0
const HUB_SYS_GAP := 16.0
const HUB_GOLD_SIZE := Vector2(184.0, 54.0)
const HUB_GOLD_GAP := 70.0  ## between the gold counter and the system buttons
const HUB_MENU_X := 28.0  ## from the side edge (or the phone safe inset)
const HUB_MENU_Y := 132.0
const HUB_MENU_ENTRY := Vector2(300.0, 100.0)  ## the plate (art aspect 1458x423 -> 300x87, centred in 100)
const HUB_MENU_STEP := 104.0
const HUB_MENU_HOVER_SHIFT := 6.0
const HUB_MENU_PRESS_SHIFT := 2.0
const HUB_MENU_ICON_SCALE := 1.05  ## medallion height / plate height
const HUB_MENU_ICON_X := 0.135  ## medallion centre, fraction of the plate width
const HUB_MENU_LABEL := Vector2(0.27, 0.93)  ## parchment label from/to, fractions of the plate width
const HUB_MENU_PRESS_ICON := 0.96
const HUB_BADGE_R := 17.0
const HUB_BADGE_AT := Vector2(0.235, 0.12)  ## badge centre on the plate
const HUB_CARD_AREA_X := 400.0  ## the card row starts right of the menu (from the side edge)
const HUB_CARD := Vector2(300.0, 450.0)
const HUB_CARD_GAP := 34.0
const HUB_CARD_MIN_W := 240.0
const HUB_PHONE_CARD_GROW := 1.12  ## phones: cards a little bigger when the row has room (names stay readable)
const HUB_CARD_TOP := 150.0
const HUB_CARD_LIFT := 12.0  ## squad cards sit a little higher
const HUB_CARD_FOCUS_LIFT := 8.0
const HUB_GLOW_PAD := 16.0
const HUB_HINT_Y := 640.0
const HUB_TRAY_X := 470.0  ## from the side edge (or the phone safe inset)
const HUB_TRAY_W := 760.0
const HUB_TRAY_BOTTOM := 34.0
const HUB_FIGHT_W := 470.0
const HUB_FIGHT_MIN_W := 300.0
const HUB_FIGHT_RIGHT := 40.0
const HUB_FIGHT_TEXT := Vector2(0.56, 0.5)  ## label centre, fraction of the button art
const HUB_FIGHT_TEXT_W := 0.6
## Card frame window (the hole in the frame PNG): WIN = (60, 150, 964, 1470) on 1024x1536, as fractions.
const HUB_CARD_WINDOW := Rect2(0.0586, 0.0977, 0.8828, 0.8594)
const HUB_CARD_WINDOW_RADIUS := 0.068  ## of the card width
const HUB_CARD_NAME := Rect2(0.06, 0.035, 0.55, 0.066)  ## top plate text box
const HUB_CARD_SQUAD := Rect2(0.42, 0.885, 0.36, 0.066)  ## bottom plate text box
const HUB_CARD_LOCK_Y := 0.47
const HUB_CARD_PLATE_TAP := 0.16  ## squad tap area: the bottom fraction of the card
## Hub card depth on hover / focus / tap (Boss 2026-11-12 option A): the whole card turns in perspective toward the
## pointer (client/card_tilt.gdshader), the backdrop slides against the tilt, the character with it, the frame stays.
const HUB_TILT_ANGLE := Vector2(0.17, 0.12)  ## radians at full tilt: yaw (x), pitch (y); about 10 and 7 degrees
const HUB_TILT_FOCAL := 1.7  ## perspective distance, in card widths (smaller = stronger perspective)
const HUB_TILT_SMOOTH := 9.0  ## how fast the tilt follows the pointer and eases back (per second)
const HUB_TILT_TAP_SECONDS := 0.7  ## touch: a tap tilts the card toward the touch point this long
const HUB_TILT_SWAY := Vector2(0.45, 0.25)  ## keyboard / gamepad focus without a pointer: slow sway (-1..1)
const HUB_TILT_SWAY_SPEED := Vector2(0.9, 0.7)
const HUB_BACK_PARALLAX := 0.05  ## backdrop shift AGAINST the tilt, fraction of the window size
const HUB_BACK_ZOOM := 1.12  ## the backdrop is drawn this much bigger than the window so the shift never shows an edge
const HUB_FIGURE_PARALLAX := 0.055  ## character shift WITH the tilt, fraction of the window size
const HUB_BACK_GLOW_SIZE := Vector2(1.1, 0.75)  ## soft class-tinted light behind the character, fraction of the window
const HUB_BACK_GLOW_AT := Vector2(0.5, 0.36)  ## its centre
const HUB_BACK_GLOW_ALPHA := 0.4
const HUB_SHEEN := 0.42  ## warm sheen band across the leather / parchment frame at full tilt
const HUB_SHEEN_EDGE := 0.6  ## rim highlight of the edge facing the pointer
const HUB_SHEEN_WIDTH := 0.17  ## band half-width, fraction of the card
const HUB_SHEEN_COLOR := Color(1.0, 0.86, 0.62)
const HUB_SHEEN_FADE_SECONDS := 0.2
## Squad tray windows, fractions of the tray art (measured on hub_squad_tray_v1).
const HUB_TRAY_SLOTS: Array[Rect2] = [Rect2(0.098, 0.215, 0.17, 0.69), Rect2(0.413, 0.215, 0.17, 0.69), Rect2(0.728, 0.215, 0.17, 0.69)]
const HUB_TRAY_NUM_Y := 0.075
const HUB_PANEL_SIZE := Vector2(1000.0, 520.0)  ## the "coming soon" panel
const HUB_PANEL_MARGIN := 48.0
const HUB_BUTTON := Vector2(240.0, 80.0)
const HUB_RADIUS := 28.0
const HUB_LINE := 4.0
const HUB_TAP_MIN_PHONE := 96.0  ## every tap target on a phone (Boss 2026-11-11)

# Character screen (spec §4)
const CHAR_PANEL_Y := 140.0
const CHAR_PANEL_ART := Vector2(1486.0, 971.0)
## Tab plates on the panel art: x from, x to, label y (art pixels).
const CHAR_TABS: Array[Vector3] = [Vector3(152.0, 502.0, 62.0), Vector3(584.0, 922.0, 62.0), Vector3(1006.0, 1343.0, 62.0)]
const CHAR_TAB_H := 100.0  ## art pixels: the tab plates' height (tap area)
const CHAR_UNDERLINE := Vector2(0.62, 102.0)  ## underline: fraction of the tab width, y in art px
## Content area inside the panel art (art px): left, top, right, bottom.
const CHAR_INNER := Rect2(80.0, 160.0, 1326.0, 740.0)
const CHAR_SLOT := 104.0
const CHAR_SLOT_GAP := 12.0
const CHAR_DETAIL_H := 0.47  ## of the right column height
const CHAR_STORE_COLUMNS := 10
const CHAR_STORE_COLUMNS_PHONE := 7
const CHAR_ACTION_H := 72.0
const CHAR_ICON := 130.0
const CHAR_STAT_STRIP_H := 64.0
const CHAR_BAR_H := 22.0
const CHAR_PIP := 5.0
const CHAR_SWITCH_H := 40.0
const CHAR_GAP := 16.0
const CHAR_PAD := 20.0
## Character screen, Equipment tab (reference units, see _mock_character_1080.png)
const CHAR_PANEL_W := 1840.0
const CHAR_PANEL_H := 930.0
const CHAR_CONTENT := Rect2(90.0, 175.0, 90.0, 80.0)  ## inner margins of the panel: left, top, right, bottom
const CHAR_DOLL_OFFSET := Vector2(10.0, -6.0)  ## slot grid origin from the inner top-left
const CHAR_RIGHT_GAP := 40.0  ## slot grid to the right column
const CHAR_DIVIDER := 2.0
const CHAR_DETAIL_BOX_H := 345.0
const CHAR_DETAIL_ICON := 150.0
const CHAR_STORE_CELL := 92.0
const CHAR_STORE_GAP := 12.0
const CHAR_FILTER_H := 44.0
const CHAR_FILTER_W := 120.0
const CHAR_SWITCH_W := 230.0
const CHAR_SWITCH_Y := 118.0
const CHAR_HINT_Y := 1060.0
const CHAR_WINDOW_RADIUS := 28.0
const CHAR_WINDOW_LINE := 5.0
const CHAR_PIP_SPACING := 2.1
const CHAR_TOAST_BOTTOM := 70.0  ## character screen: the status line sits this far above the screen foot
## Hub service panels (client/hub_service_panel.gd and its Blacksmith / Storage panels), reference units.
const SVC_PANEL := Vector2(1600.0, 900.0)  ## the leather panel over the dimmed hub (spec: 1500x880, a little more for 4 card tabs)
const SVC_LEATHER := 22.0  ## leather rim around the parchment
const SVC_PAD := 28.0
const SVC_HEAD := 72.0  ## header row: medallion, title, gold, Close
const SVC_ROW_H := 56.0  ## source tabs / picker rows (96 on phones)
const SVC_SPLIT := 0.52  ## left column (grid) share of the panel width
const SVC_DETAIL_H := 0.5
const SHOP_DETAIL_H := 0.62  ## Shop: details box share of the content height (materials under it)
const SVC_GOLD_W := 0.14  ## header money line width, share of the panel (Tailor: wider, it adds diamonds)
const TAILOR_SPLIT := 0.36  ## the character window's share of the Tailor width
const TAILOR_TILE := Vector2(170.0, 200.0)  ## a fashion piece tile (icon + name)
const TAILOR_CHIP := Vector2(250.0, 64.0)  ## a look choice (hair / colour / makeup)
const TAILOR_SWATCH := 36.0  ## colour disc on eye / skin chips  ## details box share of the content height (Blacksmith)
## Slot "slot:index" -> [column, row] on the 5 x 6 paper-doll (client/gear_panel.gd SLOT_PLACES) plus the off-hand
## between Weapon and Back (Boss 2026-11-11: Sword & Shield only).
const CHAR_SLOT_PLACES := {
	"earring:0": [0, 0], "earring:1": [1, 0], "necklace:0": [2, 0], "ring:0": [3, 0], "ring:1": [4, 0],
	"hat:0": [0, 1], "shirt:0": [0, 2], "pants:0": [0, 3], "shoes:0": [0, 4],
	"armband:0": [4, 1], "bracelet:0": [4, 2], "bracelet:1": [4, 3],
	"weapon:0": [1, 5], "offhand:0": [2, 5], "back:0": [3, 5],
}
## Storage filters: id -> slots (empty = everything).
const CHAR_FILTERS: Array[Dictionary] = [
	{"id": "all", "slots": []},
	{"id": "weapon", "slots": ["weapon", "offhand"]},
	{"id": "armor", "slots": ["hat", "shirt", "pants", "shoes", "armband", "back"]},
	{"id": "trinket", "slots": ["necklace", "earring", "bracelet", "ring"]},
]
const CHAR_STATS: Array[String] = ["HP", "ATK", "DEF", "CRIRATE"]
## The parchment part of hub_menu_plate.png (art px) used as the action-button plate; 9-slice margins l, t, r, b.
const HUB_PLATE_REGION := Rect2(182.0, 29.0, 518.0, 149.0)
const HUB_PLATE_MARGINS: Array[float] = [24.0, 24.0, 56.0, 24.0]
const HUB_TAB_LIT := Color(1.0, 0.86, 0.6, 0.28)  ## over the active tab plate
const HUB_TAB_DIM := Color(0.16, 0.08, 0.03, 0.32)  ## over an idle tab plate
const HUB_FIT_MARK := Color(1.0, 0.8, 0.36, 0.95)  ## storage piece that fits the selected slot
const HUB_STAT_KEY := Color("CDB48C")
const HUB_DETAIL_BACK := Color(0.98, 0.93, 0.82, 0.55)
const HUB_DETAIL_EDGE := Color("8A5A34")
const HUB_DIVIDER := Color("B08A5C")
const HUB_WINDOW_EDGE := Color("6B3F22")

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
## "hub" framing (leather card window, full body): model top / feet as fractions of the portrait height.
const PORTRAIT_HUB_TOP := 0.10
const PORTRAIT_HUB_BOTTOM := 0.90
## "stage" framing (character screen window): room under the feet for the stat strip.
const PORTRAIT_STAGE_TOP := 0.07
const PORTRAIT_STAGE_BOTTOM := 0.84
## "bust" (squad tray heads): head and shoulders of the chibi body (the head alone is the top half, the shoulders
## are at about 0.42 of the height). Same rule as the card framings: the top of the hair at BUST_TOP and the feet
## at BUST_BOTTOM of the view (>1 = below it), so the view shows the top 1/(BOTTOM-TOP) of the body (~0.69: down
## to the upper chest).
const PORTRAIT_BUST_TOP := 0.03
const PORTRAIT_BUST_BOTTOM := 1.48
## The tray slot's parchment window inside its frame art (fractions of the slot: left, top, right, bottom):
## the bust is drawn only inside it.
const HUB_TRAY_WINDOW_INSET := Vector4(0.085, 0.13, 0.085, 0.075)
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
## Idle variants on the live portraits (hub cards, character screen; Boss 2026-11-12): the class idle plays for
## a random GAP_MIN..GAP_MAX seconds, then one variant (data/classes/<id>.json "idle_variants") for its clip length
## clamped to SHOW_MIN..SHOW_MAX, cross-fading BLEND seconds each way. Off under reduced motion.
const PORTRAIT_IDLE_GAP_MIN := 6.0
const PORTRAIT_IDLE_GAP_MAX := 10.0
const PORTRAIT_IDLE_SHOW_MIN := 3.0
const PORTRAIT_IDLE_SHOW_MAX := 7.0
const PORTRAIT_IDLE_BLEND := 0.6

# ------------------------------------------------------------------ strings (§11): Thai first, English second
## The game has no localisation system yet; this table is the one place the screen's words live.
static var language := "en"  ## Boss 2026-11-11: hub and card text in English
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
	"makeup_none": ["ไม่แต่งตา", "Natural"],  ## the Studio's natural / no-makeup set (PO default 2026-11-12)
	"makeup_sharp_wing": ["Sharp Wing", "Sharp Wing"],
	"hair_prefix": ["ผม ", "Hair "],
	"remove_from_squad": ["เอาออกจากทัพ", "Remove from squad"],
	"add_to_squad": ["ลงทัพ", "Add to squad"],
	# hub (docs/ui/hub_layout_spec.md)
	"hub_title": ["การ์ดของฉัน", "MY CARDS"],
	"hub_hint": ["แตะการ์ดเพื่อเปิดตัวละคร · แตะป้ายล่างเพื่อลงทัพ", "Tap a card to open its character  ·  Tap its bottom plate to add or remove it from the squad"],
	"squad_n": ["ทัพ %d", "SQUAD %d"],
	"squad_add": ["+ ลงทัพ", "+ SQUAD"],
	"locked": ["ล็อก", "LOCKED"],
	"locked_toast": ["ทำเควสต์ให้เสร็จเพื่อปลดล็อก %s", "Finish the quests to unlock %s"],
	"tray_add": ["เพิ่มการ์ด", "Add a card"],
	"fight_need": ["เลือกอย่างน้อย 1 ใบ", "Pick at least 1 card"],
	"svc_blacksmith": ["ช่างตีเหล็ก", "Blacksmith"],
	"svc_shop": ["ร้านค้า", "Shop"],
	"svc_tailor": ["ช่างตัดเสื้อ", "Tailor"],
	"svc_storage": ["คลัง", "Storage"],
	"svc_quests": ["เควสต์", "Quests"],
	"svc_relics": ["วัตถุโบราณ", "Relics"],
	"svc_locked_line": ["ทำเควสต์ 3 เพื่อปลดล็อก", "Quest 3 to unlock"],
	"soon_body": ["ส่วนนี้ยังไม่เปิด", "This service is not open yet."],
	"close": ["ปิด", "Close"],
	"account": ["บัญชี", "Account"],
	# card character screen
	"tab_equipment": ["อุปกรณ์", "Equipment"],
	"card_of": ["การ์ด %d จาก %d", "Card %d of %d"],
	"prev_card": ["< %s", "< %s"],
	"next_card": ["%s >", "%s >"],
	"slot_earring": ["ต่างหู", "Earring"], "slot_necklace": ["สร้อยคอ", "Necklace"], "slot_ring": ["แหวน", "Ring"],
	"slot_hat": ["หมวก", "Hat"], "slot_shirt": ["เสื้อ", "Shirt"], "slot_pants": ["กางเกง", "Pants"], "slot_shoes": ["รองเท้า", "Shoes"],
	"slot_armband": ["ปลอกแขน", "Armband"], "slot_bracelet": ["กำไล", "Bracelet"], "slot_weapon": ["อาวุธ", "Weapon"], "slot_back": ["หลัง", "Back"],
	"storage_title": ["คลัง (ใช้ร่วมทุกการ์ด)", "Storage  (shared by all cards)"],
	"filter_all": ["ทั้งหมด", "All"], "filter_weapon": ["อาวุธ", "Weapons"], "filter_armor": ["ชุดเกราะ", "Armor"], "filter_trinket": ["เครื่องประดับ", "Trinkets"],
	"equip": ["สวม", "Equip"],
	"unequip": ["ถอด", "Unequip"],
	"refine": ["ตีบวก", "Refine"],
	"repair": ["ซ่อม", "Repair"],
	"durability": ["ความทนทาน", "Durability"],
	"pick_piece": ["แตะชิ้นอุปกรณ์เพื่อดูรายละเอียด", "Tap a piece to see its details"],
	"empty_slot_line": ["ยังไม่ได้สวม: แตะของในคลังที่ใส่ช่องนี้ได้", "Nothing worn. Tap a piece in Storage that fits this slot."],
	"char_hint": ["แตะ = รายละเอียด · แตะสองครั้ง = สวม / ถอด · Esc / B = กลับ", "Tap a piece = details  ·  Double-tap = wear / take off  ·  Esc / B = back"],
	"outfit_body": ["ผม ตา ชุด และสีผิวของการ์ดนี้แต่งได้ที่ตัวแต่งหน้าตา", "Hair, eyes, outfit and skin of this card are set in the look editor."],
	"open_editor": ["เปิดตัวแต่งหน้าตา", "Open the look editor"],
	"skills_soon": ["สกิลของคลาส: เร็วๆ นี้", "Class skills: coming soon"],
	"worn_ok": ["สวมแล้ว", "Equipped"],
	"took_off_ok": ["ถอดไปไว้ในคลังแล้ว", "Moved to Storage"],
	"err_wrong_weapon_family": ["คลาสนี้ใช้อาวุธนี้ไม่ได้", "This class can't use that weapon"],
	"err_weapon_required": ["ต้องถืออาวุธไว้เสมอ", "A weapon must stay equipped"],
	"err_reskill_required": ["ต้องรีเซ็ตสกิลก่อนเปลี่ยนอาวุธ", "Reset the skills before changing weapon family"],
	"err_bag_full": ["คลังเต็ม", "Storage is full"],
	"err_invalid_slot": ["ใส่ช่องนี้ไม่ได้", "That doesn't fit there"],
	"err_not_available_here": ["ทำตอนนี้ไม่ได้", "Not available here"],
	"err_unknown": ["ทำไม่สำเร็จ", "That didn't work"],
	"waiting": ["รอเซิร์ฟเวอร์…", "Waiting for the server..."],
	"slot_offhand": ["มือรอง", "Off-hand"],
	"slot_locked": ["ล็อก", "Locked"],
	"slot_closed_line": ["ช่องนี้ใช้ได้เฉพาะ %s", "Only %s can use this slot."],
	"stat_HP": ["HP", "HP"], "stat_ATK": ["ATK", "ATK"], "stat_DEF": ["DEF", "DEF"], "stat_CRIRATE": ["คริ", "CRIT"],
	"refine_share": ["(+%s จากตีบวก)", "(+%s refine)"],
	"tier_normal": ["ธรรมดา", "Normal"], "tier_rare": ["หายาก", "Rare"], "tier_epic": ["มหากาพย์", "Epic"], "tier_legendary": ["ตำนาน", "Legendary"],
	"durability_of": ["%d / %d", "%d / %d"],
	"cost_gold": ["%d ทอง", "%d gold"],
	"cost_free": ["ฟรี", "free"],
	"refine_max": ["ตีบวกสูงสุดแล้ว", "Max refine"],
	"like_new": ["ไม่ต้องซ่อม", "Like new"],
	"vs_worn": ["เทียบกับที่สวม:", "vs worn:"],
	"vs_empty": ["ช่องนี้ยังว่าง", "slot is empty"],
	"fits_count": ["ในคลังมี %d ชิ้นที่ใส่ช่องนี้ได้ (มีกรอบทอง)", "%d piece(s) in Storage fit this slot (gold frame)."],
	"fits_none": ["ในคลังยังไม่มีชิ้นที่ใส่ช่องนี้ได้", "Nothing in Storage fits this slot yet."],
	"storage_empty": ["คลังว่าง มอนสเตอร์ดรอปอุปกรณ์", "Storage is empty. Monsters drop gear."],
	"refined_ok": ["ตีบวกสำเร็จ: +%d", "Refined to +%d"],
	"refine_failed": ["ตีบวกไม่สำเร็จ: เหลือ +%d", "Refine failed: now +%d"],
	"repaired_ok": ["ซ่อมแล้ว", "Repaired"],
	"char_hint_touch": ["แตะ = รายละเอียด · แตะสองครั้ง = สวม / ถอด · Q / E = เปลี่ยนการ์ด · Esc / B = กลับ", "Tap a piece = details  ·  Double-tap = wear / take off  ·  Q / E = switch card  ·  Esc / B = back"],
	"err_slot_closed": ["การ์ดนี้ใช้ช่องนี้ไม่ได้", "This card can't use that slot"],
	"err_no_free_copy": ["ทุกชิ้นถูกการ์ดอื่นใส่อยู่", "Every copy is worn by another card"],
	"err_cannot_afford": ["เงินหรือวัสดุไม่พอ", "Not enough gold or materials"],
	"err_nothing_to_repair": ["ไม่ต้องซ่อม", "Nothing to repair"],
	"err_no_workbench": ["ยังไม่มีโต๊ะช่าง", "The workbench is not built"],
	"err_max_level": ["สูงสุดแล้ว", "Already at the maximum"],
	"err_not_configured": ["ยังไม่เปิดใช้", "Not available yet"],
	"err_item_destroyed": ["ชิ้นนี้พังแล้ว", "That piece is destroyed"],
	"err_nothing_worn": ["ไม่ได้สวมอะไรอยู่", "Nothing is worn there"],
	"err_conflict": ["ข้อมูลเปลี่ยน ลองใหม่", "Something changed, try again"],
	"err_invalid_item": ["ทำกับชิ้นนี้ไม่ได้", "That can't be done to this piece"],
	"err_item_not_owned": ["ไม่พบชิ้นนี้", "That piece is gone"],
	"err_no_session": ["ยังไม่เชื่อมต่อ", "Not connected"],
	"err_invalid_card": ["การ์ดไม่ถูกต้อง", "Unknown card"],
	# hub service panels (Blacksmith, Storage)
	"gold": ["ทอง", "Gold"],
	"upgrade": ["อัปเกรด", "Upgrade"],
	"upgrade_tier": ["เลื่อนขั้น", "Upgrade tier"],
	"repair_all": ["ซ่อมทั้งหมด", "Repair all"],
	"repair_all_hint": ["ซ่อมทุกชิ้นที่การ์ดนี้สวม", "Repairs everything this card wears"],
	"smith_pick": ["เลือกชิ้นอุปกรณ์", "Pick a piece"],
	"smith_none": ["คลังยังไม่มีอุปกรณ์", "No gear in Storage yet"],
	"smith_refine_line": ["ตีบวก -> +%d: %s · โอกาส %d%%", "Refine to +%d: %s  ·  %d%% chance"],
	"smith_refine_fail": ["(พลาด: เหลือ +%d)", "(fail: drops to +%d)"],
	"smith_upgrade_line": ["อัปเกรด: %s · %s · ใช้ไป %d / %d", "Upgrade: %s  ·  %s  ·  %d / %d used"],
	"smith_upgrade_add": ["เพิ่มค่าสถานะรองใหม่ 1 แถว", "adds a new substat row"],
	"smith_upgrade_boost": ["เพิ่มค่าสถานะรองแบบสุ่ม 1 แถว", "boosts one random substat"],
	"smith_repair_line": ["ซ่อม: %s · คืน %d แต้ม", "Repair: %s  ·  restores %d points"],
	"upgraded_add": ["อัปเกรดแล้ว: ได้ %s ใหม่", "Upgraded: new %s row"],
	"upgraded_boost": ["อัปเกรดแล้ว: %s +%s", "Upgraded: %s +%s"],
	"repaired_for": ["ซ่อมแล้ว (%s)", "Repaired (%s)"],
	"repaired_all": ["ซ่อม %d ชิ้น ใช้ %d ทอง · ข้าม %d", "Repaired %d piece(s) for %d gold  ·  skipped %d"],
	"store_tab_stash": ["คลัง", "Storage"],
	"store_tab_vault": ["ห้องนิรภัย", "Vault"],
	"wear_on": ["ใส่ให้การ์ด...", "Wear on card..."],
	"wear_on_title": ["ใส่ให้การ์ดใบไหน?", "Wear it on which card?"],
	"worn_on": ["%s สวมแล้ว", "Worn by %s"],
	"to_vault": ["ไปห้องนิรภัย", "To vault"],
	"to_stash": ["ไปคลัง", "To Storage"],
	"moved_to_vault": ["ย้ายไปห้องนิรภัยแล้ว", "Moved to the vault"],
	"moved_to_stash": ["ย้ายไปคลังแล้ว", "Moved to Storage"],
	"discard": ["ทิ้ง", "Discard"],
	"discard_confirm": ["ทิ้ง %s? ทิ้งแล้วเอาคืนไม่ได้", "Discard %s? It can't be undone."],
	"discarded": ["ทิ้งแล้ว", "Discarded"],
	"err_storage_full": ["ห้องนิรภัยเต็ม", "The vault is full"],
	"err_backpack_full": ["คลังเต็ม", "Storage is full"],
	"err_item_not_in_container": ["ชิ้นนี้ไม่ได้อยู่ในคลัง", "That piece isn't in Storage"],
	"err_invalid_container": ["ทำที่นี่ไม่ได้", "Not possible here"],
	# Tailor
	"diamonds": ["เพชร", "Diamonds"],
	"tailor_hair": ["ผม", "Hair"],
	"tailor_eyes": ["สีตา", "Eyes"],
	"tailor_part_iris_style": ["แบบม่านตา", "Iris style"],
	"tailor_part_eye_color": ["สีตา", "Eye colour"],
	"iris_style_0": ["Classic", "Classic"], "iris_style_1": ["Starry Violet", "Starry Violet"], "iris_style_3": ["03 · Solar Flame", "Solar Flame"],
	"iris_style_6": ["06 · Lavender Orbit", "Lavender Orbit"], "iris_style_7": ["07 · Sunburst", "Sunburst"], "iris_style_9": ["09 · Pastel Halo", "Pastel Halo"],
	"iris_style_10": ["10 · Astral Sigil", "Astral Sigil"],
	"tailor_skin": ["สีผิว", "Skin"],
	"tailor_makeup": ["แต่งตา", "Makeup"],
	"tailor_base_outfit": ["ชุดพื้นฐาน", "Base outfit"],
	"tailor_fashion": ["ชุดแฟชั่น", "Fashion"],
	"tailor_back": ["ของบนหลัง", "Back item"],
	"tailor_look_line": ["ตอนนี้: %s · แตะเพื่อเปลี่ยน (ฟรี)", "Now: %s  ·  tap a choice to change it (free)"],
	"tailor_pick_piece": ["แตะชิ้นแฟชั่นเพื่อซื้อหรือใส่", "Tap a piece to buy or wear it"],
	"tailor_owned_mark": ["มี %d", "Owned %d"],
	"tailor_copies": ["มี %d ชิ้น · ว่าง %d", "Owned %d  ·  free %d"],
	"tailor_worn_by": ["ใส่อยู่: %s", "Worn by: %s"],
	"tailor_buy": ["ซื้อ (%d เพชร)", "Buy (%d diamonds)"],
	"tailor_wear": ["ใส่ให้การ์ดนี้", "Wear on this card"],
	"tailor_take_off": ["ถอดออก", "Take off"],
	"tailor_changed": ["เปลี่ยนเป็น %s แล้ว", "Changed to %s"],
	"tailor_bought": ["ซื้อ %s แล้ว (มี %d)", "Bought %s (you own %d)"],
	"tailor_wearing": ["%s ใส่ %s แล้ว", "%s now wears %s"],
	"tailor_took_off": ["ถอด %s แล้ว", "Took off %s"],
	"eye_color_turquoise": ["ฟ้า", "Turquoise"], "eye_color_green": ["เขียว", "Green"], "eye_color_violet": ["ม่วง", "Violet"], "eye_color_brown": ["น้ำตาล", "Brown"],
	"skin_fair": ["ขาว", "Fair"], "skin_natural": ["ธรรมชาติ", "Natural"], "skin_tan": ["แทน", "Tan"], "skin_deep": ["เข้ม", "Deep"],
	"err_cosmetic_not_owned": ["ยังไม่มีชิ้นนี้ ซื้อก่อน", "You don't own this piece yet"],
	"err_not_enough_diamonds": ["เพชรไม่พอ", "Not enough diamonds"],
	"err_already_owned": ["มีครบทุกการ์ดแล้ว", "You already own one for every card"],
	"err_invalid_cosmetic": ["ใช้ชิ้นนี้ไม่ได้", "That piece isn't available"],
	# Shop
	"shop_tab_buy": ["ซื้อ", "Buy"],
	"shop_tab_sell": ["ขาย", "Sell"],
	"shop_empty_stock": ["ร้านยังไม่มีของขายตอนนี้", "The merchant has nothing for sale right now."],
	"shop_empty_stock_line": ["กลับมาใหม่ภายหลัง", "Come back later."],
	"shop_buy_for": ["ซื้อ (%d ทอง)", "Buy (%d gold)"],
	"shop_sell_for": ["ขาย (%d ทอง)", "Sell (%d gold)"],
	"shop_sell_marked": ["ขายที่เลือก %d ชิ้น (%d ทอง)", "Sell %d marked (%d gold)"],
	"shop_mark": ["เลือก", "Mark"],
	"shop_unmark": ["ไม่เลือก", "Unmark"],
	"shop_price_line": ["ราคาขาย: %d ทอง", "Sells for %d gold"],
	"shop_marked_line": ["เลือกไว้ %d ชิ้น รวม %d ทอง", "%d marked  ·  %d gold"],
	"shop_materials": ["วัสดุ", "Materials"],
	"shop_sell_material": ["ขาย %d %s (%d ทอง)", "Sell %d %s (%d gold)"],
	"shop_sold": ["ขายแล้ว ได้ %d ทอง", "Sold for %d gold"],
	"shop_bought": ["ซื้อ %s แล้ว", "Bought %s"],
	"shop_nothing_to_sell": ["คลังว่าง ไม่มีของจะขาย", "Storage is empty: nothing to sell"],
	"shop_not_sellable": ["ขายชิ้นนี้ไม่ได้", "This piece can't be sold"],
	"err_not_sellable": ["ขายชิ้นนี้ไม่ได้", "That can't be sold"],
	"err_price_changed": ["ราคาเปลี่ยน ลองใหม่", "The price changed, try again"],
	"err_gold_limit": ["ทองเต็มแล้ว", "You can't hold more gold"],
	"err_stash_full": ["คลังเต็ม", "Storage is full"],
	"err_invalid_product": ["ไม่มีสินค้านี้", "That isn't for sale"],
	"err_invalid_count": ["จำนวนไม่ถูกต้อง", "Wrong amount"],
	"err_invalid_material": ["ไม่มีวัสดุนี้", "Unknown material"],
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
static func style_text(control: Control, size: int, color: Color, s: float, outline: int = 0, face: String = "display", outline_color: Color = INK) -> void:
	var px := maxi(int(round(size * s)), FONT_MIN)
	control.add_theme_font_size_override("font_size", px)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_outline_color", outline_color)
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
static func label(text: String, size: int, color: Color, s: float, outline: int = 0, face: String = "display", outline_color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	style_text(l, size, color, s, outline, face, outline_color)
	return l


# ------------------------------------------------------------------ hub helpers
## Hub text: dark ink on parchment (outline 0) or cream with a dark outline over the scene.
static func hub_text(control: Control, size: int, color: Color, s: float, outline: int = 0, face: String = "display") -> void:
	style_text(control, size, color, s, outline, face, HUB_OUTLINE)


static func hub_label(text: String, size: int, color: Color, s: float, outline: int = 0, face: String = "display") -> Label:
	var l := label(text, size, color, s, outline, face, HUB_OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # the label may be set narrower than its text (hub_fit shrinks it first)
	return l


## Styles `control` at the largest size <= `size` whose `text` fits `width` screen px (never under FONT_MIN).
static func hub_fit(control: Control, text: String, size: int, width: float, color: Color, s: float, outline: int = 0, face: String = "display") -> void:
	var font: Font = display_font() if face == "display" else (medium_font() if face == "medium" else body_font())
	var px := maxi(int(round(size * s)), FONT_MIN)
	while px > FONT_MIN and font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		px -= 1
	# Still too wide at FONT_MIN in the serif display face: use the narrower medium face instead of an ellipsis.
	if face == "display" and font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		var narrow := medium_font()
		if narrow != null and narrow.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x < font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x:
			face = "medium"
			px = maxi(int(round(size * s)), FONT_MIN)
			while px > FONT_MIN and narrow.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
				px -= 1
	style_text(control, 1, color, 1.0, 0, face, HUB_OUTLINE)
	control.add_theme_font_size_override("font_size", px)
	control.add_theme_constant_override("outline_size", int(round(outline * s)) if outline > 0 else 0)


## Side inset in screen px: the reference edge, plus the notch inset on phones, and at least the device's safe area.
static func hub_safe_x(screen: Vector2, s: float, device_px: float = 0.0) -> float:
	var x := HUB_SAFE.x * s
	if is_phone(screen):
		x += HUB_PHONE_SAFE_X * s
	return maxf(x, device_px)


## A tap size (unscaled px): at least HUB_TAP_MIN_PHONE on a phone.
static func tap(size: float, phone: bool) -> float:
	return maxf(size, HUB_TAP_MIN_PHONE) if phone else size


static func hub_paper(s: float) -> StyleBox:
	return flat(HUB_PAPER, HUB_PAPER_EDGE, HUB_LINE * 0.5, HUB_RADIUS * 0.5, s)


static func hub_leather(s: float) -> StyleBox:
	return flat(HUB_LEATHER, HUB_LEATHER_EDGE, HUB_LINE, HUB_RADIUS, s, true)


static func hub_shade(color: Color) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


static func hub_pill(s: float) -> StyleBox:
	return flat(HUB_PILL, HUB_GOLD_EDGE, 2.0, HUB_GOLD_SIZE.y * 0.5, s)


static func hub_strip(s: float) -> StyleBox:
	return flat(HUB_STAT_STRIP, HUB_STAT_STRIP, 0.0, 12.0, s)


static func hub_bar(fill: Color, s: float) -> StyleBox:
	return flat(fill, HUB_LEATHER_EDGE, 1.0, CHAR_BAR_H * 0.5, s)


static func hub_badge(s: float) -> StyleBox:
	return flat(HUB_BADGE, HUB_BADGE_RING, 3.0, HUB_BADGE_R + 3.0, s)


static func hub_line(color: Color) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


## A vertical window gradient: the class accent on top, dark leather at the bottom.
## Soft class-tinted light behind the hub card character (the backdrop layer that slides against the tilt).
static func hub_window_glow(class_id: String) -> GradientTexture2D:
	var light: Color = palette(class_id)["light"]
	return radial("hub_glow_" + class_id, Color(light, HUB_BACK_GLOW_ALPHA), Color(light, 0.0), 0.0)


static func window_gradient(class_id: String, locked: bool = false) -> GradientTexture2D:
	var gradient := Gradient.new()
	var top: Color = HUB_WINDOW_LOCKED if locked else palette(class_id)["shadow"]
	gradient.colors = PackedColorArray([top, HUB_WINDOW_BOTTOM])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 128
	return texture


## Parchment plate buttons (action buttons, the dialog); ghost = text only (the card switcher, filters).
static func hub_button(button: Button, s: float, ghost: bool = false) -> void:
	var states := {"normal": HUB_PAPER, "hover": FRAME_LIGHT, "pressed": PAPER_SHADOW, "disabled": DISABLED}
	for state in states:
		var box: StyleBox = StyleBoxEmpty.new() if ghost else flat(states[state], HUB_LEATHER_EDGE, HUB_LINE * 0.75, 14.0, s, state == "normal" or state == "hover")
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", hub_focus(s, 16.0))


## Buttons that draw their own art (texture rects inside): no box, but keep the focus ring.
static func bare_button(button: BaseButton, s: float, radius: float = 16.0) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", hub_focus(s, radius))


## Focus ring of the hub (spec §6): 3 px cream outline.
static func hub_focus(s: float, radius: float) -> StyleBoxFlat:
	var focus := ring(HUB_CREAM, 3.0, radius, s)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		focus.set_expand_margin(side, 4.0 * s)
	return focus


static var _grey: ShaderMaterial


## The grey look of locked things (menu entry, card): a desaturating canvas shader.
static func grey_material() -> ShaderMaterial:
	if _grey == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(c.rgb, vec3(g), 0.85), c.a);\n}\n"
		_grey = ShaderMaterial.new()
		_grey.shader = shader
	return _grey


## The leather/parchment plate of hub_menu_plate.png as a button skin (action buttons of the hub panels).
static func hub_plate_button(button: Button, s: float) -> void:
	var image := tex(HUB_MENU_PLATE)
	if image == null:
		hub_button(button, s)
		return
	var tints := {"normal": HUB_WHITE, "hover": HUB_HOVER, "pressed": HUB_PRESSED, "disabled": HUB_LOCKED}
	for state in tints:
		var box := StyleBoxTexture.new()
		box.texture = image
		box.region_rect = HUB_PLATE_REGION
		box.texture_margin_left = HUB_PLATE_MARGINS[0]
		box.texture_margin_top = HUB_PLATE_MARGINS[1]
		box.texture_margin_right = HUB_PLATE_MARGINS[2]
		box.texture_margin_bottom = HUB_PLATE_MARGINS[3]
		box.modulate_color = tints[state]
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", hub_focus(s, 14.0))


## A plain coloured rounded box (tab tints, the detail box) built from tokens.
static func hub_box(fill: Color, edge: Color, line: float, radius: float, s: float) -> StyleBoxFlat:
	return flat(fill, edge, line, radius, s)


## The words of an error reason from logic/commands.gd ("err_<reason>"), or the generic line.
static func error_text(reason: String) -> String:
	return t("err_" + reason) if STRINGS.has("err_" + reason) else t("err_unknown")


static func slot_name(slot_id: String) -> String:
	var key := "slot_" + slot_id
	return t(key) if STRINGS.has(key) else slot_id.capitalize()



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


## A soft glow around a rect (the box itself is clear; only its blurred shadow shows): squad cards, FIGHT, hover.
static func hub_glow(color: Color, spread: float, radius: float, s: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = HUB_CLEAR
	box.shadow_color = color
	box.shadow_size = int(round(spread * s))
	box.set_corner_radius_all(int(round(radius * s)))
	return box


## The display name of the stage FIGHT starts (data file), "" when missing.
static func stage_name() -> String:
	if not FileAccess.file_exists(HUB_STAGE_FILE):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(HUB_STAGE_FILE))
	return str(parsed.get("name", "")) if parsed is Dictionary else ""


## A full-size art picture (scaled to its rect, never takes clicks); empty when the file is missing.
static func art_rect(art_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(art_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Height / width of an art file (fallback when missing).
static func art_aspect(art_name: String, fallback: float) -> float:
	var image := tex(art_name)
	return float(image.get_height()) / float(image.get_width()) if image != null else fallback


# ------------------------------------------------------------------ hub look outside the hub (Boss 2026-11-12)
## End-of-run summary (client/journey_screen.gd _build_wave_summary), reference units at 1080p.
const SUMMARY_PANEL_W := 1100.0
const SUMMARY_PAD := 44.0
const SUMMARY_GAP := 18.0
const SUMMARY_CELL := 84.0  ## one looted item (hub_item_cell.gd)
const SUMMARY_CELL_GAP := 10.0
const SUMMARY_COLUMNS := 8
const SUMMARY_MAX_ITEMS := 16  ## more than this: "+N more"
const SUMMARY_ICON := 40.0  ## gold coin / material icon
const SUMMARY_BUTTON := Vector2(420.0, 104.0)
const SUMMARY_DIVIDER_H := 3.0
const FONT_SUMMARY_TITLE := 96
const FONT_SUMMARY_STAGE := 34
const FONT_SUMMARY_LINE := 26
const FONT_SUMMARY_BUTTON := 34
## Battle HUD squad cards (client/squad_panel.gd), in the stage's logical pixels (1280x720 base).
const SQUAD_HUD_CARD := Vector2(280.0, 74.0)
const SQUAD_HUD_MARGIN := 10.0
const SQUAD_HUD_GAP := 10.0
const SQUAD_HUD_EMBLEM := 62.0
const SQUAD_HUD_LEATHER := 5.0  ## leather rim around the name parchment
const SQUAD_HUD_BAR_H := 18.0
const SQUAD_HUD_CALLOUT_H := 30.0
const SQUAD_HUD_RADIUS := 12.0
const SQUAD_HUD_SELECT := 4.0  ## the picked card's cream ring
const FONT_SQUAD_HUD_NAME := 17
const FONT_SQUAD_HUD_HP := 14
const FONT_SQUAD_HUD_CALLOUT := 22
const SQUAD_HUD_DEAD := Color(0.55, 0.52, 0.5, 0.75)  ## a fallen card: dimmed (plus the grey shader and "DOWN")
## The class emblem medallion on each card frame (card_frame_<class>.png, 640x960): its region in art px.
const CARD_FRAME_EMBLEM := Rect2(496.0, 14.0, 118.0, 118.0)
## Battle HUD trip panel and banners (client/hud.gd, auto-battle look).
const HUD_TRIP_PAD := Vector2(14.0, 6.0)
const HUD_TRIP_H := 38.0
const HUD_TRIP_LEATHER := 4.0
const FONT_HUD_TRIP := 17
const FONT_HUD_BANNER := 40
const FONT_HUD_BOSS := 18
const HUD_BANNER_LEATHER := 7.0
const HUD_BOSS_PLATE_PAD := Vector2(12.0, 6.0)
const HUD_HP := Color("B3352A")  ## HP fill on leather (red, with the number on top)
const HUD_HP_BACK := Color("2A140C")
## Online status pill (client/online/online_account.gd), reference units at 1080p.
const ONLINE_PILL_H := 44.0
const ONLINE_PILL_PAD := 18.0
const ONLINE_DOT := 14.0
const FONT_ONLINE := 20
const ONLINE_OFF := Color("C8372D")  ## dot colours (the word says it too)
const ONLINE_WAIT := Color("E0A83A")
const ONLINE_ON := Color("5FB65A")
## Long names in tiles (client/hub_look.gd fit_lines): shrink to FONT_MIN, then wrap to this many lines, then "…".
const FIT_MAX_LINES := 2
const FIT_LINE_HEIGHT := 1.22  ## line height / font size

const STRINGS_HUB_LOOK := {
	"summary_won": ["ชนะ", "VICTORY"],
	"summary_lost": ["พ่ายแพ้", "DEFEAT"],
	"summary_retreated": ["ถอนทัพ", "RETREATED"],
	"summary_abandoned": ["ออกจากด่าน", "LEFT"],
	"summary_waves": ["ผ่านเวฟ %d / %d", "Waves cleared  %d / %d"],
	"summary_loot": ["ของที่ได้รอบนี้", "Loot this run"],
	"summary_loot_none": ["รอบนี้ไม่ได้ของ", "Nothing was picked up this run."],
	"summary_gold": ["+%d ทอง", "+%d gold"],
	"summary_material": ["%d %s", "%d %s"],
	"summary_more": ["+%d ชิ้น", "+%d more"],
	"summary_tiers": ["%d %s", "%d %s"],
	"summary_safe": ["ของที่เก็บได้อยู่ในคลังแล้ว", "Everything picked up is safe in Storage."],
	"summary_left_lost": ["ของในกระเป๋าหายไป", "The bag's loot was left behind."],
	"summary_back": ["กลับหน้าการ์ด", "Back to Cards"],
	"summary_saving": ["กำลังบันทึกผล…", "Saving the result..."],
	"online_offline": ["ออฟไลน์", "Offline"],
	"online_connecting": ["กำลังเชื่อมต่อ…", "Connecting..."],
	"online_online": ["ออนไลน์", "Online"],
	"squad_down": ["ล้ม", "DOWN"],
}
