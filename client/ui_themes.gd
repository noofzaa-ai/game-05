extends RefCounted
## Theme proposals: each is only a set of token values for ink_ui.gd (no structure, no code).
## The live look is D (Night Brass), which is now ink_ui.gd's own values (the director chose it on
## 2026-10-12). The older proposals are kept for comparison: each is drawn over "ink", the look the
## game had before D, so they still look as they did when proposed.
## Mockups: godot --path . --script res://tools/shots/ui_theme_shots.gd -- <out_dir> <theme>
## ("current" = the live look; "brass" = the live look plus a desktop serif standing in for the
## display font that is not chosen yet).
## EXTENDING: a new proposal is one more entry in THEMES; a token name that ink_ui.gd does not have
## is an error (tests/test_ui_tokens.gd).

const InkUi := preload("res://client/ink_ui.gd")

const NAMES := ["ink", "sumi", "journal", "pop", "brass"]


## Sets every token to the theme's values (after putting the built-in ones back). False if unknown.
static func apply(theme_name: String) -> bool:
	InkUi.reset_tokens()
	if theme_name == "" or theme_name == "current":
		return true
	if not theme_name in NAMES:
		return false
	var ok := true
	if theme_name != "brass":  # the older proposals were made over the ink look
		ok = InkUi.apply_tokens(_ink())
	ok = InkUi.apply_tokens(values(theme_name)) and ok
	if not ok:
		push_error("ui_themes: theme '%s' names a token that ink_ui.gd does not have" % theme_name)
	return ok


static func values(theme_name: String) -> Dictionary:
	match theme_name:
		"ink":
			return {}
		"sumi":
			return _sumi()
		"journal":
			return _journal()
		"pop":
			return _pop()
		"brass":
			return _brass_preview()
	return {}


## The look before D: ink-and-paper, brushed corners, a red brush under titles, no ornament.
static func _ink() -> Dictionary:
	return {
		"BAD": Color(1, 0.48, 0.38), "BAG_LOST": Color(1, 0.3, 0.3), "BORDER": Color(0.36, 0.31, 0.26),
		"CANT_AFFORD": Color(1, 0.4, 0.35), "COMBO_HOT": Color(1, 0.55, 0.15), "COMBO_LABEL": Color(1, 0.85, 0.4),
		"COMBO_TIMER": Color(1, 0.6, 0.2), "CORNER_DETAIL": 8, "CORNER_SKEW": 3, "DAMAGE_BIG": Color(1, 0.82, 0.2),
		"DAMAGE_CRIT": Color(1, 0.45, 0.15), "DISABLED_BG": Color(0.1, 0.095, 0.09),
		"DISABLED_BORDER": Color(0.22, 0.2, 0.18), "DOLL_SHADE": Color(0.24, 0.215, 0.19),
		"FIELD_BG": Color(0.06, 0.055, 0.05), "FRAME_STYLE": "plain", "GOLD": Color(0.96, 0.79, 0.36),
		"GOOD": Color(0.55, 0.85, 0.55), "GOOD_TEXT": Color(0.6, 0.9, 0.6), "HEADING_ACCENT": Color(1, 0.85, 0.5),
		"HELP_PLATE": Color(0, 0, 0, 0.45), "HELP_TEXT": Color(0.92, 0.92, 0.92), "HOVER_BG": Color(0.22, 0.19, 0.16),
		"HP": Color(0.86, 0.16, 0.22), "HP_TRAIL": Color(1, 0.85, 0.85), "HUD_OUTLINE": Color(0, 0, 0),
		"HUD_PANEL": Color(0.06, 0.06, 0.09, 0.82), "HUD_TEXT": Color(1, 1, 1), "ICON_ACTIVE": Color(0.2, 0.55, 0.9, 0.92),
		"ICON_INK": Color(0.05, 0.045, 0.04), "ICON_LABEL": Color(0.92, 0.92, 0.95), "INFO_TEXT": Color(0.9, 0.9, 0.9),
		"INK": Color(0.075, 0.07, 0.065), "KEY_BADGE": Color(0, 0, 0, 0.7), "KEY_TEXT": Color(1, 0.88, 0.45),
		"LOOT_GOLD": Color(1, 0.85, 0.2), "LOOT_PROBLEM": Color(1, 0.4, 0.3), "MUTED": Color(0.64, 0.6, 0.53),
		"ORNAMENT": Color(0.82, 0.66, 0.36), "PANEL": Color(0.115, 0.105, 0.095), "PANEL_LIGHT": Color(0.16, 0.145, 0.13),
		"PAPER": Color(0.93, 0.89, 0.8), "PRESSED_BG": Color(0.3, 0.13, 0.1), "PROMPT_TEXT": Color(0.6, 1, 0.9),
		"RADIUS_ADD": 0,
		"RARITY": {"blue": Color(0.45, 0.68, 1), "gold": Color(1, 0.82, 0.25), "purple": Color(0.82, 0.55, 1), "white": Color(0.92, 0.92, 0.92)},
		"RARITY_WORLD": {"blue": Color(0.4, 0.65, 1), "gold": Color(1, 0.8, 0.2), "purple": Color(0.8, 0.5, 1), "white": Color(0.95, 0.95, 0.95)},
		"SCRIM": Color(0, 0, 0, 0.7), "SCRIM_STRONG": Color(0, 0, 0, 0.85), "SCROLL_TRACK": Color(0, 0, 0, 0.25),
		"SEAL": Color(0.84, 0.24, 0.18), "SELECT_MARK": Color(1, 1, 1), "SKILL_BANNER_BG": Color(0.05, 0.05, 0.07, 0.92),
		"SKILL_BANNER_TEXT": Color(1, 0.98, 0.92), "SLOT_BG": Color(0.085, 0.078, 0.07),
		"STAGE_BOSS": Color(0.84, 0.24, 0.18), "STAGE_CAMP": Color(0.55, 0.85, 0.55),
		"STAGE_CHALLENGE": Color(0.84, 0.24, 0.18), "STAGE_COMBAT": Color(0.93, 0.89, 0.8),
		"STAGE_TREASURE": Color(0.96, 0.79, 0.36), "STAMINA": Color(0.27, 0.6, 0.16), "SUBSTAT": Color(0.78, 0.84, 0.95),
		"TAB_HOVER_BG": Color(0.2, 0.17, 0.15), "TEXT_BRIGHT": Color(0.9, 0.9, 0.9),
		"TEXT_DISABLED": Color(0.45, 0.42, 0.38), "TEXT_LOCKED": Color(0.55, 0.55, 0.6), "TEXT_PLAIN": Color(1, 1, 1),
		"TEXT_STRONG": Color(1, 1, 1), "TEXT_TAG": Color(0.6, 0.6, 0.7), "TEXT_UNLOCKED": Color(0.9, 0.95, 0.9),
		"TITLE_BG": Color(0.84, 0.24, 0.18), "TITLE_OUTLINE": Color(0.15, 0.03, 0.02), "TITLE_STYLE": "brush",
		"TITLE_TEXT": Color(1, 1, 1), "TRIP_TEXT": Color(0.95, 0.92, 0.8), "ULT": Color(0.52, 0.27, 0.82),
		"WARN": Color(1, 0.72, 0.3), "WARNING_TEXT": Color(1, 0.45, 0.4), "WEAR_BROKEN": Color(1, 0.35, 0.3),
		"WEAR_LOW": Color(1, 0.7, 0.3), "WEAR_OK": Color(0.7, 0.75, 0.8),
		"HUD_FONT": {"hp": 17, "bar": 13, "bar_small": 12, "chip": 13, "key": 15, "icon": 13, "cooldown": 22, "loot": 18,
			"combo": 80, "combo_compact": 64, "combo_label": 22, "combo_damage": 20, "banner": 42, "skill": 40,
			"prompt": 20, "trip": 17, "info": 14, "help": 13, "warning": 13, "debug": 16},
		"ICON_STYLE": "plain", "BAR_STYLE": "plain",
	}


## A. SUMI INK: the current ink-and-paper look, tidied. Near-duplicate colors merged into one meaning
## each, secondary text lighter (contrast), the HUD's cold blue-black warmed to the same ink as the
## menus, the teal prompt replaced by paper gold, rarity the same over the world and in menus.
static func _sumi() -> Dictionary:
	var paper := Color(0.93, 0.89, 0.80)
	var muted := Color(0.72, 0.67, 0.58)
	var seal := Color(0.84, 0.24, 0.18)
	var gold := Color(0.96, 0.79, 0.36)
	var good := Color(0.55, 0.85, 0.55)
	var bad := Color(1.0, 0.48, 0.38)
	var warn := Color(1.0, 0.72, 0.3)
	var rarity := {"white": Color(0.90, 0.88, 0.83), "blue": Color(0.45, 0.68, 1.0), "purple": Color(0.82, 0.55, 1.0), "gold": Color(1.0, 0.80, 0.25)}
	return {
		"PAPER": paper, "MUTED": muted, "TEXT_PLAIN": paper, "TEXT_BRIGHT": paper, "TEXT_TAG": muted,
		"TEXT_UNLOCKED": paper, "TEXT_LOCKED": Color(0.52, 0.49, 0.44), "HEADING_ACCENT": gold,
		"SUBSTAT": Color(0.80, 0.84, 0.92),
		"SEAL": seal, "GOLD": gold, "GOOD": good, "GOOD_TEXT": good, "BAD": bad, "CANT_AFFORD": bad,
		"WARN": warn, "WEAR_LOW": warn, "WEAR_BROKEN": bad, "WEAR_OK": muted,
		"STAGE_COMBAT": paper, "STAGE_CHALLENGE": seal, "STAGE_TREASURE": gold, "STAGE_CAMP": good, "STAGE_BOSS": seal,
		"RARITY": rarity, "RARITY_WORLD": rarity.duplicate(),
		"HUD_PANEL": Color(0.075, 0.07, 0.065, 0.84), "HUD_TEXT": Color(1.0, 0.98, 0.94), "HUD_OUTLINE": Color(0.05, 0.04, 0.03),
		"HP": Color(0.80, 0.18, 0.16), "HP_TRAIL": Color(1.0, 0.86, 0.72), "STAMINA": Color(0.27, 0.55, 0.20),
		"ULT": Color(0.45, 0.30, 0.78), "KEY_TEXT": gold, "ICON_LABEL": paper,
		"ICON_ACTIVE": Color(0.22, 0.50, 0.80, 0.92), "COMBO_LABEL": gold, "COMBO_HOT": Color(1.0, 0.52, 0.22),
		"WARNING_TEXT": bad, "TRIP_TEXT": paper, "SKILL_BANNER_BG": Color(0.075, 0.07, 0.065, 0.92),
		"SKILL_BANNER_TEXT": paper, "PROMPT_TEXT": gold, "INFO_TEXT": paper, "HELP_TEXT": paper,
		"HELP_PLATE": Color(0.075, 0.07, 0.065, 0.6),
		"DAMAGE_BIG": gold, "LOOT_GOLD": gold, "LOOT_PROBLEM": bad, "BAG_LOST": bad,
	}


## B. FIELD JOURNAL: a survivor's notebook. Light parchment pages, dark ink text, a red stamp for
## selection, ochre for money; titles underlined in red. The HUD is pinned paper notes: light plates
## with dark text and a light halo. Feels like crafting, cooking and planning: the camp side of the game.
static func _journal() -> Dictionary:
	var ink := Color(0.17, 0.13, 0.10)
	var muted := Color(0.40, 0.33, 0.26)
	var page := Color(0.93, 0.89, 0.80)
	var seal := Color(0.74, 0.15, 0.10)
	var gold := Color(0.58, 0.38, 0.02)
	var good := Color(0.10, 0.45, 0.16)
	var bad := Color(0.72, 0.12, 0.08)
	var warn := Color(0.78, 0.42, 0.0)
	var halo := Color(0.97, 0.94, 0.87)
	return {
		"INK": Color(0.84, 0.79, 0.68), "PANEL": page, "PANEL_LIGHT": Color(0.97, 0.94, 0.87),
		"SLOT_BG": Color(0.82, 0.77, 0.66), "FIELD_BG": Color(0.99, 0.97, 0.92), "BORDER": Color(0.48, 0.38, 0.27),
		"HOVER_BG": Color(1.0, 0.97, 0.86), "PRESSED_BG": Color(0.96, 0.80, 0.70), "TAB_HOVER_BG": Color(0.97, 0.92, 0.82),
		"DISABLED_BG": Color(0.85, 0.81, 0.73), "DISABLED_BORDER": Color(0.70, 0.64, 0.55),
		"SCROLL_TRACK": Color(0.3, 0.2, 0.1, 0.10), "SCRIM": Color(0.10, 0.07, 0.04, 0.55), "SCRIM_STRONG": Color(0.10, 0.07, 0.04, 0.75),
		"PAPER": ink, "MUTED": muted, "TEXT_STRONG": Color(0.06, 0.04, 0.02), "TEXT_DISABLED": Color(0.55, 0.50, 0.44),
		"TEXT_PLAIN": ink, "TEXT_BRIGHT": ink, "TEXT_TAG": muted, "TEXT_LOCKED": Color(0.52, 0.48, 0.44),
		"TEXT_UNLOCKED": ink, "HEADING_ACCENT": Color(0.55, 0.28, 0.04), "SUBSTAT": Color(0.14, 0.30, 0.55),
		"SEAL": seal, "GOLD": gold, "GOOD": good, "GOOD_TEXT": good, "BAD": bad, "CANT_AFFORD": bad, "WARN": warn,
		"WEAR_OK": muted, "WEAR_LOW": warn, "WEAR_BROKEN": bad, "ICON_INK": Color(0.12, 0.09, 0.06),
		"ICON_FALLBACK": Color(0.62, 0.58, 0.52), "DOLL_SHADE": Color(0.55, 0.45, 0.32), "SELECT_MARK": Color(0.10, 0.06, 0.04),
		"TITLE_STYLE": "underline", "TITLE_BG": seal, "TITLE_TEXT": ink, "TITLE_OUTLINE": page,
		"STAGE_COMBAT": ink, "STAGE_CHALLENGE": seal, "STAGE_TREASURE": gold, "STAGE_CAMP": good, "STAGE_BOSS": seal,
		"RARITY": {"white": Color(0.38, 0.37, 0.35), "blue": Color(0.10, 0.36, 0.80), "purple": Color(0.50, 0.18, 0.72), "gold": Color(0.75, 0.50, 0.0)},
		"HUD_PANEL": Color(0.93, 0.89, 0.80, 0.92), "HUD_TEXT": ink, "HUD_OUTLINE": halo, "LOOT_OUTLINE": Color(0.10, 0.07, 0.04),
		"HP": Color(0.82, 0.20, 0.16), "HP_TRAIL": Color(0.98, 0.72, 0.56), "STAMINA": Color(0.40, 0.66, 0.26),
		"STAMINA_EXHAUSTED": Color(0.95, 0.55, 0.35), "ULT": Color(0.56, 0.40, 0.84), "ULT_READY_TEXT": Color(0.30, 0.10, 0.50),
		"BUFF": good, "DEBUFF": bad, "CHIP_BASE": halo, "CHIP_TINT": 0.30, "CHIP_ALPHA": 0.95,
		"KEY_BADGE": Color(0.17, 0.13, 0.10, 0.88), "KEY_TEXT": Color(0.98, 0.88, 0.58), "ICON_LABEL": ink,
		"COOLDOWN_COVER": Color(0.25, 0.18, 0.10, 0.45), "ICON_ACTIVE": Color(0.55, 0.72, 0.92, 0.95),
		"ICON_UNAFFORDABLE": Color(0.92, 0.62, 0.55, 0.95), "ICON_CHARGING": Color(0.82, 0.78, 0.70, 0.80),
		"COMBO_COOL": ink, "COMBO_HOT": seal, "COMBO_OUTLINE": halo, "COMBO_LABEL": Color(0.55, 0.28, 0.04), "COMBO_TIMER": seal,
		"WARNING_TEXT": bad, "TRIP_TEXT": ink, "SKILL_BANNER_BG": Color(0.95, 0.91, 0.82, 0.96), "SKILL_BANNER_TEXT": ink,
		"PROMPT_TEXT": ink, "INFO_TEXT": ink, "HELP_TEXT": ink, "HELP_PLATE": Color(0.93, 0.89, 0.80, 0.85),
	}


## C. CHIBI POP: bold and toy-like, matching the chibi characters and their ink outlines. Deep navy
## night panels, thick near-black outlines, round corners, a hard drop shadow, candy accents (coral
## selection, sunny gold, mint gains), bolder text and ribbon titles. Reads like a mobile action game.
static func _pop() -> Dictionary:
	var text := Color(0.97, 0.97, 1.0)
	var muted := Color(0.68, 0.72, 0.90)
	var outline := Color(0.03, 0.03, 0.07)
	var coral := Color(1.0, 0.36, 0.45)
	var gold := Color(1.0, 0.80, 0.22)
	var good := Color(0.40, 0.92, 0.58)
	var bad := Color(1.0, 0.45, 0.45)
	var warn := Color(1.0, 0.68, 0.18)
	var rarity := {"white": Color(0.86, 0.89, 0.96), "blue": Color(0.36, 0.70, 1.0), "purple": Color(0.80, 0.47, 1.0), "gold": Color(1.0, 0.78, 0.16)}
	return {
		"INK": Color(0.09, 0.10, 0.19), "PANEL": Color(0.14, 0.16, 0.29), "PANEL_LIGHT": Color(0.21, 0.24, 0.41),
		"SLOT_BG": Color(0.11, 0.12, 0.23), "FIELD_BG": Color(0.07, 0.08, 0.15), "BORDER": outline,
		"HOVER_BG": Color(0.28, 0.32, 0.55), "PRESSED_BG": Color(0.62, 0.20, 0.32), "TAB_HOVER_BG": Color(0.24, 0.27, 0.46),
		"DISABLED_BG": Color(0.13, 0.14, 0.22), "DISABLED_BORDER": Color(0.07, 0.07, 0.13),
		"SCRIM": Color(0.03, 0.03, 0.08, 0.75), "SCRIM_STRONG": Color(0.03, 0.03, 0.08, 0.88),
		"PAPER": text, "MUTED": muted, "TEXT_DISABLED": Color(0.45, 0.48, 0.62), "TEXT_PLAIN": text, "TEXT_BRIGHT": text,
		"TEXT_TAG": muted, "TEXT_LOCKED": Color(0.50, 0.53, 0.68), "TEXT_UNLOCKED": text, "HEADING_ACCENT": gold,
		"SUBSTAT": Color(0.60, 0.86, 1.0),
		"SEAL": coral, "GOLD": gold, "GOOD": good, "GOOD_TEXT": good, "BAD": bad, "CANT_AFFORD": bad, "WARN": warn,
		"WEAR_OK": muted, "WEAR_LOW": warn, "WEAR_BROKEN": bad, "ICON_INK": outline, "DOLL_SHADE": Color(0.35, 0.40, 0.75),
		"TITLE_STYLE": "ribbon", "TITLE_BG": coral, "TITLE_OUTLINE": Color(0.30, 0.03, 0.10),
		"STAGE_COMBAT": text, "STAGE_CHALLENGE": coral, "STAGE_TREASURE": gold, "STAGE_CAMP": good, "STAGE_BOSS": coral,
		"RARITY": rarity, "RARITY_WORLD": rarity.duplicate(),
		"RADIUS_ADD": 6, "CORNER_SKEW": 0, "BORDER_SCALE": 2, "SHADOW_SIZE": 1, "SHADOW_OFFSET": Vector2(0, 4),
		"SHADOW_COLOR": Color(0.02, 0.02, 0.06, 0.9), "FONT_EMBOLDEN": 0.3,
		"HUD_PANEL": Color(0.09, 0.10, 0.19, 0.88), "HUD_OUTLINE": outline,
		"HP": Color(0.92, 0.22, 0.36), "HP_TRAIL": Color(1.0, 0.86, 0.55), "STAMINA": Color(0.10, 0.58, 0.40),
		"ULT": Color(0.52, 0.32, 0.95), "KEY_TEXT": gold, "ICON_ACTIVE": Color(0.20, 0.58, 1.0, 0.95),
		"ICON_UNAFFORDABLE": Color(0.55, 0.12, 0.22, 0.9), "COMBO_HOT": coral, "COMBO_LABEL": gold, "COMBO_TIMER": coral,
		"WARNING_TEXT": bad, "TRIP_TEXT": text, "SKILL_BANNER_BG": Color(0.95, 0.30, 0.42, 0.95), "SKILL_BANNER_TEXT": Color.WHITE,
		"PROMPT_TEXT": gold, "INFO_TEXT": text, "HELP_TEXT": text, "HELP_PLATE": Color(0.09, 0.10, 0.19, 0.7),
		"DAMAGE_BIG": gold, "DAMAGE_CRIT": coral, "LOOT_GOLD": gold,
	}


## D. NIGHT BRASS is the live look (ink_ui.gd's own values). For mockups only, this adds a desktop
## serif (Georgia) standing in for the display font that is not chosen yet; SystemFont falls back to
## the default face where the name is missing (the web build), so nothing breaks there.
static func _brass_preview() -> Dictionary:
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Cambria", "Times New Roman"])
	serif.font_weight = 700
	return {"DISPLAY_FONT": serif}
